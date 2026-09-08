import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import '../../../core/theme/idp_theme.dart';
import 'package:file_picker/file_picker.dart';
import '../../../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../course/domain/course_tree.dart';
import '../application/chat_latency_benchmark_service.dart';
import '../application/conversation_context_builder.dart';
import '../application/reasoning_output_filter.dart';
import '../application/streaming_output_normalizer.dart';
import '../application/simple_ai_chat_component.dart';
import '../application/tutor_prompt_builder.dart';
import '../data/platform_tutor_inference_gateway.dart';
import '../data/tutor_inference_gateway.dart';
import '../data/local/chat_memory_policy_repository.dart';
import '../data/local/linux_llm_config_service.dart';
import '../../network/application/distributed_service_composer.dart';
import '../domain/tutor_message.dart';
import '../../translation/application/separate_translation_layer_service.dart';
import '../../translation/data/local/translation_engine_config_service.dart';
import '../../translation/domain/translation_engine_catalog.dart';
import '../../rag/application/embedding_index_service.dart';
import '../../rag/application/simple_rag_service.dart';
import '../../rag/data/local/embedding_index_repository.dart';
import '../../rag/data/local/rag_repository.dart';
import '../data/local/chat_session_repository.dart';
import '../data/llm_admin_channel_service.dart';
import '../../network/application/session_state.dart';
import '../../network/application/intent_detector.dart';
import '../../progress/data/local/progress_repository.dart';
import '../../shared/application/offline_error_taxonomy.dart';
import 'asset_message_widgets.dart';
import 'formatted_text_widget.dart';
import '../../language/providers/language_provider.dart';
import '../../tutor/screens/voice_tutor_screen.dart';

class ChapterChatScreen extends StatefulWidget {
  const ChapterChatScreen({
    required this.course,
    required this.subject,
    required this.chapter,
    super.key,
  });

  final Course course;
  final Subject subject;
  final Chapter chapter;

  @override
  State<ChapterChatScreen> createState() => _ChapterChatScreenState();
}

class _ChapterChatScreenState extends State<ChapterChatScreen> {
  static final RegExp _ansiEscape = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
  bool _androidNativeFastPath = true;
  int _lastUiUpdateAtMs = 0;

  final TutorInferenceGateway _gateway = PlatformTutorInferenceGateway();
  late final ChatLatencyBenchmarkService _benchmarkService =
      ChatLatencyBenchmarkService(gateway: _gateway);
  final DistributedServiceComposer _distributedServiceComposer =
      DistributedServiceComposer();
  final SimpleAiChatComponent _simpleAiComponent =
      const SimpleAiChatComponent();
  final TutorPromptBuilder _promptBuilder = TutorPromptBuilder();
  final ConversationContextBuilder _conversationContextBuilder =
      const ConversationContextBuilder();
  final SessionState _sessionState = SessionState();
  final RagRepository _ragRepository = RagRepository();
  late final SimpleRagService _simpleRagService = SimpleRagService(
    repository: _ragRepository,
  );
  late final EmbeddingIndexService _embeddingIndexService =
      EmbeddingIndexService(
        ragRepository: _ragRepository,
        embeddingRepository: EmbeddingIndexRepository(),
      );
  final ChatSessionRepository _chatSessionRepository = ChatSessionRepository();
  final ChatMemoryPolicyRepository _chatMemoryPolicyRepository =
      ChatMemoryPolicyRepository();
  final ProgressRepository _progressRepository = ProgressRepository();
  final LlmAdminChannelService _llmAdminChannelService =
      LlmAdminChannelService();
  final LinuxLlmConfigService _linuxConfigService = LinuxLlmConfigService();
  final TranslationEngineConfigService _translationConfigService =
      TranslationEngineConfigService();
  late final SeparateTranslationLayerService _translationService =
      SeparateTranslationLayerService(gateway: _gateway);
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<TutorMessage> _messages = [];
  bool _isGenerating = false;
  bool _isEmbedding = false;
  bool _isBootstrapping = true;
  String _languageCode = LanguageProvider.shared.languageCode;
  String? _sessionId;
  int _questionsAsked = 0;
  int _totalChunks = 0;
  int _indexedChunks = 0;
  int _generationMaxTokens = 256;
  String _chatMode = 'fast';
  DateTime? _inferenceStartedAt;
  int _liveEstimatedTokens = 0;
  int _liveTokensPerSec = 0;
  int _lastInferenceMs = 0;
  int _lastInferenceTokens = 0;
  int _lastInferenceTokensPerSec = 0;
  String _inferenceLog = 'Inference idle.';
  String _benchmarkLog = 'No benchmark run yet.';
  bool _runningBenchmark = false;
  ChatMemoryPolicy? _memoryPolicy;
  TranslationEngineConfig _translationConfig = TranslationEngineConfig.defaults;

  bool _engineLoaded = false;
  String _linuxStatusMessage = 'Linux model not validated yet.';
  LinuxLlmConfig _linuxConfig = LinuxLlmConfig.defaults;
  Timer? _engineStatusTimer;
  Timer? _backendStatusTimer;
  StreamSubscription<Map<String, dynamic>>? _metricsSubscription;
  StreamSubscription<String>? _activeResponseSubscription;
  int _lastAutoScrollAtMs = 0;
  bool _backendConnected = false;
  late final LanguageProvider _languageProvider = LanguageProvider()
    ..initialize();

  bool get _hasChapterRagContent => _totalChunks > 0;
  String get _chatScopeLabel =>
      _hasChapterRagContent ? 'Chapter mode' : 'General mode';

  static const Map<String, String> _chatModeLabels = <String, String>{
    'fast': 'Fast',
    'balanced': 'Balanced',
    'detailed': 'Detailed',
  };

  static const List<int> _memoryWindowOptions = <int>[4, 8, 12, 16, 20];
  static const List<int> _semanticTopKOptions = <int>[0, 1, 2, 3, 4];
  static const List<int> _inactivityMinutesOptions = <int>[15, 30, 45, 60, 90];

  @override
  void initState() {
    super.initState();
    _bootstrapSession();
    _loadTranslationConfig();
    _listenInferenceMetrics();
    _startBackendStatusPolling();
    if (_isLinux) {
      _loadLinuxConfig();
    } else {
      _startEngineStatusPolling();
    }
  }

  @override
  void dispose() {
    _metricsSubscription?.cancel();
    _activeResponseSubscription?.cancel();
    _inputController.dispose();
    _notesController.dispose();
    _scrollController.dispose();
    _engineStatusTimer?.cancel();
    _backendStatusTimer?.cancel();
    super.dispose();
  }

  bool get _isLinux => Platform.isLinux;

  Future<void> _loadTranslationConfig() async {
    final config = await _translationConfigService.load();
    if (!mounted) {
      return;
    }
    setState(() {
      _translationConfig = config;
    });
  }

