import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/kinematics_engine.dart';

void main() {
  group('KinematicsEngine', () {
    const engine = KinematicsEngine();

    test('computes vertical toss apex and trajectory analytically', () {
      // Test the exact scenario: u = 14.7 m/s, g = 9.8 m/s^2, mass = 2 kg
      final result = engine.computeVerticalToss(
        initialVelocityMps: 14.7,
        gravityMps2: 9.8,
        massKg: 2.0,
        sampleCount: 50,
      );

      // t_apex = u / g = 14.7 / 9.8 = 1.5 s
      expect(result.timeToApexSeconds, 1.5);

      // h_apex = u^2 / (2g) = 14.7^2 / (2 * 9.8) = 216.09 / 19.6 = 11.025 m
      expect(result.peakHeightMeters, 11.025);

      // Total flight time = 2 * 1.5 = 3.0 s
      expect(result.totalFlightTimeSeconds, 3.0);

      // Net force at apex: F = m * g = 2.0 * 9.8 = 19.6 N (NOT a fixed 9.8 N)
      expect(result.netForceAtPeakNewtons, 19.6);

      // Verify sample points sequence
      expect(result.samples.length, 50);
      expect(result.samples.first.timeSeconds, 0.0);
      expect(result.samples.first.yPositionMeters, 0.0);
      expect(result.samples.first.yVelocityMps, 14.7);

      expect(result.samples.last.timeSeconds, closeTo(3.0, 0.01));
      expect(result.samples.last.yPositionMeters, closeTo(0.0, 0.01));
      expect(result.samples.last.yVelocityMps, closeTo(-14.7, 0.01));

      // Query nearest sample at t = 1.5s
      final apexSample = result.sampleAtTime(1.5);
      expect(apexSample, isNotNull);
      expect(apexSample!.yPositionMeters, closeTo(11.025, 0.1));
      expect(apexSample.yVelocityMps, closeTo(0.0, 0.5));
    });

    test('computes 2D projectile trajectory analytically', () {
      final result = engine.computeProjectile2D(
        launchVelocityMps: 20.0,
        launchAngleDegrees: 45.0,
        gravityMps2: 9.8,
        sampleCount: 50,
      );

      // ux = 20 * cos(45) = 14.1421, uy = 20 * sin(45) = 14.1421
      // t_apex = uy / g = 14.1421 / 9.8 = 1.443 s
      // h_apex = uy^2 / (2g) = 200 / 19.6 = 10.204 m
      expect(result.peakHeightMeters, closeTo(10.204, 0.01));
      expect(result.timeToApexSeconds, closeTo(1.443, 0.01));
      expect(result.totalFlightTimeSeconds, closeTo(2.886, 0.01));

      // Range = ux * t_flight = 14.1421 * 2.8864 = 40.816 m
      expect(result.rangeMeters, closeTo(40.816, 0.05));
      expect(result.samples.length, 50);
    });

    test('handles zero launch velocity gracefully', () {
      final result = engine.computeVerticalToss(
        initialVelocityMps: 0.0,
        initialHeightMeters: 10.0,
        gravityMps2: 9.8,
      );

      expect(result.timeToApexSeconds, 0.0);
      expect(result.peakHeightMeters, 10.0);
      // t = sqrt(2h / g) = sqrt(20 / 9.8) = 1.4286 s
      expect(result.totalFlightTimeSeconds, closeTo(1.4286, 0.01));
    });
  });
}
