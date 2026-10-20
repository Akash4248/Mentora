import 'dart:io';
import '../../../core/theme/idp_colors.dart';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:mentora/core/utils/youtube_utils.dart';
import '../../network/services/mentora_backend_client.dart';
import '../../chat/presentation/formatted_text_widget.dart';
import 'dart:async';
import '../../home/presentation/video_player_screen.dart';
import '../../home/data/local/video_resource_repository.dart';
import '../../experiment/phet/presentation/experiment_player_screen.dart';
import '../../experiment/phet/models/experiment_descriptor.dart';
import '../../course/presentation/textbook_viewer_screen.dart';
import '../../assessment/presentation/chapter_flashcards_screen.dart';
import '../../chat/data/local/chat_session_repository.dart';
import '../../home/presentation/mentora_home_screen.dart';
import '../../assessment/data/local/quiz_result_repository.dart';
import '../../assessment/domain/quiz_result.dart';
import '../../progress/data/local/progress_repository.dart';
import '../../../config/app_environment.dart';
import '../../content_packs/data/local/content_pack_repository.dart';
import '../../assessment/application/quiz_question_loader.dart';
import '../../chat/data/local/chat_memory_policy_repository.dart';
import '../../chat/presentation/widgets/chat_memory_policy_sheet.dart';
import '../../chat/application/mentora_agent_session.dart';
import '../../chat/application/mentora_tutor_agent_provider.dart';
import '../../chat/application/tutor_session_coordinator.dart';
import '../../chat/application/context_builder.dart';
import '../../chat/application/three_tier_memory_manager.dart';
import '../../chat/domain/capability_registry.dart';
import '../../chat/domain/default_capabilities.dart';
import '../../chat/domain/learning_evidence.dart';
import '../../language/providers/language_provider.dart';
import '../../voice/services/offline_speech_service.dart';

class ChapterLearningWorkspaceScreen extends StatefulWidget {
  final String chapterTitle;
  final String subjectName;
  final int grade;

  const ChapterLearningWorkspaceScreen({
    Key? key,
    this.chapterTitle = 'Motion',
    this.subjectName = 'Science',
    this.grade = 9,
  }) : super(key: key);

  @override
  State<ChapterLearningWorkspaceScreen> createState() =>
      _ChapterLearningWorkspaceScreenState();
}

