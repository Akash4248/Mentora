import 'dart:math' as math;

/// Single analytical state point along a physical trajectory.
final class KinematicsSamplePoint {
  const KinematicsSamplePoint({
    required this.timeSeconds,
    required this.xPositionMeters,
    required this.yPositionMeters,
    required this.xVelocityMps,
    required this.yVelocityMps,
    required this.accelerationMps2,
  });

  final double timeSeconds;
  final double xPositionMeters;
  final double yPositionMeters;
  final double xVelocityMps;
  final double yVelocityMps;
  final double accelerationMps2;

  double get speedMps => math.sqrt(xVelocityMps * xVelocityMps + yVelocityMps * yVelocityMps);

  Map<String, dynamic> toJson() => {
        't': timeSeconds,
        'x': xPositionMeters,
        'y': yPositionMeters,
        'vx': xVelocityMps,
        'vy': yVelocityMps,
        'a': accelerationMps2,
      };
}

/// Fully calculated analytical trajectory solution computed independently of any LLM.
final class KinematicsTrajectoryResult {
  const KinematicsTrajectoryResult({
    required this.scenario,
    required this.timeToApexSeconds,
    required this.peakHeightMeters,
    required this.totalFlightTimeSeconds,
    required this.rangeMeters,
    required this.samples,
    this.massKg,
    this.netForceAtPeakNewtons,
  });

  final String scenario;
  final double timeToApexSeconds;
  final double peakHeightMeters;
  final double totalFlightTimeSeconds;
  final double rangeMeters;
  final List<KinematicsSamplePoint> samples;
  final double? massKg;
  final double? netForceAtPeakNewtons;

  KinematicsSamplePoint? sampleAtTime(double t) {
    if (samples.isEmpty) return null;
    if (t <= 0) return samples.first;
    if (t >= totalFlightTimeSeconds) return samples.last;

    // Find nearest sample
    var best = samples.first;
    var bestDiff = (best.timeSeconds - t).abs();
    for (final s in samples) {
      final diff = (s.timeSeconds - t).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = s;
      }
    }
    return best;
  }
}

/// Independent mathematical calculation engine for kinematics and motion physics.
///
/// Strictly computes ground-truth coordinates, velocity vectors, and peak metrics
/// using analytical equations ($s = ut + \frac{1}{2}at^2$, $v^2 = u^2 + 2as$, etc.).
/// NEVER relies on model-generated coordinates or unvalidated LLM numbers.
final class KinematicsEngine {
  const KinematicsEngine();

  /// Solves 1D vertical toss / free fall with analytical ground-truth values.
  KinematicsTrajectoryResult computeVerticalToss({
    required double initialVelocityMps,
    double gravityMps2 = 9.8,
    double initialHeightMeters = 0.0,
    double? massKg,
    int sampleCount = 60,
  }) {
    final u = initialVelocityMps;
    final g = gravityMps2 <= 0 ? 9.8 : gravityMps2;
    final h0 = math.max(0.0, initialHeightMeters);

    // Peak time: t_peak = u / g (for upward toss)
    final tApex = u > 0 ? (u / g) : 0.0;

    // Peak height: h_peak = h0 + u^2 / (2g)
    final hApex = u > 0 ? (h0 + (u * u) / (2.0 * g)) : h0;

    // Flight time to return to ground (y = 0):
    // 0 = h0 + u*t - 0.5*g*t^2  => 0.5*g*t^2 - u*t - h0 = 0
    // Discriminant D = u^2 - 4*(0.5*g)*(-h0) = u^2 + 2*g*h0
    final disc = (u * u) + (2.0 * g * h0);
    final tFlight = (u + math.sqrt(math.max(0.0, disc))) / g;

    final samples = <KinematicsSamplePoint>[];
    final count = math.max(2, sampleCount);
    for (var i = 0; i < count; i++) {
      final t = (tFlight * i) / (count - 1);
      final y = math.max(0.0, h0 + (u * t) - (0.5 * g * t * t));
      final vy = u - (g * t);

      samples.add(
        KinematicsSamplePoint(
          timeSeconds: double.parse(t.toStringAsFixed(4)),
          xPositionMeters: 0.0,
          yPositionMeters: double.parse(y.toStringAsFixed(4)),
          xVelocityMps: 0.0,
          yVelocityMps: double.parse(vy.toStringAsFixed(4)),
          accelerationMps2: -g,
        ),
      );
    }

    final netForce = massKg != null ? (massKg * g) : null;

    return KinematicsTrajectoryResult(
      scenario: 'vertical_toss',
      timeToApexSeconds: double.parse(tApex.toStringAsFixed(4)),
      peakHeightMeters: double.parse(hApex.toStringAsFixed(4)),
      totalFlightTimeSeconds: double.parse(tFlight.toStringAsFixed(4)),
      rangeMeters: 0.0,
      samples: samples,
      massKg: massKg,
      netForceAtPeakNewtons: netForce != null ? double.parse(netForce.toStringAsFixed(4)) : null,
    );
  }

  /// Solves 2D projectile trajectory analytically.
  KinematicsTrajectoryResult computeProjectile2D({
    required double launchVelocityMps,
    required double launchAngleDegrees,
    double gravityMps2 = 9.8,
    double initialHeightMeters = 0.0,
    double? massKg,
    int sampleCount = 60,
  }) {
    final u = launchVelocityMps;
    final rad = (launchAngleDegrees * math.pi) / 180.0;
    final g = gravityMps2 <= 0 ? 9.8 : gravityMps2;
    final h0 = math.max(0.0, initialHeightMeters);

    final ux = u * math.cos(rad);
    final uy = u * math.sin(rad);

    final tApex = uy > 0 ? (uy / g) : 0.0;
    final hApex = uy > 0 ? (h0 + (uy * uy) / (2.0 * g)) : h0;

    final disc = (uy * uy) + (2.0 * g * h0);
    final tFlight = (uy + math.sqrt(math.max(0.0, disc))) / g;
    final range = ux * tFlight;

    final samples = <KinematicsSamplePoint>[];
    final count = math.max(2, sampleCount);
    for (var i = 0; i < count; i++) {
      final t = (tFlight * i) / (count - 1);
      final x = ux * t;
      final y = math.max(0.0, h0 + (uy * t) - (0.5 * g * t * t));
      final vy = uy - (g * t);

      samples.add(
        KinematicsSamplePoint(
          timeSeconds: double.parse(t.toStringAsFixed(4)),
          xPositionMeters: double.parse(x.toStringAsFixed(4)),
          yPositionMeters: double.parse(y.toStringAsFixed(4)),
          xVelocityMps: double.parse(ux.toStringAsFixed(4)),
          yVelocityMps: double.parse(vy.toStringAsFixed(4)),
          accelerationMps2: -g,
        ),
      );
    }

    final netForce = massKg != null ? (massKg * g) : null;

    return KinematicsTrajectoryResult(
      scenario: 'projectile_2d',
      timeToApexSeconds: double.parse(tApex.toStringAsFixed(4)),
      peakHeightMeters: double.parse(hApex.toStringAsFixed(4)),
      totalFlightTimeSeconds: double.parse(tFlight.toStringAsFixed(4)),
      rangeMeters: double.parse(range.toStringAsFixed(4)),
      samples: samples,
      massKg: massKg,
      netForceAtPeakNewtons: netForce != null ? double.parse(netForce.toStringAsFixed(4)) : null,
    );
  }
}
