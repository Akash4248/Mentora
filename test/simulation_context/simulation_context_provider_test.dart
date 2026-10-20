import 'package:flutter_test/flutter_test.dart';

import 'package:mentora/features/simulation_context/models/simulation_context.dart';

void main() {
  // ─── SimulationContext model ─────────────────────────────────────

  group('SimulationContext', () {
    test('default has no context', () {
      const ctx = SimulationContext();
      expect(ctx.hasContext, isFalse);
      expect(ctx.experimentId, isNull);
      expect(ctx.experimentName, isNull);
      expect(ctx.variables, isEmpty);
      expect(ctx.currentState, '');
    });

    test('hasContext is true when experimentId is set', () {
      const ctx = SimulationContext(experimentId: 'water_cycle');
      expect(ctx.hasContext, isTrue);
    });

    test('toJson produces correct payload', () {
      const ctx = SimulationContext(
        experimentId: 'water_cycle',
        experimentName: 'Water Cycle',
        variables: {'temperature': 80, 'humidity': 90},
        currentState: 'raining',
      );

      final json = ctx.toJson();
      final experiment = json['experiment'] as Map;
      expect(experiment['id'], 'water_cycle');
      expect(experiment['state'], 'raining');
      expect((experiment['variables'] as Map)['temperature'], 80);
      expect((experiment['variables'] as Map)['humidity'], 90);
    });

    test('toJson uses experimentId when name is null', () {
      const ctx = SimulationContext(
        experimentId: 'water_cycle',
      );
      final experiment = ctx.toJson()['experiment'] as Map;
      expect(experiment['id'], 'water_cycle');
    });

    test('copyWith preserves unchanged fields', () {
      const original = SimulationContext(
        experimentId: 'water_cycle',
        experimentName: 'Water Cycle',
        currentState: 'raining',
      );

      final updated = original.copyWith(currentState: 'evaporating');
      expect(updated.experimentId, 'water_cycle');
      expect(updated.experimentName, 'Water Cycle');
      expect(updated.currentState, 'evaporating');
    });

    test('copyWith clearContext resets to empty', () {
      const original = SimulationContext(
        experimentId: 'water_cycle',
        experimentName: 'Water Cycle',
        variables: {'temp': 80},
        currentState: 'raining',
      );

      final cleared = original.copyWith(clearContext: true);
      expect(cleared.hasContext, isFalse);
      expect(cleared.variables, isEmpty);
      expect(cleared.currentState, '');
    });

    test('toString includes name and state', () {
      const ctx = SimulationContext(
        experimentName: 'Water Cycle',
        currentState: 'raining',
        variables: {'a': 1, 'b': 2},
      );
      expect(ctx.toString(), contains('Water Cycle'));
      expect(ctx.toString(), contains('raining'));
    });
  });
}
