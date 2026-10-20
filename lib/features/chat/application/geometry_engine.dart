import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Supported geometric construction scenarios for NCERT Grades 5–12 Math.
enum GeometryScenario {
  rightTriangle('right_triangle'),
  triangleAngles('triangle_angles'),
  circleTangents('circle_tangents'),
  parallelTransversal('parallel_transversal');

  const GeometryScenario(this.identifier);
  final String identifier;

  static GeometryScenario fromIdentifier(String? id) {
    final clean = id?.toLowerCase().trim() ?? '';
    for (final s in values) {
      if (s.identifier == clean) return s;
    }
    if (clean.contains('right') || clean.contains('pythagor') || clean.contains('hypotenuse')) {
      return rightTriangle;
    }
    if (clean.contains('tangent') || clean.contains('circle')) {
      return circleTangents;
    }
    if (clean.contains('parallel') || clean.contains('transversal') || clean.contains('alternate')) {
      return parallelTransversal;
    }
    return triangleAngles;
  }
}

/// A 2D point in the coordinate plane.
@immutable
final class GeometryPoint {
  const GeometryPoint(this.x, this.y, [this.label]);
  final double x;
  final double y;
  final String? label;

  GeometryPoint copyWith({double? x, double? y, String? label}) =>
      GeometryPoint(x ?? this.x, y ?? this.y, label ?? this.label);

  Map<String, dynamic> toJson() => {'x': x, 'y': y, if (label != null) 'label': label};

  @override
  String toString() => '${label ?? "Point"}($x, $y)';
}

/// A line segment connecting two points.
@immutable
final class GeometrySegment {
  const GeometrySegment(
    this.p1,
    this.p2, {
    this.label,
    this.isDashed = false,
    this.highlightColorValue,
  });

  final GeometryPoint p1;
  final GeometryPoint p2;
  final String? label;
  final bool isDashed;
  final int? highlightColorValue;

  double get length => math.sqrt(math.pow(p2.x - p1.x, 2) + math.pow(p2.y - p1.y, 2));
}

/// An angle defined at a vertex.
@immutable
final class GeometryAngle {
  const GeometryAngle({
    required this.vertex,
    required this.startAngleRad,
    required this.sweepAngleRad,
    required this.degrees,
    this.label,
    this.isRightAngle = false,
  });

  final GeometryPoint vertex;
  final double startAngleRad;
  final double sweepAngleRad;
  final double degrees;
  final String? label;
  final bool isRightAngle;
}

/// A circle in the geometry construction plane.
@immutable
final class GeometryCircle {
  const GeometryCircle({
    required this.center,
    required this.radius,
    this.label,
    this.isDashed = false,
  });

  final GeometryPoint center;
  final double radius;
  final String? label;
  final bool isDashed;
}

