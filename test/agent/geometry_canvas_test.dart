import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/geometry_engine.dart';
import 'package:mentora/features/chat/application/visual_resolver.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';
import 'package:mentora/features/chat/presentation/widgets/geometry_canvas.dart';

void main() {
  group('GeometryCanvas Widget & Interaction Tests', () {
    testWidgets('renders right triangle canvas with Pythagoras HUD and slider', (tester) async {
      const engine = GeometryEngine();
      final result = engine.solveRightTriangle(base: 4.0, height: 3.0);

      final payload = GeometryVisualPayload(
        intent: const VisualIntent(
          type: VisualType.geometryConstruction,
          scenario: 'right_triangle',
          inputs: {'base': 4.0, 'height': 3.0},
          title: 'Right Triangle & Pythagoras',
        ),
        result: result,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GeometryCanvas(payload: payload),
          ),
        ),
      );

      // Verify title & theorem note
      expect(find.text('Right Triangle & Pythagoras'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Pythagoras:'), findsOneWidget);

      // Verify measurements
      expect(find.text('Base (a)'), findsOneWidget);
      expect(find.text('4.0'), findsAtLeastNWidgets(1));
      expect(find.text('Hypotenuse (c)'), findsOneWidget);
      expect(find.text('5.00'), findsOneWidget);

      // Verify slider exists and is draggable
      expect(find.byType(Slider), findsOneWidget);
      await tester.drag(find.byType(Slider), const Offset(40, 0));
      await tester.pumpAndSettle();

      // Viewport remains stable after drag
      expect(find.byType(GeometryCanvas), findsOneWidget);
    });

    testWidgets('renders circle tangents with theorem badge', (tester) async {
      const engine = GeometryEngine();
      final result = engine.solveCircleTangents(radius: 3.0, externalDistance: 5.0);

      final payload = GeometryVisualPayload(
        intent: const VisualIntent(
          type: VisualType.geometryConstruction,
          scenario: 'circle_tangents',
          inputs: {'radius': 3.0, 'distance': 5.0},
          title: 'Circle Tangents',
        ),
        result: result,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GeometryCanvas(payload: payload),
          ),
        ),
      );

      expect(find.text('Circle Tangents'), findsAtLeastNWidgets(1));
      expect(find.textContaining('Tangents from external point are equal'), findsOneWidget);
      expect(find.text('Tangent (PT₁)'), findsOneWidget);
      expect(find.text('4.00'), findsAtLeastNWidgets(1));
    });
  });
}
