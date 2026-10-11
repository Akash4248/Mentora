import 'package:flutter_test/flutter_test.dart';

import 'package:mentora/features/voice/services/voice_telemetry_service.dart';

void main() {
  group('VoiceTelemetryService', () {
    late VoiceTelemetryService telemetry;

    setUp(() {
      telemetry = VoiceTelemetryService();
    });

    test('records events and calculates average correctly', () {
      telemetry.record(TelemetryMetric.responseLatency, 500);
      telemetry.record(TelemetryMetric.responseLatency, 1500);
      
      expect(telemetry.average(TelemetryMetric.responseLatency), 1000.0);
    });

    test('increments counter correctly', () {
      telemetry.increment(TelemetryMetric.playbackFailures);
      telemetry.increment(TelemetryMetric.playbackFailures);

      expect(telemetry.total(TelemetryMetric.playbackFailures), 2.0);
    });

    test('exceedsTarget returns true when average > target', () {
      telemetry.record(TelemetryMetric.responseLatency, 1500);
      expect(telemetry.exceedsTarget(TelemetryMetric.responseLatency), isTrue);

      telemetry.record(TelemetryMetric.responseLatency, 100);
      // Avg is now 800, which is < 1000
      expect(telemetry.exceedsTarget(TelemetryMetric.responseLatency), isFalse);
    });

    test('returns recent events sorted by time descending', () async {
      telemetry.record(TelemetryMetric.responseLatency, 100);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      telemetry.record(TelemetryMetric.responseLatency, 200);

      final recent = telemetry.recent(TelemetryMetric.responseLatency);
      expect(recent, hasLength(2));
      expect(recent.first.valueMs, 200.0);
      expect(recent.last.valueMs, 100.0);
    });

    test('summary includes all recorded metrics', () {
      telemetry.record(TelemetryMetric.responseLatency, 500);
      telemetry.increment(TelemetryMetric.playbackFailures);

      final summary = telemetry.summary;
      expect(summary.containsKey(TelemetryMetric.responseLatency), isTrue);
      expect(summary.containsKey(TelemetryMetric.playbackFailures), isTrue);
      expect(summary.containsKey(TelemetryMetric.connectionTime), isFalse);
    });
  });
}
