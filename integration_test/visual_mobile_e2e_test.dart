import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mentora/features/chat/application/circuit_engine.dart';
import 'package:mentora/features/chat/application/geometry_engine.dart';
import 'package:mentora/features/chat/application/kinematics_engine.dart';
import 'package:mentora/features/chat/application/optics_engine.dart';
import 'package:mentora/features/chat/application/visual_resolver.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';
import 'package:mentora/features/chat/presentation/widgets/circuit_canvas.dart';
import 'package:mentora/features/chat/presentation/widgets/geometry_canvas.dart';
import 'package:mentora/features/chat/presentation/widgets/motion_trajectory_canvas.dart';
import 'package:mentora/features/chat/presentation/widgets/ray_optics_canvas.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Mentora Mobile Visualizer E2E Device Tests', () {
    testWidgets('Validates Kinematics, Optics, and Geometry canvases on physical device', (tester) async {
      // 1. Kinematics Canvas
      const kinematicsEngine = KinematicsEngine();
      final trajectory = kinematicsEngine.computeProjectile2D(
        launchVelocityMps: 20.0,
        launchAngleDegrees: 45.0,
      );
      final trajectoryPayload = TrajectoryVisualPayload(
        intent: const VisualIntent(
          type: VisualType.motionTrajectory,
          scenario: 'projectile',
          inputs: {'launch_velocity_mps': 20.0, 'launch_angle_deg': 45.0},
          title: 'Projectile Motion (Mobile Test)',
        ),
        trajectory: trajectory,
      );

      // 2. Optics Canvas
      const opticsEngine = OpticsEngine();
      final opticsResult = opticsEngine.solve(
        scenario: OpticsScenario.concaveMirror,
        focalLengthCm: 10.0,
        objectDistanceCm: 15.0,
      );
      final opticsPayload = OpticsVisualPayload(
        intent: const VisualIntent(
          type: VisualType.opticsRayDiagram,
          scenario: 'concave_mirror',
          title: 'Concave Mirror Ray Tracing',
        ),
        result: opticsResult,
      );

      // 3. Geometry Canvas
      const geometryEngine = GeometryEngine();
      final geomResult = geometryEngine.solveRightTriangle(base: 4.0, height: 3.0);
      final geomPayload = GeometryVisualPayload(
        intent: const VisualIntent(
          type: VisualType.geometryConstruction,
          scenario: 'right_triangle',
          title: 'Pythagoras 3-4-5 Geometry',
        ),
        result: geomResult,
      );

      // 4. Circuit Canvas
      const circuitEngine = CircuitEngine();
      final circuitResult = circuitEngine.solve(
        scenario: CircuitScenario.simple,
        voltageVolts: 12.0,
        isSwitchClosed: true,
        resistances: [24.0],
      );
      final circuitPayload = CircuitVisualPayload(
        intent: const VisualIntent(
          type: VisualType.circuitSchematic,
          scenario: 'simple_circuit',
          title: 'DC Circuit Ohm’s Law',
        ),
        result: circuitResult,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            appBar: AppBar(title: const Text('Mobile Visualizer Suite')),
            body: SingleChildScrollView(
              key: const Key('visual_scroll_view'),
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  MotionTrajectoryCanvas(payload: trajectoryPayload),
                  const SizedBox(height: 16),
                  RayOpticsCanvas(payload: opticsPayload),
                  const SizedBox(height: 16),
                  GeometryCanvas(payload: geomPayload),
                  const SizedBox(height: 16),
                  CircuitCanvas(payload: circuitPayload),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));

      // Verify Kinematics canvas rendered on device
      expect(find.text('Projectile Motion (Mobile Test)'), findsOneWidget);
      expect(find.text('Time (t)'), findsOneWidget);
      expect(find.text('Height (y)'), findsOneWidget);

      // Verify Optics canvas rendered on device
      expect(find.text('Concave Mirror Ray Tracing'), findsOneWidget);
      expect(find.textContaining('Real & Inverted'), findsOneWidget);

      // Verify Geometry canvas rendered on device
      expect(find.text('Pythagoras 3-4-5 Geometry'), findsOneWidget);
      expect(find.text('Hypotenuse (c)'), findsOneWidget);

      // Interact with mobile slider: drag the first slider
      final sliders = find.byType(Slider);
      expect(sliders, findsNWidgets(4));

      // Test mobile touch drag on slider 1 (kinematics)
      await tester.drag(sliders.at(0), const Offset(50, 0));
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll down so slider 2 (optics) is fully visible
      await tester.scrollUntilVisible(sliders.at(1), 150);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.drag(sliders.at(1), const Offset(-40, 0));
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll down so slider 3 (geometry) is fully visible
      await tester.scrollUntilVisible(sliders.at(2), 150);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.drag(sliders.at(2), const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll down to Circuit Canvas and verify
      expect(find.text('DC Circuit Ohm’s Law'), findsOneWidget);
      expect(find.text('SWITCH CLOSED (ON)'), findsOneWidget);

      // Toggle switch OFF on mobile
      final toggleButton = find.text('Toggle OFF');
      await tester.scrollUntilVisible(toggleButton, 150);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(toggleButton);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('SWITCH OPEN (OFF)'), findsOneWidget);

      // Toggle switch back ON
      final onButton = find.text('Toggle ON');
      await tester.tap(onButton);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('SWITCH CLOSED (ON)'), findsOneWidget);

      // Ensure no UI crashes or exceptions on mobile device
      expect(find.byType(CircuitCanvas), findsOneWidget);
    });
  });
}
