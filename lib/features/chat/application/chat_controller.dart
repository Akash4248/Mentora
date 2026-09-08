import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local/chat_memory_policy_repository.dart';
import '../../translation/data/local/translation_engine_config_service.dart';
import '../data/local/linux_llm_config_service.dart';
import '../data/tutor_inference_gateway.dart';
import '../data/local/chat_session_repository.dart';
import '../domain/chat_view_state.dart';
import '../domain/tutor_message.dart';
import 'chat_providers.dart';

class ChatController extends StateNotifier<ChatViewState> {
  ChatController({
    required TutorInferenceGateway gateway,
    required ChatSessionRepository sessionRepo,
    required ChatMemoryPolicyRepository memoryPolicyRepo,
  })  : _gateway = gateway,
        _sessionRepo = sessionRepo,
        _memoryPolicyRepo = memoryPolicyRepo,
        super(ChatViewState(
          memoryPolicy: ChatMemoryPolicy.defaults('session'),
          translationConfig: TranslationEngineConfig.defaults,
          linuxConfig: LinuxLlmConfig.defaults,
        ));

  final TutorInferenceGateway _gateway;
  final ChatSessionRepository _sessionRepo;
  final ChatMemoryPolicyRepository _memoryPolicyRepo;

  Future<void> initializeSession({
    required String sessionId,
    required String chapterId,
    required String welcomeMessage,
  }) async {
    state = state.copyWith(isBootstrapping: true, sessionId: sessionId);

    try {
      await _sessionRepo.ensureSessionExists(
        sessionId: sessionId,
        chapterId: chapterId,
      );
      final policy = await _memoryPolicyRepo.getPolicy(sessionId);
      final history = await _sessionRepo.getMessages(sessionId);

      final initialMessages = history.isNotEmpty
          ? history
          : [
              TutorMessage(
                text: welcomeMessage,
                isUser: false,
                timestamp: DateTime.now(),
              )
            ];

      state = state.copyWith(
        messages: initialMessages,
        memoryPolicy: policy,
        isBootstrapping: false,
      );
    } catch (e) {
      state = state.copyWith(
        messages: [
          TutorMessage(
            text: welcomeMessage,
            isUser: false,
            timestamp: DateTime.now(),
          )
        ],
        isBootstrapping: false,
        error: e.toString(),
      );
    }
  }

  Future<void> updateMemoryPolicy({
    int? shortTermWindow,
    bool? semanticRecallEnabled,
    int? semanticTopK,
    SessionResetPolicy? resetPolicy,
    int? inactivityMinutes,
  }) async {
    final current = state.memoryPolicy;
    final updated = current.copyWith(
      shortTermWindow: shortTermWindow ?? current.shortTermWindow,
      semanticRecallEnabled: semanticRecallEnabled ?? current.semanticRecallEnabled,
      semanticTopK: semanticTopK ?? current.semanticTopK,
      resetPolicy: resetPolicy ?? current.resetPolicy,
      inactivityMinutes: inactivityMinutes ?? current.inactivityMinutes,
    );

    state = state.copyWith(memoryPolicy: updated);
    if (state.sessionId != null) {
      await _memoryPolicyRepo.savePolicy(updated);
    }
  }

  void setChatMode(String mode) {
    state = state.copyWith(chatMode: mode);
  }

  void addMessage(TutorMessage message) {
    final updated = [...state.messages, message];
    state = state.copyWith(messages: updated);
    
    // Save to SQLite (skips transient 'Thinking...' placeholders)
    if (state.sessionId != null && (message.isUser || message.text.trim() != 'Thinking...')) {
      _sessionRepo.appendMessage(
        sessionId: state.sessionId!,
        isUser: message.isUser,
        text: message.text,
        timestamp: message.timestamp,
      );
    }
  }

  void updateLastMessage(String text) {
    if (state.messages.isEmpty) return;
    final updated = List<TutorMessage>.from(state.messages);
    final last = updated.last;
    updated[updated.length - 1] = TutorMessage(
      text: text,
      isUser: last.isUser,
      timestamp: last.timestamp,
    );
    state = state.copyWith(messages: updated);
  }

  Future<void> persistCompletedAssistantMessage(String finalAnswer) async {
    if (state.sessionId == null || finalAnswer.trim().isEmpty) return;
    updateLastMessage(finalAnswer);
    await _sessionRepo.updateLastAssistantMessage(
      sessionId: state.sessionId!,
      text: finalAnswer,
    );
  }

  void setGenerating(bool generating) {
    state = state.copyWith(isGenerating: generating);
  }
}

final chatControllerProvider =
    StateNotifierProvider.family<ChatController, ChatViewState, String>((ref, sessionId) {
  final gateway = ref.watch(tutorInferenceGatewayProvider);
  final sessionRepo = ref.watch(chatSessionRepositoryProvider);
  final memoryPolicyRepo = ref.watch(chatMemoryPolicyRepositoryProvider);

  return ChatController(
    gateway: gateway,
    sessionRepo: sessionRepo,
    memoryPolicyRepo: memoryPolicyRepo,
  );
});
