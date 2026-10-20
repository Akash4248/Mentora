import 'dart:math' as math;

import '../domain/lab_analysis_summary.dart';
import '../domain/lab_experiment_definition.dart';
import '../domain/sensor_sample.dart';
import '../domain/sensor_type.dart';

/// Deterministic signal processing and mathematical analysis engine for sensor data.
///
/// Converts raw physical sensor time-series into validated physical quantities,
/// statistical uncertainty metrics, and honest quality evaluations.
class SignalAnalyzer {
  const SignalAnalyzer();

  /// Analyzes a recorded sequence of [SensorSample] against an experiment definition.
  LabAnalysisSummary analyze({
    required List<SensorSample> samples,
    required LabExperimentDefinition definition,
  }) {
    if (samples.length < 5) {
      return LabAnalysisSummary(
        experimentId: definition.id,
        experimentTitle: definition.title,
        sensorType: definition.requiredSensors.firstOrNull ?? SensorType.accelerometer,
        sampleCount: samples.length,
        durationSeconds: 0.0,
        samplingRateHz: 0.0,
        metrics: const {},
        quality: DataQualityRating.unusable,
        jitterMs: 0.0,
        noiseRms: 0.0,
        warnings: const ['Insufficient samples recorded (minimum 5 required).'],
      );
    }

    final warnings = <String>[];

    // 1. Timestamp Interval Analysis
    final intervalsMs = <double>[];
    for (var i = 1; i < samples.length; i++) {
      final delta = samples[i].timestamp.difference(samples[i - 1].timestamp).inMicroseconds / 1000.0;
      if (delta > 0) {
        intervalsMs.add(delta);
      }
    }

    final totalDurationSec =
        samples.last.timestamp.difference(samples.first.timestamp).inMicroseconds / 1000000.0;
    final effectiveDuration = totalDurationSec > 0 ? totalDurationSec : 0.001;
    final samplingRateHz = samples.length / effectiveDuration;

    var meanIntervalMs = 0.0;
    var jitterMs = 0.0;
    if (intervalsMs.isNotEmpty) {
      final sum = intervalsMs.reduce((a, b) => a + b);
      meanIntervalMs = sum / intervalsMs.length;

      var varianceSum = 0.0;
      for (final interval in intervalsMs) {
        varianceSum += math.pow(interval - meanIntervalMs, 2);
        // Flag large gap anomaly (> 3x mean interval)
        if (interval > meanIntervalMs * 3.0 && interval > 100.0) {
          if (!warnings.contains('Large timestamp gap detected between sensor samples.')) {
            warnings.add('Large timestamp gap detected between sensor samples.');
          }
        }
      }
      jitterMs = math.sqrt(varianceSum / intervalsMs.length);
    }

    // 2. Statistical Moments per Axis
    final n = samples.length;
    var sumX = 0.0, sumY = 0.0, sumZ = 0.0;
    for (final s in samples) {
      sumX += s.x;
      sumY += s.y;
      sumZ += s.z;
    }
    final meanX = sumX / n;
    final meanY = sumY / n;
    final meanZ = sumZ / n;

    var varX = 0.0, varY = 0.0, varZ = 0.0;
    for (final s in samples) {
      varX += math.pow(s.x - meanX, 2);
      varY += math.pow(s.y - meanY, 2);
      varZ += math.pow(s.z - meanZ, 2);
    }
    final stdX = math.sqrt(varX / n);
    final stdY = math.sqrt(varY / n);
    final stdZ = math.sqrt(varZ / n);
    final noiseRms = math.sqrt(stdX * stdX + stdY * stdY + stdZ * stdZ);

    // 3. Domain Specific Physics Calculations
    final metrics = <String, dynamic>{};
    final primarySensor = definition.requiredSensors.firstOrNull ?? SensorType.accelerometer;

    if (definition.id == 'exp_incline_friction') {
      final parallelAcc = math.sqrt(meanX * meanX + meanY * meanY);
      final normalAcc = meanZ.abs();
      final totalMagnitude = math.sqrt(parallelAcc * parallelAcc + normalAcc * normalAcc);

      // Verify that device is resting in static equilibrium (magnitude ~ 9.8 m/s²)
      if ((totalMagnitude - 9.8).abs() > 2.5) {
        warnings.add(
            'Device experienced non-gravitational acceleration. Keep the incline board steady.');
      }

      // Incline tilt angle theta relative to horizontal:
      // theta = atan2(parallelComponent, normalComponent)
      final thetaRad = math.atan2(parallelAcc, normalAcc);
      final thetaDeg = thetaRad * (180.0 / math.pi);

      final normalForceRatio = math.cos(thetaRad); // N / (mg)
      final parallelForceRatio = math.sin(thetaRad); // F_parallel / (mg)
      final staticFrictionCoeff = math.tan(thetaRad); // mu_s = tan(theta) at impending slip

      metrics['tilt_angle_deg'] = double.parse(thetaDeg.toStringAsFixed(2));
      metrics['tilt_angle_rad'] = double.parse(thetaRad.toStringAsFixed(4));
      metrics['normal_force_ratio'] = double.parse(normalForceRatio.toStringAsFixed(3));
      metrics['parallel_force_ratio'] = double.parse(parallelForceRatio.toStringAsFixed(3));
      metrics['static_friction_coeff'] = double.parse(staticFrictionCoeff.toStringAsFixed(3));
      metrics['mean_acceleration_mps2'] = double.parse(totalMagnitude.toStringAsFixed(2));
    } else if (definition.id == 'exp_rest_gravity') {
      final totalMagnitude = math.sqrt(meanX * meanX + meanY * meanY + meanZ * meanZ);
      final horizontalDrift = math.sqrt(meanX * meanX + meanY * meanY);
      final gravityDeviation = totalMagnitude - 9.80665;

      if (horizontalDrift > 0.8) {
        warnings.add('Phone was not placed completely flat (horizontal tilt detected).');
      }

      metrics['observed_gravity_mps2'] = double.parse(totalMagnitude.toStringAsFixed(3));
      metrics['gravity_deviation_mps2'] = double.parse(gravityDeviation.toStringAsFixed(3));
      metrics['horizontal_drift_mps2'] = double.parse(horizontalDrift.toStringAsFixed(3));
      metrics['mean_z_mps2'] = double.parse(meanZ.toStringAsFixed(3));
    } else {
      // General 3-axis statistical summary
      final totalMagnitude = math.sqrt(meanX * meanX + meanY * meanY + meanZ * meanZ);
      metrics['mean_x'] = double.parse(meanX.toStringAsFixed(2));
      metrics['mean_y'] = double.parse(meanY.toStringAsFixed(2));
      metrics['mean_z'] = double.parse(meanZ.toStringAsFixed(2));
      metrics['magnitude'] = double.parse(totalMagnitude.toStringAsFixed(2));
    }

    // 4. Quality Rating Assessment
    DataQualityRating quality;
    if (noiseRms > 2.0 || jitterMs > 35.0) {
      quality = DataQualityRating.low;
      warnings.add('High vibration or measurement jitter degraded data quality.');
    } else if (noiseRms > 0.6 || jitterMs > 15.0) {
      quality = DataQualityRating.moderate;
    } else if (samples.length >= 20) {
      quality = DataQualityRating.high;
    } else {
      quality = DataQualityRating.moderate;
    }

    return LabAnalysisSummary(
      experimentId: definition.id,
      experimentTitle: definition.title,
      sensorType: primarySensor,
      sampleCount: samples.length,
      durationSeconds: double.parse(effectiveDuration.toStringAsFixed(2)),
      samplingRateHz: double.parse(samplingRateHz.toStringAsFixed(1)),
      metrics: metrics,
      quality: quality,
      jitterMs: double.parse(jitterMs.toStringAsFixed(2)),
      noiseRms: double.parse(noiseRms.toStringAsFixed(3)),
      warnings: warnings,
    );
  }
}
