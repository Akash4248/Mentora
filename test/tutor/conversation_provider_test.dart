import 'package:flutter_test/flutter_test.dart';

import 'package:mentora/features/language/models/app_language.dart';
import 'package:mentora/features/tutor/models/conversation_message.dart';
import 'package:mentora/features/tutor/models/conversation_state.dart';
import 'package:mentora/features/tutor/providers/conversation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── ConversationState enum ──────────────────────────────────────

  group('ConversationState', () {
    test('has all nine expected values', () {
      expect(ConversationState.values, hasLength(9));
      expect(ConversationState.values, containsAll([
        ConversationState.idle,
        ConversationState.listening,
        ConversationState.uploading,
        ConversationState.transcribing,
        ConversationState.translating,
        ConversationState.thinking,
        ConversationState.generatingAudio,
        ConversationState.speaking,
        ConversationState.error,
      ]));
    });

    test('expected flow order is sequential', () {
      const flow = [
        ConversationState.idle,
        ConversationState.listening,
        ConversationState.uploading,
        ConversationState.transcribing,
        ConversationState.translating,
        ConversationState.thinking,
        ConversationState.generatingAudio,
        ConversationState.speaking,
        ConversationState.idle,
      ];
      for (final s in flow) {
        expect(ConversationState.values.contains(s), isTrue);
      }
    });
  });

  // ─── MessageRole ─────────────────────────────────────────────────

  group('MessageRole', () {
    test('has student, assistant, system', () {
      expect(MessageRole.values, hasLength(3));
      expect(MessageRole.values, containsAll([
        MessageRole.student,
        MessageRole.assistant,
        MessageRole.system,
      ]));
    });
  });

  // ─── ConversationMessage ─────────────────────────────────────────

  group('ConversationMessage', () {
    test('stores all fields correctly', () {
      final now = DateTime.now();
      final msg = ConversationMessage(
        id: 'msg_1',
        role: MessageRole.student,
        text: 'What is water cycle?',
        language: AppLanguage.english,
        timestamp: now,
      );

      expect(msg.id, 'msg_1');
      expect(msg.role, MessageRole.student);
      expect(msg.text, 'What is water cycle?');
      expect(msg.language, AppLanguage.english);
      expect(msg.timestamp, now);
    });

    test('toString includes role and text', () {
      final msg = ConversationMessage(
        id: 'msg_2',
        role: MessageRole.assistant,
        text: 'ನೀರಿನ ಚಕ್ರ',
        language: AppLanguage.kannada,
        timestamp: DateTime.now(),
      );
      expect(msg.toString(), contains('assistant'));
      expect(msg.toString(), contains('ನೀರಿನ ಚಕ್ರ'));
    });
  });

  // ─── ConversationProviderState ───────────────────────────────────

  group('ConversationProviderState', () {
    test('default values are correct', () {
      const state = ConversationProviderState();
      expect(state.state, ConversationState.idle);
      expect(state.messages, isEmpty);
      expect(state.partialTranscript, '');
      expect(state.finalTranscript, '');
      expect(state.responseLatency, Duration.zero);
    });

    test('copyWith preserves unchanged fields', () {
      const original = ConversationProviderState(
        state: ConversationState.listening,
        partialTranscript: 'hel',
      );

      final updated = original.copyWith(
        state: ConversationState.transcribing,
      );

      expect(updated.state, ConversationState.transcribing);
      expect(updated.partialTranscript, 'hel');
    });

    test('copyWith replaces messages list', () {
      const original = ConversationProviderState();
      final msg = ConversationMessage(
        id: 'msg_1',
        role: MessageRole.student,
        text: 'hello',
        language: AppLanguage.english,
        timestamp: DateTime.now(),
      );

      final updated = original.copyWith(messages: [msg]);
      expect(updated.messages, hasLength(1));
      expect(updated.messages.first.text, 'hello');
    });

    test('error state can be set from any state', () {
      for (final s in ConversationState.values) {
        final state = ConversationProviderState(state: s);
        final errored = state.copyWith(state: ConversationState.error);
        expect(errored.state, ConversationState.error);
      }
    });
  });
}
