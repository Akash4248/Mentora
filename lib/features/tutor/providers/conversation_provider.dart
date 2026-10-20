import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../language/models/app_language.dart';
import '../../simulation_context/providers/simulation_context_provider.dart';
import '../../voice/models/voice_event.dart';
import '../../voice/providers/voice_connection_provider.dart';
import '../../voice/providers/voice_provider.dart';
import '../models/conversation_message.dart';
import '../models/conversation_state.dart';

// ─── State ──────────────────────────────────────────────────────────

class ConversationProviderState {
  const ConversationProviderState({
    this.state = ConversationState.idle,
    this.messages = const [],
    this.partialTranscript = '',
    this.finalTranscript = '',
    this.responseLatency = Duration.zero,
  });

  final ConversationState state;
  final List<ConversationMessage> messages;
  final String partialTranscript;
  final String finalTranscript;
  final Duration responseLatency;

  ConversationProviderState copyWith({
    ConversationState? state,
    List<ConversationMessage>? messages,
    String? partialTranscript,
    String? finalTranscript,
    Duration? responseLatency,
  }) {
    return ConversationProviderState(
      state: state ?? this.state,
      messages: messages ?? this.messages,
      partialTranscript: partialTranscript ?? this.partialTranscript,
      finalTranscript: finalTranscript ?? this.finalTranscript,
      responseLatency: responseLatency ?? this.responseLatency,
    );
  }
}
// ─── Notifier ───────────────────────────────────────────────────────

class ConversationNotifier extends StateNotifier<ConversationProviderState> {
  ConversationNotifier({required this.ref})
    : super(const ConversationProviderState()) {
    // Auto-attach after the provider graph settles so voiceConnectionProvider
    // is fully initialised before we try to read it.
    Future.microtask(attachToSocket);
  }

  final Ref ref;
  // NOTE: Audio playback is handled entirely by VoiceNotifier._streamPlayer.
  // ConversationNotifier does NOT own a VoiceStreamPlayer — having two separate
  // players was the root cause of silent audio output (chunks were queued into
  // an unconnected player that nobody ever read from).
  StreamSubscription<VoiceEvent>? _eventSub;
  StreamSubscription<VoiceEvent>? _offlineEventSub;
  DateTime? _requestTimestamp;
  int _messageCounter = 0;

  /// Start listening to voice events from the socket and the offline pipeline.
  void attachToSocket() {
    final socket = ref.read(voiceConnectionProvider.notifier).socket;
    _eventSub?.cancel();
    _eventSub = socket.eventStream.listen(_onVoiceEvent);

    _offlineEventSub?.cancel();
    _offlineEventSub = ref
        .read(voiceProvider.notifier)
        .offlineEventStream
        .listen(_onVoiceEvent);
  }

  // ─── Public API ─────────────────────────────────────────────────

  /// Start a new conversation turn: begin recording.
  Future<void> startListening({String languageCode = 'en'}) async {
    // Interrupt any ongoing playback via VoiceNotifier
    await ref.read(voiceProvider.notifier).stopPlayback();
    state = state.copyWith(
      state: ConversationState.listening,
      partialTranscript: '',
      finalTranscript: '',
    );
    await ref
        .read(voiceProvider.notifier)
        .startRecording(languageCode: languageCode);
  }

  /// Stop recording and send audio to server.
  Future<void> stopListeningAndSend() async {
    state = state.copyWith(state: ConversationState.transcribing);
    _requestTimestamp = DateTime.now();
    await ref
        .read(voiceProvider.notifier)
        .stopRecording(context: _buildContextPayload());
  }

  Map<String, dynamic>? _buildContextPayload() {
    final context = ref.read(simulationContextProvider);
    return context.hasContext ? context.toJson() : null;
  }

  /// Handle a transcript received from server.
  void onTranscriptReceived(String text, {required bool isFinal}) {
    if (isFinal) {
      state = state.copyWith(finalTranscript: text, partialTranscript: '');
    } else {
      state = state.copyWith(partialTranscript: text);
    }
  }

  /// Handle tutor response text from server.
  void onAssistantResponse(String text, AppLanguage language) {
    final latency = _requestTimestamp != null
        ? DateTime.now().difference(_requestTimestamp!)
        : Duration.zero;

    final message = ConversationMessage(
      id: 'msg_${++_messageCounter}',
      role: MessageRole.assistant,
      text: text,
      language: language,
      timestamp: DateTime.now(),
    );

    final updatedMessages = [...state.messages];
    if (updatedMessages.isNotEmpty &&
        updatedMessages.last.role == MessageRole.assistant) {
      updatedMessages[updatedMessages.length - 1] = message;
    } else {
      updatedMessages.add(message);
    }

    state = state.copyWith(
      state: ConversationState.speaking,
      messages: updatedMessages,
      responseLatency: latency,
    );
  }

