import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/optics_engine.dart';
import 'package:mentora/features/chat/application/visual_resolver.dart';
import 'package:mentora/features/chat/application/visual_schema_registry.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';

void main() {
  group('OpticsEngine Physics Solver', () {
    const engine = OpticsEngine();

    test('Concave Mirror: object between F and 2F produces real, inverted, magnified image beyond C', () {
      // f = 10 cm, u = 15 cm (between F=10 and C=20)
      final result = engine.solve(
        scenario: OpticsScenario.concaveMirror,
        focalLengthCm: 10.0,
        objectDistanceCm: 15.0,
        objectHeightCm: 3.0,
      );

      // 1/v = 1/f - 1/u = -1/10 - (-1/15) = -1/30 => v = -30 cm
      expect(result.imageDistanceCm, closeTo(-30.0, 0.01));
      // m = -v/u = -(-30)/(-15) = -2.0
      expect(result.magnification, closeTo(-2.0, 0.01));
      expect(result.imageHeightCm, closeTo(-6.0, 0.01));
      expect(result.isReal, isTrue);
      expect(result.isErect, isFalse);
      expect(result.natureDescription, contains('Real & Inverted, Magnified'));
      expect(result.rays.length, greaterThanOrEqualTo(2));
    });

    test('Concave Mirror: object at 2F (center C) produces real, inverted image of same size at C', () {
      final result = engine.solve(
        scenario: OpticsScenario.concaveMirror,
        focalLengthCm: 10.0,
        objectDistanceCm: 20.0,
        objectHeightCm: 4.0,
      );

      expect(result.imageDistanceCm, closeTo(-20.0, 0.01));
      expect(result.magnification, closeTo(-1.0, 0.01));
      expect(result.imageHeightCm, closeTo(-4.0, 0.01));
      expect(result.natureDescription, contains('Same size'));
    });

    test('Concave Mirror: object inside focus (between F and P) produces virtual, erect, magnified image', () {
      // u = 5 cm, f = 10 cm
      final result = engine.solve(
        scenario: OpticsScenario.concaveMirror,
        focalLengthCm: 10.0,
        objectDistanceCm: 5.0,
        objectHeightCm: 2.0,
      );

      // 1/v = -1/10 - (-1/5) = 1/10 => v = +10 cm (behind mirror)
      expect(result.imageDistanceCm, closeTo(10.0, 0.01));
      // m = -(10)/(-5) = +2.0
      expect(result.magnification, closeTo(2.0, 0.01));
      expect(result.isReal, isFalse);
      expect(result.isErect, isTrue);
      expect(result.natureDescription, contains('Virtual & Erect, Magnified'));

      // Verify that virtual ray back-projections exist
      final hasVirtualRays = result.rays.any((r) => r.virtualPoints.isNotEmpty);
      expect(hasVirtualRays, isTrue);
    });

    test('Convex Mirror: always produces virtual, erect, diminished image behind mirror', () {
      final result = engine.solve(
        scenario: OpticsScenario.convexMirror,
        focalLengthCm: 10.0,
        objectDistanceCm: 20.0,
        objectHeightCm: 3.0,
      );

      // 1/v = 1/10 - (-1/20) = 3/20 => v = 20/3 ≈ 6.67 cm
      expect(result.imageDistanceCm, closeTo(6.67, 0.02));
      expect(result.magnification, closeTo(0.333, 0.02));
      expect(result.isReal, isFalse);
      expect(result.isErect, isTrue);
      expect(result.natureDescription, contains('Diminished'));
    });

    test('Convex Lens: object at 2F produces real, inverted image at 2F on other side', () {
      final result = engine.solve(
        scenario: OpticsScenario.convexLens,
        focalLengthCm: 10.0,
        objectDistanceCm: 20.0,
        objectHeightCm: 5.0,
      );

      // Lens: 1/v = 1/10 + (-1/20) = 1/20 => v = +20 cm
      expect(result.imageDistanceCm, closeTo(20.0, 0.01));
      // m = v/u = 20 / (-20) = -1.0
      expect(result.magnification, closeTo(-1.0, 0.01));
      expect(result.isReal, isTrue);
      expect(result.isErect, isFalse);
    });

    test('Concave Lens: produces virtual, erect, diminished image on same side', () {
      final result = engine.solve(
        scenario: OpticsScenario.concaveLens,
        focalLengthCm: 10.0,
        objectDistanceCm: 20.0,
        objectHeightCm: 3.0,
      );

      // Lens: 1/v = -1/10 + (-1/20) = -3/20 => v = -20/3 ≈ -6.67 cm
      expect(result.imageDistanceCm, closeTo(-6.67, 0.02));
      expect(result.magnification, closeTo(0.333, 0.02));
      expect(result.isReal, isFalse);
      expect(result.isErect, isTrue);
    });
  });

  group('VisualSchemaRegistry & Resolver Optics Extensions', () {
    const registry = VisualSchemaRegistry();
    const resolver = VisualResolver();

    test('approves and resolves valid optics.ray_diagram visual intent', () {
      const intent = VisualIntent(
        schemaVersion: 1,
        type: VisualType.opticsRayDiagram,
        scenario: 'concave_mirror',
        inputs: {
          'focal_length_cm': 12.0,
          'object_distance_cm': 18.0,
          'object_height_cm': 4.0,
        },
      );

      final report = registry.validate(intent);
      expect(report.isValid, isTrue);
      expect(report.errors, isEmpty);

      final payload = resolver.resolve(intent);
      expect(payload, isA<OpticsVisualPayload>());
      final opticsPayload = payload as OpticsVisualPayload;
      expect(opticsPayload.result.scenario, OpticsScenario.concaveMirror);
      expect(opticsPayload.result.imageDistanceCm, closeTo(-36.0, 0.01));
    });

    test('allows initial velocity = 0 and downward velocity in motion.trajectory', () {
      const intentDrop = VisualIntent(
        schemaVersion: 1,
        type: VisualType.motionTrajectory,
        scenario: 'vertical_toss',
        inputs: {'initial_velocity_mps': 0.0},
      );

      final reportDrop = registry.validate(intentDrop);
      expect(reportDrop.isValid, isTrue);

      const intentDownward = VisualIntent(
        schemaVersion: 1,
        type: VisualType.motionTrajectory,
        scenario: 'vertical_toss',
        inputs: {'initial_velocity_mps': -15.0},
      );

      final reportDownward = registry.validate(intentDownward);
      expect(reportDownward.isValid, isTrue);
    });
  });
}
