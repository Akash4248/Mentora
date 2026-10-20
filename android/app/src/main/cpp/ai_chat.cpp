#include <android/log.h>
#include <jni.h>
#include <iomanip>
#include <cmath>
#include <atomic>
#include <array>
#include <cerrno>
#include <cstring>
#include <string>
#include <unistd.h>
#include <sampling.h>

#include "logging.h"
#include "chat.h"
#include "common.h"
#include "llama.h"

template<class T>
static std::string join(const std::vector<T> &values, const std::string &delim) {
    std::ostringstream str;
    for (size_t i = 0; i < values.size(); i++) {
        str << values[i];
        if (i < values.size() - 1) { str << delim; }
    }
    return str.str();
}

/**
 * LLama resources: context, model, batch and sampler
 */
constexpr int   N_THREADS_MIN           = 1;
constexpr int   N_THREADS_MAX           = 4;
constexpr int   N_THREADS_HEADROOM      = 2;

constexpr int   DEFAULT_CONTEXT_SIZE    = 2048;
constexpr int   OVERFLOW_HEADROOM       = 4;
constexpr int   BATCH_SIZE              = 128;
constexpr int   TOKENS_PER_CHUNK        = 4;
constexpr float DEFAULT_SAMPLER_TEMP    = 0.3f;

static llama_model                      * g_model;
static llama_context                    * g_context;
static llama_batch                        g_batch;
static common_chat_templates_ptr          g_chat_templates;
static common_sampler                   * g_sampler;
static bool                               g_batch_initialized = false;
static std::atomic<bool>                  g_stop_requested{false};

static void release_native_resources() {
    g_stop_requested.store(false, std::memory_order_relaxed);

    if (g_sampler != nullptr) {
        common_sampler_free(g_sampler);
        g_sampler = nullptr;
    }

    g_chat_templates.reset();

    if (g_batch_initialized) {
        llama_batch_free(g_batch);
        g_batch_initialized = false;
    }

    if (g_context != nullptr) {
        llama_free(g_context);
        g_context = nullptr;
    }

    if (g_model != nullptr) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
}

extern "C"
JNIEXPORT void JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_init(JNIEnv *env, jobject /*unused*/, jstring nativeLibDir) {
    // Set llama log handler to Android
    llama_log_set(aichat_android_log_callback, nullptr);

    // Register statically linked backends (CPU) and also try dynamic backends from lib path.
    ggml_backend_load_all();

    // Loading all CPU backend variants
    const auto *path_to_backend = env->GetStringUTFChars(nativeLibDir, 0);
    LOGi("Loading backends from %s", path_to_backend);
    ggml_backend_load_all_from_path(path_to_backend);
    env->ReleaseStringUTFChars(nativeLibDir, path_to_backend);

    // Initialize backends
    llama_backend_init();
    LOGi("Backend initiated; Log handler set.");
}

extern "C"
JNIEXPORT jint JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_load(JNIEnv *env, jobject, jstring jmodel_path) {
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0;
    // Use mmap for fast loading; fall back to NONE if the filesystem doesn't support it.
    // (use_mmap / use_mlock / use_direct_io were removed in favour of load_mode enum)
    model_params.load_mode      = LLAMA_LOAD_MODE_MMAP;
    model_params.check_tensors  = false;
    model_params.use_extra_bufts = false;

    const auto *model_path = env->GetStringUTFChars(jmodel_path, 0);
    LOGd("%s: Loading model from: \n%s\n", __func__, model_path);

    // PERMANENT LOAD: Only load if not already loaded (keep model in memory between questions)
    // This prevents the 500ms+ reload penalty on every question
    if (g_model != nullptr) {
        LOGi("%s: Model already loaded, reusing cached instance", __func__);
        env->ReleaseStringUTFChars(jmodel_path, model_path);
        return 0;  // Already loaded, no need to reload
    }

    auto *model = llama_model_load_from_file(model_path, model_params);
    if (!model) {
        // Fallback for devices/filesystems where mmap can fail (e.g. some Android OEMs).
        LOGw("%s: mmap load failed, retrying without mmap...", __func__);
        model_params.load_mode = LLAMA_LOAD_MODE_NONE;
        model = llama_model_load_from_file(model_path, model_params);
    }
    env->ReleaseStringUTFChars(jmodel_path, model_path);
    if (!model) {
        LOGe("%s: llama_model_load_from_file failed (errno=%d, %s)", __func__, errno, std::strerror(errno));
        return 1;
    }
    g_model = model;
    LOGi("%s: Model loaded successfully and cached in memory", __func__);
    return 0;
}


