import '../data/local/chat_memory_policy_repository.dart';
import '../../translation/data/local/translation_engine_config_service.dart';
import '../data/local/linux_llm_config_service.dart';
import 'tutor_message.dart';

class ChatViewState {
  const ChatViewState({
    this.messages = const [],
    this.isGenerating = false,
    this.isEmbedding = false,
    this.isBootstrapping = true,
    this.chatMode = 'fast',
    required this.memoryPolicy,
    required this.translationConfig,
    required this.linuxConfig,
    this.engineLoaded = false,
    this.backendConnected = false,
    this.liveEstimatedTokens = 0,
    this.liveTokensPerSec = 0,
    this.inferenceLog = 'Inference idle.',
    this.benchmarkLog = 'No benchmark run yet.',
    this.runningBenchmark = false,
    this.totalChunks = 0,
    this.indexedChunks = 0,
    this.questionsAsked = 0,
    this.sessionId,
    this.error,
  });

  final List<TutorMessage> messages;
  final bool isGenerating;
  final bool isEmbedding;
  final bool isBootstrapping;
  final String chatMode;
  final ChatMemoryPolicy memoryPolicy;
  final TranslationEngineConfig translationConfig;
  final LinuxLlmConfig linuxConfig;
  final bool engineLoaded;
  final bool backendConnected;
  final int liveEstimatedTokens;
  final int liveTokensPerSec;
  final String inferenceLog;
  final String benchmarkLog;
  final bool runningBenchmark;
  final int totalChunks;
  final int indexedChunks;
  final int questionsAsked;
  final String? sessionId;
  final String? error;

  bool get hasChapterRagContent => totalChunks > 0;
  String get chatScopeLabel => hasChapterRagContent ? 'Chapter mode' : 'General mode';

  ChatViewState copyWith({
    List<TutorMessage>? messages,
    bool? isGenerating,
    bool? isEmbedding,
    bool? isBootstrapping,
    String? chatMode,
    ChatMemoryPolicy? memoryPolicy,
    TranslationEngineConfig? translationConfig,
    LinuxLlmConfig? linuxConfig,
    bool? engineLoaded,
    bool? backendConnected,
    int? liveEstimatedTokens,
    int? liveTokensPerSec,
    String? inferenceLog,
    String? benchmarkLog,
    bool? runningBenchmark,
    int? totalChunks,
    int? indexedChunks,
    int? questionsAsked,
    String? sessionId,
    String? error,
  }) {
    return ChatViewState(
      messages: messages ?? this.messages,
      isGenerating: isGenerating ?? this.isGenerating,
      isEmbedding: isEmbedding ?? this.isEmbedding,
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      chatMode: chatMode ?? this.chatMode,
      memoryPolicy: memoryPolicy ?? this.memoryPolicy,
      translationConfig: translationConfig ?? this.translationConfig,
      linuxConfig: linuxConfig ?? this.linuxConfig,
      engineLoaded: engineLoaded ?? this.engineLoaded,
      backendConnected: backendConnected ?? this.backendConnected,
      liveEstimatedTokens: liveEstimatedTokens ?? this.liveEstimatedTokens,
      liveTokensPerSec: liveTokensPerSec ?? this.liveTokensPerSec,
      inferenceLog: inferenceLog ?? this.inferenceLog,
      benchmarkLog: benchmarkLog ?? this.benchmarkLog,
      runningBenchmark: runningBenchmark ?? this.runningBenchmark,
      totalChunks: totalChunks ?? this.totalChunks,
      indexedChunks: indexedChunks ?? this.indexedChunks,
      questionsAsked: questionsAsked ?? this.questionsAsked,
      sessionId: sessionId ?? this.sessionId,
      error: error,
    );
  }
}
