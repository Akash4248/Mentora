import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/circuit_engine.dart';
import 'package:mentora/features/chat/application/visual_fallback_policy.dart';
import 'package:mentora/features/chat/application/visual_resolver.dart';
import 'package:mentora/features/chat/application/visual_schema_registry.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';

void main() {
  group('CircuitEngine Analytical DC Solver Tests', () {
    const engine = CircuitEngine();

    test("Simple Circuit Ohm's Law: I = V / R with switch toggle", () {
      // Switch CLOSED
      final closed = engine.solve(
        scenario: CircuitScenario.simple,
        voltageVolts: 12.0,
        isSwitchClosed: true,
        resistances: [24.0],
      );

      expect(closed.isSwitchClosed, isTrue);
      expect(closed.equivalentResistanceOhms, 24.0);
      expect(closed.totalCurrentAmps, 0.50);
      expect(closed.totalPowerWatts, 6.0);
      expect(closed.bulbBrightnessFactor, greaterThan(0.0));
      expect(closed.theoremNote, contains("Ohm's Law"));

      // Switch OPEN
      final opened = engine.solve(
        scenario: CircuitScenario.simple,
        voltageVolts: 12.0,
        isSwitchClosed: false,
        resistances: [24.0],
      );

      expect(opened.isSwitchClosed, isFalse);
      expect(opened.totalCurrentAmps, 0.0);
      expect(opened.totalPowerWatts, 0.0);
      expect(opened.bulbBrightnessFactor, 0.0);
      expect(opened.theoremNote, contains('Open Circuit'));
    });

    test('Series Resistors: Req = R1 + R2, constant current, voltage drop sum = V', () {
      final res = engine.solve(
        scenario: CircuitScenario.series,
        voltageVolts: 12.0,
        isSwitchClosed: true,
        resistances: [10.0, 20.0],
      );

      expect(res.equivalentResistanceOhms, 30.0);
      expect(res.totalCurrentAmps, 0.40);
      expect(res.branchCurrentsAmps, [0.40, 0.40]);
      expect(res.componentVoltages, [4.0, 8.0]);
      expect(res.componentVoltages[0] + res.componentVoltages[1], 12.0);
      expect(res.theoremNote, contains('Req = R₁ + R₂'));
    });

    test('Parallel Resistors: 1/Req = 1/R1 + 1/R2, constant voltage, Itotal = I1 + I2', () {
      final res = engine.solve(
        scenario: CircuitScenario.parallel,
        voltageVolts: 12.0,
        isSwitchClosed: true,
        resistances: [10.0, 10.0],
      );

      expect(res.equivalentResistanceOhms, 5.0);
      expect(res.totalCurrentAmps, 2.40);
      expect(res.branchCurrentsAmps, [1.20, 1.20]);
      expect(res.componentVoltages, [12.0, 12.0]);
      expect(res.theoremNote, contains('1/Req = 1/R₁ + 1/R₂'));
    });
  });

  group('VisualSchemaRegistry & Resolver Circuit Extensions', () {
    const registry = VisualSchemaRegistry();
    const resolver = VisualResolver();

    test('approves and resolves valid circuit.schematic series intent', () {
      const intent = VisualIntent(
        type: VisualType.circuitSchematic,
        scenario: 'series_circuit',
        inputs: {'voltage': 9.0, 'resistances': [15.0, 30.0]},
        title: 'Series Resistors Test',
      );

      final report = registry.validate(intent);
      expect(report.isValid, isTrue);

      final payload = resolver.resolve(intent);
      expect(payload, isA<CircuitVisualPayload>());
      final circuitPayload = payload as CircuitVisualPayload;
      expect(circuitPayload.result.equivalentResistanceOhms, 45.0);
      expect(circuitPayload.result.totalCurrentAmps, 0.20);
    });

    test('rejects negative voltage in circuit.schematic', () {
      const intent = VisualIntent(
        type: VisualType.circuitSchematic,
        scenario: 'simple_circuit',
        inputs: {'voltage': -12.0, 'resistance': 10.0},
      );

      final report = registry.validate(intent);
      expect(report.isValid, isFalse);
      expect(report.errors.first, contains('strictly positive'));
    });

    test('VisualFallbackPolicy matches circuit queries deterministically', () {
      const policy = VisualFallbackPolicy();
      final match = policy.matchDeterministicFallback(
        question: 'Explain how resistors connect in a series circuit',
        existingIntents: [],
      );

      expect(match, isNotNull);
      expect(match?.type, VisualType.circuitSchematic);
      expect(match?.scenario, 'series_circuit');
    });
  });
}