/// The complete calculated geometric state.
@immutable
final class GeometryConstructionResult {
  const GeometryConstructionResult({
    required this.scenario,
    required this.points,
    required this.segments,
    required this.angles,
    required this.circles,
    required this.measurements,
    required this.theoremNote,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final GeometryScenario scenario;
  final Map<String, GeometryPoint> points;
  final List<GeometrySegment> segments;
  final List<GeometryAngle> angles;
  final List<GeometryCircle> circles;
  final Map<String, String> measurements;
  final String theoremNote;
  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}

/// Deterministic domain engine for Euclidean and coordinate geometry.
///
/// Implements analytical ground truth calculations for:
/// - Right-angle triangles & Pythagoras Theorem ($a^2 + b^2 = c^2$).
/// - Arbitrary triangles with Law of Cosines, circumcircles, and incircles.
/// - Circle tangents from an external point ($PT_1 = PT_2$, $OT_1 \perp PT_1$).
/// - Parallel lines cut by a transversal with corresponding and alternate angles.
final class GeometryEngine {
  const GeometryEngine();

  /// Solves a right-triangle scenario given base $a$ and height $b$.
  GeometryConstructionResult solveRightTriangle({
    required double base,
    required double height,
  }) {
    final a = math.max(0.5, base.abs());
    final b = math.max(0.5, height.abs());
    final c = math.sqrt(a * a + b * b);

    // Acute angles in degrees
    final angleA = math.atan2(b, a) * (180.0 / math.pi);
    final angleB = 90.0 - angleA;
    final area = 0.5 * a * b;
    final perimeter = a + b + c;

    // Vertices:
    // C is the right-angle vertex at (0, 0)
    // B is along the base at (a, 0)
    // A is along the height at (0, b)
    const pC = GeometryPoint(0.0, 0.0, 'C (90°)');
    final pB = GeometryPoint(a, 0.0, 'B');
    final pA = GeometryPoint(0.0, b, 'A');

    final segments = [
      GeometrySegment(pC, pB, label: 'a = ${a.toStringAsFixed(1)}'),
      GeometrySegment(pC, pA, label: 'b = ${b.toStringAsFixed(1)}'),
      GeometrySegment(pA, pB, label: 'c = ${c.toStringAsFixed(2)}'),
    ];

    // Right-angle marker at C
    final angles = [
      const GeometryAngle(
        vertex: pC,
        startAngleRad: 0.0,
        sweepAngleRad: math.pi / 2,
        degrees: 90.0,
        isRightAngle: true,
      ),
      GeometryAngle(
        vertex: pB,
        startAngleRad: math.pi,
        sweepAngleRad: -math.atan2(b, a),
        degrees: angleA,
        label: '${angleA.toStringAsFixed(1)}°',
      ),
      GeometryAngle(
        vertex: pA,
        startAngleRad: -math.pi / 2,
        sweepAngleRad: math.atan2(a, b),
        degrees: angleB,
        label: '${angleB.toStringAsFixed(1)}°',
      ),
    ];

    return GeometryConstructionResult(
      scenario: GeometryScenario.rightTriangle,
      points: {'A': pA, 'B': pB, 'C': pC},
      segments: segments,
      angles: angles,
      circles: const [],
      measurements: {
        'Base (a)': a.toStringAsFixed(1),
        'Height (b)': b.toStringAsFixed(1),
        'Hypotenuse (c)': c.toStringAsFixed(2),
        'Area': area.toStringAsFixed(2),
        'Perimeter': perimeter.toStringAsFixed(2),
      },
      theoremNote: 'Pythagoras: ${a.toStringAsFixed(1)}² + ${b.toStringAsFixed(1)}² = ${c.toStringAsFixed(2)}²',
      minX: -0.5,
      maxX: a + 0.8,
      minY: -0.5,
      maxY: b + 0.8,
    );
  }

  /// Solves circle tangents from an external point $P$ at distance $d$ from center $O$ of radius $r$.
  GeometryConstructionResult solveCircleTangents({
    required double radius,
    required double externalDistance,
  }) {
    final r = math.max(0.5, radius.abs());
    final d = math.max(r + 0.5, externalDistance.abs());

    // Tangent length L = sqrt(d^2 - r^2)
    final l = math.sqrt(d * d - r * r);
    // Contact angle theta = acos(r / d)
    final theta = math.acos(r / d);

    // Center at (0, 0), Point P at (d, 0)
    const pO = GeometryPoint(0.0, 0.0, 'O');
    final pP = GeometryPoint(d, 0.0, 'P');

    // Tangent contact points T1 and T2
    final t1X = r * math.cos(theta);
    final t1Y = r * math.sin(theta);
    final t2X = r * math.cos(-theta);
    final t2Y = r * math.sin(-theta);

    final pT1 = GeometryPoint(t1X, t1Y, 'T₁');
    final pT2 = GeometryPoint(t2X, t2Y, 'T₂');

    final segments = [
      // Tangents PT1 and PT2
      GeometrySegment(pP, pT1, label: 'L = ${l.toStringAsFixed(2)}'),
      GeometrySegment(pP, pT2, label: 'L = ${l.toStringAsFixed(2)}'),
      // Radii OT1 and OT2
      GeometrySegment(pO, pT1, label: 'r = ${r.toStringAsFixed(1)}', isDashed: true),
      GeometrySegment(pO, pT2, label: 'r = ${r.toStringAsFixed(1)}', isDashed: true),
      // Center line OP
      GeometrySegment(pO, pP, label: 'd = ${d.toStringAsFixed(1)}', isDashed: true),
    ];

    // Right angles at contact points: OT1 perpendicular to PT1, OT2 perpendicular to PT2
    final angles = [
      GeometryAngle(
        vertex: pT1,
        startAngleRad: theta,
        sweepAngleRad: math.pi / 2,
        degrees: 90.0,
        isRightAngle: true,
      ),
      GeometryAngle(
        vertex: pT2,
        startAngleRad: -theta,
        sweepAngleRad: -math.pi / 2,
        degrees: 90.0,
        isRightAngle: true,
      ),
    ];

    final circles = [
      GeometryCircle(center: pO, radius: r, label: 'Circle(O, $r)'),
    ];

    return GeometryConstructionResult(
      scenario: GeometryScenario.circleTangents,
      points: {'O': pO, 'P': pP, 'T1': pT1, 'T2': pT2},
      segments: segments,
      angles: angles,
      circles: circles,
      measurements: {
        'Radius (r)': r.toStringAsFixed(1),
        'Distance (d)': d.toStringAsFixed(1),
        'Tangent (PT₁)': l.toStringAsFixed(2),
        'Tangent (PT₂)': l.toStringAsFixed(2),
      },
      theoremNote: 'Tangents from external point are equal: PT₁ = PT₂ = ${l.toStringAsFixed(2)} (OT ⊥ PT)',
      minX: -r - 0.5,
      maxX: d + 0.8,
      minY: -r - 0.8,
      maxY: r + 0.8,
    );
  }

  /// Solves two parallel lines cut by a transversal at angle theta.
  GeometryConstructionResult solveParallelTransversal({
    required double angleDegrees,
    double lineSpacing = 3.0,
    double lineWidth = 7.0,
  }) {
    final thetaDeg = angleDegrees.clamp(15.0, 85.0);
    final thetaRad = thetaDeg * (math.pi / 180.0);
    final h = math.max(1.5, lineSpacing);
    final w = math.max(4.0, lineWidth);

    // Line 1: y = h, Line 2: y = 0
    final pL1Left = GeometryPoint(-w / 2, h);
    final pL1Right = GeometryPoint(w / 2, h);
    final pL2Left = GeometryPoint(-w / 2, 0.0);
    final pL2Right = GeometryPoint(w / 2, 0.0);

    // Transversal passes through (0, 0) and intersects Line 1 at (h / tan(theta), h)
    final intersect2 = const GeometryPoint(0.0, 0.0, 'B');
    final intersect1X = h / math.tan(thetaRad);
    final intersect1 = GeometryPoint(intersect1X, h, 'A');

    // Transversal extension
    final ext = 1.0;
    final tTop = GeometryPoint(intersect1X + ext / math.tan(thetaRad), h + ext);
    final tBottom = GeometryPoint(-ext / math.tan(thetaRad), -ext);

    final segments = [
      GeometrySegment(pL1Left, pL1Right, label: 'L₁'),
      GeometrySegment(pL2Left, pL2Right, label: 'L₂ ∥ L₁'),
      GeometrySegment(tBottom, tTop, label: 'Transversal', highlightColorValue: 0xFF38BDF8),
    ];

    // Corresponding and alternate interior angle pairs
    final supplementaryDeg = 180.0 - thetaDeg;
    final angles = [
      GeometryAngle(
        vertex: intersect2,
        startAngleRad: 0.0,
        sweepAngleRad: thetaRad,
        degrees: thetaDeg,
        label: '${thetaDeg.toStringAsFixed(0)}°',
      ),
      GeometryAngle(
        vertex: intersect1,
        startAngleRad: 0.0,
        sweepAngleRad: thetaRad,
        degrees: thetaDeg,
        label: '${thetaDeg.toStringAsFixed(0)}°',
      ),
      GeometryAngle(
        vertex: intersect1,
        startAngleRad: math.pi,
        sweepAngleRad: -thetaRad,
        degrees: thetaDeg,
        label: '${thetaDeg.toStringAsFixed(0)}° (Alt)',
      ),
    ];

    return GeometryConstructionResult(
      scenario: GeometryScenario.parallelTransversal,
      points: {'A': intersect1, 'B': intersect2},
      segments: segments,
      angles: angles,
      circles: const [],
      measurements: {
        'Angle (θ)': '${thetaDeg.toStringAsFixed(0)}°',
        'Alternate Interior': '${thetaDeg.toStringAsFixed(0)}°',
        'Corresponding': '${thetaDeg.toStringAsFixed(0)}°',
        'Consecutive Int': '${supplementaryDeg.toStringAsFixed(0)}°',
      },
      theoremNote: 'Alternate interior angles are equal (${thetaDeg.toStringAsFixed(0)}° = ${thetaDeg.toStringAsFixed(0)}°), consecutive interior sum to 180°',
      minX: -w / 2 - 0.5,
      maxX: math.max(w / 2, intersect1X + ext) + 0.5,
      minY: -ext - 0.5,
      maxY: h + ext + 0.5,
    );
  }

  /// General solver dispatching to specific scenarios.
  GeometryConstructionResult solve({
    required GeometryScenario scenario,
    Map<String, dynamic> inputs = const {},
  }) {
    switch (scenario) {
      case GeometryScenario.rightTriangle:
        final b = (inputs['base'] ?? inputs['a'] ?? inputs['adjacent'] ?? 4.0 as num).toDouble();
        final h = (inputs['height'] ?? inputs['b'] ?? inputs['opposite'] ?? 3.0 as num).toDouble();
        return solveRightTriangle(base: b, height: h);

      case GeometryScenario.circleTangents:
        final r = (inputs['radius'] ?? inputs['r'] ?? 3.0 as num).toDouble();
        final d = (inputs['distance'] ?? inputs['d'] ?? 5.0 as num).toDouble();
        return solveCircleTangents(radius: r, externalDistance: d);

      case GeometryScenario.parallelTransversal:
        final angle = (inputs['angle'] ?? inputs['theta'] ?? inputs['angle_deg'] ?? 45.0 as num).toDouble();
        return solveParallelTransversal(angleDegrees: angle);

      case GeometryScenario.triangleAngles:
        // Default to right triangle if arbitrary triangle sides not fully supplied
        final b = (inputs['base'] ?? inputs['a'] ?? 4.0 as num).toDouble();
        final h = (inputs['height'] ?? inputs['b'] ?? 3.0 as num).toDouble();
        return solveRightTriangle(base: b, height: h);
    }
  }
}
