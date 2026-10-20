import 'package:flutter_test/flutter_test.dart';

import 'package:mentora/features/voice/models/connection_status.dart';
import 'package:mentora/features/voice/models/voice_event.dart';
import 'package:mentora/features/voice/providers/voice_connection_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ─── VoiceEvent ──────────────────────────────────────────────────

  group('VoiceEvent', () {
    test('fromJson parses valid event', () {
      final json = {
        'type': 'partial_transcript',
        'payload': {'text': 'hello'},
      };
      final event = VoiceEvent.fromJson(json);
      expect(event.type, 'partial_transcript');
      expect(event.payload['text'], 'hello');
    });

    test('fromJson handles missing payload', () {
      final json = {'type': 'connected'};
      final event = VoiceEvent.fromJson(json);
      expect(event.type, 'connected');
      expect(event.payload, isEmpty);
    });

    test('fromJson handles missing type', () {
      final json = <String, dynamic>{};
      final event = VoiceEvent.fromJson(json);
      expect(event.type, 'unknown');
    });

    test('toJson round-trips correctly', () {
      const event = VoiceEvent(
        type: 'audio_chunk',
        payload: {'data': 'base64stuff'},
      );
      final json = event.toJson();
      final restored = VoiceEvent.fromJson(json);
      expect(restored.type, event.type);
      expect(restored.payload['data'], event.payload['data']);
    });

    test('toString includes type and payload', () {
      const event = VoiceEvent(type: 'error', payload: {'message': 'fail'});
      expect(event.toString(), contains('error'));
      expect(event.toString(), contains('fail'));
    });
  });

  // ─── ConnectionStatus ────────────────────────────────────────────

  group('ConnectionStatus', () {
    test('has all expected values', () {
      expect(ConnectionStatus.values, hasLength(5));
      expect(ConnectionStatus.values, containsAll([
        ConnectionStatus.disconnected,
        ConnectionStatus.connecting,
        ConnectionStatus.connected,
        ConnectionStatus.reconnecting,
        ConnectionStatus.error,
      ]));
    });
  });

  // ─── VoiceEventType constants ────────────────────────────────────

  group('VoiceEventType', () {
    test('server event types are correct strings', () {
      expect(VoiceEventType.connected, 'connected');
      expect(VoiceEventType.partialTranscript, 'partial_transcript');
      expect(VoiceEventType.finalTranscript, 'final_transcript');
      expect(VoiceEventType.assistantMessage, 'assistant_message');
      expect(VoiceEventType.audioChunk, 'audio_chunk');
      expect(VoiceEventType.error, 'error');
    });

    test('client event types are correct strings', () {
      expect(VoiceEventType.audioData, 'audio_data');
      expect(VoiceEventType.audioComplete, 'audio_complete');
    });
  });

  // ─── VoiceConnectionState ────────────────────────────────────────

  group('VoiceConnectionState', () {
    test('default values are correct', () {
      const state = VoiceConnectionState();
      expect(state.status, ConnectionStatus.disconnected);
      expect(state.latency, 0.0);
      expect(state.error, isNull);
    });

    test('copyWith preserves unchanged fields', () {
      const original = VoiceConnectionState(
        status: ConnectionStatus.connected,
        latency: 42.0,
      );
      final updated = original.copyWith(latency: 99.0);
      expect(updated.status, ConnectionStatus.connected);
      expect(updated.latency, 99.0);
    });

    test('copyWith clearError nullifies error', () {
      const original = VoiceConnectionState(error: 'timeout');
      final updated = original.copyWith(clearError: true);
      expect(updated.error, isNull);
    });

    test('copyWith sets error', () {
      const original = VoiceConnectionState();
      final updated = original.copyWith(error: 'socket closed');
      expect(updated.error, 'socket closed');
    });
  });
}
