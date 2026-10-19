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
  });
}
