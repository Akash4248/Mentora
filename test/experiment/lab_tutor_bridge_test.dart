import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/mentora_agent_session.dart';
import 'package:mentora/features/chat/application/mentora_tutor_agent_provider.dart';
import 'package:mentora/features/chat/application/tutor_session_coordinator.dart';
import 'package:mentora/features/chat/domain/tutor_stream_event.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/lab_analysis_summary.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/sensor_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Lab Tutor Bridge & Grounded Evidence Interpretation Suite', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('toCompactTutorContext produces concise summary strictly within token budget', () {
      const summary = LabAnalysisSummary(
        experimentId: 'exp_incline_friction',
        experimentTitle: 'Incline Plane & Static Friction Experiment',
        sensorType: SensorType.accelerometer,
        sampleCount: 150,
        durationSeconds: 3.0,
        samplingRateHz: 50.0,
        metrics: {
          'tilt_angle_deg': 30.0,
          'normal_force_ratio': 0.866,
          'static_friction_coeff': 0.577,
        },
        quality: DataQualityRating.high,
        jitterMs: 1.2,
        noiseRms: 0.045,
      );

      final contextText = summary.toCompactTutorContext();

      expect(contextText, contains('exp_incline_friction'));
      expect(contextText, contains('tilt_angle_deg=30.000'));
      expect(contextText, contains('static_friction_coeff=0.577'));
      expect(contextText, contains('Quality Rating: High Confidence'));

      // Token estimation check: ~4 chars per token; context must be < 100 tokens (< 400 chars)
      expect(contextText.length, lessThan(400));
    });

    test('tutor receives empirical evidence and explains results using physical principles', () async {
      const summary = LabAnalysisSummary(
        experimentId: 'exp_incline_friction',
        experimentTitle: 'Incline Plane & Static Friction Experiment',
        sensorType: SensorType.accelerometer,
        sampleCount: 150,
        durationSeconds: 3.0,
        samplingRateHz: 50.0,
        metrics: {
          'tilt_angle_deg': 30.0,
          'normal_force_ratio': 0.866,
          'static_friction_coeff': 0.577,
        },
        quality: DataQualityRating.high,
        jitterMs: 1.2,
        noiseRms: 0.045,
      );

      String? promptReceived;
      final provider = MentoraTutorAgentProvider(
        streamTutor: ({
          required question,
          required topic,
          required grade,
          cancelToken,
          history = const [],
          tools = const [],
        }) async* {
          promptReceived = question;
          yield const TutorStreamChunkEvent('Based on your recorded data, the tilt angle was 30° ');
          yield const TutorStreamChunkEvent('which means the coefficient of static friction is μs = tan(30°) ≈ 0.577.');
          yield const TutorStreamCompletedEvent(
            fullText:
                'Based on your recorded data, the tilt angle was 30° which means the coefficient of static friction is μs = tan(30°) ≈ 0.577.',
            source: 'test_provider',
          );
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Laws of Motion',
        initialGrade: 9,
      );

      final studentQueryWithEvidence =
          'Here is my experiment data:\n${summary.toCompactTutorContext()}\nCan you explain what this tells us about the friction of the board?';

      final events = await coordinator.submitQuestion(studentQueryWithEvidence).toList();
      final completed = events.whereType<TutorTurnCompletedEvent>().single;

      expect(promptReceived, contains('exp_incline_friction'));
      expect(promptReceived, contains('tilt_angle_deg=30.000'));
      expect(completed.text, contains('0.577'));
      expect(completed.text, contains('30°'));

      await coordinator.dispose();
    });
  });
}
