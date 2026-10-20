import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/optics_engine.dart';
import 'package:mentora/features/chat/application/visual_resolver.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';
import 'package:mentora/features/chat/presentation/widgets/ray_optics_canvas.dart';

void main() {
  group('RayOpticsCanvas Widget & Interaction Tests', () {
    testWidgets('renders concave mirror ray diagram and telemetry HUD', (tester) async {
      const engine = OpticsEngine();
      final result = engine.solve(
        scenario: OpticsScenario.concaveMirror,
        focalLengthCm: 10.0,
        objectDistanceCm: 15.0,
        objectHeightCm: 3.0,
      );

      final payload = OpticsVisualPayload(
        intent: const VisualIntent(
          type: VisualType.opticsRayDiagram,
          scenario: 'concave_mirror',
          title: 'Concave Mirror: Object between F and C',
        ),
        result: result,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RayOpticsCanvas(payload: payload),
          ),
        ),
      );

      // Verify title and nature badge
      expect(find.text('Concave Mirror: Object between F and C'), findsOneWidget);
      expect(find.textContaining('Real & Inverted'), findsOneWidget);

      // Verify telemetry labels
      expect(find.text('Object (u)'), findsOneWidget);
      expect(find.text('-15.0 cm'), findsOneWidget);
      expect(find.text('Image (v)'), findsOneWidget);
      expect(find.text('-30.0 cm'), findsOneWidget);
      expect(find.text('Focal (f)'), findsOneWidget);
      expect(find.text('10.0 cm'), findsOneWidget);
      expect(find.text('Mag (m)'), findsOneWidget);
      expect(find.text('-2.00×'), findsOneWidget);

      // Verify slider exists
      expect(find.byType(Slider), findsOneWidget);

      // Simulate dragging slider to change object distance
      await tester.drag(find.byType(Slider), const Offset(-50, 0));
      await tester.pumpAndSettle();

      // Verify slider changed value without errors or crashes
      expect(find.byType(RayOpticsCanvas), findsOneWidget);
    });

    testWidgets('renders convex lens ray diagram with virtual image badge when inside F', (tester) async {
      const engine = OpticsEngine();
      final result = engine.solve(
        scenario: OpticsScenario.convexLens,
        focalLengthCm: 10.0,
        objectDistanceCm: 5.0, // Inside focus
        objectHeightCm: 2.0,
      );

      final payload = OpticsVisualPayload(
        intent: const VisualIntent(
          type: VisualType.opticsRayDiagram,
          scenario: 'convex_lens',
          title: 'Convex Lens: Magnifying Glass',
        ),
        result: result,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RayOpticsCanvas(payload: payload),
          ),
        ),
      );

      expect(find.text('Convex Lens: Magnifying Glass'), findsOneWidget);
      expect(find.textContaining('Virtual & Erect'), findsOneWidget);
      expect(find.text('-5.0 cm'), findsOneWidget); // u
      expect(find.text('-10.0 cm'), findsOneWidget); // v
      expect(find.text('2.00×'), findsOneWidget); // m
    });
  });
}