  /// Called when tutor audio playback finishes.
  void onSpeakingComplete() {
    state = state.copyWith(state: ConversationState.idle);
  }

  /// Add a student message to the history.
  void addStudentMessage(String text, AppLanguage language) {
    final message = ConversationMessage(
      id: 'msg_${++_messageCounter}',
      role: MessageRole.student,
      text: text,
      language: language,
      timestamp: DateTime.now(),
    );
    state = state.copyWith(messages: [...state.messages, message]);
  }

  /// Clear all history and return to idle.
  void reset() {
    state = const ConversationProviderState();
    _messageCounter = 0;
    _requestTimestamp = null;
  }

  // ─── Internal: voice event routing ──────────────────────────────

  void _onVoiceEvent(VoiceEvent event) {
    switch (event.type) {
      case VoiceEventType.partialTranscript:
        // event.payload['text'] is populated by VoiceEvent.fromJson which merges
        // the backend's top-level "text" key into payload.
        onTranscriptReceived(
          event.payload['text'] as String? ?? '',
          isFinal: false,
        );
        break;

      case VoiceEventType.sessionAcknowledged:
        state = state.copyWith(state: ConversationState.listening);
        break;

      case VoiceEventType.finalTranscript:
        final text = event.payload['text'] as String? ?? '';
        onTranscriptReceived(text, isFinal: true);
        addStudentMessage(
          text,
          AppLanguage.fromCode(
            event.language ?? event.payload['language'] as String? ?? 'en',
          ),
        );
        state = state.copyWith(state: ConversationState.translating);
        break;

      case VoiceEventType.responseChunk:
        final chunk = event.payload['text'] as String? ?? '';
        if (chunk.isNotEmpty) {
          final currentMessages = [...state.messages];
          if (currentMessages.isNotEmpty &&
              currentMessages.last.role == MessageRole.assistant) {
            final last = currentMessages.removeLast();
            currentMessages.add(
              ConversationMessage(
                id: last.id,
                role: last.role,
                text: '${last.text}$chunk',
                language: last.language,
                timestamp: last.timestamp,
              ),
            );
          } else {
            currentMessages.add(
              ConversationMessage(
                id: 'msg_${++_messageCounter}',
                role: MessageRole.assistant,
                text: chunk,
                language: AppLanguage.fromCode(
                  event.language ??
                      event.payload['language'] as String? ??
                      'en',
                ),
                timestamp: DateTime.now(),
              ),
            );
          }
          state = state.copyWith(
            messages: currentMessages,
            state: ConversationState.thinking,
          );
        }
        break;

      case VoiceEventType.responseComplete:
        state = state.copyWith(state: ConversationState.generatingAudio);
        break;

      case VoiceEventType.assistantMessage:
        final text = event.payload['text'] as String? ?? '';
        final langCode = event.payload['language'] as String? ?? 'en';
        onAssistantResponse(text, AppLanguage.fromCode(langCode));
        break;

      case VoiceEventType.generatingAudio:
        state = state.copyWith(state: ConversationState.generatingAudio);
        break;

      case VoiceEventType.audioChunk:
        // Audio playback is delegated entirely to VoiceNotifier which owns the
        // single VoiceStreamPlayer. event.data contains the base64 bytes
        // (backend sends "data" as a top-level key, already mapped by fromJson).
        final b64 = event.data;
        if (b64 != null && b64.isNotEmpty) {
          ref.read(voiceProvider.notifier).queueAudioChunk(b64);
        }
        state = state.copyWith(state: ConversationState.speaking);
        break;

      case VoiceEventType.audioComplete:
        // VoiceNotifier's _streamPlayer handles draining + markComplete().
        // ConversationNotifier just updates its own state.
        ref.read(voiceProvider.notifier).markAudioComplete();
        state = state.copyWith(state: ConversationState.idle);
        break;

      case VoiceEventType.error:
        state = state.copyWith(state: ConversationState.error);
        break;

      default:
        break;
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _offlineEventSub?.cancel();
    super.dispose();
  }
}

// ─── Provider ───────────────────────────────────────────────────────

final conversationProvider =
    StateNotifierProvider<ConversationNotifier, ConversationProviderState>((
      ref,
    ) {
      return ConversationNotifier(ref: ref);
    });
