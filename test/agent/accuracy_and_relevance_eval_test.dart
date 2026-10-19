import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/kinematics_engine.dart';
import 'package:mentora/features/chat/application/learning_accuracy_guard.dart';
import 'package:mentora/features/chat/application/unit_validator.dart';
import 'package:mentora/features/chat/application/visual_fallback_policy.dart';
import 'package:mentora/features/chat/domain/teaching_strategy.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';

void main() {
  group('Accuracy and Visual Relevance Evaluation Suite', () {
    const validator = UnitValidator();
    const guard = LearningAccuracyGuard(unitValidator: validator);
    const kinematics = KinematicsEngine();
    const fallbackPolicy = VisualFallbackPolicy();

    group('Physical Ground Truth Calculations', () {
      test('kinematics calculation matches analytical physics solutions', () {
        // 1. Vertical projectile peak: u = 14.7 m/s, g = 9.8 m/s^2
        final hPeak = validator.calculateKinematics(
          formula: 's = ut + 0.5at^2',
          parameters: {'u': 14.7, 'a': -9.8, 't': 1.5},
        );
        expect(hPeak, closeTo(11.025, 1e-4)); // Approximately 11.025m, rejecting the erroneous 11.25m

        // 2. Dynamic net force: F = m * a (mass = 3 kg, g = 9.8 m/s^2)
        final netForce = validator.calculateKinematics(
          formula: 'F = m * a',
          parameters: {'m': 3.0, 'a': 9.8},
        );
        expect(netForce, closeTo(29.4, 1e-4)); // Dynamic calculation, not hardcoded 9.8 N

        // 3. Kinetic energy: KE = 0.5 * m * v^2 (m = 4 kg, v = 5 m/s)
        final ke = validator.calculateKinematics(
          formula: 'ke = 0.5mv^2',
          parameters: {'m': 4.0, 'v': 5.0},
        );
        expect(ke, 50.0);
      });

      test('KinematicsEngine analytical solver produces continuous valid samples', () {
        final traj = kinematics.computeVerticalToss(
          initialVelocityMps: 14.7,
          gravityMps2: 9.8,
          massKg: 1.5,
          sampleCount: 100,
        );

        expect(traj.timeToApexSeconds, closeTo(1.5, 1e-4));
        expect(traj.peakHeightMeters, closeTo(11.025, 1e-4));
        expect(traj.totalFlightTimeSeconds, closeTo(3.0, 1e-4));
        expect(traj.netForceAtPeakNewtons, closeTo(14.7, 1e-4)); // 1.5 * 9.8 = 14.7 N

        // Check monotonicity of time and bounds of position
        for (var i = 0; i < traj.samples.length; i++) {
          final sample = traj.samples[i];
          expect(sample.yPositionMeters, greaterThanOrEqualTo(0.0));
          expect(sample.yPositionMeters, lessThanOrEqualTo(11.025 + 1e-4));
          if (i > 0) {
            expect(sample.timeSeconds, greaterThan(traj.samples[i - 1].timeSeconds));
          }
        }
      });
    });

    group('Accuracy Guard and Dimensional Violations', () {
      test('rejects responses with dimensional mismatch errors', () {
        // Claiming acceleration is 5 m/s (speed unit)
        const badAcceleration = 'The acceleration is 5 m/s.';
        final report = guard.inspect(
          question: 'Find acceleration',
          responseText: badAcceleration,
          strategy: TeachingStrategy.workedProblem,
        );
        expect(report.isApproved, isFalse);
        expect(report.detectedErrors.first, contains('Dimensional mismatch'));

        // Claiming force is 100 Joules (energy unit)
        const badForce = 'The net force is 100 Joules.';
        final forceReport = guard.inspect(
          question: 'Find force',
          responseText: badForce,
          strategy: TeachingStrategy.workedProblem,
        );
        expect(forceReport.isApproved, isFalse);
        expect(forceReport.detectedErrors.first, contains('Dimensional mismatch'));
      });

      test('approves responses with matching physical units', () {
        const goodResponse = 'The acceleration is 5 m/s^2 and the net force is 50 N.';
        final report = guard.inspect(
          question: 'Calculate force',
          responseText: goodResponse,
          strategy: TeachingStrategy.workedProblem,
        );
        expect(report.isApproved, isTrue);
      });
    });

    group('Visual Relevance and Deduplication', () {
      test('does not attach visual card to pure factual definitions', () {
        final fallback = fallbackPolicy.matchDeterministicFallback(
          question: 'Define momentum and give its formula',
          existingIntents: const [],
        );
        expect(fallback, isNull);
      });

      test('attaches correct PhET visual card only to matching simulation queries', () {
        final simFallback = fallbackPolicy.matchDeterministicFallback(
          question: 'Show me forces and motion simulation',
          existingIntents: const [],
        );
        expect(simFallback, isNotNull);
        expect(simFallback!.type, VisualType.simulationLauncher);
        expect(simFallback.scenario, 'phet-forces-motion');
      });
    });
  });
}
