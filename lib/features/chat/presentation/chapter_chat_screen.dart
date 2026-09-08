import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/idp_colors.dart';
import '../../course/domain/course_tree.dart';
import '../domain/tutor_message.dart';
import '../domain/chat_view_state.dart';
import '../application/chat_controller.dart';
import '../application/chat_providers.dart';
import '../application/conversation_memory_harness.dart';
import '../data/tutor_inference_gateway.dart';
import 'widgets/chat_app_bar.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_memory_policy_sheet.dart';

class ChapterChatScreen extends ConsumerStatefulWidget {
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
  ConsumerState<ChapterChatScreen> createState() => _ChapterChatScreenState();
}

class _ChapterChatScreenState extends ConsumerState<ChapterChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ConversationMemoryHarness _memoryHarness = ConversationMemoryHarness();
  late String _sessionId;

  @override
  void initState() {
    super.initState();
    _sessionId = 'session_${widget.course.id}_${widget.subject.id}_${widget.chapter.id}';
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final welcome = 'Welcome to ${widget.course.name} ${widget.subject.name}: *${widget.chapter.title}*! 👋\n\n'
          'I am your Mentora Socratic AI Tutor. Ask me any question or concept related to *${widget.chapter.title}* to begin learning.';

      ref.read(chatControllerProvider(_sessionId).notifier).initializeSession(
            sessionId: _sessionId,
            chapterId: widget.chapter.id,
            welcomeMessage: welcome,
          );
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _handleSendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final controller = ref.read(chatControllerProvider(_sessionId).notifier);
    final gateway = ref.read(tutorInferenceGatewayProvider);
    final state = ref.read(chatControllerProvider(_sessionId));

    _inputController.clear();
    final userMsg = TutorMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
    );
    controller.addMessage(userMsg);
    controller.setGenerating(true);
    _scrollToBottom();

    try {
      final contextualPrompt = await _memoryHarness.buildContextualPrompt(
        history: state.messages,
        currentQuestion: text,
        chapterTitle: widget.chapter.title,
        courseName: widget.course.name,
        policy: state.memoryPolicy,
      );

      final responseBuffer = StringBuffer();
      final placeholderMsg = TutorMessage(
        text: 'Thinking...',
        isUser: false,
        timestamp: DateTime.now(),
      );
      controller.addMessage(placeholderMsg);

      await for (final token in gateway.streamResponse(
        prompt: contextualPrompt,
      )) {
        responseBuffer.write(token);
        controller.updateLastMessage(responseBuffer.toString());
        _scrollToBottom();
      }

      final finalAnswer = responseBuffer.toString();
      if (finalAnswer.isNotEmpty) {
        await controller.persistCompletedAssistantMessage(finalAnswer);
      }
    } catch (e) {
      final errorMsg = 'I faced an issue retrieving the response: $e';
      await controller.persistCompletedAssistantMessage(errorMsg);
    } finally {
      controller.setGenerating(false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _openMemoryPolicySheet(ChatViewState state) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ChatMemoryPolicySheet(
          policy: state.memoryPolicy,
          onPolicyChanged: ({
            shortTermWindow,
            semanticRecallEnabled,
            semanticTopK,
            resetPolicy,
            inactivityMinutes,
          }) {
            ref.read(chatControllerProvider(_sessionId).notifier).updateMemoryPolicy(
                  shortTermWindow: shortTermWindow,
                  semanticRecallEnabled: semanticRecallEnabled,
                  semanticTopK: semanticTopK,
                  resetPolicy: resetPolicy,
                  inactivityMinutes: inactivityMinutes,
                );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider(_sessionId));

    return Scaffold(
      backgroundColor: IDPColors.background,
      appBar: ChatAppBar(
        title: '${widget.subject.name} - ${widget.chapter.title}',
        subtitle: '${widget.course.name} NCERT • Offline Socratic Tutor',
        activeModel: 'On-Device GGUF Llama-3',
        isOfflineMode: true,
        onOpenMemoryPolicy: () => _openMemoryPolicySheet(state),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ChatMessageList(
                messages: state.messages,
                scrollController: _scrollController,
                isGenerating: state.isGenerating,
              ),
            ),
            ChatInputBar(
              controller: _inputController,
              onSend: _handleSendMessage,
              isGenerating: state.isGenerating,
            ),
          ],
        ),
      ),
    );
  }
}
