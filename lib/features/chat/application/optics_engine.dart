import 'dart:math' as math;

/// Types of optical elements supported by [OpticsEngine].
enum OpticsScenario {
  concaveMirror('concave_mirror'),
  convexMirror('convex_mirror'),
  convexLens('convex_lens'),
  concaveLens('concave_lens'),
  planeMirror('plane_mirror');

  const OpticsScenario(this.identifier);
  final String identifier;

  static OpticsScenario fromIdentifier(String? id) {
    final clean = id?.toLowerCase().trim() ?? '';
    for (final s in values) {
      if (s.identifier == clean) return s;
    }
    if (clean.contains('concave') && clean.contains('mirror')) return concaveMirror;
    if (clean.contains('convex') && clean.contains('mirror')) return convexMirror;
    if (clean.contains('concave') && clean.contains('lens')) return concaveLens;
    if (clean.contains('convex') && clean.contains('lens')) return convexLens;
    if (clean.contains('plane')) return planeMirror;
    return concaveMirror;
  }
}

/// A 2D point in the optical coordinate plane (origin at the optical center/pole).
final class OpticsPoint {
  const OpticsPoint(this.x, this.y);
  final double x;
  final double y;

  Map<String, double> toJson() => {'x': x, 'y': y};
}

/// A single continuous or segmented light ray path.
final class OpticsRayPath {
  const OpticsRayPath({
    required this.name,
    required this.points,
    this.virtualPoints = const [],
  });

  final String name;
  final List<OpticsPoint> points;
  final List<OpticsPoint> virtualPoints;
}

/// The complete calculated optical state result.
final class OpticsRayResult {
  const OpticsRayResult({
    required this.scenario,
    required this.focalLengthCm,
    required this.objectDistanceCm,
    required this.objectHeightCm,
    required this.imageDistanceCm,
    required this.imageHeightCm,
    required this.magnification,
    required this.isReal,
    required this.isErect,
    required this.isAtInfinity,
    required this.natureDescription,
    required this.rays,
  });

  final OpticsScenario scenario;
  final double focalLengthCm;
  final double objectDistanceCm;
  final double objectHeightCm;
  final double imageDistanceCm;
  final double imageHeightCm;
  final double magnification;
  final bool isReal;
  final bool isErect;
  final bool isAtInfinity;
  final String natureDescription;
  final List<OpticsRayPath> rays;
}

/// Independent analytical calculation engine for geometrical optics (mirrors & lenses).
///
/// Strictly computes ground-truth image distance ($v$), magnification ($m$),
/// image height ($h_i$), and exact ray tracing geometry following the Cartesian
/// sign convention ($u < 0$ in front of mirror/lens).
final class OpticsEngine {
  const OpticsEngine();

