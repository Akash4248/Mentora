import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/visual_resolver.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';

void main() {
  group('VisualResolver', () {
    const resolver = VisualResolver();

    test('resolves vertical toss intent into TrajectoryVisualPayload with ground truth values', () {
      const intent = VisualIntent(
        schemaVersion: 1,
        type: VisualType.motionTrajectory,
        scenario: 'vertical_toss',
        inputs: {
          'initial_velocity_mps': 14.7,
          'gravity_mps2': 9.8,
          'mass_kg': 1.0,
        },
        focus: {'kind': 'apex'},
      );

      final payload = resolver.resolve(intent);
      expect(payload, isA<TrajectoryVisualPayload>());

      final trajPayload = payload as TrajectoryVisualPayload;
      expect(trajPayload.trajectory.timeToApexSeconds, 1.5);
      expect(trajPayload.trajectory.peakHeightMeters, 11.025);
      expect(trajPayload.trajectory.totalFlightTimeSeconds, 3.0);
      expect(trajPayload.trajectory.netForceAtPeakNewtons, 9.8);
      expect(trajPayload.trajectory.samples, isNotEmpty);
    });

    test('resolves simulation launcher intent into SimulationVisualPayload with verified metadata', () {
      const intent = VisualIntent(
        schemaVersion: 1,
        type: VisualType.simulationLauncher,
        scenario: 'phet-forces-motion',
        inputs: {'simulation_id': 'phet-forces-motion'},
      );

      final payload = resolver.resolve(intent);
      expect(payload, isA<SimulationVisualPayload>());

      final simPayload = payload as SimulationVisualPayload;
      expect(simPayload.simulationId, 'phet-forces-motion');
      expect(simPayload.title, 'Forces and Motion: Basics');
      expect(simPayload.subject, 'Physics');
      expect(simPayload.localPath, 'assets/phet/simulations/placeholder.html');
    });

    test('resolves steps solution intent into StepsVisualPayload', () {
      const intent = VisualIntent(
        schemaVersion: 1,
        type: VisualType.stepsSolution,
        scenario: 'worked_problem',
        inputs: {
          'steps': [
            {'step': 1, 'title': 'Formula', 'formula': 'v = u + at'},
            {'step': 2, 'title': 'Substitution', 'explanation': 'Plug in values'},
          ],
        },
      );

      final payload = resolver.resolve(intent);
      expect(payload, isA<StepsVisualPayload>());

      final stepsPayload = payload as StepsVisualPayload;
      expect(stepsPayload.steps.length, 2);
      expect(stepsPayload.steps[0]['title'], 'Formula');
    });

    test('gracefully degrades invalid intent to FallbackTextVisualPayload', () {
      const invalidIntent = VisualIntent(
        schemaVersion: 99, // Unsupported
        type: VisualType.motionTrajectory,
        scenario: 'vertical_toss',
      );

      final payload = resolver.resolve(invalidIntent);
      expect(payload, isA<FallbackTextVisualPayload>());

      final fallback = payload as FallbackTextVisualPayload;
      expect(fallback.reason, contains('Unsupported schema version'));
    });
  });
}
