import 'package:flutter_test/flutter_test.dart';

import 'package:mentora/features/voice/models/voice_state.dart';
import 'package:mentora/features/voice/providers/voice_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── VoiceState enum ─────────────────────────────────────────────

  group('VoiceState', () {
    test('has all five expected values', () {
      expect(VoiceState.values, hasLength(5));
      expect(VoiceState.values, containsAll([
        VoiceState.idle,
        VoiceState.listening,
        VoiceState.processing,
        VoiceState.speaking,
        VoiceState.error,
      ]));
    });
  });

  // ─── VoiceProviderState ──────────────────────────────────────────

  group('VoiceProviderState', () {
    test('default values are correct', () {
      const state = VoiceProviderState();
      expect(state.state, VoiceState.idle);
      expect(state.hasPermission, isFalse);
      expect(state.currentRecording, isNull);
      expect(state.recordingDuration, Duration.zero);
      expect(state.isPlaying, isFalse);
    });

    test('copyWith preserves unchanged fields', () {
      const original = VoiceProviderState(
        state: VoiceState.listening,
        hasPermission: true,
        recordingDuration: Duration(seconds: 5),
      );

      final updated = original.copyWith(state: VoiceState.idle);

      expect(updated.state, VoiceState.idle);
      expect(updated.hasPermission, isTrue);
      expect(updated.recordingDuration, const Duration(seconds: 5));
    });

    test('copyWith clearRecording nullifies recording', () {
      const original = VoiceProviderState(
        currentRecording: '/tmp/test.wav',
      );

      final updated = original.copyWith(clearRecording: true);
      expect(updated.currentRecording, isNull);
    });

    test('copyWith with all fields', () {
      const original = VoiceProviderState();
      final updated = original.copyWith(
        state: VoiceState.speaking,
        hasPermission: true,
        currentRecording: '/test.wav',
        recordingDuration: const Duration(seconds: 10),
        isPlaying: true,
      );

      expect(updated.state, VoiceState.speaking);
      expect(updated.hasPermission, isTrue);
      expect(updated.currentRecording, '/test.wav');
      expect(updated.recordingDuration, const Duration(seconds: 10));
      expect(updated.isPlaying, isTrue);
    });
  });

  // ─── VoiceState transitions (logical, no device) ─────────────────

  group('VoiceState transitions', () {
    test('expected state flow: idle → listening → idle', () {
      // Verify the enum supports the expected flow
      const flow = [
        VoiceState.idle,
        VoiceState.listening,
        VoiceState.processing,
        VoiceState.speaking,
        VoiceState.idle,
      ];

      for (final s in flow) {
        expect(VoiceState.values.contains(s), isTrue);
      }
    });

    test('error can occur from any state', () {
      // VoiceState.error is always a valid target
      for (final s in VoiceState.values) {
        final state = VoiceProviderState(state: s);
        final errored = state.copyWith(state: VoiceState.error);
        expect(errored.state, VoiceState.error);
      }
    });
  });
}
