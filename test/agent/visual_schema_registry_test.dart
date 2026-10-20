import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/visual_schema_registry.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';

void main() {
  group('VisualSchemaRegistry', () {
    const registry = VisualSchemaRegistry();

    test('approves valid motion.trajectory visual intent', () {
      const intent = VisualIntent(
        schemaVersion: 1,
        type: VisualType.motionTrajectory,
        scenario: 'vertical_toss',
        inputs: {
          'initial_velocity_mps': 14.7,
          'gravity_mps2': 9.8,
          'mass_kg': 1.5,
        },
      );

      final report = registry.validate(intent);
      expect(report.isValid, isTrue);
      expect(report.errors, isEmpty);
      expect(report.validatedIntent, isNotNull);
    });

    test('rejects unsupported schema version', () {
      const intent = VisualIntent(
        schemaVersion: 2,
        type: VisualType.motionTrajectory,
        scenario: 'vertical_toss',
      );

      final report = registry.validate(intent);
      expect(report.isValid, isFalse);
      expect(report.errors.first, contains('Unsupported schema version: 2'));
    });

    test('rejects unrealistic physical velocity or negative mass', () {
      const intentSuperluminal = VisualIntent(
        schemaVersion: 1,
        type: VisualType.motionTrajectory,
        scenario: 'vertical_toss',
        inputs: {'initial_velocity_mps': 5000.0},
      );

      final report = registry.validate(intentSuperluminal);
      expect(report.isValid, isFalse);
      expect(report.errors.first, contains('Initial velocity out of realistic domain bounds'));

      const intentNegativeMass = VisualIntent(
        schemaVersion: 1,
        type: VisualType.motionTrajectory,
        scenario: 'vertical_toss',
        inputs: {'mass_kg': -2.0},
      );

      final massReport = registry.validate(intentNegativeMass);
      expect(massReport.isValid, isFalse);
      expect(massReport.errors.first, contains('Mass must be strictly positive'));
    });

    test('validates simulation.launcher against catalog', () {
      const validSim = VisualIntent(
        schemaVersion: 1,
        type: VisualType.simulationLauncher,
        scenario: 'phet-bending-light',
        inputs: {'simulation_id': 'phet-bending-light'},
      );
      expect(registry.validate(validSim).isValid, isTrue);

      const invalidSim = VisualIntent(
        schemaVersion: 1,
        type: VisualType.simulationLauncher,
        scenario: 'unknown-fake-sim',
        inputs: {'simulation_id': 'unknown-fake-sim'},
      );
      final report = registry.validate(invalidSim);
      expect(report.isValid, isFalse);
      expect(report.errors.first, contains('not verified in local catalog'));
    });

    test('validates steps.solution requires a non-empty list of steps', () {
      const emptySteps = VisualIntent(
        schemaVersion: 1,
        type: VisualType.stepsSolution,
        scenario: 'derivation',
        inputs: {'steps': []},
      );
      final report = registry.validate(emptySteps);
      expect(report.isValid, isFalse);
      expect(report.errors.first, contains('requires a non-empty list of steps'));
    });
  });
}
