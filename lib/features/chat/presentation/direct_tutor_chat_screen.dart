import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/idp_colors.dart';
import '../../../core/theme/idp_theme.dart';
import '../../network/services/mentora_backend_client.dart';
import '../application/context_builder.dart';
import '../application/mentora_agent_session.dart';
import '../application/mentora_tutor_agent_provider.dart';
import '../application/three_tier_memory_manager.dart';
import '../application/tutor_session_coordinator.dart';
import '../data/local/chat_memory_policy_repository.dart';
import '../data/local/chat_session_repository.dart';
import '../domain/capability_registry.dart';
import '../domain/default_capabilities.dart';
import '../domain/learning_evidence.dart';
import 'formatted_text_widget.dart';
import 'widgets/chat_memory_policy_sheet.dart';

/// Direct AI Tutor screen providing open, general conversational tutoring across
/// NCERT science and math without requiring chapter packs or pre-downloaded curriculum assets.
class DirectTutorChatScreen extends StatefulWidget {
  const DirectTutorChatScreen({super.key});

  @override
  State<DirectTutorChatScreen> createState() => _DirectTutorChatScreenState();
}

class _DirectTutorChatScreenState extends State<DirectTutorChatScreen> {
  static const String _sessionId = 'direct_open_ai_tutor_session';

  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final MentoraBackendClient _client = MentoraBackendClient();
  final MentoraTutorAgentProvider _agentProvider = MentoraTutorAgentProvider();
  final ChatSessionRepository _chatRepo = ChatSessionRepository();

  late final ThreeTierMemoryManager _memoryManager;
  late final CapabilityRegistry _capabilityRegistry;
  late final ContextBuilder _contextBuilder;
  late final TutorSessionCoordinator _coordinator;

  int _activeGrade = 9;
  final String _activeTopic = 'General Science & Mathematics';
  bool _isSending = false;
  ChatMemoryPolicy? _memoryPolicy;
  final List<Map<String, dynamic>> _messages = [];

  static const List<int> _availableGrades = [6, 7, 8, 9, 10, 11, 12];

  @override
  void initState() {
    super.initState();
    _memoryManager = ThreeTierMemoryManager();
    _capabilityRegistry = DefaultCapabilities.createDefaultRegistry(client: _client);
    _contextBuilder = ContextBuilder(
      registry: _capabilityRegistry,
      memoryManager: _memoryManager,
    );
    _coordinator = TutorSessionCoordinator(
      agentProvider: _agentProvider,
      initialTopic: _activeTopic,
      initialGrade: _activeGrade,
      capabilityRegistry: _capabilityRegistry,
      contextBuilder: _contextBuilder,
    );

    _loadInitialState();
  }

