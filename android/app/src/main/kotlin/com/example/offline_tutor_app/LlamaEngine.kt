package com.example.offline_tutor_app

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.arm.aichat.AiChat
import com.arm.aichat.InferenceEngine
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.File

class LlamaEngine(private val context: Context) {
    private var maxOutputTokens = 1024  // Allow up to 1024 output tokens by default for detailed answers
    private var maxGenerationDurationMs = 300000  // 300 seconds timeout for on-device LLMs (e.g. Bonsai, Phi-2)
    private val defaultSystemPrompt = "You are a helpful educational tutor. Provide clear, comprehensive, and accurate explanations. Structure your response logically. Do not repeat phrases. Do not produce speaker labels like A:, B:, User:, Assistant:. Do not continue into another turn."
    private var activeSystemPrompt = defaultSystemPrompt
    private val prefs: SharedPreferences =
        context.getSharedPreferences("offline_tutor_prefs", Context.MODE_PRIVATE)
    private val modelPathKey = "selected_model_path"
    private val lastSelectedAtKey = "selected_model_last_selected_at"
    private val modelFileName = "phi-2.Q4_K_M.gguf"
    private var modelPath = resolveInitialModelPath()
    @Volatile
    private var loaded = false
    private var initAttempts = 0
    private var successfulInits = 0
    private var totalInferenceCount = 0
    private var lastInitAtMillis = 0L
    private var lastInferenceAtMillis = 0L
    private var lastInferenceDurationMs = 0L
    private var totalInferenceDurationMs = 0L
    private var minInferenceDurationMs = Long.MAX_VALUE
    private var maxInferenceDurationMs = 0L
    private var lastPromptChars = 0
    private var lastOutputChars = 0
    @Volatile
    private var lastEngineError = ""
    private val inferenceEngine: InferenceEngine = AiChat.getInferenceEngine(context)
    private var systemPromptApplied = false

    fun getModelPath(): String = modelPath

    fun getActiveModelName(): String {
        val fileName = File(modelPath).name
        return when {
            fileName.isBlank() -> "unknown"
            fileName.endsWith(".gguf", ignoreCase = true) -> fileName.substring(0, fileName.length - 5)
            else -> fileName
        }
    }

    fun getChatTemplateName(): String {
        val name = getActiveModelName().lowercase(java.util.Locale.US)
        return when {
            name.contains("bonsai") -> "ChatML/Bonsai"
            name.contains("phi-2") -> "ChatML/Phi-2"
            name.contains("phi-3") || name.contains("phi-4") -> "Phi-3/4"
            name.contains("llama-2") || name.contains("tinyllama") -> "Llama-2"
            name.contains("llama-3") -> "Llama-3"
            name.contains("gemma") -> "Gemma"
            name.contains("qwen") -> "ChatML/Qwen"
            else -> "ChatML/Generic"
        }
    }

    private fun resolveInitialModelPath(): String {
        val configuredPath = prefs.getString(modelPathKey, null)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }

        if (configuredPath != null &&
            !AndroidModelCompatibility.isDFlashDraft(File(configuredPath).name)
        ) {
            return configuredPath
        }

        discoverDefaultModelPath()?.let { return it }