  /// Solves ray tracing for mirrors and lenses using analytical Gaussian optics formulas.
  OpticsRayResult solve({
    required OpticsScenario scenario,
    required double focalLengthCm,
    required double objectDistanceCm,
    double objectHeightCm = 3.0,
  }) {
    // Standardize object distance to negative value in front of lens/mirror
    final u = -objectDistanceCm.abs();
    final ho = math.max(0.5, objectHeightCm);

    double f;
    final bool isLens = scenario == OpticsScenario.convexLens || scenario == OpticsScenario.concaveLens;

    switch (scenario) {
      case OpticsScenario.concaveMirror:
        f = -focalLengthCm.abs();
        break;
      case OpticsScenario.convexMirror:
        f = focalLengthCm.abs();
        break;
      case OpticsScenario.convexLens:
        f = focalLengthCm.abs();
        break;
      case OpticsScenario.concaveLens:
        f = -focalLengthCm.abs();
        break;
      case OpticsScenario.planeMirror:
        f = double.infinity;
        break;
    }

    double v;
    double m;
    bool isAtInfinity = false;

    if (scenario == OpticsScenario.planeMirror) {
      v = -u; // behind mirror (+ value)
      m = 1.0;
    } else if (isLens) {
      // Lens formula: 1/v - 1/u = 1/f => 1/v = 1/f + 1/u = (u + f)/(u*f)
      if ((u + f).abs() < 1e-4) {
        // Object at focus: image at infinity
        isAtInfinity = true;
        v = (u * f) < 0 ? -1000.0 : 1000.0;
        m = 50.0;
      } else {
        v = (u * f) / (u + f);
        m = v / u;
      }
    } else {
      // Mirror formula: 1/v + 1/u = 1/f => 1/v = 1/f - 1/u = (u - f)/(u*f)
      if ((u - f).abs() < 1e-4) {
        // Object at focus: image at infinity
        isAtInfinity = true;
        v = -1000.0;
        m = 50.0;
      } else {
        v = (u * f) / (u - f);
        m = -(v / u);
      }
    }

    final hi = m * ho;
    final isReal = isLens ? (v > 0) : (v < 0);
    final isErect = m > 0;

    final String sizeDesc;
    if (m.abs() > 1.05) {
      sizeDesc = 'Magnified (${m.abs().toStringAsFixed(1)}×)';
    } else if (m.abs() < 0.95) {
      sizeDesc = 'Diminished (${m.abs().toStringAsFixed(1)}×)';
    } else {
      sizeDesc = 'Same size';
    }

    final String nature = isAtInfinity
        ? 'Image at Infinity ($sizeDesc)'
        : '${isReal ? "Real & Inverted" : "Virtual & Erect"}, $sizeDesc';

    // Compute ray paths
    final rays = <OpticsRayPath>[];

    // Ray 1: Parallel to principal axis
    // Object tip -> Surface at (0, ho)
    final p1Start = OpticsPoint(u, ho);
    final p1Surface = OpticsPoint(0, ho);

    if (isLens) {
      if (scenario == OpticsScenario.convexLens) {
        // Refracts through real focus (f, 0) towards image (v, hi)
        final p1End = isAtInfinity ? OpticsPoint(f * 3, -ho * 2) : OpticsPoint(v, hi);
        rays.add(OpticsRayPath(
          name: 'Parallel Ray',
          points: [p1Start, p1Surface, p1End],
        ));
      } else {
        // Concave lens: refracts diverging as if coming from virtual focus (-|f|, 0)
        final slope = ho / (0 - f);
        final p1Diverge = OpticsPoint(30, ho + slope * 30);
        rays.add(OpticsRayPath(
          name: 'Parallel Ray',
          points: [p1Start, p1Surface, p1Diverge],
          virtualPoints: [OpticsPoint(f, 0), p1Surface],
        ));
      }
    } else if (scenario == OpticsScenario.concaveMirror) {
      // Reflects through focus (f, 0)
      final p1End = isAtInfinity ? OpticsPoint(f * 2, -ho) : OpticsPoint(v, hi);
      final virt = !isReal ? [p1Surface, OpticsPoint(v, hi)] : <OpticsPoint>[];
      rays.add(OpticsRayPath(
        name: 'Parallel Ray',
        points: [p1Start, p1Surface, p1End],
        virtualPoints: virt,
      ));
    } else if (scenario == OpticsScenario.convexMirror) {
      // Reflects diverging away from virtual focus (+f, 0)
      final slope = ho / (0 - f);
      final p1Diverge = OpticsPoint(-30, ho - slope * 30);
      rays.add(OpticsRayPath(
        name: 'Parallel Ray',
        points: [p1Start, p1Surface, p1Diverge],
        virtualPoints: [p1Surface, OpticsPoint(v, hi), OpticsPoint(f, 0)],
      ));
    }

    // Ray 2: Central ray (through optical center (0,0))
    if (isLens) {
      // Passes undeflected through (0,0)
      final slope = ho / u;
      final p2End = isAtInfinity ? OpticsPoint(30, slope * 30) : OpticsPoint(v, hi);
      rays.add(OpticsRayPath(
        name: 'Central Ray',
        points: [p1Start, const OpticsPoint(0, 0), p2End],
        virtualPoints: !isReal ? [const OpticsPoint(0, 0), OpticsPoint(v, hi)] : const [],
      ));
    } else {
      // Central ray through Pole (0,0) reflecting symmetrically at equal angle
      final p2End = isReal ? OpticsPoint(v, hi) : OpticsPoint(-30, -ho * (-30 / u));
      rays.add(OpticsRayPath(
        name: 'Pole Ray',
        points: [p1Start, const OpticsPoint(0, 0), p2End],
        virtualPoints: !isReal ? [const OpticsPoint(0, 0), OpticsPoint(v, hi)] : const [],
      ));
    }

    return OpticsRayResult(
      scenario: scenario,
      focalLengthCm: f,
      objectDistanceCm: u,
      objectHeightCm: ho,
      imageDistanceCm: v,
      imageHeightCm: hi,
      magnification: m,
      isReal: isReal,
      isErect: isErect,
      isAtInfinity: isAtInfinity,
      natureDescription: nature,
      rays: rays,
    );
  }
}