  @override
  void dispose() {
    unawaited(_coordinator.dispose());
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedGrade = prefs.getInt('selected_grade') ?? 9;
      final policy = await ChatMemoryPolicyRepository().getPolicy(_sessionId);
      final savedMessages = await _chatRepo.getMessages(_sessionId);

      if (mounted) {
        setState(() {
          _activeGrade = savedGrade;
          _memoryPolicy = policy;
          _coordinator.updateTopicAndGrade(topic: _activeTopic, grade: savedGrade);

          if (savedMessages.isNotEmpty) {
            _messages.clear();
            for (var i = 0; i < savedMessages.length; i++) {
              final m = savedMessages[i];
              String? question;
              if (!m.isUser && i > 0 && savedMessages[i - 1].isUser) {
                question = savedMessages[i - 1].text;
              }
              _messages.add({
                'isUser': m.isUser,
                'text': m.text,
                'question': question,
                'timestamp': m.timestamp,
              });
            }
          }
        });
        _scrollToBottom(force: true);
      }
    } catch (_) {}
  }

  void _scrollToBottom({bool animated = true, bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final currentOffset = _scrollController.offset;
      final distanceToBottom = maxExtent - currentOffset;

      if (!force && distanceToBottom > 160) return;

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

  Future<void> _changeGrade(int newGrade) async {
    if (_activeGrade == newGrade) return;
    setState(() {
      _activeGrade = newGrade;
    });
    _coordinator.updateTopicAndGrade(topic: _activeTopic, grade: newGrade);
  }

  Future<void> _clearChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Start New Chat?'),
        content: const Text('This will clear the current open conversation history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _chatRepo.clearMessages(_sessionId);
      if (mounted) {
        setState(() {
          _messages.clear();
        });
      }
    }
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
        topic: _activeTopic,
        onPolicyChanged: ({
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

  Future<void> _sendMessage(String text) async {
    final clean = text.trim();
    if (clean.isEmpty || _isSending) return;

    _textController.clear();
    final userTimestamp = DateTime.now();

    setState(() {
      _messages.add({
        'isUser': true,
        'text': clean,
        'timestamp': userTimestamp,
      });
      _messages.add({
        'isUser': false,
        'text': '',
        'question': clean,
        'timestamp': DateTime.now(),
        'toolStatus': null,
        'toolOutput': null,
      });
      _isSending = true;
    });
    final assistantIndex = _messages.length - 1;
    _scrollToBottom(force: true);

    try {
      await _chatRepo.ensureSessionExists(
        sessionId: _sessionId,
        chapterId: 'general_ai_tutor',
      );
      await _chatRepo.appendMessage(
        sessionId: _sessionId,
        isUser: true,
        text: clean,
        timestamp: userTimestamp,
      );
    } catch (_) {}

    final answer = StringBuffer();
    var answerToPersist = '';

    try {
      await for (final event in _coordinator.submitQuestion(
        clean,
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
                  _messages[assistantIndex]['toolStatus'] = '✓ $label completed';
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
    }

    if (answerToPersist.isEmpty) {
      answerToPersist = answer.toString().trim();
    }
    if (answerToPersist.isEmpty) {
      answerToPersist = '⚠️ The tutor returned no answer. Please try again.';
    }

    // Automatic concept & learning evidence tracking
    _memoryManager.recordSessionConcept(_sessionId, _activeTopic);
    _detectAndRecordLearningEvidence(clean, answerToPersist);

    try {
      await _chatRepo.ensureSessionExists(
        sessionId: _sessionId,
        chapterId: 'general_ai_tutor',
      );
      await _chatRepo.appendMessage(
        sessionId: _sessionId,
        isUser: false,
        text: answerToPersist,
        timestamp: DateTime.now(),
      );
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isSending = false;
        _messages[assistantIndex]['text'] = answerToPersist;
      });
      _scrollToBottom(force: false);
    }
  }

  void _detectAndRecordLearningEvidence(String studentQuestion, String tutorAnswer) {
    final lowerQ = studentQuestion.toLowerCase();
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
            topic: _activeTopic,
            concept: _activeTopic,
            observation: 'Student expressed difficulty: "${studentQuestion.length > 60 ? '${studentQuestion.substring(0, 60)}…' : studentQuestion}"',
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
            topic: _activeTopic,
            concept: _activeTopic,
            observation: 'Student confirmed mastery: "${studentQuestion.length > 60 ? '${studentQuestion.substring(0, 60)}…' : studentQuestion}"',
            isMastery: true,
            sourceType: EvidenceSourceType.directStudentStatement,
            timestamp: DateTime.now(),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0.5,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: IDPColors.primary, size: 18),
                SizedBox(width: 6),
                Text(
                  'Mentora AI Tutor',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Text(
              'Open Chat • Class $_activeGrade',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Change Grade',
            initialValue: _activeGrade,
            onSelected: _changeGrade,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Row(
                children: [
                  Text(
                    'Class $_activeGrade',
                    style: const TextStyle(
                      color: IDPColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, color: IDPColors.primary, size: 18),
                ],
              ),
            ),
            itemBuilder: (context) => _availableGrades
                .map(
                  (g) => PopupMenuItem<int>(
                    value: g,
                    child: Text('Class $g'),
                  ),
                )
                .toList(),
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, color: Color(0xFF64748B)),
            tooltip: 'Memory Policy',
            onPressed: _openMemoryPolicySheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
            tooltip: 'New Conversation',
            onPressed: _clearChat,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _messages.isEmpty ? _buildWelcomeView() : _buildMessageList(),
            ),
            _buildFollowUpSuggestions(),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeView() {
    final starterPrompts = [
      ('🔢 Solve Math Problem', 'Solve 2x + 5 = 15 step-by-step with clear reasoning.'),
      ('⚡ Physics Concept', 'Explain Newton\'s laws of motion with real-world examples.'),
      ('🧬 Biology Question', 'What is the role of mitochondria in a plant vs animal cell?'),
      ('🔬 Simulation Finder', 'Find an interactive simulation for gravity or pendulum.'),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFC7D2FE), width: 2),
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: IDPColors.primary, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'Direct AI Tutor',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Ask any question across science, mathematics, formulas, or homework. Works instantly without downloading any chapter packs!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.5),
          ),
          const SizedBox(height: 28),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Try asking:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: Color(0xFF334155),
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: starterPrompts.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final prompt = starterPrompts[index];
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _sendMessage(prompt.$2),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x060F172A),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              prompt.$1,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: IDPColors.primary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              prompt.$2,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFF94A3B8)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final isUser = message['isUser'] as bool;
    final maxWidth = MediaQuery.of(context).size.width * 0.82;

    final bubble = Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: isUser ? IDPColors.primary : Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(18),
          topRight: const Radius.circular(18),
          bottomLeft: Radius.circular(isUser ? 18 : 4),
          bottomRight: Radius.circular(isUser ? 4 : 18),
        ),
        border: isUser ? null : Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: isUser
            ? null
            : const [
                BoxShadow(
                  color: Color(0x080F172A),
                  blurRadius: 10,
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
              letterSpacing: 0.6,
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
                  const Icon(Icons.build_circle_outlined, size: 14, color: IDPColors.primary),
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
                  const Icon(Icons.calculate_outlined, size: 16, color: IDPColors.primary),
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
              studentQuestion: message['question'] as String?,
              style: const TextStyle(
                color: IDPColors.textPrimary,
                fontSize: 15,
                height: 1.55,
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(child: bubble),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 15,
              backgroundColor: Color(0xFFE2E8F0),
              child: Icon(Icons.person_rounded, color: IDPColors.textSecondary, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFollowUpSuggestions() {
    final followUps = _coordinator.latestFollowUps;
    if (followUps.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: followUps.map((action) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.auto_awesome_outlined, size: 14, color: IDPColors.primary),
                label: Text(action.label),
                labelStyle: const TextStyle(
                  color: IDPColors.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFCBD5E1)),
                onPressed: () => _sendMessage(action.intentQuery),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildComposer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: _sendMessage,
                decoration: const InputDecoration(
                  hintText: 'Ask any math, science, or formula question…',
                  hintStyle: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _isSending ? Icons.stop_circle_rounded : Icons.send_rounded,
              color: IDPColors.primary,
              size: 28,
            ),
            onPressed: _isSending
                ? () => _coordinator.cancelActiveTurn()
                : () => _sendMessage(_textController.text),
          ),
        ],
      ),
    );
  }
}
