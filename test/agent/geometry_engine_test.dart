import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/geometry_engine.dart';
import 'package:mentora/features/chat/application/visual_fallback_policy.dart';
import 'package:mentora/features/chat/application/visual_resolver.dart';
import 'package:mentora/features/chat/application/visual_schema_registry.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';

void main() {
  group('GeometryEngine Analytical Solver Tests', () {
    const engine = GeometryEngine();

    test('Right Triangle 3-4-5: computes exact hypotenuse 5.0, area 6.0, and right angle marker', () {
      final res = engine.solveRightTriangle(base: 3.0, height: 4.0);

      expect(res.scenario, GeometryScenario.rightTriangle);
      expect(res.measurements['Hypotenuse (c)'], '5.00');
      expect(res.measurements['Area'], '6.00');
      expect(res.measurements['Perimeter'], '12.00');

      // Vertices verification
      expect(res.points['C']?.x, 0.0);
      expect(res.points['C']?.y, 0.0);
      expect(res.points['B']?.x, 3.0);
      expect(res.points['A']?.y, 4.0);

      // Verify right angle marker exists at vertex C
      final rightAngle = res.angles.firstWhere((a) => a.isRightAngle);
      expect(rightAngle.vertex.label, contains('C'));
      expect(rightAngle.degrees, 90.0);

      // Theorem note
      expect(res.theoremNote, contains('Pythagoras'));
    });

    test('Right Triangle 5-12-13: computes exact hypotenuse 13.0', () {
      final res = engine.solveRightTriangle(base: 5.0, height: 12.0);

      expect(res.measurements['Hypotenuse (c)'], '13.00');
      expect(res.measurements['Area'], '30.00');
    });

    test('Circle Tangents: verifies equal tangents PT1 = PT2 = sqrt(d^2 - r^2) and OT ⊥ PT', () {
      final res = engine.solveCircleTangents(radius: 3.0, externalDistance: 5.0);

      expect(res.scenario, GeometryScenario.circleTangents);
      expect(res.measurements['Tangent (PT₁)'], '4.00');
      expect(res.measurements['Tangent (PT₂)'], '4.00');

      // Verify contact points T1 and T2 distance to P is 4.0
      final p = res.points['P']!;
      final t1 = res.points['T1']!;
      final t2 = res.points['T2']!;

      final distPT1 = math.sqrt(math.pow(p.x - t1.x, 2) + math.pow(p.y - t1.y, 2));
      final distPT2 = math.sqrt(math.pow(p.x - t2.x, 2) + math.pow(p.y - t2.y, 2));

      expect((distPT1 - 4.0).abs(), lessThan(1e-5));
      expect((distPT2 - 4.0).abs(), lessThan(1e-5));

      // Right-angle verification at contact points
      expect(res.angles.where((a) => a.isRightAngle).length, 2);
    });

    test('Parallel Lines & Transversal: computes equal alternate interior angles and supplementary sum 180°', () {
      final res = engine.solveParallelTransversal(angleDegrees: 50.0);

      expect(res.scenario, GeometryScenario.parallelTransversal);
      expect(res.measurements['Angle (θ)'], '50°');
      expect(res.measurements['Alternate Interior'], '50°');
      expect(res.measurements['Consecutive Int'], '130°');
      expect(res.theoremNote, contains('180°'));
    });
  });

  group('VisualSchemaRegistry & Resolver Geometry Extensions', () {
    const registry = VisualSchemaRegistry();
    const resolver = VisualResolver();

    test('approves and resolves valid geometry.construction right triangle', () {
      const intent = VisualIntent(
        type: VisualType.geometryConstruction,
        scenario: 'right_triangle',
        inputs: {'base': 6.0, 'height': 8.0},
        title: 'Pythagoras 6-8-10',
      );

      final report = registry.validate(intent);
      expect(report.isValid, isTrue);

      final payload = resolver.resolve(intent);
      expect(payload, isA<GeometryVisualPayload>());
      final geomPayload = payload as GeometryVisualPayload;
      expect(geomPayload.result.measurements['Hypotenuse (c)'], '10.00');
    });

    test('rejects negative base in geometry.construction', () {
      const intent = VisualIntent(
        type: VisualType.geometryConstruction,
        scenario: 'right_triangle',
        inputs: {'base': -4.0, 'height': 3.0},
      );

      final report = registry.validate(intent);
      expect(report.isValid, isFalse);
      expect(report.errors.first, contains('strictly positive'));
    });

    test('VisualFallbackPolicy matches geometry queries deterministically', () {
      const policy = VisualFallbackPolicy();
      final match = policy.matchDeterministicFallback(
        question: 'How do you find the hypotenuse of a right angled triangle?',
        existingIntents: [],
      );

      expect(match, isNotNull);
      expect(match?.type, VisualType.geometryConstruction);
      expect(match?.scenario, 'right_triangle');
    });
  });
}
