import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/data/llm_admin_channel_service.dart';

void main() {
  group('waitForLocalEngineReady', () {
    test('returns a native load error without waiting for the timeout', () async {
      var statusReads = 0;

      final status = await waitForLocalEngineReady(
        timeout: const Duration(seconds: 10),
        readStatus: () async {
          statusReads++;
          return const EngineStatus(
            loaded: false,
            modelPath: '/models/incompatible.gguf',
            lastEngineError: 'Native model load failed (code=1).',
            totalInferenceCount: 0,
            lastInferenceDurationMs: 0,
            avgInferenceDurationMs: 0,
          );
        },
      );

      expect(status.loaded, isFalse);
      expect(status.lastEngineError, contains('Native model load failed'));
      expect(statusReads, 1);
    });

    test('continues polling until the model is loaded', () async {
      var statusReads = 0;

      final status = await waitForLocalEngineReady(
        timeout: const Duration(seconds: 1),
        pollInterval: const Duration(milliseconds: 1),
        readStatus: () async {
          statusReads++;
          return EngineStatus(
            loaded: statusReads == 2,
            modelPath: '/models/supported.gguf',
            lastEngineError: '',
            totalInferenceCount: 0,
            lastInferenceDurationMs: 0,
            avgInferenceDurationMs: 0,
          );
        },
      );

      expect(status.loaded, isTrue);
      expect(statusReads, 2);
    });

    test('returns the latest status after the timeout', () async {
      var statusReads = 0;

      final status = await waitForLocalEngineReady(
        timeout: Duration.zero,
        readStatus: () async {
          statusReads++;
          return const EngineStatus(
            loaded: false,
            modelPath: '/models/slow.gguf',
            lastEngineError: '',
            totalInferenceCount: 0,
            lastInferenceDurationMs: 0,
            avgInferenceDurationMs: 0,
          );
        },
      );

      expect(status.loaded, isFalse);
      expect(statusReads, 1);
    });
  });
}