static llama_context *init_context(llama_model *model, const int n_ctx = DEFAULT_CONTEXT_SIZE) {
    if (!model) {
        LOGe("%s: model cannot be null", __func__);
        return nullptr;
    }

    // Multi-threading setup
    const int n_threads = std::max(N_THREADS_MIN, std::min(N_THREADS_MAX,
                                                     (int) sysconf(_SC_NPROCESSORS_ONLN) -
                                                     N_THREADS_HEADROOM));
    LOGi("%s: Using %d threads", __func__, n_threads);

    // Context parameters setup
    llama_context_params ctx_params = llama_context_default_params();
    const int trained_context_size = llama_model_n_ctx_train(model);
    const int effective_ctx = std::min(n_ctx, trained_context_size > 0 ? trained_context_size : n_ctx);
    if (n_ctx > trained_context_size) {
        LOGw("%s: Model was trained with only %d context size! Enforcing %d context size...",
             __func__, trained_context_size, n_ctx);
    }
    ctx_params.n_ctx = effective_ctx;
    ctx_params.n_batch = BATCH_SIZE;
    ctx_params.n_ubatch = BATCH_SIZE;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;
    ctx_params.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;
    auto *context = llama_init_from_model(g_model, ctx_params);
    if (context == nullptr) {
        LOGe("%s: llama_new_context_with_model() returned null)", __func__);
    }
    return context;
}

static common_sampler *new_sampler(float temp) {
    common_params_sampling sparams;
    sparams.temp = temp;
    sparams.penalty_last_n = 64;
    sparams.penalty_repeat = 1.15f;
    sparams.penalty_freq = 0.50f;
    sparams.penalty_present = 0.50f;
    return common_sampler_init(g_model, sparams);
}

extern "C"
JNIEXPORT jint JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_prepare(JNIEnv * /*env*/, jobject /*unused*/) {
    auto *context = init_context(g_model);
    if (!context) { return 1; }
    g_context = context;
    g_batch = llama_batch_init(BATCH_SIZE, 0, 1);
    g_batch_initialized = true;
    g_chat_templates = common_chat_templates_init(g_model, "");
    g_sampler = new_sampler(DEFAULT_SAMPLER_TEMP);
    return 0;
}

