import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/sensor_lab/application/signal_analyzer.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/lab_analysis_summary.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/lab_experiment_definition.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/sensor_sample.dart';

void main() {
  group('SignalAnalyzer Deterministic Math & Uncertainty Suite', () {
    const analyzer = SignalAnalyzer();

    test('Reference Signal 1: Flat Horizontal Table (Zero Incline)', () {
      final now = DateTime.now();
      final flatSamples = List.generate(
        50,
        (i) => SensorSample(
          x: 0.0,
          y: 0.0,
          z: 9.8,
          timestamp: now.add(Duration(milliseconds: i * 20)),
        ),
      );

      final summary = analyzer.analyze(
        samples: flatSamples,
        definition: LabExperimentCatalog.inclineFriction,
      );

      expect(summary.quality, DataQualityRating.high);
      expect(summary.sampleCount, 50);
      expect(summary.warnings, isEmpty);

      // In flat position: theta = 0 deg, normal force ratio = 1.0, mu_s = 0.0
      final theta = (summary.metrics['tilt_angle_deg'] as num).toDouble();
      final normalForce = (summary.metrics['normal_force_ratio'] as num).toDouble();
      final frictionCoeff = (summary.metrics['static_friction_coeff'] as num).toDouble();

      expect(theta, closeTo(0.0, 1e-2));
      expect(normalForce, closeTo(1.0, 1e-2));
      expect(frictionCoeff, closeTo(0.0, 1e-2));
    });

    test('Reference Signal 2: 30-Degree Incline Board (Impending Slip at 30°)', () {
      final now = DateTime.now();
      // For 30 deg incline: parallel component = 9.8 * sin(30°) = 4.900
      // Normal component = 9.8 * cos(30°) = 8.487
      final incline30Samples = List.generate(
        60,
        (i) => SensorSample(
          x: 0.0,
          y: 4.900,
          z: 8.487,
          timestamp: now.add(Duration(milliseconds: i * 20)),
        ),
      );

      final summary = analyzer.analyze(
        samples: incline30Samples,
        definition: LabExperimentCatalog.inclineFriction,
      );

      expect(summary.quality, DataQualityRating.high);
      final theta = (summary.metrics['tilt_angle_deg'] as num).toDouble();
      final normalForce = (summary.metrics['normal_force_ratio'] as num).toDouble();
      final frictionCoeff = (summary.metrics['static_friction_coeff'] as num).toDouble();

      // Theoretical: theta = 30.0°, N/mg = cos(30°) ≈ 0.866, mu_s = tan(30°) ≈ 0.577
      expect(theta, closeTo(30.0, 0.1));
      expect(normalForce, closeTo(0.866, 0.005));
      expect(frictionCoeff, closeTo(0.577, 0.005));
    });

    test('Reference Signal 3: 45-Degree Incline Board (mu_s = 1.0)', () {
      final now = DateTime.now();
      // For 45 deg incline: parallel = 9.8 * sin(45°) ≈ 6.9296, normal = 9.8 * cos(45°) ≈ 6.9296
      final gComponent = 9.8 * math.sin(math.pi / 4.0);
      final incline45Samples = List.generate(
        50,
        (i) => SensorSample(
          x: gComponent,
          y: 0.0,
          z: gComponent,
          timestamp: now.add(Duration(milliseconds: i * 20)),
        ),
      );

      final summary = analyzer.analyze(
        samples: incline45Samples,
        definition: LabExperimentCatalog.inclineFriction,
      );

      expect(summary.quality, DataQualityRating.high);
      final theta = (summary.metrics['tilt_angle_deg'] as num).toDouble();
      final normalForce = (summary.metrics['normal_force_ratio'] as num).toDouble();
      final frictionCoeff = (summary.metrics['static_friction_coeff'] as num).toDouble();

      // Theoretical: theta = 45.0°, N/mg = cos(45°) ≈ 0.707, mu_s = tan(45°) = 1.0
      expect(theta, closeTo(45.0, 0.1));
      expect(normalForce, closeTo(0.707, 0.005));
      expect(frictionCoeff, closeTo(1.0, 0.005));
    });

    test('detects timestamp gap anomaly and flags warning honestly', () {
      final now = DateTime.now();
      final samplesWithGap = <SensorSample>[
        SensorSample(x: 0, y: 0, z: 9.8, timestamp: now),
        SensorSample(x: 0, y: 0, z: 9.8, timestamp: now.add(const Duration(milliseconds: 20))),
        SensorSample(x: 0, y: 0, z: 9.8, timestamp: now.add(const Duration(milliseconds: 40))),
        // 500ms gap (missing samples due to system stall)
        SensorSample(x: 0, y: 0, z: 9.8, timestamp: now.add(const Duration(milliseconds: 540))),
        SensorSample(x: 0, y: 0, z: 9.8, timestamp: now.add(const Duration(milliseconds: 560))),
        SensorSample(x: 0, y: 0, z: 9.8, timestamp: now.add(const Duration(milliseconds: 580))),
      ];

      final summary = analyzer.analyze(
        samples: samplesWithGap,
        definition: LabExperimentCatalog.restGravity,
      );

      expect(
        summary.warnings.any((w) => w.contains('timestamp gap')),
        isTrue,
      );
    });

    test('degrades quality rating to low when high vibration/noise is detected', () {
      final now = DateTime.now();
      // Artificially noisy signal with high variance
      final noisySamples = List.generate(
        30,
        (i) => SensorSample(
          x: (i % 2 == 0 ? 3.0 : -3.0),
          y: (i % 2 == 0 ? -2.5 : 2.5),
          z: 9.8 + (i % 2 == 0 ? 2.0 : -2.0),
          timestamp: now.add(Duration(milliseconds: i * 20)),
        ),
      );

      final summary = analyzer.analyze(
        samples: noisySamples,
        definition: LabExperimentCatalog.inclineFriction,
      );

      expect(summary.quality, DataQualityRating.low);
      expect(summary.noiseRms, greaterThan(2.0));
      expect(summary.warnings.any((w) => w.contains('vibration')), isTrue);
    });

    test('gracefully rejects recordings with insufficient samples (< 5)', () {
      final fewSamples = [
        SensorSample(x: 0, y: 0, z: 9.8, timestamp: DateTime.now()),
        SensorSample(x: 0, y: 0, z: 9.8, timestamp: DateTime.now()),
      ];

      final summary = analyzer.analyze(
        samples: fewSamples,
        definition: LabExperimentCatalog.inclineFriction,
      );

      expect(summary.quality, DataQualityRating.unusable);
      expect(summary.warnings.first, contains('Insufficient samples'));
    });
  });
}