class _ChapterLearningWorkspaceScreenState
    extends State<ChapterLearningWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final MentoraBackendClient _client = MentoraBackendClient();
  final MentoraTutorAgentProvider _agentProvider = MentoraTutorAgentProvider();
  late final ThreeTierMemoryManager _memoryManager;
  late final CapabilityRegistry _capabilityRegistry;
  late final ContextBuilder _contextBuilder;
  late final TutorSessionCoordinator _coordinator;

  String _activeChapterTitle = 'Motion';
  String _activeSubjectName = 'Science';
  int _activeGrade = 9;
  bool _argsResolved = false;
  ChatMemoryPolicy? _memoryPolicy;

  // Tab 1 state
  bool _isSending = false;
  final List<Map<String, dynamic>> _messages = [];

  YoutubePlayerController? _youtubeController;
  String? _activeVideoId;
  bool _islOnly = false;

  static const _islKeywords = [
    'isl',
    'sign language',
    'sign-language',
    'signlang',
    'indian sign',
    'deaf',
  ];

  /// A video counts as ISL when its metadata mentions sign language.
  /// There is no separate ISL catalog yet — this filters the real playlist
  /// instead of showing a dead toggle.
  static bool _isIslVideo(Map<String, dynamic> item) {
    final haystack =
        '${item['title'] ?? ''} ${item['channel'] ?? ''} ${item['description'] ?? ''}'
            .toLowerCase();
    return _islKeywords.any(haystack.contains);
  }

  @override
  void initState() {
    super.initState();
    _memoryManager = ThreeTierMemoryManager();
    _capabilityRegistry = DefaultCapabilities.createDefaultRegistry(
      client: _client,
    );
    _contextBuilder = ContextBuilder(
      registry: _capabilityRegistry,
      memoryManager: _memoryManager,
    );
    _coordinator = TutorSessionCoordinator(
      agentProvider: _agentProvider,
      initialTopic: _activeChapterTitle,
      initialGrade: _activeGrade,
      capabilityRegistry: _capabilityRegistry,
      contextBuilder: _contextBuilder,
    );
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || _tabController.index != 4) {
        print(
          '[VIDEO_DEBUG] Workspace Tab changed to ${_tabController.index}. Pausing YouTube player plugin.',
        );
        _youtubeController?.pauseVideo();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_coordinator.dispose());
    _youtubeController?.close();
    _scrollController.dispose();
    _chatController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animated = true, bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final currentOffset = _scrollController.offset;
      final distanceToBottom = maxExtent - currentOffset;

      if (!force && distanceToBottom > 160) {
        return;
      }

      if (animated) {
        _scrollController.animateTo(
          maxExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(maxExtent);
      }
    });
  }

  // Tab 2 Simulation state
  Map<String, dynamic>? _simData;
  double _simLength = 2.0;
  double _simGravity = 9.8;
  bool _simIsPlaying = true;

  // Tab 2 PDF state
  String _resolvedPdfPath = '';

  // Tab 3 Video state
  Map<String, dynamic>? _videoData;

  void _initYoutubeControllerForVideo(String? rawUrl) {
    if (!_isWebViewSupported || rawUrl == null || rawUrl.isEmpty) return;
    final extractedId = YouTubeUtils.extractYouTubeId(rawUrl);
    if (extractedId == null || extractedId == _activeVideoId) return;

    _youtubeController?.close();
    _activeVideoId = extractedId;
    _youtubeController = YoutubePlayerController.fromVideoId(
      videoId: extractedId,
      autoPlay: false,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
      ),
    );
  }

  // Tab 4 Quiz state
  Map<String, dynamic>? _quizData;
  int _currentQuestionIndex = 0;
  int? _selectedOptionIndex;
  bool _showExplanation = false;
  bool _quizComplete = false;
  int _score = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsResolved) {
      _argsResolved = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _activeChapterTitle =
            args['chapterTitle']?.toString() ?? widget.chapterTitle;
        _activeSubjectName =
            args['subjectName']?.toString() ??
            args['subject']?.toString() ??
            widget.subjectName;
        _activeGrade = (args['grade'] as num?)?.toInt() ?? widget.grade;
        final initialTab = (args['initialTabIndex'] as num?)?.toInt();
        if (initialTab != null &&
            initialTab >= 0 &&
            initialTab < _tabController.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tabController.animateTo(initialTab);
          });
        }
      } else if (args is String) {
        _activeChapterTitle = args;
        _activeSubjectName = widget.subjectName;
        _activeGrade = widget.grade;
      } else {
        _activeChapterTitle = widget.chapterTitle;
        _activeSubjectName = widget.subjectName;
        _activeGrade = widget.grade;
      }

      _coordinator.updateTopicAndGrade(
        topic: _activeChapterTitle,
        grade: _activeGrade,
      );

      _messages.clear();
      _messages.add({
        'isUser': false,
        'text':
            'Welcome to Grade $_activeGrade $_activeSubjectName: *$_activeChapterTitle*! 👋\n\nI am your Mentora Socratic AI Tutor. Ask me any question or concept related to *$_activeChapterTitle* to begin learning.',
        'formulas': <String>[],
        'hasAudio': false,
      });

      _loadMemoryPolicy();
      _loadTabResources();
    }
  }

  String get _sessionId =>
      'session_grade${_activeGrade}_${_activeSubjectName.replaceAll(' ', '_')}_${_activeChapterTitle.replaceAll(' ', '_')}';

  Future<void> _loadMemoryPolicy() async {
    try {
      final policy = await ChatMemoryPolicyRepository().getPolicy(_sessionId);
      if (mounted) setState(() => _memoryPolicy = policy);
    } catch (_) {}
  }

  void _openMemoryPolicySheet() {
    final policy = _memoryPolicy ?? ChatMemoryPolicy.defaults(_sessionId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ChatMemoryPolicySheet(
        policy: policy,
        memoryManager: _memoryManager,
        sessionId: _sessionId,
        topic: _activeChapterTitle,
        onPolicyChanged:
            ({
              shortTermWindow,
              semanticRecallEnabled,
              semanticTopK,
              resetPolicy,
              inactivityMinutes,
            }) async {
              final updated = policy.copyWith(
                shortTermWindow: shortTermWindow,
                semanticRecallEnabled: semanticRecallEnabled,
                semanticTopK: semanticTopK,
                resetPolicy: resetPolicy,
                inactivityMinutes: inactivityMinutes,
              );
              try {
                await ChatMemoryPolicyRepository().savePolicy(updated);
              } catch (_) {}
              if (mounted) setState(() => _memoryPolicy = updated);
            },
      ),
    );
  }

  /// Deterministic 31-bit FNV-1a of grade|subject|title. Stable across
  /// restarts (unlike [Object.hashCode]), so quiz/flashcard rows keyed by
  /// this id survive app kills.
  int get _stableChapterId {
    const fnvPrime = 0x01000193;
    var hash = 0x811C9DC5;
    final key =
        '$_activeGrade|${_activeSubjectName.toLowerCase().trim()}|${_activeChapterTitle.toLowerCase().trim()}';
    for (var i = 0; i < key.length; i++) {
      hash ^= key.codeUnitAt(i);
      hash = (hash * fnvPrime) & 0x7FFFFFFF;
    }
    return hash;
  }

  Future<void> _loadTabResources() async {
    print(
      '[VIDEO_DEBUG] Workspace: Loading resources for chapter: "$_activeChapterTitle" (Grade $_activeGrade $_activeSubjectName)',
    );

    // Load SQLite Chat History
    try {
      final chatRepo = ChatSessionRepository();
      await chatRepo.ensureSessionExists(
        sessionId: _sessionId,
        chapterId: _activeChapterTitle,
      );
      final storedMessages = await chatRepo.getMessages(_sessionId);
      if (storedMessages.isNotEmpty && mounted) {
        setState(() {
          _messages.clear();
          for (final msg in storedMessages) {
            _messages.add({
              'isUser': msg.isUser,
              'text': msg.text,
              'hasAudio': !msg.isUser,
            });
          }
        });
        _scrollToBottom(force: true);
      }
    } catch (e) {
      print('[CHAT_DEBUG] Error loading chat history: $e');
    }

    final sim = await _client.getSimulationForChapter(_activeChapterTitle);
    final video = await _client.getVideoLecturesForChapter(_activeChapterTitle);
    final quiz = await _client.getQuizForChapter(_activeChapterTitle);

    List<Map<String, dynamic>> playlistItems = [];
    try {
      final localRepo = VideoResourceRepository();
      final localVideos = await localRepo.getVideosForChapter(
        _activeChapterTitle,
        grade: _activeGrade,
      );
      print(
        '[VIDEO_DEBUG] Workspace: Found ${localVideos.length} local SQLite videos for "$_activeChapterTitle"',
      );
      if (localVideos.isNotEmpty) {
        playlistItems = localVideos.map((v) {
          final m = v.durationSeconds ~/ 60;
          final s = v.durationSeconds % 60;
          final dur = m >= 60
              ? '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
              : '$m:${s.toString().padLeft(2, '0')}';
          return {
            'id': v.videoId,
            'youtubeId': v.videoId,
            'videoUrl': v.videoUrl,
            'title': v.videoTitle,
            'channel': v.channelName,
            'duration': dur,
            'description': v.description,
          };
        }).toList();
      }
    } catch (e) {
      print(
        '[VIDEO_DEBUG] Workspace: Error querying VideoResourceRepository: $e',
      );
    }

    final pdfItem = await ContentPackRepository().findPdfItemForChapter(
      chapterTitle: _activeChapterTitle,
      subject: _activeSubjectName,
      grade: _activeGrade,
    );
    // Single canonical loader: installed pack → live backend → offline mock.
    final loaderQs = await QuizQuestionLoader.load(
      grade: _activeGrade,
      subject: _activeSubjectName,
      chapterTitle: _activeChapterTitle,
    );

    if (mounted) {
      setState(() {
        _simData = sim;
        if (pdfItem != null && File(pdfItem.absolutePath).existsSync()) {
          _resolvedPdfPath = pdfItem.absolutePath;
        }
        if (loaderQs.isNotEmpty) {
          _quizData = {
            'chapter': _activeChapterTitle,
            'title': 'NCERT Practice Quiz: $_activeChapterTitle',
            'totalQuestions': loaderQs.length,
            'userMastery': 0,
            'questions': loaderQs,
          };
        } else {
          _quizData = quiz;
        }
        if (playlistItems.isNotEmpty) {
          _videoData = {
            'chapter': _activeChapterTitle,
            'currentVideo': playlistItems.first,
            'playlist': playlistItems,
            'islAvailable': true,
          };
        } else {
          _videoData = video;
        }
        final currentVid = _videoData?['currentVideo'] as Map<String, dynamic>?;
        final heroUrl =
            currentVid?['videoUrl']?.toString() ??
            currentVid?['youtubeId']?.toString();
        _initYoutubeControllerForVideo(heroUrl);
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isSending) return;
    await _sendTutorMessage(text, clearComposer: true);
  }

  void _showExplainDifferentlySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '💡 How would you like me to explain this?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 16),
              _buildExplainOption(
                Icons.directions_car,
                'Use a Real-World Analogy',
                'Practical daily life example',
              ),
              _buildExplainOption(
                Icons.child_care,
                'Simplify the Language',
                'Easier words for younger readers',
              ),
              _buildExplainOption(
                Icons.format_list_numbered,
                'Show Step-by-Step Math',
                'Detailed breakdown',
              ),
              _buildExplainOption(
                Icons.science,
                'Suggest a Visual Simulation',
                'Opens interactive lab',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExplainOption(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFEEF2FF),
        child: Icon(Icons.lightbulb, color: IDPColors.primary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
      ),
      onTap: () {
        Navigator.pop(context);
        String prompt = 'Please explain $_activeChapterTitle in clear detail.';
        if (title.contains('Analogy')) {
          prompt =
              'Please explain $_activeChapterTitle using a practical real-world daily life example or analogy.';
        } else if (title.contains('Simplify')) {
          prompt =
              'Please simplify the core concepts and equations of $_activeChapterTitle for a school student.';
        } else if (title.contains('Step-by-Step')) {
          prompt =
              'Please show a clear, step-by-step mathematical breakdown and key formulas for $_activeChapterTitle.';
        } else if (title.contains('Visual')) {
          prompt =
              'Please describe an interactive visual experiment or simulation to understand $_activeChapterTitle.';
        }
        _sendMessageWithTopic(prompt);
      },
    );
  }

  Future<void> _sendMessageWithTopic(String text) async {
    if (_isSending) return;
    await _sendTutorMessage(text);
  }

  Future<void> _sendTutorMessage(
    String text, {
    bool clearComposer = false,
  }) async {
    final chatRepo = ChatSessionRepository();
    final userTimestamp = DateTime.now();
    final assistantIndex = _messages.length + 1;

    setState(() {
      _messages.add({'isUser': true, 'text': text});
      _messages.add({'isUser': false, 'text': 'Thinking…', 'hasAudio': false});
      if (clearComposer) {
        _chatController.clear();
      }
      _isSending = true;
    });
    _scrollToBottom(force: true);

    try {
      await chatRepo.ensureSessionExists(
        sessionId: _sessionId,
        chapterId: _activeChapterTitle,
      );
      await chatRepo.appendMessage(
        sessionId: _sessionId,
        isUser: true,
        text: text,
        timestamp: userTimestamp,
      );
    } catch (error) {
      AppEnvironment.log(
        'CHAT',
        'Could not persist the student message: $error',
      );
    }

    unawaited(
      ProgressRepository()
          .recordQuestionAsked(chapterId: _activeChapterTitle)
          .catchError(
            (error) => AppEnvironment.log(
              'PROGRESS',
              'Failed recording question: $error',
            ),
          ),
    );
    unawaited(
      ProgressRepository()
          .recordChatMessage(
            chapterId: _activeChapterTitle,
            sessionId: _sessionId,
          )
          .catchError(
            (error) => AppEnvironment.log(
              'PROGRESS',
              'Failed recording chat message: $error',
            ),
          ),
    );

    final answer = StringBuffer();
    var answerToPersist = '';
    try {
      await for (final event in _coordinator.submitQuestion(
        text,
        sessionId: _sessionId,
        rawHistory: _messages,
      )) {
        switch (event) {
          case TutorTextDeltaEvent(:final delta):
            answer.write(delta);
            if (mounted) {
              setState(() {
                _messages[assistantIndex]['text'] = answer.toString();
              });
              _scrollToBottom(force: false);
            }
          case TutorTurnCompletedEvent(:final text):
            answerToPersist = text;
          case TutorTurnFailedEvent(:final message):
            answerToPersist = '⚠️ $message';
          case TutorTurnAbortedEvent():
            answerToPersist = 'Response cancelled.';
          case TutorToolStatusEvent(:final label, :final status, :final output):
            if (mounted) {
              setState(() {
                if (status == TutorToolStatus.started) {
                  _messages[assistantIndex]['toolStatus'] = '⚙️ $label…';
                } else if (status == TutorToolStatus.completed) {
                  _messages[assistantIndex]['toolStatus'] =
                      '✓ $label completed';
                  if (output != null && output.isNotEmpty) {
                    _messages[assistantIndex]['toolOutput'] = output;
                  }
                } else if (status == TutorToolStatus.failed) {
                  _messages[assistantIndex]['toolStatus'] = '⚠️ $label failed';
                }
              });
            }
        }
      }
    } catch (error) {
      answerToPersist = '⚠️ Tutor inference failed: $error';
      AppEnvironment.log('CHAT', 'Agent turn failed: $error');
    }

    if (answerToPersist.isEmpty) {
      answerToPersist = answer.toString().trim();
    }
    if (answerToPersist.isEmpty) {
      answerToPersist = '⚠️ The tutor returned no answer. Please try again.';
    }

    // Automatic concept and learning evidence extraction
    _memoryManager.recordSessionConcept(_sessionId, _activeChapterTitle);
    _detectAndRecordLearningEvidence(text, answerToPersist);

    try {
      await chatRepo.ensureSessionExists(
        sessionId: _sessionId,
        chapterId: _activeChapterTitle,
      );
      await chatRepo.appendMessage(
        sessionId: _sessionId,
        isUser: false,
        text: answerToPersist,
        timestamp: DateTime.now(),
      );
    } catch (error) {
      AppEnvironment.log(
        'CHAT',
        'Could not persist the tutor response: $error',
      );
    }

    if (mounted) {
      setState(() {
        _isSending = false;
        _messages[assistantIndex]
          ..['text'] = answerToPersist
          ..['formulas'] = <String>[]
          ..['hasAudio'] = false;
      });
      _scrollToBottom(force: false);
    }
  }

  void _detectAndRecordLearningEvidence(
    String studentQuestion,
    String tutorAnswer,
  ) {
    final lowerQ = studentQuestion.toLowerCase();

    // Struggle cues
    final struggleTriggers = [
      "i don't understand",
      "i do not understand",
      "i'm confused",
      "i am confused",
      "not clear",
      "still don't get",
      "can't solve",
      "cannot solve",
      "hard for me",
      "explain again",
      "too difficult",
    ];

    // Mastery cues
    final masteryTriggers = [
      "i understand now",
      "understood",
      "i get it now",
      "i got it",
      "makes sense now",
      "that makes sense",
      "clear now",
      "solved it",
      "now i understand",
    ];

    final isStruggle = struggleTriggers.any(lowerQ.contains);
    final isMastery = masteryTriggers.any(lowerQ.contains);

    if (isStruggle) {
      unawaited(
        _memoryManager.addEvidence(
          LearningEvidence(
            id: 'ev_${DateTime.now().millisecondsSinceEpoch}',
            topic: _activeChapterTitle,
            concept: _activeChapterTitle,
            observation:
                'Student expressed difficulty: "${studentQuestion.length > 60 ? '${studentQuestion.substring(0, 60)}…' : studentQuestion}"',
            isMastery: false,
            sourceType: EvidenceSourceType.directStudentStatement,
            timestamp: DateTime.now(),
          ),
        ),
      );
    } else if (isMastery) {
      unawaited(
        _memoryManager.addEvidence(
          LearningEvidence(
            id: 'ev_${DateTime.now().millisecondsSinceEpoch}',
            topic: _activeChapterTitle,
            concept: _activeChapterTitle,
            observation:
                'Student confirmed mastery: "${studentQuestion.length > 60 ? '${studentQuestion.substring(0, 60)}…' : studentQuestion}"',
            isMastery: true,
            sourceType: EvidenceSourceType.directStudentStatement,
            timestamp: DateTime.now(),
          ),
        ),
      );
    }
  }

  Widget _buildChatMessage(Map<String, dynamic> message) {
    final isUser = message['isUser'] as bool;
    final formulas = message['formulas'];
    final maxWidth = MediaQuery.of(context).size.width * 0.82;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: isUser ? IDPColors.primary : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 5),
          bottomRight: Radius.circular(isUser ? 5 : 18),
        ),
        border: isUser ? null : Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: isUser
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0A0F172A),
                  blurRadius: 12,
                  offset: Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isUser ? 'YOU' : 'ON-DEVICE LOCAL AI TUTOR',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isUser ? Colors.white70 : IDPColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 6),
          if (!isUser && message['toolStatus'] != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.build_circle_outlined,
                    size: 14,
                    color: IDPColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      message['toolStatus'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: IDPColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!isUser && message['toolOutput'] != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calculate_outlined,
                    size: 16,
                    color: IDPColors.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      message['toolOutput'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: IDPColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isUser)
            Text(
              message['text'] as String,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.5,
              ),
            )
          else
            FormattedTextWidget(
              text: message['text'] as String,
              style: const TextStyle(
                color: IDPColors.textPrimary,
                fontSize: 15,
                height: 1.55,
              ),
            ),
          if (!isUser && formulas is List<String> && formulas.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: formulas.map((formula) {
                return Chip(
                  label: Text(
                    formula,
                    style: const TextStyle(
                      color: IDPColors.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: IDPColors.primaryContainer,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          ],
          if (!isUser) ...[
            const Divider(height: 20, color: Color(0xFFE2E8F0)),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  onPressed: _showExplainDifferentlySheet,
                  icon: const Icon(Icons.lightbulb_outline, size: 16),
                  label: const Text('Explain another way'),
                ),
                _ReadAloudButton(
                  key: ValueKey('read-${message['text']}'),
                  text: message['text'] as String,
                ),
              ],
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(child: bubble),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFE2E8F0),
              child: Icon(
                Icons.person_rounded,
                color: IDPColors.textSecondary,
                size: 18,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChatSuggestions() {
    final followUps = _coordinator.latestFollowUps;
    if (followUps.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 40, bottom: 16),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: followUps.map((action) {
            return ActionChip(
              avatar: const Icon(
                Icons.auto_awesome_outlined,
                size: 16,
                color: IDPColors.primary,
              ),
              label: Text(action.label),
              labelStyle: const TextStyle(
                color: IDPColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFFCBD5E1)),
              onPressed: () {
                _sendMessageWithTopic(action.intentQuery);
              },
            );
          }).toList(),
        ),
      );
    }

    const suggestions = [
      ('Explain simply', Icons.auto_awesome_outlined),
      ('Give a real-life example', Icons.lightbulb_outline),
      ('Show the steps', Icons.format_list_numbered_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 40, bottom: 16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: suggestions.map((suggestion) {
          return ActionChip(
            avatar: Icon(suggestion.$2, size: 16, color: IDPColors.primary),
            label: Text(suggestion.$1),
            labelStyle: const TextStyle(
              color: IDPColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            backgroundColor: Colors.white,
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            onPressed: () {
              final prompt = switch (suggestion.$1) {
                'Explain simply' =>
                  'Please explain $_activeChapterTitle in simpler words for a Grade $_activeGrade student.',
                'Give a real-life example' =>
                  'Explain $_activeChapterTitle with a practical real-life example.',
                _ =>
                  'Show a clear step-by-step explanation of $_activeChapterTitle.',
              };
              _sendMessageWithTopic(prompt);
            },
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_tabController.length != 6) {
      _tabController.dispose();
      _tabController = TabController(length: 6, vsync: this);
      _tabController.addListener(() {
        if (_tabController.indexIsChanging || _tabController.index != 4) {
          print(
            '[VIDEO_DEBUG] Workspace Tab changed to ${_tabController.index}. Pausing YouTube player plugin.',
          );
          _youtubeController?.pauseVideo();
        }
      });
    }

    const primaryIndigo = IDPColors.primary;
    const slateBg = Color(0xFFF8FAFC);
    const cardBg = Color(0xFFFFFFFF);
    const borderColor = Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: slateBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Grade $_activeGrade $_activeSubjectName > $_activeChapterTitle',
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              'NCERT Class $_activeGrade $_activeSubjectName',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Color(0xFF64748B)),
            tooltip: 'Memory Policy Settings',
            onPressed: _openMemoryPolicySheet,
          ),
          IconButton(
            icon: const Icon(Icons.home_rounded, color: primaryIndigo),
            tooltip: 'Home Dashboard',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => const MentoraHomeScreen(initialTabIndex: 0),
                ),
                (route) => false,
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: primaryIndigo,
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: primaryIndigo,
          isScrollable: true,
          tabs: const [
            Tab(text: '💬 Chat'),
            Tab(text: '📖 Textbook'),
            Tab(text: '🎴 Flashcards'),
            Tab(text: '🔬 Simulation'),
            Tab(text: '🎥 Watch'),
            Tab(text: '📝 Quiz'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: CHAT WORKSPACE
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  itemCount:
                      _messages.length +
                      (_messages.length == 1 && !_isSending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) {
                      return _buildChatSuggestions();
                    }
                    return _buildChatMessage(_messages[index]);
                  },
                ),
              ),
              if (_isSending)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 15,
                        backgroundColor: IDPColors.primaryContainer,
                        child: Icon(
                          Icons.school_rounded,
                          color: IDPColors.primary,
                          size: 17,
                        ),
                      ),
                      SizedBox(width: 10),
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: primaryIndigo,
                        ),
                      ),
                      SizedBox(width: 9),
                      Text(
                        'Mentora is thinking…',
                        style: TextStyle(
                          color: IDPColors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              // INPUT BAR
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                color: cardBg,
                child: SafeArea(
                  top: false,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: 'Open voice tutor',
                        icon: const Icon(
                          Icons.mic_rounded,
                          color: primaryIndigo,
                        ),
                        onPressed: () {
                          Navigator.pushNamed(context, '/voice_overlay');
                        },
                      ),
                      Expanded(
                        child: TextField(
                          controller: _chatController,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendMessage(),
                          decoration: InputDecoration(
                            hintText: 'Ask about $_activeChapterTitle…',
                            filled: true,
                            fillColor: slateBg,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: const BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(22),
                              borderSide: const BorderSide(
                                color: primaryIndigo,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 46,
                        height: 46,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: _isSending
                                ? Colors.red.shade600
                                : primaryIndigo,
                            shape: const CircleBorder(),
                          ),
                          onPressed: _isSending
                              ? () => _coordinator.cancelActiveTurn()
                              : _sendMessage,
                          child: Icon(
                            _isSending
                                ? Icons.stop_rounded
                                : Icons.arrow_upward_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // TAB 2: TEXTBOOK PDF VIEWER
          TextbookViewerScreen(
            pdfPath: _resolvedPdfPath,
            chapterTitle: _activeChapterTitle,
            subjectName: _activeSubjectName,
            grade: _activeGrade,
            showAppBar: false,
          ),

          // TAB 3: CHAPTER FLASHCARDS DECK
          // Stable cross-restart id (Dart String.hashCode is randomized per
          // run — never use it for persisted keys). Flashcards also fall back
          // to title lookup, so this is belt-and-braces.
          ChapterFlashcardsScreen(
            chapterId: _stableChapterId,
            chapterTitle: _activeChapterTitle,
            subjectName: _activeSubjectName,
            grade: _activeGrade,
            showAppBar: false,
          ),

          // TAB 4: INTERACTIVE SIMULATION PLAYER
          _buildSimulationTab(),

          // TAB 5: YOUTUBE VIDEO LECTURE WATCH SCREEN
          _buildWatchTab(),

          // TAB 6: DIAGNOSTIC ASSESSMENT QUIZ
          _buildQuizTab(),
        ],
      ),
    );
  }

  bool get _isWebViewSupported {
    if (kIsWeb) return true;
    if (Platform.isLinux || Platform.isWindows) return false;
    return InAppWebViewPlatform.instance != null;
  }

  // STITCH TAB 2: INTERACTIVE HTML5 SIMULATION PLAYER
  Widget _buildSimulationTab() {
    const primaryIndigo = IDPColors.primary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SIMULATION CANVAS VIEWPORT WITH DYNAMIC HTML5 CANVAS ENGINE
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 230,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF334155)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: _isWebViewSupported
                  ? InAppWebView(
                      initialData: InAppWebViewInitialData(
                        data:
                            '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    html, body { width: 100%; height: 100%; background: #0F172A; font-family: sans-serif; overflow: hidden; }
    #canvas { width: 100%; height: 100%; display: block; }
    .badge { position: absolute; top: 12px; left: 12px; background: rgba(139, 92, 246, 0.2); border: 1px solid #8B5CF6; color: #C4B5FD; padding: 4px 10px; border-radius: 20px; font-size: 11px; font-weight: bold; }
  </style>
</head>
<body>
  <div class="badge">🧪 Interactive Lab: $_activeChapterTitle</div>
  <canvas id="canvas"></canvas>
  <script>
    const canvas = document.getElementById('canvas');
    const ctx = canvas.getContext('2d');
    let width, height;
    let t = 0;
    const lengthVal = $_simLength;
    const gravityVal = $_simGravity;

    function resize() {
      width = canvas.width = window.innerWidth;
      height = canvas.height = window.innerHeight;
    }
    window.addEventListener('resize', resize);
    resize();

    function draw() {
      ctx.clearRect(0, 0, width, height);
      
      // Grid background
      ctx.strokeStyle = 'rgba(51, 65, 85, 0.4)';
      ctx.lineWidth = 1;
      const step = 30;
      for (let x = 0; x < width; x += step) {
        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke();
      }
      for (let y = 0; y < height; y += step) {
        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
      }

      // Animated mathematical / physics curve
      ctx.beginPath();
      ctx.strokeStyle = '#38BDF8';
      ctx.lineWidth = 3;
      const cy = height / 2;
      for (let x = 0; x < width; x += 2) {
        const freq = 0.02 * lengthVal;
        const amp = 30 * (gravityVal / 5.0);
        const y = cy + Math.sin(x * freq + t) * amp + Math.cos(x * 0.01 - t * 0.5) * (amp * 0.4);
        if (x === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.stroke();

      // Floating particles
      ctx.fillStyle = '#8B5CF6';
      for (let i = 0; i < 8; i++) {
        const px = (width / 8) * i + Math.sin(t + i) * 20;
        const py = cy + Math.sin(px * 0.02 * lengthVal + t) * (30 * (gravityVal / 5.0));
        ctx.beginPath();
        ctx.arc(px, py, 5, 0, Math.PI * 2);
        ctx.fill();
      }

      t += 0.03;
      requestAnimationFrame(draw);
    }
    draw();
  </script>
</body>
</html>
''',
                        mimeType: 'text/html',
                        encoding: 'utf-8',
                      ),
                      initialSettings: InAppWebViewSettings(
                        javaScriptEnabled: true,
                        transparentBackground: true,
                        supportZoom: false,
                      ),
                    )
                  : NativeSimulationCanvasWidget(
                      chapterTitle: _activeChapterTitle,
                      simLength: _simLength,
                      simGravity: _simGravity,
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // PARAMETER SLIDERS CARD
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚙️ Simulation Controls',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 16),

                  // Slider 1: Intensity / Parameter 1
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'System Length (L): ${_simLength.toStringAsFixed(1)} m',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Chip(
                        label: Text(
                          '${_simLength.toStringAsFixed(1)} m',
                          style: const TextStyle(
                            color: primaryIndigo,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        backgroundColor: const Color(0xFFEEF2FF),
                      ),
                    ],
                  ),
                  Slider(
                    value: _simLength,
                    min: 0.5,
                    max: 5.0,
                    divisions: 45,
                    activeColor: primaryIndigo,
                    onChanged: (val) => setState(() => _simLength = val),
                  ),
                  const SizedBox(height: 10),

                  // Slider 2: Factor / Parameter 2
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Environmental Factor (k): ${_simGravity.toStringAsFixed(1)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Chip(
                        label: Text(
                          '${_simGravity.toStringAsFixed(1)} const',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        backgroundColor: const Color(0xFFECFDF5),
                      ),
                    ],
                  ),
                  Slider(
                    value: _simGravity.clamp(1.0, 10.0),
                    min: 1.0,
                    max: 10.0,
                    divisions: 90,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) => setState(() => _simGravity = val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // FULLSCREEN LANDSCAPE PHET SIMULATION BUTTON
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                final exp = ExperimentDescriptor(
                  id: 'phet-${_activeSubjectName.toLowerCase()}',
                  slug: _activeSubjectName.toLowerCase(),
                  title: 'PhET Interactive Simulation: $_activeChapterTitle',
                  subject: _activeSubjectName,
                  provider: 'PhET Interactive Simulations',
                  launchLocation: 'assets/phet/simulations/placeholder.html',
                  launchSource: ExperimentLaunchSource.bundledFallback,
                  publicUrl: null,
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExperimentPlayerScreen(experiment: exp),
                  ),
                );
              },
              icon: const Icon(
                Icons.screen_rotation_rounded,
                color: Colors.white,
              ),
              label: const Text(
                'Play Interactive Fullscreen (Landscape)',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryIndigo,
                padding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // STITCH TAB 3: YOUTUBE VIDEO LECTURE WATCH SCREEN
  Widget _buildWatchTab() {
    const primaryIndigo = IDPColors.primary;
    final playlist = List<Map<String, dynamic>>.from(
      _videoData?['playlist'] ?? [],
    );
    final currentVideo = _videoData?['currentVideo'] as Map<String, dynamic>?;

    final heroTitle =
        currentVideo?['title']?.toString() ??
        'NCERT Class $_activeGrade $_activeSubjectName: $_activeChapterTitle';
    final heroUrl =
        currentVideo?['videoUrl']?.toString() ??
        currentVideo?['youtubeId']?.toString();
    final videoId = heroUrl != null
        ? YouTubeUtils.extractYouTubeId(heroUrl)
        : null;

    if (_isWebViewSupported && videoId != null && _youtubeController == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _youtubeController == null) {
          setState(() {
            _initYoutubeControllerForVideo(heroUrl);
          });
        }
      });
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // EMBEDDED YOUTUBE VIDEO PLAYER INLINE WIDGET
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  _isWebViewSupported && _youtubeController != null
                      ? YoutubePlayer(controller: _youtubeController!)
                      : Container(
                          height: 200,
                          width: double.infinity,
                          color: const Color(0xFF0F172A),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.play_circle_fill,
                                color: Colors.redAccent,
                                size: 48,
                              ),
                              const SizedBox(height: 12),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Text(
                                  heroTitle,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (heroUrl != null && heroUrl.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    final uri = Uri.tryParse(heroUrl);
                                    if (uri != null) launchUrl(uri);
                                  },
                                  icon: const Icon(
                                    Icons.open_in_browser,
                                    size: 16,
                                  ),
                                  label: const Text(
                                    'Open Lecture Video in Browser',
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    color: const Color(0xFF0F172A),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.play_circle_filled,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            heroTitle,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // TITLE ROW
          Text(
            'NCERT Class $_activeGrade $_activeSubjectName: $_activeChapterTitle',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 16),

          // PLAYLIST SECTION
          Row(
            children: [
              const Expanded(
                child: Text(
                  '📚 Playlist Chapters',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              FilterChip(
                label: const Text(
                  'ISL 🤟',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                selected: _islOnly,
                onSelected: (value) => setState(() => _islOnly = value),
                tooltip: 'Show only Indian Sign Language videos',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_islOnly && !playlist.any((item) => _isIslVideo(item))) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Text(
                'No sign-language videos for this chapter yet. Showing all videos below — turn ISL off to browse.',
                style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
              ),
            ),
            const SizedBox(height: 8),
          ],
          ...playlist.where((item) => !_islOnly || _isIslVideo(item)).map((
            item,
          ) {
            final itemTitle = item['title']?.toString() ?? 'Video Chapter';
            final itemUrl =
                item['videoUrl']?.toString() ??
                item['youtubeId']?.toString() ??
                '';
            final itemDuration = item['duration']?.toString() ?? '10:00';
            final itemChannel = item['channel']?.toString() ?? 'NCERT';

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: ListTile(
                onTap: () {
                  print(
                    '[VIDEO_DEBUG] Tapped Workspace Playlist Item "$itemTitle". Launching VideoPlayerScreen with URL "$itemUrl"',
                  );
                  _initYoutubeControllerForVideo(itemUrl);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => VideoPlayerScreen(
                        videoUrl: itemUrl,
                        title: itemTitle,
                        subtitle:
                            '$itemChannel • Grade $_activeGrade $_activeChapterTitle',
                        description: item['description']?.toString(),
                      ),
                    ),
                  );
                },
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFEEF2FF),
                  child: Icon(
                    Icons.play_circle_fill,
                    color: primaryIndigo,
                    size: 20,
                  ),
                ),
                title: Text(
                  itemTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  itemChannel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                  ),
                ),
                trailing: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      itemDuration,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    if (_isIslVideo(item))
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'ISL 🤟',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // STITCH TAB 4: DIAGNOSTIC ASSESSMENT QUIZ
  Widget _buildQuizTab() {
    const primaryIndigo = IDPColors.primary;
    final questions = List<Map<String, dynamic>>.from(
      _quizData?['questions'] ?? [],
    );
    if (questions.isEmpty)
      return const Center(child: CircularProgressIndicator());

    if (_quizComplete) {
      return _buildQuizResults(questions.length);
    }

    final currentQ = questions[_currentQuestionIndex];
    final options = List<String>.from(currentQ['options']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PROGRESS HEADER BAR
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Question ${_currentQuestionIndex + 1} of ${questions.length} • Score: $_score',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                  fontSize: 13,
                ),
              ),
              Chip(
                label: Text(
                  '${_quizData?['userMastery'] ?? 0}% Mastered',
                  style: const TextStyle(
                    color: Color(0xFF059669),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                backgroundColor: const Color(0xFFECFDF5),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // QUESTION CARD
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                currentQ['question'] as String,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF0F172A),
                  height: 1.4,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // MCQ OPTIONS
          ...List.generate(options.length, (idx) {
            final isSelected = _selectedOptionIndex == idx;
            final isCorrect = currentQ['correctIndex'] == idx;

            Color optionBg = Colors.white;
            Color optionBorder = const Color(0xFFE2E8F0);
            if (_showExplanation) {
              if (isCorrect) {
                optionBg = const Color(0xFFECFDF5);
                optionBorder = const Color(0xFF10B981);
              } else if (isSelected) {
                optionBg = const Color(0xFFFEF2F2);
                optionBorder = const Color(0xFFEF4444);
              }
            } else if (isSelected) {
              optionBg = const Color(0xFFEEF2FF);
              optionBorder = primaryIndigo;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: optionBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: optionBorder,
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: ListTile(
                onTap: () {
                  if (!_showExplanation) {
                    setState(() => _selectedOptionIndex = idx);
                  }
                },
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: isSelected
                      ? primaryIndigo
                      : const Color(0xFFF1F5F9),
                  child: Text(
                    String.fromCharCode(65 + idx),
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF0F172A),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Text(
                  options[idx],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 16),
          if (!_showExplanation && _selectedOptionIndex != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final isCorrect =
                      _selectedOptionIndex == currentQ['correctIndex'];
                  setState(() {
                    _showExplanation = true;
                    if (isCorrect) {
                      _score++;
                    }
                  });
                  final chapterId = _activeChapterTitle;
                  unawaited(
                    QuizResultRepository()
                        .saveResult(
                          QuizResult(
                            chapterId: chapterId,
                            score: isCorrect ? 1 : 0,
                            totalQuestions: 1,
                            answers: {
                              _currentQuestionIndex: _selectedOptionIndex ?? 0,
                            },
                            attemptedAt: DateTime.now(),
                          ),
                        )
                        .catchError((e) {
                          AppEnvironment.log(
                            'QUIZ',
                            'Failed saving workspace quiz result: $e',
                          );
                          return -1;
                        }),
                  );
                  unawaited(
                    ProgressRepository()
                        .recordQuestionAsked(chapterId: chapterId)
                        .catchError(
                          (e) => AppEnvironment.log(
                            'PROGRESS',
                            'Failed recording workspace question: $e',
                          ),
                        ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryIndigo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Submit Answer',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

          if (_showExplanation) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '💡 Explanation:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentQ['explanation'] as String,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF334155),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (_currentQuestionIndex < questions.length - 1) {
                    setState(() {
                      _currentQuestionIndex += 1;
                      _selectedOptionIndex = null;
                      _showExplanation = false;
                    });
                  } else {
                    setState(() {
                      _quizComplete = true;
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryIndigo,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _currentQuestionIndex < questions.length - 1
                      ? 'Next Question'
                      : 'View Results',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuizResults(int totalQuestions) {
    final percentage = totalQuestions == 0
        ? 0
        : ((_score / totalQuestions) * 100).round();
    final passed = percentage >= 60;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          Icon(
            passed ? Icons.emoji_events_rounded : Icons.school_rounded,
            size: 72,
            color: passed ? const Color(0xFF10B981) : const Color(0xFF64748B),
          ),
          const SizedBox(height: 16),
          Text(
            passed ? 'Quiz Complete!' : 'Keep Practising',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You scored $_score out of $totalQuestions ($percentage%).',
            style: const TextStyle(fontSize: 14, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  _currentQuestionIndex = 0;
                  _selectedOptionIndex = null;
                  _showExplanation = false;
                  _quizComplete = false;
                  _score = 0;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: IDPColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Restart Quiz',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NativeSimulationCanvasWidget extends StatefulWidget {
  const NativeSimulationCanvasWidget({
    super.key,
    required this.chapterTitle,
    required this.simLength,
    required this.simGravity,
  });

  final String chapterTitle;
  final double simLength;
  final double simGravity;

  @override
  State<NativeSimulationCanvasWidget> createState() =>
      _NativeSimulationCanvasWidgetState();
}

class _NativeSimulationCanvasWidgetState
    extends State<NativeSimulationCanvasWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Stack(
          children: [
            CustomPaint(
              size: Size.infinite,
              painter: _SimulationPainter(
                time: _controller.value * 20,
                lengthVal: widget.simLength,
                gravityVal: widget.simGravity,
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x338B5CF6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF8B5CF6)),
                ),
                child: Text(
                  '🧪 Interactive Lab (Native Desktop): ${widget.chapterTitle}',
                  style: const TextStyle(
                    color: Color(0xFFC4B5FD),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SimulationPainter extends CustomPainter {
  _SimulationPainter({
    required this.time,
    required this.lengthVal,
    required this.gravityVal,
  });

  final double time;
  final double lengthVal;
  final double gravityVal;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final gridPaint = Paint()
      ..color = const Color(0x66334155)
      ..strokeWidth = 1;

    const step = 30.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final wavePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final path = Path();
    final cy = size.height / 2;
    for (double x = 0; x < size.width; x += 2) {
      final freq = 0.02 * lengthVal;
      final amp = 30 * (gravityVal / 5.0);
      final y =
          cy +
          math.sin(x * freq + time) * amp +
          math.cos(x * 0.01 - time * 0.5) * (amp * 0.4);
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, wavePaint);

    final particlePaint = Paint()..color = const Color(0xFF8B5CF6);
    for (int i = 0; i < 8; i++) {
      final px = (size.width / 8) * i + math.sin(time + i) * 20;
      final py =
          cy +
          math.sin(px * 0.02 * lengthVal + time) * (30 * (gravityVal / 5.0));
      canvas.drawCircle(Offset(px, py), 5, particlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SimulationPainter oldDelegate) =>
      oldDelegate.time != time ||
      oldDelegate.lengthVal != lengthVal ||
      oldDelegate.gravityVal != gravityVal;
}

/// Reads a tutor answer aloud using the on-device TTS engine.
class _ReadAloudButton extends StatefulWidget {
  const _ReadAloudButton({super.key, required this.text});

  final String text;

  @override
  State<_ReadAloudButton> createState() => _ReadAloudButtonState();
}

class _ReadAloudButtonState extends State<_ReadAloudButton> {
  final OfflineSpeechService _speech = OfflineSpeechService();
  bool _speaking = false;
  int _requestId = 0;

  Future<void> _toggle() async {
    if (_speaking) {
      _requestId++;
      await _speech.stopSpeaking();
      if (mounted) {
        setState(() => _speaking = false);
      }
      return;
    }

    final requestId = ++_requestId;
    setState(() => _speaking = true);
    final languageCode = LanguageProvider.shared.languageCode;
    final available = await _speech.isLanguageAvailable(languageCode);
    if (!mounted || requestId != _requestId) return;
    if (!available) {
      setState(() => _speaking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No offline voice is installed for $languageCode. '
            'Install the language in your device text-to-speech settings.',
          ),
        ),
      );
      return;
    }

    await _speech.speakText(widget.text, languageCode: languageCode);
    if (!mounted || requestId != _requestId) return;
    setState(() => _speaking = false);
  }

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: _toggle,
      icon: Icon(
        _speaking ? Icons.stop_rounded : Icons.volume_up_rounded,
        size: 16,
      ),
      label: Text(_speaking ? 'Stop' : 'Listen'),
    );
  }
}