static std::string get_backend() {
    std::vector<std::string> backends;
    for (size_t i = 0; i < ggml_backend_reg_count(); i++) {
        auto *reg = ggml_backend_reg_get(i);
        std::string name = ggml_backend_reg_name(reg);
        if (name != "CPU") {
            backends.push_back(ggml_backend_reg_name(reg));
        }
    }
    return backends.empty() ? "CPU" : join(backends, ",");
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_systemInfo(JNIEnv *env, jobject /*unused*/) {
    return env->NewStringUTF(llama_print_system_info());
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_benchModel(JNIEnv *env, jobject /*unused*/, jint pp, jint tg,
                                                      jint pl, jint nr) {
    auto *context = init_context(g_model, pp);
    if (!context) {
        const auto *const err_msg = "Fail to init_context! Bench aborted.";
        LOGe(err_msg);
        return env->NewStringUTF(err_msg);
    }

    auto pp_avg = 0.0;
    auto tg_avg = 0.0;
    auto pp_std = 0.0;
    auto tg_std = 0.0;

    const uint32_t n_ctx = llama_n_ctx(context);
    LOGi("n_ctx = %d", n_ctx);

    int i, j;
    int nri;
    for (nri = 0; nri < nr; nri++) {
        LOGi("Benchmark prompt processing (pp = %d)", pp);

        common_batch_clear(g_batch);

        const int n_tokens = pp;
        for (i = 0; i < n_tokens; i++) {
            common_batch_add(g_batch, 0, i, {0}, false);
        }

        g_batch.logits[g_batch.n_tokens - 1] = true;
        llama_memory_clear(llama_get_memory(context), false);

        const auto t_pp_start = ggml_time_us();
        if (llama_decode(context, g_batch) != 0) {
            LOGe("llama_decode() failed during prompt processing");
        }
        const auto t_pp_end = ggml_time_us();

        // bench text generation

        LOGi("Benchmark text generation (tg = %d)", tg);

        llama_memory_clear(llama_get_memory(context), false);
        const auto t_tg_start = ggml_time_us();
        for (i = 0; i < tg; i++) {
            common_batch_clear(g_batch);
            for (j = 0; j < pl; j++) {
                common_batch_add(g_batch, 0, i, {j}, true);
            }

            if (llama_decode(context, g_batch) != 0) {
                LOGe("llama_decode() failed during text generation");
            }
        }
        const auto t_tg_end = ggml_time_us();

        llama_memory_clear(llama_get_memory(context), false);

        const auto t_pp = double(t_pp_end - t_pp_start) / 1000000.0;
        const auto t_tg = double(t_tg_end - t_tg_start) / 1000000.0;

        const auto speed_pp = double(pp) / t_pp;
        const auto speed_tg = double(pl * tg) / t_tg;

        pp_avg += speed_pp;
        tg_avg += speed_tg;

        pp_std += speed_pp * speed_pp;
        tg_std += speed_tg * speed_tg;

        LOGi("pp %f t/s, tg %f t/s", speed_pp, speed_tg);
    }

    llama_free(context);

    pp_avg /= double(nr);
    tg_avg /= double(nr);

    if (nr > 1) {
        pp_std = sqrt(pp_std / double(nr - 1) - pp_avg * pp_avg * double(nr) / double(nr - 1));
        tg_std = sqrt(tg_std / double(nr - 1) - tg_avg * tg_avg * double(nr) / double(nr - 1));
    } else {
        pp_std = 0;
        tg_std = 0;
    }

    char model_desc[128];
    llama_model_desc(g_model, model_desc, sizeof(model_desc));

    const auto model_size = double(llama_model_size(g_model)) / 1024.0 / 1024.0 / 1024.0;
    const auto model_n_params = double(llama_model_n_params(g_model)) / 1e9;

    const auto backend = get_backend();
    std::stringstream result;
    result << std::setprecision(3);
    result << "| model | size | params | backend | test | t/s |\n";
    result << "| --- | --- | --- | --- | --- | --- |\n";
    result << "| " << model_desc << " | " << model_size << "GiB | " << model_n_params << "B | "
           << backend << " | pp " << pp << " | " << pp_avg << " ± " << pp_std << " |\n";
    result << "| " << model_desc << " | " << model_size << "GiB | " << model_n_params << "B | "
           << backend << " | tg " << tg << " | " << tg_avg << " ± " << tg_std << " |\n";
    return env->NewStringUTF(result.str().c_str());
}


/**
 * Completion loop's long-term states:
 * - chat management
 * - position tracking
 */
constexpr const char *ROLE_SYSTEM       = "system";
constexpr const char *ROLE_USER         = "user";
constexpr const char *ROLE_ASSISTANT    = "assistant";

static std::vector<common_chat_msg> chat_msgs;
static llama_pos system_prompt_position;
static llama_pos current_position;

static void reset_long_term_states(const bool clear_kv_cache = true) {
    chat_msgs.clear();
    system_prompt_position = 0;
    current_position = 0;

    if (clear_kv_cache)
        llama_memory_clear(llama_get_memory(g_context), false);
}

/**
 * TODO-hyin: implement sliding-window version as a better alternative
 *
 * Context shifting by discarding the older half of the tokens appended after system prompt:
 * - take the [system_prompt_position] first tokens from the original prompt
 * - take half of the last (system_prompt_position - system_prompt_position) tokens
 * - recompute the logits in batches
 */
static void shift_context() {
    const int n_discard = (current_position - system_prompt_position) / 2;
    LOGi("%s: Discarding %d tokens", __func__, n_discard);
    llama_memory_seq_rm(llama_get_memory(g_context), 0, system_prompt_position, system_prompt_position + n_discard);
    llama_memory_seq_add(llama_get_memory(g_context), 0, system_prompt_position + n_discard, current_position, -n_discard);
    current_position -= n_discard;
    LOGi("%s: Context shifting done! Current position: %d", __func__, current_position);
}

static std::string chat_add_and_format(const std::string &role, const std::string &content, const bool persist = true) {
    common_chat_msg new_msg;
    new_msg.role = role;
    new_msg.content = content;
    auto formatted = common_chat_format_single(
            g_chat_templates.get(), chat_msgs, new_msg, role == ROLE_USER, /* use_jinja */ false);
    if (persist) {
        chat_msgs.push_back(new_msg);
    }
    LOGi("%s: Formatted %s message%s", __func__, role.c_str(), persist ? " (persisted)" : "");
    return formatted;
}

/**
 * Completion loop's short-term states:
 * - stop generation position
 * - token chars caching
 * - current assistant message being generated
 */
static llama_pos stop_generation_position;
static std::string cached_token_chars;
static std::ostringstream assistant_ss;

static void reset_short_term_states() {
    stop_generation_position = 0;
    cached_token_chars.clear();
    assistant_ss.str("");
    if (g_sampler != nullptr) {
        common_sampler_reset(g_sampler);
    }
}

static void reset_to_system_prompt_context() {
    if (g_context == nullptr) {
        return;
    }

    // Keep only the system prompt in KV so each user turn has consistent latency.
    llama_memory_seq_rm(llama_get_memory(g_context), 0, system_prompt_position, -1);
    current_position = system_prompt_position;
}

static bool use_chat_template() {
    // Gemma-family models (gemma-2/gemma-3) require their native control tokens
    // to generate; without engine-side templating they emit empty/stop tokens.
    // Enable the native chat template (from the GGUF) only for models that ship
    // a Gemma template. Llama/Qwen continue to use Dart-side manual templates.
    if (!g_chat_templates) {
        return false;
    }
    const std::string src = common_chat_templates_source(g_chat_templates.get());
    return src.find("gemma") != std::string::npos;
}

static size_t find_first_stop_marker(const std::string & text) {
    static const std::array<const char *, 8> kMarkers = {
            "<|question_end|>",
            "\nUser:",
            "\nAssistant:",
            "</s>",
            "<|im_end|>",
            "<end_of_turn>",
            "<|im_start|>",
            "<start_of_turn>",
    };

    size_t best = std::string::npos;
    for (const char * marker : kMarkers) {
        const size_t pos = text.find(marker);
        if (pos != std::string::npos && (best == std::string::npos || pos < best)) {
            best = pos;
        }
    }
    return best;
}

static int decode_tokens_in_batches(
        llama_context *context,
        llama_batch &batch,
        const llama_tokens &tokens,
        const llama_pos start_pos,
        const bool compute_last_logit = false) {
    // Process tokens in batches using the global batch
    LOGd("%s: Decode %d tokens starting at position %d", __func__, (int) tokens.size(), start_pos);
    for (int i = 0; i < (int) tokens.size(); i += BATCH_SIZE) {
        const int cur_batch_size = std::min((int) tokens.size() - i, BATCH_SIZE);
        common_batch_clear(batch);
        LOGv("%s: Preparing a batch size of %d starting at: %d", __func__, cur_batch_size, i);

        // Shift context if current batch cannot fit into the context
        if (start_pos + i + cur_batch_size >= DEFAULT_CONTEXT_SIZE - OVERFLOW_HEADROOM) {
            LOGw("%s: Current batch won't fit into context! Shifting...", __func__);
            shift_context();
        }

        // Add tokens to the batch with proper positions
        for (int j = 0; j < cur_batch_size; j++) {
            const llama_token token_id = tokens[i + j];
            const llama_pos position = start_pos + i + j;
            const bool want_logit = compute_last_logit && (i + j == tokens.size() - 1);
            common_batch_add(batch, token_id, position, {0}, want_logit);
        }

        // Decode this batch
        const int decode_result = llama_decode(context, batch);
        if (decode_result) {
            LOGe("%s: llama_decode failed w/ %d", __func__, decode_result);
            return 1;
        }
    }
    return 0;
}

extern "C"
JNIEXPORT jint JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_processSystemPrompt(
        JNIEnv *env,
        jobject /*unused*/,
        jstring jsystem_prompt
) {
    // Reset long-term & short-term states
    reset_long_term_states();
    reset_short_term_states();

    // Obtain system prompt from JEnv
    const auto *system_prompt = env->GetStringUTFChars(jsystem_prompt, nullptr);
    LOGd("%s: System prompt received: \n%s", __func__, system_prompt);
    std::string formatted_system_prompt(system_prompt);
    env->ReleaseStringUTFChars(jsystem_prompt, system_prompt);

    // Format system prompt if applicable
    const bool has_chat_template = use_chat_template();
    if (has_chat_template) {
        formatted_system_prompt = chat_add_and_format(ROLE_SYSTEM, system_prompt, true);
    }

    // Tokenize system prompt
    const auto system_tokens = common_tokenize(g_context, formatted_system_prompt,
                                               has_chat_template, has_chat_template);
    for (auto id: system_tokens) {
        LOGv("token: `%s`\t -> `%d`", common_token_to_piece(g_context, id).c_str(), id);
    }

    // Handle context overflow
    const int max_batch_size = DEFAULT_CONTEXT_SIZE - OVERFLOW_HEADROOM;
    if ((int) system_tokens.size() > max_batch_size) {
        LOGe("%s: System prompt too long for context! %d tokens, max: %d",
             __func__, (int) system_tokens.size(), max_batch_size);
        return 1;
    }

    // Decode system tokens in batches
    if (decode_tokens_in_batches(g_context, g_batch, system_tokens, current_position)) {
        LOGe("%s: llama_decode() failed!", __func__);
        return 2;
    }

    // Update position
    system_prompt_position = current_position = (int) system_tokens.size();
    return 0;
}

extern "C"
JNIEXPORT jint JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_processUserPrompt(
        JNIEnv *env,
        jobject /*unused*/,
        jstring juser_prompt,
        jint n_predict
) {
    // Reset short-term states
    reset_short_term_states();
    g_stop_requested.store(false, std::memory_order_relaxed);
    reset_to_system_prompt_context();

    // Obtain and tokenize user prompt
    const auto *const user_prompt = env->GetStringUTFChars(juser_prompt, nullptr);
    std::string user_prompt_str(user_prompt != nullptr ? user_prompt : "");
    LOGd("%s: User prompt received: \n%s", __func__, user_prompt_str.c_str());
    std::string formatted_user_prompt(user_prompt_str);
    env->ReleaseStringUTFChars(juser_prompt, user_prompt);

    // Format user prompt if applicable (never re-wrap already formatted turn templates)
    const bool is_already_formatted = (user_prompt_str.rfind("<|im_start|", 0) == 0) ||
                                      (user_prompt_str.rfind("<s>[INST]", 0) == 0) ||
                                      (user_prompt_str.rfind("<start_of_turn>", 0) == 0);
    const bool has_chat_template = use_chat_template() && !is_already_formatted;
    if (has_chat_template) {
        // Keep turns stateless for speed: persist only system prompt, not every user/assistant turn.
        formatted_user_prompt = chat_add_and_format(ROLE_USER, user_prompt_str, false);
    } else {
        // Fast non-template path: raw question avoids injecting role tokens that can leak into output.
        formatted_user_prompt = user_prompt_str;
    }

    // Decode formatted user prompts
    auto user_tokens = common_tokenize(g_context, formatted_user_prompt, has_chat_template, has_chat_template);
    for (auto id: user_tokens) {
        LOGv("token: `%s`\t -> `%d`", common_token_to_piece(g_context, id).c_str(), id);
    }

    // Ensure user prompt doesn't exceed the context size by truncating if necessary.
    const int user_prompt_size = (int) user_tokens.size();
    const int max_batch_size = DEFAULT_CONTEXT_SIZE - OVERFLOW_HEADROOM;
    if (user_prompt_size > max_batch_size) {
        const int skipped_tokens = user_prompt_size - max_batch_size;
        user_tokens.resize(max_batch_size);
        LOGw("%s: User prompt too long! Skipped %d tokens!", __func__, skipped_tokens);
    }

    // Decode user tokens in batches
    if (decode_tokens_in_batches(g_context, g_batch, user_tokens, current_position, true)) {
        LOGe("%s: llama_decode() failed!", __func__);
        return 2;
    }

    // Update position
    current_position += (int) user_tokens.size();
    stop_generation_position = current_position + n_predict;
    return 0;
}

static bool is_valid_utf8(const char *string) {
    if (!string) { return true; }

    const auto *bytes = (const unsigned char *) string;
    int num;

    while (*bytes != 0x00) {
        if ((*bytes & 0x80) == 0x00) {
            // U+0000 to U+007F
            num = 1;
        } else if ((*bytes & 0xE0) == 0xC0) {
            // U+0080 to U+07FF
            num = 2;
        } else if ((*bytes & 0xF0) == 0xE0) {
            // U+0800 to U+FFFF
            num = 3;
        } else if ((*bytes & 0xF8) == 0xF0) {
            // U+10000 to U+10FFFF
            num = 4;
        } else {
            return false;
        }

        bytes += 1;
        for (int i = 1; i < num; ++i) {
            if ((*bytes & 0xC0) != 0x80) {
                return false;
            }
            bytes += 1;
        }
    }
    return true;
}

extern "C"
JNIEXPORT jstring JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_generateNextToken(
        JNIEnv *env,
        jobject /*unused*/
) {
    std::string chunk;
    chunk.reserve(48);

    for (int i = 0; i < TOKENS_PER_CHUNK; ++i) {
        if (g_stop_requested.load(std::memory_order_relaxed)) {
            LOGi("%s: stop requested by UI", __func__);
            if (chunk.empty()) {
                return nullptr;
            }
            break;
        }

        // Infinite text generation via context shifting
        if (current_position >= DEFAULT_CONTEXT_SIZE - OVERFLOW_HEADROOM) {
            LOGw("%s: Context full! Shifting...", __func__);
            shift_context();
        }

        // Stop if reaching the marked position
        if (current_position >= stop_generation_position) {
            LOGw("%s: STOP: hitting stop position: %d", __func__, stop_generation_position);
            if (chunk.empty()) {
                return nullptr;
            }
            break;
        }

        // Sample next token
        const auto new_token_id = common_sampler_sample(g_sampler, g_context, -1);
        common_sampler_accept(g_sampler, new_token_id, true);

        // Populate the batch with new token, then decode
        common_batch_clear(g_batch);
        common_batch_add(g_batch, new_token_id, current_position, {0}, true);
        if (llama_decode(g_context, g_batch) != 0) {
            LOGe("%s: llama_decode() failed for generated token", __func__);
            if (chunk.empty()) {
                return nullptr;
            }
            break;
        }

        // Update position
        current_position++;

        // Stop if next token is EOG
        if (llama_vocab_is_eog(llama_model_get_vocab(g_model), new_token_id)) {
            LOGd("id: %d,\tIS EOG!\nSTOP.", new_token_id);
            stop_generation_position = current_position;
            chat_add_and_format(ROLE_ASSISTANT, assistant_ss.str(), false);
            break;
        }

        // If not EOG, convert to text
        auto new_token_chars = common_token_to_piece(g_context, new_token_id);
        cached_token_chars += new_token_chars;

        if (is_valid_utf8(cached_token_chars.c_str())) {
            LOGv("id: %d,\tcached: `%s`,\tnew: `%s`", new_token_id, cached_token_chars.c_str(), new_token_chars.c_str());
            const size_t chunk_prev_len = chunk.size();
            chunk += cached_token_chars;
            assistant_ss << cached_token_chars;
            cached_token_chars.clear();

            std::string full_text = assistant_ss.str();

            // Strip common leading assistant prefixes for cleaner UX.
            if (full_text.rfind("Assistant:", 0) == 0) {
                full_text.erase(0, 10);
                if (!full_text.empty() && full_text[0] == ' ') {
                    full_text.erase(0, 1);
                }
                assistant_ss.str("");
                assistant_ss << full_text;
                chunk = full_text;
            }

            const size_t stop_pos = find_first_stop_marker(full_text);
            if (stop_pos != std::string::npos) {
                const std::string trimmed = full_text.substr(0, stop_pos);
                assistant_ss.str("");
                assistant_ss << trimmed;

                const size_t emit_start = chunk_prev_len;
                if (stop_pos <= emit_start) {
                    chunk.resize(emit_start);
                } else {
                    const size_t keep_in_chunk = stop_pos - emit_start;
                    chunk.resize(emit_start + keep_in_chunk);
                }

                stop_generation_position = current_position;
                break;
            }
        } else {
            LOGv("id: %d,\tappend to cache", new_token_id);
        }
    }

    if (chunk.empty()) {
        return env->NewStringUTF("");
    }
    return env->NewStringUTF(chunk.c_str());
}

extern "C"
JNIEXPORT void JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_requestStopGeneration(JNIEnv *, jobject /*unused*/) {
    g_stop_requested.store(true, std::memory_order_relaxed);
}


extern "C"
JNIEXPORT jstring JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_generateFullResponse(
        JNIEnv *env,
        jobject /*unused*/,
        jstring juser_prompt,
        jint n_predict
) {
    // ============================================================
    // PERFORMANCE CRITICAL: Fast single-JNI-call generation
    // System prompt is already in KV cache from processSystemPrompt()
    // Just process user prompt and generate - NO system prompt reprocessing!
    // ============================================================

    if (g_model == nullptr || g_context == nullptr || g_sampler == nullptr) {
        LOGe("%s: Model not initialized", __func__);
        return env->NewStringUTF("");
    }

    // Reset short-term states only (keep system prompt in KV cache)
    reset_short_term_states();
    g_stop_requested.store(false, std::memory_order_relaxed);
    
    // Reset context to system prompt boundary (don't reprocess system prompt)
    reset_to_system_prompt_context();

    // Get and process user prompt ONLY (no system prompt reprocessing)
    const auto *user_prompt_cstr = env->GetStringUTFChars(juser_prompt, nullptr);
    const std::string user_prompt(user_prompt_cstr != nullptr ? user_prompt_cstr : "");
    if (user_prompt_cstr) env->ReleaseStringUTFChars(juser_prompt, user_prompt_cstr);

    // Format user prompt (same as processUserPrompt)
    std::string formatted_user_prompt = user_prompt;
    const bool has_chat_template = use_chat_template();
    if (has_chat_template) {
        formatted_user_prompt = chat_add_and_format(ROLE_USER, user_prompt, false);
    }

    // Tokenize and decode user prompt
    const auto user_tokens = common_tokenize(g_context, formatted_user_prompt, has_chat_template, has_chat_template);
    if (!user_tokens.empty()) {
        const int user_prompt_size = (int) user_tokens.size();
        if (decode_tokens_in_batches(g_context, g_batch, user_tokens, current_position, true)) {
            LOGe("%s: Failed to decode user prompt", __func__);
            return env->NewStringUTF("");
        }
        current_position += user_prompt_size;
    }

    stop_generation_position = current_position + n_predict;

    // ========== GENERATION LOOP: ALL NATIVE, NO JNI CALLS ==========
    std::string result;
    result.reserve(2048);

    while (current_position < stop_generation_position && !g_stop_requested.load(std::memory_order_relaxed)) {
        if (current_position >= DEFAULT_CONTEXT_SIZE - OVERFLOW_HEADROOM) {
            shift_context();
        }

        const auto new_token_id = common_sampler_sample(g_sampler, g_context, -1);
        common_sampler_accept(g_sampler, new_token_id, true);

        common_batch_clear(g_batch);
        common_batch_add(g_batch, new_token_id, current_position, {0}, true);
        if (llama_decode(g_context, g_batch) != 0) break;
        current_position++;

        if (llama_vocab_is_eog(llama_model_get_vocab(g_model), new_token_id)) break;

        result += common_token_to_piece(g_context, new_token_id);

        // Stop at markers
        if (result.find("\nUser:") != std::string::npos) {
            result = result.substr(0, result.find("\nUser:"));
            break;
        }
    }

    // Cleanup output
    if (result.rfind("Assistant:", 0) == 0) {
        result = result.substr(10);
        if (!result.empty() && result[0] == ' ') result = result.substr(1);
    }

    LOGi("%s: Generated %zu chars in fast path (no system prompt reprocessing)", __func__, result.size());
    return env->NewStringUTF(result.c_str());
}

extern "C"
JNIEXPORT void JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_unload(JNIEnv * /*unused*/, jobject /*unused*/) {
    // Reset long-term & short-term states
    reset_long_term_states();
    reset_short_term_states();

    // Free up resources
    release_native_resources();
}

extern "C"
JNIEXPORT void JNICALL
Java_com_arm_aichat_internal_InferenceEngineImpl_shutdown(JNIEnv *, jobject /*unused*/) {
    llama_backend_free();
}