        return File(context.filesDir, "models/$modelFileName").absolutePath
    }

    private fun discoverDefaultModelPath(): String? {
        val candidateDirectories = listOfNotNull(
            File(context.filesDir, "models"),
            context.getExternalFilesDir(null)?.let { File(it, "models") },
            File("/sdcard/Download"),
            File("/storage/emulated/0/Download"),
            context.getExternalFilesDir(null)?.let { File(it, "Download") },
        )

        val discovered = candidateDirectories
            .flatMap { directory ->
                directory.listFiles()
                    ?.filter { file -> 
                        file.isFile && 
                        file.name.lowercase().endsWith(".gguf") && 
                        !AndroidModelCompatibility.isDFlashDraft(file.name) &&
                        !file.name.lowercase().contains("gemma-3")
                    }
                    ?: emptyList()
            }
            .sortedWith(
                compareByDescending<File> { it.lastModified() }
                    .thenByDescending { it.length() },
            )

        return discovered.firstOrNull()?.absolutePath
    }

    fun getGenerationConfig(): Map<String, Any> {
        return mapOf(
            "maxTokens" to maxOutputTokens,
            "timeoutMs" to maxGenerationDurationMs,
            "systemPrompt" to activeSystemPrompt,
        )
    }

    fun updateGenerationConfig(
        maxTokens: Int?,
        timeoutMs: Int?,
        systemPrompt: String?,
    ): Map<String, Any> {
        if (maxTokens != null) {
            maxOutputTokens = maxTokens.coerceIn(16, 4096)
        }
        if (timeoutMs != null) {
            // 0 disables timeout; otherwise allow up to 10 minutes for slow devices.
            maxGenerationDurationMs = timeoutMs.coerceIn(0, 600000)
        }
        if (systemPrompt != null) {
            val cleaned = systemPrompt.trim()
            if (cleaned.isNotEmpty() && cleaned != activeSystemPrompt) {
                activeSystemPrompt = cleaned
                // Apply updated prompt on next ask without full model reload.
                systemPromptApplied = false
            }
        }

        return getGenerationConfig()
    }

    fun getEngineStatus(): Map<String, Any> {
        val minMs = if (minInferenceDurationMs == Long.MAX_VALUE) 0L else minInferenceDurationMs
        val avgMs = if (totalInferenceCount > 0) totalInferenceDurationMs / totalInferenceCount else 0L

        return mapOf(
            "loaded" to loaded,
            "modelPath" to modelPath,
            "initAttempts" to initAttempts,
            "successfulInits" to successfulInits,
            "totalInferenceCount" to totalInferenceCount,
            "lastInitAtMillis" to lastInitAtMillis,
            "lastInferenceAtMillis" to lastInferenceAtMillis,
            "lastInferenceDurationMs" to lastInferenceDurationMs,
            "avgInferenceDurationMs" to avgMs,
            "minInferenceDurationMs" to minMs,
            "maxInferenceDurationMs" to maxInferenceDurationMs,
            "lastPromptChars" to lastPromptChars,
            "lastOutputChars" to lastOutputChars,
            "generationMaxTokens" to maxOutputTokens,
            "generationTimeoutMs" to maxGenerationDurationMs,
            "lastEngineError" to lastEngineError,
            "activeModel" to getActiveModelName(),
            "chatTemplate" to getChatTemplateName(),
        )
    }

    fun preloadModel(): Boolean {
        if (loaded) {
            return true
        }

        val modelFile = File(modelPath)
        val validationError = validateModelFile(modelFile)
        if (validationError != null) {
            lastEngineError = validationError
            return false
        }

        lastEngineError = ""
        Thread {
            try {
                runBlocking {
                    initAttempts += 1
                    ensureModelLoadedWithRecovery(modelPath)
                    successfulInits += 1
                    lastInitAtMillis = System.currentTimeMillis()
                    loaded = true
                    systemPromptApplied = false
                }
                println("[Engine] ✓ Model preloaded: $modelPath")
            } catch (e: Throwable) {
                lastEngineError = e.message ?: "Failed to preload model"
                println("[Engine] ✗ Preload failed: $lastEngineError")
            }
        }.start()

        return true
    }

    fun getModelMetadata(): Map<String, Any> {
        val modelFile = File(modelPath)
        val sizeBytes = if (modelFile.exists() && modelFile.isFile) modelFile.length() else 0L
        val lastSelectedAtMillis = prefs.getLong(lastSelectedAtKey, 0L)

        return mapOf(
            "path" to modelPath,
            "sizeBytes" to sizeBytes,
            "lastSelectedAtMillis" to lastSelectedAtMillis,
        )
    }

    fun setModelPath(newPath: String, onCopyProgress: ((progress: Int) -> Unit)? = null): Boolean {
        val normalized = newPath.trim()
        if (normalized.isEmpty()) {
            lastEngineError = "Model path is empty."
            return false
        }

        val modelFile = File(normalized)
        val validationError = validateModelFile(modelFile)
        if (validationError != null) {
            lastEngineError = validationError
            return false
        }

        val internalPath = try {
            prepareModelForNativeLoad(modelFile, onCopyProgress)
        } catch (e: Exception) {
            lastEngineError = e.message ?: "Failed to copy model into app storage."
            return false
        }

        if (modelPath != internalPath) {
            close()
            modelPath = internalPath
        }

        prefs.edit()
            .putString(modelPathKey, internalPath)
            .putLong(lastSelectedAtKey, System.currentTimeMillis())
            .apply()

        return true
    }

    @Synchronized
    fun ask(question: String): String {
        val startedAt = System.currentTimeMillis()

        ensureModelInAppStorage()

        if (!isPathInAppStorage(modelPath)) {
            try {
                val migrated = prepareModelForNativeLoad(File(modelPath), null)
                if (migrated != modelPath) {
                    close()
                    modelPath = migrated
                    prefs.edit().putString(modelPathKey, modelPath).apply()
                }
            } catch (e: Exception) {
                lastEngineError = e.message ?: "Failed to prepare model file"
                return "Failed to run local model: $lastEngineError"
            }
        }

        val modelFile = File(modelPath)

        val validationError = validateModelFile(modelFile)
        if (validationError != null) {
            close()
            lastEngineError = validationError
            return "Model cannot be used: $validationError"
        }

        val prompt = buildPrompt(question)
        val output = try {
            runBlocking {
                if (!loaded) {
                    initAttempts += 1
                    ensureModelLoadedWithRecovery(modelPath)
                    successfulInits += 1
                    lastInitAtMillis = System.currentTimeMillis()
                    loaded = true
                    systemPromptApplied = false
                }

                val promptToProcess = if (prompt.contains(activeSystemPrompt)) prompt else "$activeSystemPrompt\n\n$prompt"

                val result = StringBuilder()
                if (maxGenerationDurationMs > 0) {
                    withTimeout(maxGenerationDurationMs.toLong()) {
                        inferenceEngine.sendUserPrompt(
                            message = promptToProcess,
                            predictLength = maxOutputTokens,
                        ).collect { token ->
                            result.append(token)
                        }
                    }
                } else {
                    inferenceEngine.sendUserPrompt(
                        message = promptToProcess,
                        predictLength = maxOutputTokens,
                    ).collect { token ->
                        result.append(token)
                    }
                }

                systemPromptApplied = true

                result.toString().ifBlank {
                    "I could not generate an answer. Please try again."
                }
            }
        } catch (e: Throwable) {
            val stateName = inferenceEngine.state.value.javaClass.simpleName
            lastEngineError = "${e.message ?: "unknown runtime error"} (state=$stateName)"
            // KEEP MODEL LOADED: Don't unload on transient errors
            return "Failed to run local model: ${lastEngineError}"
        }

        totalInferenceCount += 1
        lastInferenceAtMillis = System.currentTimeMillis()
        lastInferenceDurationMs = lastInferenceAtMillis - startedAt
        totalInferenceDurationMs += lastInferenceDurationMs
        minInferenceDurationMs = minOf(minInferenceDurationMs, lastInferenceDurationMs)
        maxInferenceDurationMs = maxOf(maxInferenceDurationMs, lastInferenceDurationMs)
        lastPromptChars = prompt.length
        lastOutputChars = output.length

        lastEngineError = ""

        return output
    }

    @Synchronized
    fun askStream(question: String, onToken: (String) -> Unit): String {
        val startedAt = System.currentTimeMillis()

        ensureModelInAppStorage()

        if (!isPathInAppStorage(modelPath)) {
            try {
                val migrated = prepareModelForNativeLoad(File(modelPath), null)
                if (migrated != modelPath) {
                    close()
                    modelPath = migrated
                    prefs.edit().putString(modelPathKey, modelPath).apply()
                }
            } catch (e: Exception) {
                lastEngineError = e.message ?: "Failed to prepare model file"
                return "Failed to run local model: $lastEngineError"
            }
        }

        val modelFile = File(modelPath)
        val validationError = validateModelFile(modelFile)
        if (validationError != null) {
            close()
            lastEngineError = validationError
            return "Model cannot be used: $validationError"
        }

        val prompt = buildPrompt(question)
        val output = try {
            runBlocking {
                if (!loaded) {
                    initAttempts += 1
                    ensureModelLoadedWithRecovery(modelPath)
                    successfulInits += 1
                    lastInitAtMillis = System.currentTimeMillis()
                    loaded = true
                    systemPromptApplied = false
                }

                val promptToProcess = if (prompt.contains(activeSystemPrompt)) prompt else "$activeSystemPrompt\n\n$prompt"

                val result = StringBuilder()
                val collector: (String) -> Unit = { token ->
                    result.append(token)
                    onToken(token)
                }

                if (maxGenerationDurationMs > 0) {
                    withTimeout(maxGenerationDurationMs.toLong()) {
                        inferenceEngine.sendUserPrompt(
                            message = promptToProcess,
                            predictLength = maxOutputTokens,
                        ).collect(collector)
                    }
                } else {
                    inferenceEngine.sendUserPrompt(
                        message = promptToProcess,
                        predictLength = maxOutputTokens,
                    ).collect(collector)
                }
                
                systemPromptApplied = true

                result.toString().ifBlank {
                    "I could not generate an answer. Please try again."
                }
            }
        } catch (e: Throwable) {
            val stateName = inferenceEngine.state.value.javaClass.simpleName
            lastEngineError = "${e.message ?: "unknown runtime error"} (state=$stateName)"
            // KEEP MODEL LOADED: Don't unload on transient errors
            return "Failed to run local model: ${lastEngineError}"
        }

        totalInferenceCount += 1
        lastInferenceAtMillis = System.currentTimeMillis()
        lastInferenceDurationMs = lastInferenceAtMillis - startedAt
        totalInferenceDurationMs += lastInferenceDurationMs
        minInferenceDurationMs = minOf(minInferenceDurationMs, lastInferenceDurationMs)
        maxInferenceDurationMs = maxOf(maxInferenceDurationMs, lastInferenceDurationMs)
        lastPromptChars = prompt.length
        lastOutputChars = output.length
        lastEngineError = ""

        return output
    }

    private suspend fun ensureModelLoadedWithRecovery(path: String) {
        try {
            inferenceEngine.loadModel(path)
            return
        } catch (e: IllegalStateException) {
            val msg = e.message.orEmpty()
            if (!msg.contains("Cannot load model in")) {
                throw e
            }
            // Recover from stale intermediate states left by prior failed attempts.
            runCatching { inferenceEngine.cleanUp() }
            inferenceEngine.loadModel(path)
            return
        }
    }

    // STREAMING FAST PATH: Real-time display + fast native generation
    // Uses the optimized streaming which emits in batches (5-10 tokens) not per-token
    @Synchronized
    fun askStreamFast(question: String, onToken: (String) -> Unit): String {
        Log.i("LLM", "[Engine] askStreamFast ENTER question='${question.take(40)}'")
        val startedAt = System.currentTimeMillis()
        fun elapsed(): String = "+${System.currentTimeMillis() - startedAt}ms"
        
        println("[Engine] [${elapsed()}] 📝 Question: '${question.take(50)}...'")
        println("[Engine] [${elapsed()}] 🔄 System prompt applied: $systemPromptApplied")

        ensureModelInAppStorage()

        if (!isPathInAppStorage(modelPath)) {
            try {
                val migrated = prepareModelForNativeLoad(File(modelPath), null)
                if (migrated != modelPath) {
                    close()
                    modelPath = migrated
                    prefs.edit().putString(modelPathKey, modelPath).apply()
                }
            } catch (e: Exception) {
                lastEngineError = e.message ?: "Failed to prepare model file"
                return "Failed to run local model: $lastEngineError"
            }
        }

        val modelFile = File(modelPath)
        val validationError = validateModelFile(modelFile)
        if (validationError != null) {
            close()
            lastEngineError = validationError
            return "Model cannot be used: $validationError"
        }

        val activeModel = getActiveModelName()
        val activeTemplate = getChatTemplateName()
        val modelSizeBytes = if (modelFile.exists()) modelFile.length() else 0L
        val modelSizeGbStr = String.format(java.util.Locale.US, "%.2fGB", modelSizeBytes.toDouble() / (1024 * 1024 * 1024))

        val output = try {
            runBlocking {
                // Load model if needed
                if (!loaded) {
                    println("[Engine] [${elapsed()}] 🚀 Loading model for first time...")
                    val loadStart = System.currentTimeMillis()
                    initAttempts += 1
                    ensureModelLoadedWithRecovery(modelPath)
                    successfulInits += 1
                    val loadTimeMs = System.currentTimeMillis() - loadStart
                    lastInitAtMillis = System.currentTimeMillis()
                    loaded = true
                    systemPromptApplied = false
                    println("[Engine] [${elapsed()}] ✓ Model loaded in ${loadTimeMs}ms ($activeModel, $modelSizeGbStr)")
                    println("[MODEL] ACTIVE_MODEL=$activeModel")
                    println("[MODEL] MODEL_PATH=$modelPath")
                    println("[MODEL] CHAT_TEMPLATE=$activeTemplate")
                } else {
                    println("[Engine] [${elapsed()}] 📦 Model already loaded, using cached instance ($activeModel)")
                }

                // TERMUX-STYLE OPTIMIZATION: Combine system + user on first question
                // Since the Dart layer (HybridInferenceService) already provides the complete
                // system prompt and context, we do NOT prepend activeSystemPrompt here 
                // to avoid double-prompting and saving 30-40s of redundant KV cache computation.
                // If Dart already formatted the prompt with a chat template
                // (ChatML: starts with <|im_start|>, or Llama-2: starts with <s>[INST])
                // pass it verbatim — the native C++ layer will see the full formatted
                // prompt as the user turn and NOT prepend an extra system block.
                val trimmedQ = question.trim()
                val isPreFormatted = trimmedQ.startsWith("<|im_start|") ||
                    trimmedQ.startsWith("<s>[INST]") ||
                    trimmedQ.startsWith("<start_of_turn>")

                val promptToProcess = if (isPreFormatted) {
                    println("[Engine] [${elapsed()}] 📜 Pre-formatted prompt detected ($activeTemplate)")
                    if (activeTemplate == "Gemma" && trimmedQ.contains("<|im_start|>")) {
                        // Translate ChatML format to Gemma native turn tokens
                        val systemRegex = Regex("""<\|im_start\|>system\s*([\s\S]*?)<\|im_end\|>""")
                        val userRegex = Regex("""<\|im_start\|>user\s*([\s\S]*?)<\|im_end\|>""")
                        val sysMatch = systemRegex.find(trimmedQ)?.groupValues?.get(1)?.trim().orEmpty()
                        val userMatch = userRegex.find(trimmedQ)?.groupValues?.get(1)?.trim().orEmpty()

                        val combinedUser = if (sysMatch.isNotEmpty() && userMatch.isNotEmpty()) {
                            "$sysMatch\n\n$userMatch"
                        } else if (userMatch.isNotEmpty()) {
                            userMatch
                        } else {
                            trimmedQ.replace(Regex("""<\|im_start\|>\w*"""), "").replace("<|im_end|>", "").replace("<|im_start|>assistant", "").trim()
                        }
                        println("[Engine] [${elapsed()}] 🔄 Converted ChatML prompt to Gemma native tokens (<start_of_turn>user ...)")
                        "<start_of_turn>user\n$combinedUser<end_of_turn>\n<start_of_turn>model\n"
                    } else {
                        trimmedQ
                    }
                } else if (!systemPromptApplied) {
                    println("[Engine] [${elapsed()}] 🔗 Q1: Processing raw prompt from Dart layer")
                    trimmedQ
                } else {
                    println("[Engine] [${elapsed()}] ⚡ Q2+: Processing user only (system cached)")
                    trimmedQ
                }

                // Use the proven streaming path for stability on physical devices.
                val genStart = System.currentTimeMillis()
                val result = StringBuffer()
                var tokenCount = 0
                var firstTokenAt = 0L

                println("[Engine] [${elapsed()}] [TRACE] THREAD=${Thread.currentThread().name}")
                println("[Engine] [${elapsed()}] [TRACE] PROMPT_LENGTH=${promptToProcess.length}")
                println("[Engine] [${elapsed()}] [TRACE] PROMPT_FIRST_200=${promptToProcess.take(200)}")
                println("[Engine] [${elapsed()}] [TRACE] BEFORE_SEND_USER_PROMPT")
                println("[Engine] [${elapsed()}] [TRACE] SEND_USER_PROMPT_START")

                val flow = inferenceEngine.sendUserPrompt(
                    message = promptToProcess,
                    predictLength = maxOutputTokens,
                )

                println("[Engine] [${elapsed()}] [TRACE] SEND_USER_PROMPT_FLOW_CREATED")
                println("[Engine] [${elapsed()}] [TRACE] COLLECT_START (evaluating prompt on CPU/NPU...)")

                flow.collect { token ->
                    tokenCount++
                    if (firstTokenAt == 0L) {
                        firstTokenAt = System.currentTimeMillis()
                        val ttft = firstTokenAt - genStart
                        println("[Engine] [${elapsed()}] [TRACE] FIRST_TOKEN_AFTER_MS=${ttft} (TTFT: ${ttft}ms)")
                    }
                    if (tokenCount <= 5 || tokenCount % 20 == 0) {
                        println("[Engine] [${elapsed()}] [TRACE] TOKEN_RECEIVED count=$tokenCount length=${token.length} thread=${Thread.currentThread().name}")
                    }
                    result.append(token)
                    onToken(token)

                    // Guard against runaway loops like repeated A:/B: turns or repeated syllables.
                    val current = result.toString()
                    if (isRunawayRepetition(current)) {
                        println("[Engine] [${elapsed()}] 🛑 Repetition loop detected, stopping generation")
                        inferenceEngine.stopGeneration()
                    }
                }

                println("[Engine] [${elapsed()}] [TRACE] COLLECT_COMPLETE")
                val genTimeMs = System.currentTimeMillis() - genStart
                println("[Engine] [${elapsed()}] [TRACE] TOTAL_GENERATION_TIME=${genTimeMs}ms (prefill + generation)")
                println("[Engine] [${elapsed()}] [TRACE] TOKENS_GENERATED=$tokenCount")
                
                // Mark system as applied after first question processes it
                systemPromptApplied = true
                
                // POST-PROCESS: Strip chat-template markers that may leak into output
                var cleanedResponse = stripTemplateArtifacts(result.toString()).trim()
                    .takeIf { it.isNotEmpty() } ?: "I could not generate an answer. Please try again."

                // Remove question patterns that model might generate (self-questioning)
                // Stop at "Q:" or "Question:" or "?" followed by user response pattern
                val questionStartPatterns = listOf(
                    Regex("\\n\\s*Q\\d*:\\s.*", RegexOption.DOT_MATCHES_ALL),
                    Regex("\\n\\s*Question:\\s.*", RegexOption.DOT_MATCHES_ALL),
                    Regex("\\n\\s*\\?\\s*[A-Z].*", RegexOption.DOT_MATCHES_ALL),
                    Regex("\\n\\s*Assistant:\\s.*", RegexOption.DOT_MATCHES_ALL),
                    Regex("\\n\\s*User:\\s.*", RegexOption.DOT_MATCHES_ALL),
                    Regex("\\n\\s*A:\\s.*", RegexOption.DOT_MATCHES_ALL),
                    Regex("\\n\\s*B:\\s.*", RegexOption.DOT_MATCHES_ALL),
                    Regex("\\n\\n[A-Z][^.!?]*\\?", RegexOption.DOT_MATCHES_ALL)
                )

                for (pattern in questionStartPatterns) {
                    val match = pattern.find(cleanedResponse)
                    if (match != null) {
                        cleanedResponse = cleanedResponse.substring(0, match.range.first).trim()
                        break
                    }
                }

                // Remove trailing incomplete sentences
                if (cleanedResponse.endsWith("?")) {
                    cleanedResponse = cleanedResponse.substringBeforeLast("?").trim()
                }

                // Remove incomplete words at end
                if (cleanedResponse.lastOrNull()?.isLetter() == true) {
                    val lastSpace = cleanedResponse.lastIndexOf(' ')
                    if (lastSpace > 0 && cleanedResponse.length - lastSpace < 3) {
                        cleanedResponse = cleanedResponse.substring(0, lastSpace).trim()
                    }
                }
                
                println("[Engine] [${elapsed()}] 💬 Generated ${cleanedResponse.length} chars in ${genTimeMs}ms")

                cleanedResponse.ifBlank {
                    "I could not generate an answer. Please try again."
                }
            }
        } catch (e: Throwable) {
            val stateName = inferenceEngine.state.value.javaClass.simpleName
            lastEngineError = "${e.message ?: "unknown runtime error"} (state=$stateName)"
            Log.e("LLM", "[Engine] askStreamFast ERROR: $lastEngineError", e)
            println("[Engine] [${elapsed()}] ❌ Error: $lastEngineError")
            // KEEP MODEL LOADED: Don't unload on transient errors
            // Model is now permanently cached in native memory
            return "Failed to run local model: ${lastEngineError}"
        }
        
        val elapsedMs = System.currentTimeMillis() - startedAt
        println("[Engine] [${elapsed()}] ✅ Done in ${elapsedMs}ms | Output: ${output.length} chars")

        totalInferenceCount += 1
        lastInferenceAtMillis = System.currentTimeMillis()
        lastInferenceDurationMs = lastInferenceAtMillis - startedAt
        totalInferenceDurationMs += lastInferenceDurationMs
        minInferenceDurationMs = minOf(minInferenceDurationMs, lastInferenceDurationMs)
        maxInferenceDurationMs = maxOf(maxInferenceDurationMs, lastInferenceDurationMs)
        lastPromptChars = question.length
        lastOutputChars = output.length
        lastEngineError = ""

        return output
    }

    private fun isRunawayRepetition(text: String): Boolean {
        if (text.length < 80) {
            return false
        }

        val lower = text.lowercase()
        val repeatedTurns = Regex("(?:\\n\\s*(a|b):\\s*){3,}").containsMatchIn(lower)
        if (repeatedTurns) {
            return true
        }

        // Detect repeated short chunks at the tail: e.g., "hinghinghing..."
        val window = lower.takeLast(96)
        if (window.length < 24) {
            return false
        }

        for (chunkLen in 3..8) {
            if (window.length < chunkLen * 4) continue
            val chunk = window.takeLast(chunkLen)
            val repeated = chunk.repeat(4)
            if (window.contains(repeated)) {
                return true
            }
        }

        return false
    }

    fun runSelfTest(): Map<String, Any> {
        val answer = ask("Respond with only: ok")

        val ok = !answer.contains("failed", ignoreCase = true) &&
            !answer.contains("timed out", ignoreCase = true) &&
            !answer.contains("not initialized", ignoreCase = true)

        return mapOf(
            "ok" to ok,
            "answerPreview" to answer.take(120),
            "status" to getEngineStatus(),
        )
    }

    @Synchronized
    fun runInferenceHealthCheck(): Map<String, Any> {
        val startedAt = System.currentTimeMillis()
        var firstTokenAt = 0L
        var tokenCount = 0

        val oldMaxTokens = maxOutputTokens
        val oldTimeoutMs = maxGenerationDurationMs
        val oldPrompt = activeSystemPrompt
        val oldSystemPromptApplied = systemPromptApplied

        return try {
            // Use a fast, deterministic probe so health check validates real inference quickly.
            maxOutputTokens = 48
            maxGenerationDurationMs = 45000
            activeSystemPrompt =
                "You are a health-check probe. Reply with exactly: MODEL_OK"
            systemPromptApplied = false

            val answer = askStreamFast("Reply with exactly: MODEL_OK") { token ->
                if (firstTokenAt == 0L && token.isNotEmpty()) {
                    firstTokenAt = System.currentTimeMillis()
                }
                if (token.isNotEmpty()) {
                    tokenCount += 1
                }
            }

            val totalMs = System.currentTimeMillis() - startedAt
            val ttftMs = if (firstTokenAt > 0L) firstTokenAt - startedAt else -1L
            val cleaned = answer.trim()
            val ok = cleaned.isNotEmpty() &&
                !cleaned.startsWith("Failed to", ignoreCase = true) &&
                !cleaned.startsWith("Model cannot", ignoreCase = true)

            mapOf(
                "ok" to ok,
                "answerPreview" to cleaned.take(180),
                "ttftMs" to ttftMs,
                "totalMs" to totalMs,
                "tokenCount" to tokenCount,
                "status" to getEngineStatus(),
            )
        } catch (e: Throwable) {
            mapOf(
                "ok" to false,
                "answerPreview" to (e.message ?: "Inference probe failed"),
                "ttftMs" to -1L,
                "totalMs" to (System.currentTimeMillis() - startedAt),
                "tokenCount" to tokenCount,
                "status" to getEngineStatus(),
            )
        } finally {
            maxOutputTokens = oldMaxTokens
            maxGenerationDurationMs = oldTimeoutMs
            activeSystemPrompt = oldPrompt
            systemPromptApplied = oldSystemPromptApplied
        }
    }

    fun close() {
        if (!loaded) {
            return
        }

        try {
            inferenceEngine.cleanUp()
        } catch (_: Throwable) {
            // Best-effort cleanup; status is reset below.
        } finally {
            loaded = false
            systemPromptApplied = false
        }
    }

    fun resetEngine(): Map<String, Any> {
        close()
        lastEngineError = ""
        return getEngineStatus()
    }

    fun stopGeneration(): Map<String, Any> {
        inferenceEngine.stopGeneration()
        return getEngineStatus()
    }

    fun runPerformanceProbe(iterations: Int): Map<String, Any> {
        val safeIters = iterations.coerceIn(1, 5)
        val runs = mutableListOf<Long>()
        var lastPreview = ""

        for (i in 0 until safeIters) {
            val started = System.currentTimeMillis()
            val output = ask("What is 12 + 8?")
            val elapsed = System.currentTimeMillis() - started
            runs.add(elapsed)
            lastPreview = output.take(160)
        }

        val minMs = runs.minOrNull() ?: 0L
        val maxMs = runs.maxOrNull() ?: 0L
        val avgMs = if (runs.isEmpty()) 0L else runs.sum() / runs.size

        return mapOf(
            "iterations" to safeIters,
            "minMs" to minMs,
            "maxMs" to maxMs,
            "avgMs" to avgMs,
            "lastOutputPreview" to lastPreview,
            "status" to getEngineStatus(),
        )
    }

    private fun ensureModelInAppStorage() {
        if (modelPath != File(context.filesDir, "models/$modelFileName").absolutePath) {
            return
        }

        val target = File(modelPath)
        if (target.exists()) {
            return
        }

        target.parentFile?.mkdirs()

        val sourceCandidates = listOf(
            File("/sdcard/Download/$modelFileName"),
            File("/storage/emulated/0/Download/$modelFileName"),
            File(context.getExternalFilesDir(null), "Download/$modelFileName"),
        )

        for (source in sourceCandidates) {
            if (!source.exists() || !source.isFile) {
                continue
            }

            try {
                copyFile(source, target)
                if (target.exists() && target.length() > 0L) {
                    return
                }
            } catch (_: Exception) {
                // Continue trying the next candidate source path.
            }
        }
    }

    private fun copyFile(source: File, target: File, onProgress: ((Int) -> Unit)? = null) {
        val totalBytes = source.length()
        val bufferSize = 1024 * 1024 // 1MB chunks

        FileInputStream(source).use { input ->
            FileOutputStream(target).use { output ->
                var copiedBytes = 0L
                val buffer = ByteArray(bufferSize)
                var bytesRead = input.read(buffer)

                while (bytesRead > 0) {
                    output.write(buffer, 0, bytesRead)
                    copiedBytes += bytesRead

                    val progressPercent = if (totalBytes > 0L) {
                        (copiedBytes * 100 / totalBytes).toInt()
                    } else {
                        100
                    }
                    onProgress?.invoke(progressPercent)

                    bytesRead = input.read(buffer)
                }
            }
        }
    }

    private fun isPathInAppStorage(path: String): Boolean {
        val modelsDir = File(context.filesDir, "models")
        return path.startsWith(modelsDir.absolutePath)
    }

    private fun prepareModelForNativeLoad(source: File, onCopyProgress: ((Int) -> Unit)? = null): String {
        val modelsDir = File(context.filesDir, "models")
        modelsDir.mkdirs()

        if (source.absolutePath.startsWith(modelsDir.absolutePath)) {
            onCopyProgress?.invoke(100)
            return source.absolutePath
        }

        val safeName = source.name.ifBlank { "selected-model.gguf" }
        val target = File(modelsDir, safeName)

        val shouldCopy = !target.exists() || target.length() != source.length()
        if (shouldCopy) {
            onCopyProgress?.invoke(0)
            copyFile(source, target, onCopyProgress)
            onCopyProgress?.invoke(100)
        } else {
            onCopyProgress?.invoke(100)
        }

        val copiedError = validateModelFile(target)
        if (copiedError != null) {
            throw IllegalStateException("Model copy invalid: $copiedError")
        }

        return target.absolutePath
    }

    private fun validateModelFile(modelFile: File): String? {
        if (!modelFile.exists() || !modelFile.isFile) {
            return "Selected model file does not exist."
        }

        val path = modelFile.absolutePath
        if (!path.lowercase().endsWith(".gguf")) {
            return "Selected file is not a GGUF model."
        }

        AndroidModelCompatibility.dflashDraftError(modelFile.name)?.let { return it }

        val size = modelFile.length()
        if (size < 1024L * 1024L) {
            return "Selected model file is too small/corrupted."
        }

        return null
    }

    private fun buildPrompt(question: String): String {
        return question.trim()
    }

    /**
     * Strips residual chat-template control tokens from model output.
     * These leak when the model echoes parts of the prompt or generates
     * a new turn marker before the stop marker triggers.
     */
    private fun stripTemplateArtifacts(text: String): String {
        val artifacts = listOf(
            "<|im_start|>assistant", "<|im_start|>user", "<|im_start|>system",
            "<|im_start|>", "<|im_end|>",
            "<start_of_turn>model", "<start_of_turn>user", "<end_of_turn>",
            "[/INST]", "<<SYS>>", "<</SYS>>", "</s>",
        )
        var cleaned = text
        for (artifact in artifacts) {
            cleaned = cleaned.replace(artifact, "")
        }
        return cleaned.trimStart('\n', '\r', ' ')
    }

}