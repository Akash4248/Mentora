import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';

void main() {
  group('VisualIntent', () {
    test('parses well-formed JSON string into typed VisualIntent', () {
      const jsonStr = '''
{
  "schema_version": 1,
  "type": "motion.trajectory",
  "scenario": "vertical_toss",
  "inputs": {
    "initial_velocity_mps": 14.7,
    "gravity_mps2": 9.8,
    "initial_height_m": 0.0
  },
  "focus": {
    "kind": "apex"
  },
  "title": "Ball Toss",
  "description": "Trajectory reaching apex at 1.5s"
}
''';
      final intent = VisualIntent.tryParse(jsonStr);
      expect(intent, isNotNull);
      expect(intent!.schemaVersion, 1);
      expect(intent.type, VisualType.motionTrajectory);
      expect(intent.scenario, 'vertical_toss');
      expect(intent.inputs['initial_velocity_mps'], 14.7);
      expect(intent.focus?['kind'], 'apex');
      expect(intent.title, 'Ball Toss');
      expect(intent.description, 'Trajectory reaching apex at 1.5s');
    });

    test('serializes to JSON and round-trips correctly', () {
      const intent = VisualIntent(
        schemaVersion: 1,
        type: VisualType.simulationLauncher,
        scenario: 'phet-forces-motion',
        inputs: {'simulation_id': 'phet-forces-motion'},
        title: 'Forces & Motion',
      );

      final map = intent.toJson();
      expect(map['type'], 'simulation.launcher');
      expect(map['scenario'], 'phet-forces-motion');

      final restored = VisualIntent.tryParse(map);
      expect(restored, isNotNull);
      expect(restored!.type, VisualType.simulationLauncher);
      expect(restored.inputs['simulation_id'], 'phet-forces-motion');
    });

    test('maps unknown type identifiers gracefully to VisualType.unknown', () {
      expect(VisualType.fromIdentifier('non_existent.type'), VisualType.unknown);
      expect(VisualType.fromIdentifier(null), VisualType.unknown);
      expect(VisualType.fromIdentifier('steps.solution'), VisualType.stepsSolution);
      expect(VisualType.fromIdentifier('math.function_graph'), VisualType.mathFunctionGraph);
    });

    test('returns null on invalid or non-object JSON', () {
      expect(VisualIntent.tryParse('not a json'), isNull);
      expect(VisualIntent.tryParse('["array", "not", "object"]'), isNull);
      expect(VisualIntent.tryParse(null), isNull);
      expect(VisualIntent.tryParse(123), isNull);
    });
  });
}
