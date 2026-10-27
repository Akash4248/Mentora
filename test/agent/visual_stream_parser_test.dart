import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/visual_stream_parser.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';

void main() {
  group('VisualStreamParser', () {
    const parser = VisualStreamParser();

    test('extracts single mentora-visual block and strips raw JSON from prose', () {
      const rawText = '''
Here is the explanation for the vertical toss problem.
At apex, the ball stops moving upwards.

```mentora-visual
{
  "schema_version": 1,
  "type": "motion.trajectory",
  "scenario": "vertical_toss",
  "inputs": {
    "initial_velocity_mps": 14.7,
    "gravity_mps2": 9.8
  },
  "focus": {
    "kind": "apex"
  }
}
```

Notice how gravity brings velocity down to zero.
''';

      final result = parser.parse(rawText);
      expect(result.hasIncompleteBlock, isFalse);
      expect(result.visualIntents.length, 1);
      expect(result.visualIntents.first.type, VisualType.motionTrajectory);
      expect(result.visualIntents.first.scenario, 'vertical_toss');

      // The prose should NOT contain raw JSON or code fence
      expect(result.proseText, contains('Here is the explanation for the vertical toss problem.'));
      expect(result.proseText, contains('Notice how gravity brings velocity down to zero.'));
      expect(result.proseText, isNot(contains('```mentora-visual')));
      expect(result.proseText, isNot(contains('"schema_version": 1')));
    });

    test('supports ```json:mentora-visual fence variation', () {
      const rawText = '''
Check this simulation out:
```json:mentora-visual
{
  "schema_version": 1,
  "type": "simulation.launcher",
  "scenario": "phet-bending-light",
  "inputs": {
    "simulation_id": "phet-bending-light"
  }
}
```
Have fun experimenting!
''';

      final result = parser.parse(rawText);
      expect(result.hasIncompleteBlock, isFalse);
      expect(result.visualIntents.length, 1);
      expect(result.visualIntents.first.type, VisualType.simulationLauncher);
      expect(result.proseText, contains('Check this simulation out:'));
      expect(result.proseText, contains('Have fun experimenting!'));
      expect(result.proseText, isNot(contains('```json:mentora-visual')));
    });

    test('handles mid-stream unclosed block without leaking incomplete JSON', () {
      const incompleteStream = '''
The ball travels upwards.
```mentora-visual
{
  "schema_version": 1,
  "type": "motion.trajectory"
''';

      final result = parser.parse(incompleteStream);
      expect(result.hasIncompleteBlock, isTrue);
      expect(result.visualIntents, isEmpty);
      // The prose text should contain preceding text and NOT the half-typed JSON
      expect(result.proseText, 'The ball travels upwards.');
      expect(result.proseText, isNot(contains('"motion.trajectory"')));
    });

    test('parses pure markdown text with zero visual blocks cleanly', () {
      const text = 'Inertia is the tendency of a body to resist changes in its state of motion.';
      final result = parser.parse(text);

      expect(result.hasIncompleteBlock, isFalse);
      expect(result.visualIntents, isEmpty);
      expect(result.proseText, text);
    });

    test('strips mentora-tool-call blocks completely from prose output', () {
      const textWithTool = '''
General Science & Mathematics Explained

```mentora-tool-call
{"name": "lookup_simulation", "arguments": {"topic": "Interactive Pendulum & Motion Lab"}}
```

Here is the explanation for the pendulum motion.
''';

      final result = parser.parse(textWithTool);
      expect(result.proseText, contains('General Science & Mathematics Explained'));
      expect(result.proseText, contains('Here is the explanation for the pendulum motion.'));
      expect(result.proseText, isNot(contains('mentora-tool-call')));
      expect(result.proseText, isNot(contains('lookup_simulation')));
    });

    test('parses merora-visual misspelling with single-line JSON and extraneous trailing brace', () {
      const rawText =
          '```merora-visual {"type": "optics.ray_diagram", "scenario": "concave_mirror", "title": "Rays Reflecting from a Concave Mirror", "inputs": {"focal_length_cm": 15, "object_distance_cm": 30}} } ```';

      final result = parser.parse(rawText);
      expect(result.hasIncompleteBlock, isFalse);
      expect(result.visualIntents.length, 1);
      final intent = result.visualIntents.first;
      expect(intent.type, VisualType.opticsRayDiagram);
      expect(intent.scenario, 'concave_mirror');
      expect(intent.title, 'Rays Reflecting from a Concave Mirror');
      expect(intent.inputs['focal_length_cm'], 15);
      expect(intent.inputs['object_distance_cm'], 30);
      expect(result.proseText, isEmpty);
    });

    test('intercepts model tool-call escaping into ```mermaid fence and extracts visual intent', () {
      const rawText =
          '```mermaid {"name": "geometry.construction", "arguments": {"scenario": "bionomial", "inputs": {"base": 10, "height": 6, "radius": 3, "distance": 4}}} ```';

      final result = parser.parse(rawText);
      expect(result.visualIntents.length, 1);
      final intent = result.visualIntents.first;
      expect(intent.type, VisualType.geometryConstruction);
      expect(intent.scenario, 'bionomial');
      expect(intent.inputs['base'], 10);
      expect(result.proseText, isEmpty);
    });

    test('preserves legitimate Mermaid diagram flowchart syntax in proseText', () {
      const rawText = '''
Here is the lifecycle of a plant:
```mermaid
graph TD
  A[Seed] --> B[Sprout]
  B --> C[Plant]
```
Notice each stage.
''';

      final result = parser.parse(rawText);
      expect(result.visualIntents, isEmpty);
      expect(result.proseText, contains('graph TD'));
      expect(result.proseText, contains('A[Seed] --> B[Sprout]'));
      expect(result.proseText, contains('Notice each stage.'));
    });
  });
}