  Future<void> _loadLinuxConfig() async {
    final config = await _linuxConfigService.load();
    final validation = await _linuxConfigService.validate(config);

    LinuxLlmConfig nextConfig = config;
    final resolvedExec = validation.resolvedExecutablePath;
    if (resolvedExec != null && resolvedExec != config.executablePath) {
      nextConfig = await _linuxConfigService.update(
        executablePath: resolvedExec,
      );
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _linuxConfig = nextConfig;
      _engineLoaded = validation.ready;
      _linuxStatusMessage = validation.message;
    });
  }

  Future<void> _syncDistributedClassroomState() async {
    final sessionId = _sessionId;
    if (sessionId == null || !_distributedServiceComposer.isInitialized) {
      return;
    }

    final recovery = _distributedServiceComposer.classroomRecoveryCoordinator;
    final persistence = _distributedServiceComposer.sessionPersistenceManager;

    await persistence.saveSession(sessionId, <String, dynamic>{
      'courseId': widget.course.id,
      'subjectId': widget.subject.id,
      'chapterId': widget.chapter.id,
      'languageCode': _languageCode,
      'questionsAsked': _questionsAsked,
      'totalChunks': _totalChunks,
      'indexedChunks': _indexedChunks,
    });

    await recovery.restoreIfNeeded(sessionId);
  }

  Future<void> _pickLinuxModel() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: const ['gguf', 'bin'],
    );
    final path = picked?.files.single.path?.trim();
    if (path == null || path.isEmpty) {
      return;
    }
    final updated = await _linuxConfigService.update(modelPath: path);
    final validation = await _linuxConfigService.validate(updated);
    if (!mounted) {
      return;
    }
    setState(() {
      _linuxConfig = updated;
      _engineLoaded = validation.ready;
      _linuxStatusMessage = validation.message;
    });
  }

  Future<void> _copyModelToAppStorage() async {
    if (!_isLinux) return;
    if (_linuxConfig.modelPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a model file first.')),
      );
      return;
    }

    try {
      setState(() {
        _linuxStatusMessage = 'Copying model to app storage...';
      });
      final newPath = await _linuxConfigService.copyModelToAppStorage(
        _linuxConfig.modelPath,
      );
      final updated = await _linuxConfigService.update(modelPath: newPath);
      final validation = await _linuxConfigService.validate(updated);
      if (!mounted) return;
      setState(() {
        _linuxConfig = updated;
        _engineLoaded = validation.ready;
        _linuxStatusMessage = 'Copied model: ${newPath.split('/').last}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Model copied to app storage.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _linuxStatusMessage = 'Copy failed: $e';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Copy failed: $e')));
    }
  }

  Future<void> _pickLinuxExecutable() async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    final path = picked?.files.single.path?.trim();
    if (path == null || path.isEmpty) {
      return;
    }
    final updated = await _linuxConfigService.update(executablePath: path);
    final validation = await _linuxConfigService.validate(updated);
    if (!mounted) {
      return;
    }
    setState(() {
      _linuxConfig = updated;
      _engineLoaded = validation.ready;
      _linuxStatusMessage = validation.message;
    });
  }

  Future<void> _autoDetectLinuxExecutable() async {
    final detected = await _linuxConfigService.autoDetectExecutable();
    if (detected == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('llama-cli not found. Use Select Llama CLI.'),
        ),
      );
      return;
    }

    final updated = await _linuxConfigService.update(executablePath: detected);
    final validation = await _linuxConfigService.validate(updated);
    if (!mounted) {
      return;
    }
    setState(() {
      _linuxConfig = updated;
      _engineLoaded = validation.ready;
      _linuxStatusMessage = validation.message;
    });
  }

  void _startEngineStatusPolling() {
    // Trigger immediate preload attempt, then poll status
    Future.microtask(() {
      _llmAdminChannelService.preloadModel().ignore();
    });

    _engineStatusTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final status = await _llmAdminChannelService.getEngineStatus();
        if (mounted) {
          setState(() {
            _engineLoaded = status.loaded;
          });
        }
      } catch (e) {
        // Silently ignore polling errors
      }
    });
  }

  void _startBackendStatusPolling() {
    Future.microtask(() => _checkBackendStatus());
    _backendStatusTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkBackendStatus();
    });
  }

  Future<void> _checkBackendStatus() async {
    if (!_distributedServiceComposer.isInitialized) return;
    try {
      final available = await _distributedServiceComposer.backendService
          .isBackendAvailable();
      if (mounted && _backendConnected != available) {
        setState(() {
          _backendConnected = available;
        });
      }
    } catch (_) {}
  }

  void _openVoiceTutor() {
    if (!_backendConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backend not connected. Voice streaming unavailable.'),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceTutorScreen(languageProvider: _languageProvider),
      ),
    );
  }

  void _listenInferenceMetrics() {
    _metricsSubscription = _gateway.metricsStream().listen((metrics) {
      if (!mounted || !_isGenerating) {
        return;
      }

      setState(() {
        _lastInferenceMs = metrics['totalMs'] as int? ?? 0;
        _lastInferenceTokens =
            metrics['tokens'] as int? ?? _liveEstimatedTokens;
        _lastInferenceTokensPerSec =
            metrics['tokensPerSec'] as int? ?? _liveTokensPerSec;
        _inferenceLog =
            'Native metrics: ${_lastInferenceMs}ms | $_lastInferenceTokens tokens | $_lastInferenceTokensPerSec tok/s';
      });
    });
  }

  Future<void> _applyChatMode(String mode, {bool showFeedback = true}) async {
    const modeConfigs = <String, Map<String, int>>{
      'fast': <String, int>{'maxTokens': 512, 'timeoutMs': 120000, 'topK': 2},
      'balanced': <String, int>{
        'maxTokens': 512,
        'timeoutMs': 180000,
        'topK': 3,
      },
      'detailed': <String, int>{
        'maxTokens': 512,
        'timeoutMs': 240000,
        'topK': 4,
      },
    };

    final config = modeConfigs[mode] ?? modeConfigs['balanced']!;
    final maxTokens = config['maxTokens']!;
    final timeoutMs = config['timeoutMs']!;

    final modePrompt = switch (mode) {
      'fast' =>
        'You are a concise offline tutor. Prioritize direct, short, accurate answers in 2-5 sentences.',
      'detailed' =>
        'You are a thorough offline tutor. Provide clear step-by-step explanations with examples when helpful.',
      _ =>
        'You are a helpful tutor. Answer the user clearly and directly with practical explanation.',
    };

    try {
      final updated = await _llmAdminChannelService.updateGenerationConfig(
        maxTokens: maxTokens,
        timeoutMs: timeoutMs,
        systemPrompt: modePrompt,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _chatMode = mode;
        _generationMaxTokens = updated.maxTokens;
      });
      if (showFeedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Chat mode: ${_chatModeLabels[mode] ?? mode} | max ${updated.maxTokens} tokens',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _chatMode = mode;
        _generationMaxTokens = maxTokens;
      });
    }
  }

  Future<void> _openAddNotesDialog() async {
    _notesController.clear();

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Chapter Notes'),
          content: SizedBox(
            width: 480,
            child: TextField(
              controller: _notesController,
              minLines: 6,
              maxLines: 10,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.chatSyllabusNotesHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final text = _notesController.text.trim();
                if (text.isEmpty) {
                  return;
                }

                await RagRepository().ingestChapterNotes(
                  chapterId: widget.chapter.id,
                  sourceTitle: '${widget.chapter.title} - Manual Notes',
                  rawText: text,
                );

                await _refreshEmbeddingStats();

                if (!mounted) {
                  return;
                }

                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Notes indexed for RAG retrieval.'),
                  ),
                );
              },
              child: const Text('Save & Index'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _bootstrapSession() async {
    final sessionId = await _chatSessionRepository.createOrGetSession(
      chapterId: widget.chapter.id,
      languageCode: _languageCode,
    );
    var policy = await _chatMemoryPolicyRepository.getOrCreatePolicy(sessionId);
    final lastMessageAt = await _chatSessionRepository.getLastMessageAt(
      sessionId,
    );

    // Preserve chat conversation history across sessions (only clear if explicit inactivity threshold reached or user manually clears)
    final shouldResetOnOpen = false;
    final shouldResetOnInactivity =
        policy.resetPolicy == SessionResetPolicy.inactivity &&
        lastMessageAt != null &&
        DateTime.now().difference(lastMessageAt).inMinutes >=
            policy.inactivityMinutes;

    if (shouldResetOnOpen || shouldResetOnInactivity) {
      await _chatSessionRepository.clearMessages(sessionId);
      if (shouldResetOnOpen) {
        policy = ChatMemoryPolicy(
          sessionId: policy.sessionId,
          shortTermWindow: policy.shortTermWindow,
          semanticRecallEnabled: policy.semanticRecallEnabled,
          semanticTopK: policy.semanticTopK,
          resetPolicy: SessionResetPolicy.manual,
          inactivityMinutes: policy.inactivityMinutes,
        );
        await _chatMemoryPolicyRepository.savePolicy(policy);
      }
    }

    final existingMessages = await _chatSessionRepository.getMessages(
      sessionId,
    );
    final questionsAsked = await _progressRepository.getQuestionCount(
      chapterId: widget.chapter.id,
    );
    final totalChunks = await _ragRepository.getChunkCountForChapter(
      widget.chapter.id,
    );
    final indexedChunks = await EmbeddingIndexRepository()
        .getIndexedCountForChapter(chapterId: widget.chapter.id);

    var generationMaxTokens = 256;
    try {
      final config = await _llmAdminChannelService.getGenerationConfig();
      generationMaxTokens = config.maxTokens;
    } catch (_) {
      // Keep default when config API is unavailable (non-Android, early init, etc).
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _sessionId = sessionId;
      _memoryPolicy = policy;
      _questionsAsked = questionsAsked;
      _totalChunks = totalChunks;
      _indexedChunks = indexedChunks;
      _generationMaxTokens = generationMaxTokens;
      _messages
        ..clear()
        ..addAll(
          existingMessages.isEmpty
              ? [
                  TutorMessage(
                    text:
                        'You are learning ${widget.chapter.title}. Ask your doubt to start.',
                    isUser: false,
                    timestamp: DateTime.now(),
                  ),
                ]
              : existingMessages,
        );
      _isBootstrapping = false;
    });

    await _syncDistributedClassroomState();
    await _applyChatMode(_chatMode, showFeedback: false);

    if (existingMessages.isEmpty && _messages.isNotEmpty) {
      await _chatSessionRepository.appendMessage(
        sessionId: sessionId,
        isUser: false,
        text: _messages.first.text,
        timestamp: _messages.first.timestamp,
      );
    }
  }

  String _resetPolicyLabel(SessionResetPolicy policy) {
    switch (policy) {
      case SessionResetPolicy.chapterOpen:
        return 'On chapter open';
      case SessionResetPolicy.inactivity:
        return 'On inactivity';
      case SessionResetPolicy.manual:
        return 'Manual only';
    }
  }

  Future<void> _updateMemoryPolicy({
    int? shortTermWindow,
    bool? semanticRecallEnabled,
    int? semanticTopK,
    SessionResetPolicy? resetPolicy,
    int? inactivityMinutes,
  }) async {
    final sessionId = _sessionId;
    final current = _memoryPolicy;
    if (sessionId == null || current == null) {
      return;
    }

    final next = ChatMemoryPolicy(
      sessionId: sessionId,
      shortTermWindow: shortTermWindow ?? current.shortTermWindow,
      semanticRecallEnabled:
          semanticRecallEnabled ?? current.semanticRecallEnabled,
      semanticTopK: semanticTopK ?? current.semanticTopK,
      resetPolicy: resetPolicy ?? current.resetPolicy,
      inactivityMinutes: inactivityMinutes ?? current.inactivityMinutes,
    );

    await _chatMemoryPolicyRepository.savePolicy(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _memoryPolicy = next;
    });
  }

  Future<void> _resetSessionMemoryNow() async {
    final sessionId = _sessionId;
    if (sessionId == null || _isGenerating) {
      return;
    }

    await _chatSessionRepository.clearMessages(sessionId);
    if (!mounted) {
      return;
    }

    final welcome = TutorMessage(
      text:
          'Session memory reset. Ask your next doubt from ${widget.chapter.title}.',
      isUser: false,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages
        ..clear()
        ..add(welcome);
    });

    await _chatSessionRepository.appendMessage(
      sessionId: sessionId,
      isUser: false,
      text: welcome.text,
      timestamp: welcome.timestamp,
    );
  }

  Future<void> _updateTranslationEngine(TranslationEngineId engineId) async {
    final next = await _translationConfigService.update(engineId: engineId);
    if (!mounted) {
      return;
    }
    setState(() {
      _translationConfig = next;
    });

    final selected = TranslationEngineCatalog.byId(engineId);
    if (!selected.implementedInApp) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${selected.label} is catalog-only right now. App will use LLM Prompt Translator fallback.',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _updateShowOriginalTranslation(bool value) async {
    final next = await _translationConfigService.update(
      showOriginalAlongside: value,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _translationConfig = next;
    });
  }

  Future<void> _pickApertiumBinary() async {
    final picked = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    final path = picked?.files.single.path?.trim();
    if (path == null || path.isEmpty) {
      return;
    }
    final next = await _translationConfigService.update(
      apertiumExecutablePath: path,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _translationConfig = next;
    });
  }

  void _showKannadaEngineCatalog() {
    final engines = TranslationEngineCatalog.kannadaEngines();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: engines.length,
            separatorBuilder: (_, _) => const Divider(height: 16),
            itemBuilder: (context, index) {
              final engine = engines[index];
              final status = engine.implementedInApp
                  ? 'available in app'
                  : 'catalog only (not wired yet)';
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(engine.label),
                subtitle: Text('${engine.description}\nStatus: $status'),
                trailing: engine.offlineCapable
                    ? const Icon(Icons.cloud_off_rounded, size: 18)
                    : const Icon(Icons.cloud_rounded, size: 18),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _refreshEmbeddingStats() async {
    final totalChunks = await _ragRepository.getChunkCountForChapter(
      widget.chapter.id,
    );
    final indexedChunks = await EmbeddingIndexRepository()
        .getIndexedCountForChapter(chapterId: widget.chapter.id);

    if (!mounted) {
      return;
    }

    setState(() {
      _totalChunks = totalChunks;
      _indexedChunks = indexedChunks;
    });
  }

  Future<void> _indexEmbeddingsForChapter() async {
    if (_isEmbedding) {
      return;
    }

    setState(() {
      _isEmbedding = true;
    });

    try {
      await for (final progress in _embeddingIndexService.indexChapter(
        chapterId: widget.chapter.id,
      )) {
        if (!mounted) {
          return;
        }

        setState(() {
          _totalChunks = progress.total;
          _indexedChunks = progress.indexed;
        });
      }

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Embedding index updated for this chapter.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isEmbedding = false;
        });
      }
    }
  }

  Future<void> _ask() async {
    final startTime = DateTime.now();
    print('[TRACE] QUESTION_RECEIVED');
    final question = _inputController.text.trim();
    if (question.isEmpty || _isGenerating || _sessionId == null) {
      return;
    }
    FocusScope.of(context).unfocus();

    // ── Cancel any orphaned stream subscription ──
    print(
      '[TRACE] OLD_SUBSCRIPTION_EXISTS=${_activeResponseSubscription != null}',
    );
    if (_activeResponseSubscription != null) {
      await _activeResponseSubscription!.cancel();
      _activeResponseSubscription = null;
      print('[TRACE] SUBSCRIPTION_CANCELLED=true');
    }

    final useAndroidFastPath = Platform.isAndroid && _androidNativeFastPath;

    final localFastReply = _simpleAiComponent.localFastReply(
      question: question,
    );
    if (localFastReply != null) {
      final now = DateTime.now();
      setState(() {
        _messages.add(
          TutorMessage(text: question, isUser: true, timestamp: now),
        );
        _messages.add(
          TutorMessage(text: localFastReply, isUser: false, timestamp: now),
        );
        _inputController.clear();
        _inferenceLog = 'Quick local response.';
      });

      await _progressRepository.recordQuestionAsked(
        chapterId: widget.chapter.id,
      );
      await _progressRepository.recordChatMessage(
        chapterId: widget.chapter.id,
        sessionId: _sessionId!,
      );
      await _progressRepository.recordChatMessage(
        chapterId: widget.chapter.id,
        sessionId: _sessionId!,
      );

      await _chatSessionRepository.appendMessage(
        sessionId: _sessionId!,
        isUser: true,
        text: question,
        timestamp: now,
      );
      await _chatSessionRepository.appendMessage(
        sessionId: _sessionId!,
        isUser: false,
        text: localFastReply,
        timestamp: now,
      );

      _scrollToBottom(animated: true, force: true);
      return;
    }

    final localMathReply = _simpleAiComponent.localMathReply(
      question: question,
    );
    if (localMathReply != null) {
      final now = DateTime.now();
      setState(() {
        _messages.add(
          TutorMessage(text: question, isUser: true, timestamp: now),
        );
        _messages.add(
          TutorMessage(text: localMathReply, isUser: false, timestamp: now),
        );
        _inputController.clear();
        _inferenceLog = 'Quick math response.';
      });

      await _progressRepository.recordQuestionAsked(
        chapterId: widget.chapter.id,
      );
      await _progressRepository.recordChatMessage(
        chapterId: widget.chapter.id,
        sessionId: _sessionId!,
      );
      await _progressRepository.recordChatMessage(
        chapterId: widget.chapter.id,
        sessionId: _sessionId!,
      );

      await _chatSessionRepository.appendMessage(
        sessionId: _sessionId!,
        isUser: true,
        text: question,
        timestamp: now,
      );
      await _chatSessionRepository.appendMessage(
        sessionId: _sessionId!,
        isUser: false,
        text: localMathReply,
        timestamp: now,
      );

      _scrollToBottom(animated: true, force: true);
      return;
    }

    final distributedStreamingReady = _distributedServiceComposer.isInitialized;

    final canUseDistributedBackend = _distributedServiceComposer.isInitialized;
    if (!_engineLoaded && !canUseDistributedBackend) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isLinux
                ? _linuxStatusMessage
                : 'Offline AI model is not ready yet.',
          ),
        ),
      );
      return;
    }

    final needsTranslation = !useAndroidFastPath && _languageCode != 'en';

    final recoveryPrompt = useAndroidFastPath && !distributedStreamingReady
        ? ''
        : _simpleAiComponent.buildRecoveryPrompt(question: question);

    setState(() {
      print("[TRACE] ASSISTANT_MESSAGE_CREATED");
      _messages.add(
        TutorMessage(text: question, isUser: true, timestamp: DateTime.now()),
      );
      _messages.add(
        TutorMessage(text: '', isUser: false, timestamp: DateTime.now()),
      );
      print("[TRACE] MESSAGE_ID=${_messages.length - 1}");
      _isGenerating = true;
      _inferenceStartedAt = DateTime.now();
      _liveEstimatedTokens = 0;
      _liveTokensPerSec = 0;
      _lastInferenceMs = 0;
      _lastInferenceTokens = 0;
      _lastInferenceTokensPerSec = 0;
      _inferenceLog = 'Inference started...';
      _inputController.clear();
    });

    final userTimestamp = _messages[_messages.length - 2].timestamp;
    if (useAndroidFastPath) {
      _persistUserTurnAsync(question: question, timestamp: userTimestamp);
    } else {
      // Record question asked and chat message
      await _progressRepository.recordQuestionAsked(
        chapterId: widget.chapter.id,
      );
      await _progressRepository.recordChatMessage(
        chapterId: widget.chapter.id,
        sessionId: _sessionId!,
      );

      await _chatSessionRepository.appendMessage(
        sessionId: _sessionId!,
        isUser: true,
        text: question,
        timestamp: userTimestamp,
      );
    }

    _scrollToBottom(animated: true, force: true);

    final assistantIndex = _messages.length - 1;
    final responseBuffer = StringBuffer();
    print('[TRACE] ASSISTANT_MESSAGE_CREATED assistantIndex=$assistantIndex');
    print('[TRACE] BUFFER_LENGTH_BEFORE_RESET=0 (new StringBuffer)');
    var assistantPersisted = false;
    var lastNonEmptyAssistant = '';
    var usedAutoFallback = false;
    GenerationConfig? previousConfigForFallback;
    GenerationConfig? previousConfigForShortQuery;

    final shortQuery =
        question.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length <= 8;
    if (!useAndroidFastPath && Platform.isAndroid && shortQuery) {
      previousConfigForShortQuery = await _enableShortQueryConfig();
    }

    try {
      // ── Task B: Intent detection BEFORE retrieval ──
      final preDetection = IntentDetector().detect(
        question,
        sessionState: _sessionState,
      );
      final ragQuery = _expandRetrievalQuery(
        question: question,
        detectedTopic: preDetection.topic,
      );
      print('[RETRIEVAL] RAW_QUERY=$question');
      print('[RETRIEVAL] TOPIC=${preDetection.topic}');
      print('[RETRIEVAL] FINAL_SEARCH_QUERY=$ragQuery');

      final ragCheck = await _ragRepository.localRagPreCheck(
        chapterId: widget.chapter.id,
        query: ragQuery,
        limit: 5,
      );

      final hasRelevantLocalContent = ragCheck.hasRelevantLocalContent;

      bool backendAvailable = false;
      if (distributedStreamingReady) {
        backendAvailable = await _distributedServiceComposer.backendService
            .isBackendAvailable();
      }

      print('[DIAGNOSTICS] BACKEND_AVAILABLE=$backendAvailable');

      final conversationContext = await _conversationContextBuilder.build(
        sessionId: _sessionId!,
        messages: _messages,
        currentQuestion: question,
        subject: widget.subject.name,
        chapter: widget.chapter.title,
      );
      final conversationHistory = conversationContext.promptLines;
      final detailedContext = await _simpleRagService.retrieveContextDetailed(
        chapterId: widget.chapter.id,
        query: ragQuery,
        topK: 5,
        maxContextChars: 3200,
      );
      final localCurriculumContext = detailedContext
          .take(3)
          .map(
            (item) =>
                '[Source: ${item.sourceTitle} | confidence ${(item.confidence * 100).round()}%] ${_clipText(item.content, 850)}',
          )
          .toList();
      String modelPath = '';
      try {
        modelPath = await _llmAdminChannelService.getModelPath() ?? '';
      } catch (_) {}
      final isQwen = modelPath.toLowerCase().contains('qwen');
      final isGemma = modelPath.toLowerCase().contains('gemma');

      final preparedPrompt = distributedStreamingReady
          ? _promptBuilder.buildChapterPrompt(
              course: widget.course,
              subject: widget.subject,
              chapter: widget.chapter,
              question: question,
              languageCode: _languageCode,
              retrievedContext: localCurriculumContext,
              conversationContext: conversationContext,
            )
          : isQwen
              ? '<|im_start|>system\nYou are a helpful school tutor. Explain the topic clearly and concisely.<|im_end|>\n<|im_start|>user\nSubject: ${widget.subject.name}\nChapter: ${widget.chapter.title}\nQuestion: $question<|im_end|>\n<|im_start|>assistant\n'
              : isGemma
                  ? 'You are a helpful school tutor. Explain the topic clearly and concisely.\nSubject: ${widget.subject.name}\nChapter: ${widget.chapter.title}\nQuestion: $question'
                  : '<s>[INST] <<SYS>>\nYou are a helpful school tutor. Explain the topic clearly and concisely.\n<</SYS>>\n\nSubject: ${widget.subject.name}\nChapter: ${widget.chapter.title}\nQuestion: $question [/INST]';

      _logPromptContextAudit(
        subject: widget.subject.name,
        chapter: widget.chapter.title,
        summaryChars: conversationContext.sessionSummary.length,
        historyChars: conversationContext.recentConversation.join('\n').length,
        ragChunks: localCurriculumContext.length,
        ragChars: localCurriculumContext.join('\n').length,
        promptChars: preparedPrompt.length,
      );

      final responseStream = distributedStreamingReady
          ? _distributedServiceComposer.hybridInferenceService
                .streamTutorAnswer(
                  question,
                  backendAvailable: backendAvailable,
                  hasRelevantLocalContent: hasRelevantLocalContent,
                  localCurriculumContext: localCurriculumContext,
                  grade: int.tryParse(
                    RegExp(r'\d+').firstMatch(widget.course.id)?.group(0) ?? '',
                  ),
                  subject: widget.subject.name,
                  chapter: widget.chapter.title,
                  language: _languageCode,
                  conversationHistory: conversationHistory,
                  preparedPrompt: preparedPrompt,
                  sessionState: _sessionState,
                )
          : _gateway.streamResponse(prompt: preparedPrompt);

      final primaryTimeout = Duration(
        milliseconds: Platform.isAndroid
            ? 720000
            : (_chatMode == 'fast')
            ? 90000
            : (_chatMode == 'balanced')
            ? 120000
            : 180000,
      );

      Future<void> consumeStream({
        required Duration timeout,
        required bool isFallback,
        required Stream<String> stream,
      }) async {
        final completer = Completer<void>();
        late final StreamSubscription<String> subscription;
        final reasoningFilter = ReasoningOutputFilter();

        subscription = stream.listen(
          (chunk) {
            // Handle backend correction reset signal
            if (chunk == '\x00RESET\x00') {
              responseBuffer.clear();
              return;
            }

            final visibleChunk = reasoningFilter.push(chunk);
            if (visibleChunk.isEmpty) {
              return;
            }
            final elapsedSinceStart = DateTime.now()
                .difference(startTime)
                .inMilliseconds;
            print(
              '[TRACE] UI_RECEIVED chunk_length=${visibleChunk.length} elapsed_ms=$elapsedSinceStart',
            );
            print('[TRACE] MESSAGE_ID_BEING_UPDATED=$assistantIndex');
            final mergedText = StreamingOutputNormalizer.merge(
              responseBuffer.toString(),
              visibleChunk,
            );
            if (mergedText == responseBuffer.toString()) {
              return;
            }
            responseBuffer
              ..clear()
              ..write(mergedText);

            final nowMs = DateTime.now().millisecondsSinceEpoch;
            final shouldForceUpdate = visibleChunk.contains('\n');
            if (nowMs - _lastUiUpdateAtMs > 40 || shouldForceUpdate) {
              final liveText = responseBuffer.toString();
              if (liveText.isNotEmpty) lastNonEmptyAssistant = liveText;

              if (!mounted) {
                return;
              }

              final elapsedMs = DateTime.now()
                  .difference(_inferenceStartedAt ?? DateTime.now())
                  .inMilliseconds;
              final estimatedTokens = (liveText.length / 4).round();
              final liveTokensPerSec = elapsedMs <= 0
                  ? 0
                  : ((estimatedTokens * 1000) / elapsedMs).round();

              print("[TRACE] UI_APPEND_START");
              setState(() {
                print("[TRACE] UI_STATE_UPDATED");
                _messages[assistantIndex] = TutorMessage(
                  text: liveText,
                  isUser: false,
                  timestamp: _messages[assistantIndex].timestamp,
                );
                _liveEstimatedTokens = estimatedTokens;
                _liveTokensPerSec = liveTokensPerSec;
                _inferenceLog = isFallback
                    ? 'Fallback streaming... ${responseBuffer.length} chars | ~$_liveEstimatedTokens tokens | $_liveTokensPerSec tok/s'
                    : 'Streaming... ${responseBuffer.length} chars | ~$_liveEstimatedTokens tokens | $_liveTokensPerSec tok/s';
              });
              print("[TRACE] UI_APPEND_END");
              print(
                "[TRACE] MESSAGE_LENGTH=${_messages[assistantIndex].text.length}",
              );

              _scrollToBottom(animated: false, force: true);
              _lastUiUpdateAtMs = nowMs;
            }
          },

          onError: (error, stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          },
          onDone: () {
            print('[DIAGNOSTICS] FINAL_RESPONSE_RECEIVED');
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          cancelOnError: true,
        );

        _activeResponseSubscription = subscription;

        try {
          await completer.future.timeout(timeout);
        } finally {
          await subscription.cancel();
          if (identical(_activeResponseSubscription, subscription)) {
            _activeResponseSubscription = null;
          }
        }
      }

      try {
        await consumeStream(
          timeout: primaryTimeout,
          isFallback: false,
          stream: responseStream,
        );
      } catch (error) {
        final details = OfflineErrorTaxonomy.fromError(
          error,
          context: OfflineErrorContext.chatInference,
        );
        final shouldFallback =
            !useAndroidFastPath &&
            _chatMode != 'fast' &&
            (details.category == OfflineErrorCategory.timeout ||
                details.category == OfflineErrorCategory.network ||
                details.category == OfflineErrorCategory.unavailable);

        if (!shouldFallback) {
          rethrow;
        }

        usedAutoFallback = true;
        previousConfigForFallback = await _enableFastFallbackConfig();
        responseBuffer.clear();
        lastNonEmptyAssistant = '';

        if (mounted) {
          setState(() {
            _messages[assistantIndex] = TutorMessage(
              text: '',
              isUser: false,
              timestamp: _messages[assistantIndex].timestamp,
            );
            _inferenceLog =
                'Auto fallback triggered (${details.code}). Retrying in Fast mode...';
          });
        }

        await consumeStream(
          timeout: const Duration(milliseconds: 90000),
          isFallback: true,
          stream: _gateway.streamResponse(
            prompt: await _buildModelPrompt(question: question),
          ),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      final details = OfflineErrorTaxonomy.fromError(
        error,
        context: OfflineErrorContext.chatInference,
        fallbackMessage: 'Model unavailable. Check native engine setup.',
      );
      final message = details.userMessage;

      try {
        await _gateway.stopGeneration();
      } catch (_) {
        // Ignore stop errors after timeout/failure.
      }

      setState(() {
        _messages[assistantIndex] = TutorMessage(
          text: message,
          isUser: false,
          timestamp: _messages[assistantIndex].timestamp,
        );
        _inferenceLog = '${details.title} (${details.code}): $message';
      });

      await _chatSessionRepository.appendMessage(
        sessionId: _sessionId!,
        isUser: false,
        text: message,
        timestamp: _messages[assistantIndex].timestamp,
      );
      // Record assistant message
      await _progressRepository.recordChatMessage(
        chapterId: widget.chapter.id,
        sessionId: _sessionId!,
      );
      assistantPersisted = true;
    } finally {
      _isGenerating = false;
      var finalAssistant = _sanitizeAssistantText(
        _messages[assistantIndex].text,
      ).trim();
      if (finalAssistant.isEmpty && lastNonEmptyAssistant.isNotEmpty) {
        finalAssistant = lastNonEmptyAssistant;
        if (mounted) {
          setState(() {
            _messages[assistantIndex] = TutorMessage(
              text: finalAssistant,
              isUser: false,
              timestamp: _messages[assistantIndex].timestamp,
            );
          });
        }
      }

      if (finalAssistant.isEmpty) {
        finalAssistant = _sanitizeAssistantText(
          responseBuffer.toString(),
        ).trim();
      }

      if (finalAssistant.isNotEmpty && mounted) {
        setState(() {
          _messages[assistantIndex] = TutorMessage(
            text: finalAssistant,
            isUser: false,
            timestamp: _messages[assistantIndex].timestamp,
          );
        });
      }

      if (!useAndroidFastPath && _looksLooped(finalAssistant)) {
        try {
          final retryText = await _runRecoveryPrompt(recoveryPrompt);
          if (retryText.isNotEmpty) {
            finalAssistant = retryText;
            if (mounted) {
              setState(() {
                _messages[assistantIndex] = TutorMessage(
                  text: retryText,
                  isUser: false,
                  timestamp: _messages[assistantIndex].timestamp,
                );
                _inferenceLog = 'Recovered from looped answer.';
              });
            }
          }
        } catch (_) {
          // Keep the first usable answer if recovery fails.
        }
      }

      if (usedAutoFallback) {
        await _restoreGenerationConfig(previousConfigForFallback);
      } else if (!useAndroidFastPath) {
        await _restoreGenerationConfig(previousConfigForShortQuery);
      }

      if (!assistantPersisted &&
          finalAssistant.isNotEmpty &&
          needsTranslation) {
        try {
          if (mounted) {
            setState(() {
              _inferenceLog = AppLocalizations.of(context)!
                  .chatStatusTranslating(_languageCode.toUpperCase());
            });
          }

          final translation = await _translationService.translate(
            text: finalAssistant,
            sourceLang: 'en',
            targetLang: _languageCode,
            config: _translationConfig,
          );

          final translated = translation.translated.trim();
          if (translated.isNotEmpty && mounted) {
            final displayText = _translationConfig.showOriginalAlongside
                ? AppLocalizations.of(context)!.chatTranslationHeaderOriginal(
                    finalAssistant,
                    _languageCode.toUpperCase(),
                    translated,
                  )
                : translated;

            finalAssistant = displayText;

            if (mounted) {
              setState(() {
                _messages[assistantIndex] = TutorMessage(
                  text: displayText,
                  isUser: false,
                  timestamp: _messages[assistantIndex].timestamp,
                );
                _inferenceLog = translation.fallbackUsed
                    ? 'Translated via ${translation.engineUsed.name} (fallback used).'
                    : 'Translated via ${translation.engineUsed.name}.';
              });
            }
          }
        } catch (_) {
          if (mounted) {
            setState(() {
              _inferenceLog =
                  'Translation failed. Showing original English response.';
            });
          }
        }
      }

      if (!assistantPersisted && finalAssistant.isNotEmpty) {
        if (useAndroidFastPath) {
          _persistAssistantTurnAsync(
            answer: finalAssistant,
            timestamp: _messages[assistantIndex].timestamp,
          );
        } else {
          await _chatSessionRepository.appendMessage(
            sessionId: _sessionId!,
            isUser: false,
            text: finalAssistant,
            timestamp: _messages[assistantIndex].timestamp,
          );
          // Record assistant message
          await _progressRepository.recordChatMessage(
            chapterId: widget.chapter.id,
            sessionId: _sessionId!,
          );
        }
      }

      final updatedCount = useAndroidFastPath
          ? (_questionsAsked + 1)
          : await _progressRepository.getQuestionCount(
              chapterId: widget.chapter.id,
            );

      if (mounted) {
        final elapsedMs = DateTime.now()
            .difference(_inferenceStartedAt ?? DateTime.now())
            .inMilliseconds;
        setState(() {
          _isGenerating = false;
          _questionsAsked = updatedCount;
          if (_lastInferenceMs == 0) {
            _lastInferenceMs = elapsedMs > 0 ? elapsedMs : 0;
          }
          if (_lastInferenceTokens == 0) {
            _lastInferenceTokens = _liveEstimatedTokens;
          }
          if (_lastInferenceTokensPerSec == 0) {
            _lastInferenceTokensPerSec = _liveTokensPerSec;
          }
          if (_lastInferenceMs > 0) {
            final completionPrefix = usedAutoFallback
                ? 'Completed with auto fallback'
                : 'Completed';
            _inferenceLog =
                '$completionPrefix in ${_lastInferenceMs}ms | $_lastInferenceTokens tokens | $_lastInferenceTokensPerSec tok/s';
          }
        });
      }
      _scrollToBottom(animated: true, force: true);
    }

    final elapsed = DateTime.now().difference(startTime);
    print('[DIAGNOSTICS] TOTAL_REQUEST_TIME=${elapsed.inMilliseconds}ms');
  }

  void _persistUserTurnAsync({
    required String question,
    required DateTime timestamp,
  }) {
    unawaited(() async {
      try {
        await _progressRepository.recordQuestionAsked(
          chapterId: widget.chapter.id,
        );
        await _progressRepository.recordChatMessage(
          chapterId: widget.chapter.id,
          sessionId: _sessionId!,
        );
        await _chatSessionRepository.appendMessage(
          sessionId: _sessionId!,
          isUser: true,
          text: question,
          timestamp: timestamp,
        );
      } catch (_) {
        // Best-effort persistence in fast path.
      }
    }());
  }

  void _persistAssistantTurnAsync({
    required String answer,
    required DateTime timestamp,
  }) {
    unawaited(() async {
      try {
        await _chatSessionRepository.appendMessage(
          sessionId: _sessionId!,
          isUser: false,
          text: answer,
          timestamp: timestamp,
        );
        await _progressRepository.recordChatMessage(
          chapterId: widget.chapter.id,
          sessionId: _sessionId!,
        );
      } catch (_) {
        // Best-effort persistence in fast path.
      }
    }());
  }

  Future<String> _buildModelPrompt({required String question}) async {
    final sessionId = _sessionId;
    if (_hasChapterRagContent && _sessionId != null && _memoryPolicy != null) {
      final ragQuery = _expandRetrievalQuery(question: question);
      final chapterChunks = await _ragRepository.searchChunksForChapter(
        chapterId: widget.chapter.id,
        query: ragQuery,
        limit: 5,
      );

      if (chapterChunks.isNotEmpty) {
        final conversationContext = await _conversationContextBuilder.build(
          sessionId: sessionId!,
          messages: _messages,
          currentQuestion: question,
          subject: widget.subject.name,
          chapter: widget.chapter.title,
        );
        final retrievedContext = chapterChunks
            .take(3)
            .map((chunk) => _clipText(chunk.content, 850))
            .toList(growable: false);

        String modelPath = '';
        try {
          modelPath = await _llmAdminChannelService.getModelPath() ?? '';
        } catch (_) {}
        final isQwen = modelPath.toLowerCase().contains('qwen');
        final isGemma = modelPath.toLowerCase().contains('gemma');

        final promptText = _distributedServiceComposer.isInitialized
            ? _promptBuilder.buildChapterPrompt(
                course: widget.course,
                subject: widget.subject,
                chapter: widget.chapter,
                question: question,
                languageCode: _languageCode,
                retrievedContext: retrievedContext,
                conversationContext: conversationContext,
              )
            : isQwen
                ? '<|im_start|>system\nYou are a helpful school tutor. Explain the topic clearly and concisely.<|im_end|>\n<|im_start|>user\nSubject: ${widget.subject.name}\nChapter: ${widget.chapter.title}\nQuestion: $question<|im_end|>\n<|im_start|>assistant\n'
                : isGemma
                    ? 'You are a helpful school tutor. Explain the topic clearly and concisely.\nSubject: ${widget.subject.name}\nChapter: ${widget.chapter.title}\nQuestion: $question'
                    : '<s>[INST] <<SYS>>\nYou are a helpful school tutor. Explain the topic clearly and concisely.\n<</SYS>>\n\nSubject: ${widget.subject.name}\nChapter: ${widget.chapter.title}\nQuestion: $question [/INST]';
        _logPromptContextAudit(
          subject: widget.subject.name,
          chapter: widget.chapter.title,
          summaryChars: conversationContext.sessionSummary.length,
          historyChars: conversationContext.recentConversation
              .join('\n')
              .length,
          ragChunks: retrievedContext.length,
          ragChars: retrievedContext.join('\n').length,
          promptChars: promptText.length,
        );
        return promptText;
      }
    }

    final promptText = _simpleAiComponent.buildPrompt(question: question);
    print('[DIAGNOSTICS] PROMPT_LENGTH=${promptText.length}');
    return promptText;
  }

  Future<String> _runRecoveryPrompt(String recoveryPrompt) async {
    final buffer = StringBuffer();
    await for (final chunk
        in (_distributedServiceComposer.isInitialized
            ? _distributedServiceComposer.hybridInferenceService.streamAnswer(
                recoveryPrompt,
                forceLocal: true,
                language: _languageCode,
              )
            : _gateway.streamResponse(prompt: recoveryPrompt))) {
      buffer.write(chunk);
    }
    return _sanitizeAssistantText(buffer.toString()).trim();
  }

  String _expandRetrievalQuery({
    required String question,
    String? detectedTopic,
  }) {
    final parts = <String>[
      widget.subject.name,
      widget.chapter.title,
      if (detectedTopic != null && detectedTopic.trim().isNotEmpty)
        detectedTopic,
      question,
    ];
    final seen = <String>{};
    return parts
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .where((part) => seen.add(part.toLowerCase()))
        .join(' ');
  }

  String _clipText(String value, int maxChars) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.length <= maxChars) {
      return clean;
    }
    return '${clean.substring(0, maxChars).trimRight()}...';
  }

  void _logPromptContextAudit({
    required String subject,
    required String chapter,
    required int summaryChars,
    required int historyChars,
    required int ragChunks,
    required int ragChars,
    int? promptChars,
  }) {
    final audit = <String, dynamic>{
      'subject': subject,
      'chapter': chapter,
      'summary_chars': summaryChars,
      'history_chars': historyChars,
      'rag_chunks': ragChunks,
      'rag_chars': ragChars,
      if (promptChars != null) 'prompt_chars': promptChars,
    };
    print('[PROMPT_AUDIT] ${jsonEncode(audit)}');
  }

  Future<GenerationConfig?> _enableFastFallbackConfig() async {
    try {
      final previous = await _llmAdminChannelService.getGenerationConfig();
      await _llmAdminChannelService.updateGenerationConfig(
        maxTokens: 256,
        timeoutMs: 90000,
        systemPrompt:
            'You are a concise offline tutor. Provide direct, accurate answers in simple steps.',
      );
      return previous;
    } catch (_) {
      return null;
    }
  }

  Future<GenerationConfig?> _enableShortQueryConfig() async {
    try {
      final previous = await _llmAdminChannelService.getGenerationConfig();
      await _llmAdminChannelService.updateGenerationConfig(
        maxTokens: 128,
        timeoutMs: 60000,
        systemPrompt:
            'You are a concise offline tutor. Give direct answers in 1-4 short sentences unless user asks for detail.',
      );
      return previous;
    } catch (_) {
      return null;
    }
  }

  Future<void> _restoreGenerationConfig(GenerationConfig? previous) async {
    if (previous == null) {
      return;
    }
    try {
      await _llmAdminChannelService.updateGenerationConfig(
        maxTokens: previous.maxTokens,
        timeoutMs: previous.timeoutMs,
        systemPrompt: previous.systemPrompt,
      );
    } catch (_) {
      // Ignore restoration failure; current session can still proceed.
    }
  }

  Future<void> _runLatencyBenchmark() async {
    if (_runningBenchmark || _isGenerating) {
      return;
    }

    setState(() {
      _runningBenchmark = true;
      _benchmarkLog = 'Running benchmark...';
    });

    final prompts = <String>[
      'Explain the core concept of this chapter in short.',
      'Give one solved example from this chapter.',
      'List 3 common mistakes students make in this topic.',
    ];

    try {
      await for (final progress in _benchmarkService.runBenchmark(
        chapterId: widget.chapter.id,
        mode: _chatMode,
        prompts: prompts,
      )) {
        if (!mounted) {
          return;
        }
        setState(() {
          _benchmarkLog =
              'Benchmark ${progress.completed}/${progress.total} | last TTFT ${progress.lastItem?.ttftMs ?? 0}ms';
        });
      }

      final summary = await _benchmarkService.getLatestSummary(
        chapterId: widget.chapter.id,
        mode: _chatMode,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _benchmarkLog =
            'Benchmark done: TTFT ${summary.avgTtftMs}ms | Total ${summary.avgTotalMs}ms | ${summary.avgTokensPerSec.toStringAsFixed(1)} tok/s';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Latency benchmark saved.')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _benchmarkLog = 'Benchmark failed: $e';
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Benchmark failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _runningBenchmark = false;
        });
      }
    }
  }
  Future<void> _stop() async {
    if (!_isGenerating) {
      return;
    }

    if (mounted) {
      setState(() {
        _isGenerating = false;
        _inferenceLog = 'Inference stopped by user.';
      });
    }

    final sub = _activeResponseSubscription;
    _activeResponseSubscription = null;

    Future.microtask(() async {
      try {
        await sub?.cancel();
      } catch (e) {
        debugPrint('Error cancelling stream subscription: $e');
      }

      try {
        if (_distributedServiceComposer.isInitialized) {
          await _distributedServiceComposer.hybridInferenceService.stopGeneration();
        }
      } catch (e) {
        debugPrint('Error stopping hybrid generation: $e');
      }

      try {
        await _gateway.stopGeneration();
      } catch (e) {
        debugPrint('Error stopping gateway generation: $e');
      }
    });
  }

  String _sanitizeAssistantText(String raw) {
    var text = ReasoningOutputFilter.stripComplete(
      raw,
    ).replaceAll(_ansiEscape, '').replaceAll('\r', '');

    // Remove template/control markers emitted by some prompt formats.
    text = text.replaceAll(RegExp(r'<\|[^>]*\|>'), '');
    text = text.replaceAll(RegExp(r'<\|[^\n]*'), '');
    text = text.replaceAll(RegExp(r'<[^\s>]*\|>'), '');

    final tutorAnswerMatch = RegExp(
      r'Tutor Answer:\s*',
      caseSensitive: false,
    ).allMatches(text);
    if (tutorAnswerMatch.isNotEmpty) {
      final last = tutorAnswerMatch.last;
      text = text.substring(last.end);
    }

    text = text
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|im_start|>assistant', '')
        .replaceAll('<|question|>', '')
        .replaceAll('<|answer|>', '')
        .replaceAll('<|roleplay|>', '')
        .replaceAll('<im_start>assistant', '')
        .replaceAll('<im_end>', '')
        .replaceAll('</s>', '')
        .replaceAll('<s>', '');

    final lowerText = text.toLowerCase();
    final answerTagIndex = lowerText.indexOf('<|answer|>');
    if (answerTagIndex >= 0) {
      text = text.substring(answerTagIndex + '<|answer|>'.length);
    }

    final roleplayTagIndex = text.toLowerCase().indexOf('<|roleplay|>');
    if (roleplayTagIndex >= 0) {
      text = text.substring(0, roleplayTagIndex);
    }

    final roleplayTextIndex = text.toLowerCase().indexOf('as the tutor:');
    if (roleplayTextIndex >= 0) {
      text = text.substring(0, roleplayTextIndex);
    }

    final lines = text.split('\n');
    final kept = <String>[];
    var skipCommandBlock = false;
    var seenAnswerBody = false;
    var lastKeptKey = '';
    var repeatedKeptCount = 0;

    bool appendIfUnique(String value) {
      final key = _normalizeLine(value);
      if (key.isEmpty) {
        return false;
      }

      if (key == lastKeptKey) {
        repeatedKeptCount += 1;
        if (repeatedKeptCount >= 2 && seenAnswerBody) {
          return false;
        }
      } else {
        lastKeptKey = key;
        repeatedKeptCount = 0;
      }

      kept.add(value);
      seenAnswerBody = true;
      return true;
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (!skipCommandBlock) {
          kept.add('');
        }
        continue;
      }

      final lower = trimmed.toLowerCase();

      if (trimmed == '?') {
        continue;
      }

      if (lower.startsWith('student question:')) {
        if (kept.isNotEmpty) {
          break;
        }
        continue;
      }

      if (lower.startsWith('user query:') ||
          lower.startsWith('direct reply:')) {
        if (seenAnswerBody) {
          break;
        }
        continue;
      }

      if (lower.startsWith('answer:')) {
        final stripped = trimmed.replaceFirst(RegExp(r'^[Aa]nswer:\s*'), '');
        if (stripped.isNotEmpty) {
          if (!appendIfUnique(stripped)) {
            break;
          }
        }
        continue;
      }

      if (lower.startsWith('student:')) {
        continue;
      }

      if (lower.startsWith('tutor:')) {
        final stripped = trimmed.replaceFirst(RegExp(r'^[Tt]utor:\s*'), '');
        if (!appendIfUnique(stripped)) {
          break;
        }
        continue;
      }

      if (lower.startsWith('available commands:')) {
        skipCommandBlock = true;
        continue;
      }

      if (skipCommandBlock) {
        if (trimmed.startsWith('> ')) {
          skipCommandBlock = false;
        } else {
          continue;
        }
      }

      if (lower.startsWith('--no-conversation is not supported')) continue;
      if (lower.startsWith('please use llama-completion')) continue;
      if (lower.startsWith('loading model')) continue;
      if (lower.startsWith('[ prompt:')) continue;
      if (lower.startsWith('<|question|>')) continue;
      if (lower.startsWith('<|answer|>')) continue;
      if (lower.startsWith('<|roleplay|>')) continue;
      if (lower.startsWith('as the tutor:')) continue;
      if (lower.startsWith('as the student:')) continue;
      if (RegExp(r'^/(exit|regen|clear|read|glob)\b').hasMatch(lower)) continue;
      if (RegExp(r'^(build|model|modalities)\s*:').hasMatch(lower)) continue;
      if (trimmed.startsWith('> You are an offline tutor')) continue;

      if (lower.startsWith('what is ') ||
          lower.startsWith('algebra is ') ||
          lower.startsWith('student question')) {
        if (seenAnswerBody && kept.isNotEmpty) {
          break;
        }
      }

      if (!appendIfUnique(line)) {
        break;
      }
    }

    final collapsed = kept.join('\n').trim();
    return _dedupeParagraphs(
      collapsed.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim(),
    );
  }

  bool _looksLooped(String text) {
    final normalized = text.toLowerCase().trim();
    if (normalized.isEmpty) {
      return false;
    }

    if (normalized.contains('student question:') ||
        normalized.contains('educational context:') ||
        normalized.contains('session summary:') ||
        normalized.contains('recent conversation:') ||
        normalized.contains('relevant notes:') ||
        normalized.contains('priority context:') ||
        normalized.contains('tutor answer:') ||
        normalized.contains('direct reply:') ||
        normalized.contains('answer:') ||
        normalized.contains('question:')) {
      return true;
    }

    final paragraphs = text
        .split(RegExp(r'\n{2,}'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .toList();

    for (var index = 1; index < paragraphs.length; index += 1) {
      if (_normalizeLine(paragraphs[index]) ==
          _normalizeLine(paragraphs[index - 1])) {
        return true;
      }
    }

    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final counts = <String, int>{};
    for (final line in lines) {
      final key = _normalizeLine(line);
      counts[key] = (counts[key] ?? 0) + 1;
      if ((counts[key] ?? 0) >= 3 && key.length > 18) {
        return true;
      }
    }

    return false;
  }

  String _dedupeParagraphs(String text) {
    final paragraphs = text
        .split(RegExp(r'\n{2,}'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .toList();

    final kept = <String>[];
    String? lastKey;
    for (final paragraph in paragraphs) {
      final key = _normalizeLine(paragraph);
      if (key == lastKey) {
        continue;
      }
      kept.add(paragraph);
      lastKey = key;
    }

    return kept.join('\n\n').trim();
  }

  String _normalizeLine(String line) {
    return line.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  double? _inferenceProgressValue() {
    if (_generationMaxTokens <= 0) {
      return null;
    }
    final raw = _liveEstimatedTokens / _generationMaxTokens;
    final clamped = raw.clamp(0.0, 1.0);
    return clamped.toDouble();
  }

  void _scrollToBottom({bool animated = true, bool force = false}) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force && (nowMs - _lastAutoScrollAtMs) < 30) {
      return;
    }
    _lastAutoScrollAtMs = nowMs;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }

      final maxExtent = _scrollController.position.maxScrollExtent;
      final currentOffset = _scrollController.offset;
      final distanceToBottom = maxExtent - currentOffset;

      if (!force && distanceToBottom > 160) {
        return;
      }

      if (animated) {
        _scrollController.animateTo(
          maxExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(maxExtent);
      }
    });
  }

  Future<void> _copyMessage(TutorMessage message) async {
    final text = message.text.trim();
    if (text.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message.isUser ? 'Copied your message.' : 'Copied tutor response.',
        ),
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _openChatSettingsSheet(ChatMemoryPolicy memoryPolicy) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chat Settings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Conversation Memory',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: memoryPolicy.shortTermWindow,
                        borderRadius: BorderRadius.circular(12),
                        items: _memoryWindowOptions
                            .map(
                              (value) => DropdownMenuItem<int>(
                                value: value,
                                child: Text('Window $value msgs'),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          _updateMemoryPolicy(shortTermWindow: value);
                        },
                      ),
                    ),
                    FilterChip(
                      selected: memoryPolicy.semanticRecallEnabled,
                      label: const Text('Semantic Recall'),
                      onSelected: (selected) {
                        _updateMemoryPolicy(
                          semanticRecallEnabled: selected,
                          semanticTopK: selected
                              ? (memoryPolicy.semanticTopK == 0
                                    ? 2
                                    : memoryPolicy.semanticTopK)
                              : 0,
                        );
                      },
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: memoryPolicy.semanticTopK,
                        borderRadius: BorderRadius.circular(12),
                        items: _semanticTopKOptions
                            .map(
                              (value) => DropdownMenuItem<int>(
                                value: value,
                                child: Text('Semantic top-$value'),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: memoryPolicy.semanticRecallEnabled
                            ? (value) {
                                if (value == null) {
                                  return;
                                }
                                _updateMemoryPolicy(semanticTopK: value);
                              }
                            : null,
                      ),
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<SessionResetPolicy>(
                        value: memoryPolicy.resetPolicy,
                        borderRadius: BorderRadius.circular(12),
                        items: SessionResetPolicy.values
                            .map(
                              (value) => DropdownMenuItem<SessionResetPolicy>(
                                value: value,
                                child: Text(_resetPolicyLabel(value)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value == null) {
                            return;
                          }
                          _updateMemoryPolicy(resetPolicy: value);
                        },
                      ),
                    ),
                    if (memoryPolicy.resetPolicy ==
                        SessionResetPolicy.inactivity)
                      DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: memoryPolicy.inactivityMinutes,
                          borderRadius: BorderRadius.circular(12),
                          items: _inactivityMinutesOptions
                              .map(
                                (value) => DropdownMenuItem<int>(
                                  value: value,
                                  child: Text('Idle $value min'),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (value) {
                            if (value == null) {
                              return;
                            }
                            _updateMemoryPolicy(inactivityMinutes: value);
                          },
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _isGenerating ? null : _resetSessionMemoryNow,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reset Memory'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isBootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    print("[TRACE] CHAT_MESSAGE_COUNT=${_messages.length}");

    const bool _showDebugTelemetry = false;
    final memoryPolicy =
        _memoryPolicy ?? ChatMemoryPolicy.defaults(_sessionId ?? 'session');
        
    return Scaffold(
      backgroundColor: IDPColors.surface,
      body: Stack(
        children: [
          // Background Decoration
          Positioned(
            top: -150,
            right: -150,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                width: 600,
                height: 600,
                decoration: BoxDecoration(
                  color: IDPColors.primary.withValues(alpha: 0.05),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -150,
            left: -150,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
              child: Container(
                width: 600,
                height: 600,
                decoration: BoxDecoration(
                  color: IDPColors.secondaryFixedDim.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                // Glass AppBar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.containerMargin, vertical: IDPSpacing.md),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.7),
                    border: Border(bottom: BorderSide(color: IDPColors.outlineVariant.withValues(alpha: 0.3))),
                  ),
                  child: ClipRRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.arrow_back, color: IDPColors.onSurface),
                              ),
                              const SizedBox(width: IDPSpacing.sm),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AI Tutor',
                                    style: IDPTypography.titleMd.copyWith(color: IDPColors.primary, height: 1.1),
                                  ),
                                  Row(
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: IDPColors.secondaryFixedDim,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: IDPSpacing.xs),
                                      Text(
                                        'Model: On-Device Llama-3',
                                        style: IDPTypography.caption.copyWith(color: IDPColors.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              if (MediaQuery.sizeOf(context).width > 600)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text('Offline Mode', style: IDPTypography.labelMd.copyWith(color: IDPColors.onSurface)),
                                    Text('ACTIVE', style: IDPTypography.caption.copyWith(color: IDPColors.secondary, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 10)),
                                  ],
                                ),
                              const SizedBox(width: IDPSpacing.sm),
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: IDPColors.primaryContainer, width: 2),
                                ),
                                padding: const EdgeInsets.all(2),
                                child: const CircleAvatar(
                                  backgroundImage: NetworkImage('https://lh3.googleusercontent.com/aida-public/AB6AXuD6bA2RIuBCkImSriaxheASsbLmUY38iJw0YjiDS4aUVeH_SEuWaOxYf7Yo_PiZGplhkgLoWGirleWmu0oFDgZvbWTPWJVtwWXWBCUH7vkWKssqz66JIS0w6795DaRgDeIToPbTjbmD58P9Mwz1UrAT7DIsw3MHQZ9fdb4PJv7EJvAO7wbsiawL0Vm3f2VmX-3iqn_CRpezQQVVdqSMFcv_LG-6EcE3NxeoxwNYklgKI1iq21w1qPAnRnG9mn5WmTIakXzl9PFyPs-P'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Debug Telemetry
                if (_showDebugTelemetry)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    color: IDPColors.surfaceContainerLowest,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _engineLoaded
                                ? const Color(0xFFD0F0C0).withAlpha(204)
                                : const Color(0xFFFFC0CB).withAlpha(204),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _engineLoaded ? Colors.green : Colors.red,
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            _engineLoaded ? 'Model Ready' : 'Model Not Ready',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _engineLoaded
                                  ? Colors.green[800]
                                  : Colors.red[800],
                            ),
                          ),
                        ),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _chatMode,
                            borderRadius: BorderRadius.circular(12),
                            items: const [
                              DropdownMenuItem(value: 'fast', child: Text('Fast')),
                              DropdownMenuItem(
                                value: 'balanced',
                                child: Text('Balanced'),
                              ),
                              DropdownMenuItem(
                                value: 'detailed',
                                child: Text('Detailed'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null || value == _chatMode) {
                                return;
                              }
                              _applyChatMode(value);
                            },
                          ),
                        ),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _languageCode,
                            borderRadius: BorderRadius.circular(12),
                            items: const [
                              DropdownMenuItem(value: 'en', child: Text('English')),
                              DropdownMenuItem(value: 'kn', child: Text('Kannada')),
                            ],
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _languageCode = value;
                              });
                            },
                          ),
                        ),
                        if (_languageCode != 'en')
                          DropdownButtonHideUnderline(
                            child: DropdownButton<TranslationEngineId>(
                              value: _translationConfig.engineId,
                              borderRadius: BorderRadius.circular(12),
                              items: TranslationEngineCatalog.kannadaEngines()
                                  .map(
                                    (engine) => DropdownMenuItem<TranslationEngineId>(
                                      value: engine.id,
                                      child: Text(engine.label),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (value) {
                                if (value == null) {
                                  return;
                                }
                                _updateTranslationEngine(value);
                              },
                            ),
                          ),
                        if (_languageCode != 'en')
                          IconButton(
                            tooltip: 'Kannada translation engines',
                            onPressed: _showKannadaEngineCatalog,
                            icon: const Icon(Icons.translate_rounded),
                          ),
                        if (_isLinux)
                          OutlinedButton.icon(
                            onPressed: _pickLinuxExecutable,
                            icon: const Icon(Icons.terminal_rounded),
                            label: const Text('Select Llama Runner'),
                          ),
                        if (_isLinux)
                          OutlinedButton.icon(
                            onPressed: _autoDetectLinuxExecutable,
                            icon: const Icon(Icons.search_rounded),
                            label: const Text('Auto Detect CLI'),
                          ),
                        if (_isLinux)
                          OutlinedButton.icon(
                            onPressed: _pickLinuxModel,
                            icon: const Icon(Icons.memory_rounded),
                            label: const Text('Select GGUF Model'),
                          ),
                        if (_isLinux)
                          OutlinedButton.icon(
                            onPressed: _copyModelToAppStorage,
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('Copy Model to App'),
                          ),
                        if (Platform.isAndroid)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Fast Native'),
                              const SizedBox(width: 6),
                              Switch.adaptive(
                                value: _androidNativeFastPath,
                                onChanged: (v) {
                                  setState(() {
                                    _androidNativeFastPath = v;
                                  });
                                },
                              ),
                            ],
                          ),
                        if (_languageCode != 'en' &&
                            _translationConfig.engineId ==
                                TranslationEngineId.apertiumCli)
                          OutlinedButton.icon(
                            onPressed: _pickApertiumBinary,
                            icon: const Icon(Icons.extension_rounded),
                            label: const Text('Set Apertium'),
                          ),
                      ],
                    ),
                  ),

                // Main Content Canvas
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(IDPSpacing.containerMargin, IDPSpacing.lg, IDPSpacing.containerMargin, 180),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Column(
                          children: [
                            // Current Topic Indicator
                            Center(
                              child: Container(
                                margin: const EdgeInsets.only(bottom: IDPSpacing.xl),
                                padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.md, vertical: IDPSpacing.sm),
                                decoration: BoxDecoration(
                                  color: IDPColors.surfaceContainerHigh,
                                  borderRadius: BorderRadius.circular(IDPRadius.full),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.history_edu, color: IDPColors.primary, size: 18),
                                    const SizedBox(width: IDPSpacing.sm),
                                    Text(
                                      'Current Topic: ${widget.chapter.title}',
                                      style: IDPTypography.labelMd.copyWith(color: IDPColors.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _buildChatMessage(context, _messages[index]),
                          ],
                        );
                      }
                      return _buildChatMessage(context, _messages[index]);
                    },
                  ),
                ),
              ],
            ),
          ),
          
          // Bottom Controls (Floating)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildChatComposer(context),
          ),
        ],
      ),
    );
  }

  Widget _buildChatMessage(BuildContext context, TutorMessage message) {
    final isUser = message.isUser;
    final availableWidth = MediaQuery.sizeOf(context).width;
    final maxWidth = availableWidth >= 900
        ? 720.0
        : availableWidth * (isUser ? 0.85 : 0.85);

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: IDPSpacing.lg),
        child: Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                GestureDetector(
                  onLongPress: () => _copyMessage(message),
                  child: Container(
                    padding: const EdgeInsets.all(IDPSpacing.lg),
                    decoration: const BoxDecoration(
                      color: IDPColors.primary,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(IDPRadius.defaultRadius),
                        topRight: Radius.circular(IDPRadius.defaultRadius),
                        bottomLeft: Radius.circular(IDPRadius.defaultRadius),
                        bottomRight: Radius.zero,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SelectableText(
                      message.text,
                      style: IDPTypography.bodyMd.copyWith(color: IDPColors.onPrimary),
                    ),
                  ),
                ),
                const SizedBox(height: IDPSpacing.xs),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                      style: IDPTypography.caption.copyWith(color: IDPColors.onSurfaceVariant),
                    ),
                    const SizedBox(width: IDPSpacing.xs),
                    const Icon(Icons.done_all, size: 14, color: IDPColors.secondary),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: IDPSpacing.lg),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: IDPColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.smart_toy, size: 18, color: IDPColors.onPrimaryContainer),
                  ),
                  const SizedBox(width: IDPSpacing.sm),
                  Text('Tutor', style: IDPTypography.labelMd.copyWith(color: IDPColors.primary)),
                ],
              ),
              const SizedBox(height: IDPSpacing.xs),
              GestureDetector(
                onLongPress: () => _copyMessage(message),
                child: Container(
                  padding: const EdgeInsets.all(IDPSpacing.lg),
                  decoration: BoxDecoration(
                    color: IDPColors.surfaceContainerLow,
                    border: Border.all(color: IDPColors.outlineVariant.withValues(alpha: 0.2)),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(IDPRadius.defaultRadius),
                      topRight: Radius.circular(IDPRadius.defaultRadius),
                      bottomRight: Radius.circular(IDPRadius.defaultRadius),
                      bottomLeft: Radius.zero,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (AssetMessageRenderer.isAssetMessage(message.text))
                        AssetMessageRenderer.render(message.text)
                      else
                        FormattedTextWidget(
                          text: message.text.isEmpty && _isGenerating ? 'Thinking...' : message.text,
                          style: IDPTypography.bodyMd.copyWith(color: IDPColors.onSurface),
                        ),
                      if (_isGenerating && message.text.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: IDPSpacing.sm),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(width: 6, height: 6, decoration: BoxDecoration(color: IDPColors.primary.withValues(alpha: 0.4), shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Container(width: 6, height: 6, decoration: BoxDecoration(color: IDPColors.primary.withValues(alpha: 0.4), shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Container(width: 6, height: 6, decoration: BoxDecoration(color: IDPColors.primary.withValues(alpha: 0.4), shape: BoxShape.circle)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: IDPSpacing.xs),
              Text(
                '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                style: IDPTypography.caption.copyWith(color: IDPColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChatComposer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(IDPSpacing.containerMargin, 0, IDPSpacing.containerMargin, IDPSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Suggested Prompts
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: IDPSpacing.sm),
                child: Row(
                  children: [
                    _buildSuggestedPromptChip(context, Icons.functions, 'Example Problems'),
                    _buildSuggestedPromptChip(context, Icons.public, 'Real-world use'),
                    _buildSuggestedPromptChip(context, Icons.quiz, 'Quiz me'),
                  ],
                ),
              ),
              
              // Input Bar
              Container(
                padding: const EdgeInsets.all(IDPSpacing.xs),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(IDPRadius.xl),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 15,
                      offset: Offset(0, 5),
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(IDPRadius.xl),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.attach_file, color: IDPColors.onSurfaceVariant),
                        ),
                        Expanded(
                          child: Localizations.override(
                            context: context,
                            locale: Locale(_languageCode),
                            child: TextField(
                              controller: _inputController,
                              minLines: 1,
                              maxLines: 4,
                              style: IDPTypography.bodyMd.copyWith(color: IDPColors.onSurface),
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)?.chatMessageTutorHint ?? "Ask your offline tutor...",
                                hintStyle: IDPTypography.bodyMd.copyWith(color: IDPColors.onSurfaceVariant.withValues(alpha: 0.5)),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              decoration: const BoxDecoration(
                                color: IDPColors.primaryContainer,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: _backendConnected ? _openVoiceTutor : null,
                                color: IDPColors.onPrimaryContainer,
                                tooltip: _backendConnected
                                    ? AppLocalizations.of(context)!.chatVoiceTutorTooltip
                                    : AppLocalizations.of(context)!.chatVoiceRequiresBackendTooltip,
                                icon: const Icon(Icons.mic),
                              ),
                            ),
                            const SizedBox(width: IDPSpacing.sm),
                            Container(
                              decoration: const BoxDecoration(
                                color: IDPColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: IconButton(
                                onPressed: _isGenerating ? _stop : _ask,
                                color: IDPColors.onPrimary,
                                tooltip: _isGenerating
                                    ? AppLocalizations.of(context)!.chatStopResponseTooltip
                                    : AppLocalizations.of(context)!.chatSendTooltip,
                                icon: Icon(_isGenerating ? Icons.stop_rounded : Icons.send),
                              ),
                            ),
                            const SizedBox(width: IDPSpacing.xs),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestedPromptChip(BuildContext context, IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(right: IDPSpacing.sm),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(IDPRadius.full),
          onTap: () {
            _inputController.text = text;
            _ask();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.lg, vertical: IDPSpacing.sm),
            decoration: BoxDecoration(
              color: IDPColors.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(IDPRadius.full),
              border: Border.all(color: IDPColors.outlineVariant.withValues(alpha: 0.5)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: IDPColors.onSurfaceVariant),
                const SizedBox(width: IDPSpacing.sm),
                Text(text, style: IDPTypography.labelMd.copyWith(color: IDPColors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
