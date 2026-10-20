import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/circuit_engine.dart';
import 'package:mentora/features/chat/application/visual_resolver.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';
import 'package:mentora/features/chat/presentation/widgets/circuit_canvas.dart';

void main() {
  group('CircuitCanvas Widget & Interaction Tests', () {
    testWidgets('renders circuit canvas with switch CLOSED, voltage HUD, and slider', (tester) async {
      const engine = CircuitEngine();
      final result = engine.solve(
        scenario: CircuitScenario.simple,
        voltageVolts: 12.0,
        isSwitchClosed: true,
        resistances: [24.0],
      );

      final payload = CircuitVisualPayload(
        intent: const VisualIntent(
          type: VisualType.circuitSchematic,
          scenario: 'simple_circuit',
          inputs: {'voltage': 12.0, 'resistances': [24.0]},
          title: "Simple DC Circuit & Ohm's Law",
        ),
        result: result,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CircuitCanvas(payload: payload),
          ),
        ),
      );

      // Verify title & status badge
      expect(find.text("Simple DC Circuit & Ohm's Law"), findsOneWidget);
      expect(find.text('SWITCH CLOSED (ON)'), findsOneWidget);

      // Verify telemetry readouts
      expect(find.text('Voltage (V)'), findsOneWidget);
      expect(find.text('12.0 V'), findsAtLeastNWidgets(1));
      expect(find.text('Current (I)'), findsOneWidget);
      expect(find.text('0.50 A'), findsOneWidget);
      expect(find.text('Total R'), findsOneWidget);
      expect(find.text('24.0 Ω'), findsOneWidget);

      // Tap Switch toggle button to turn OFF
      final toggleButton = find.text('Toggle OFF');
      expect(toggleButton, findsOneWidget);
      await tester.tap(toggleButton);
      await tester.pump(const Duration(milliseconds: 100));

      // Verify switch state flipped to OPEN
      expect(find.text('SWITCH OPEN (OFF)'), findsOneWidget);
      expect(find.text('0.00 A'), findsOneWidget); // Current dropped to 0
      expect(find.text('Toggle ON'), findsOneWidget);

      // Tap Switch toggle again to turn back ON
      await tester.tap(find.text('Toggle ON'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('SWITCH CLOSED (ON)'), findsOneWidget);
      expect(find.text('0.50 A'), findsOneWidget);

      // Drag voltage slider
      expect(find.byType(Slider), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircuitCanvas), findsOneWidget);
    });

    testWidgets('renders series resistor network with correct Req', (tester) async {
      const engine = CircuitEngine();
      final result = engine.solve(
        scenario: CircuitScenario.series,
        voltageVolts: 12.0,
        isSwitchClosed: true,
        resistances: [10.0, 20.0],
      );

      final payload = CircuitVisualPayload(
        intent: const VisualIntent(
          type: VisualType.circuitSchematic,
          scenario: 'series_circuit',
          inputs: {'voltage': 12.0, 'resistances': [10.0, 20.0]},
          title: 'Series Resistor Circuit',
        ),
        result: result,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CircuitCanvas(payload: payload),
          ),
        ),
      );

      expect(find.text('Series Resistor Circuit'), findsOneWidget);
      expect(find.text('30.0 Ω'), findsOneWidget); // Req = 10 + 20
      expect(find.text('0.40 A'), findsOneWidget); // I = 12 / 30
      expect(find.textContaining('Series: Req = R₁ + R₂'), findsOneWidget);
    });
  });
}
