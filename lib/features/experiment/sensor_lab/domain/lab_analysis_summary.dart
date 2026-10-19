import 'sensor_type.dart';

/// Data quality rating derived from noise level, sensor jitter, and sample count.
enum DataQualityRating {
  high,
  moderate,
  low,
  unusable;

  String get displayName {
    switch (this) {
      case DataQualityRating.high:
        return 'High Confidence';
      case DataQualityRating.moderate:
        return 'Moderate Confidence';
      case DataQualityRating.low:
        return 'Low Confidence (Noisy)';
      case DataQualityRating.unusable:
        return 'Unusable (Invalid Data)';
    }
  }
}

/// Compact, validated physical analysis summary produced by the deterministic SignalAnalyzer.
///
/// Designed to be fed into the tutor context without bloating the token budget.
class LabAnalysisSummary {
  const LabAnalysisSummary({
    required this.experimentId,
    required this.experimentTitle,
    required this.sensorType,
    required this.sampleCount,
    required this.durationSeconds,
    required this.samplingRateHz,
    required this.metrics,
    required this.quality,
    required this.jitterMs,
    required this.noiseRms,
    this.warnings = const [],
    this.notes = '',
  });

  factory LabAnalysisSummary.fromJson(Map<String, dynamic> json) {
    return LabAnalysisSummary(
      experimentId: json['experiment_id'] as String,
      experimentTitle: json['experiment_title'] as String? ?? '',
      sensorType: SensorType.values.firstWhere(
        (e) => e.name == json['sensor_type'],
        orElse: () => SensorType.accelerometer,
      ),
      sampleCount: json['sample_count'] as int,
      durationSeconds: (json['duration_seconds'] as num).toDouble(),
      samplingRateHz: (json['sampling_rate_hz'] as num).toDouble(),
      metrics: Map<String, dynamic>.from(json['metrics'] as Map),
      quality: DataQualityRating.values.firstWhere(
        (e) => e.name == json['quality'],
        orElse: () => DataQualityRating.moderate,
      ),
      jitterMs: (json['jitter_ms'] as num).toDouble(),
      noiseRms: (json['noise_rms'] as num).toDouble(),
      warnings: (json['warnings'] as List?)?.cast<String>() ?? const [],
      notes: json['notes'] as String? ?? '',
    );
  }

  final String experimentId;
  final String experimentTitle;
  final SensorType sensorType;
  final int sampleCount;
  final double durationSeconds;
  final double samplingRateHz;

  /// Derived physical metrics with standard SI units (e.g. {'tilt_angle_deg': 28.5, 'static_friction_coeff': 0.543})
  final Map<String, dynamic> metrics;

  final DataQualityRating quality;
  final double jitterMs;
  final double noiseRms;
  final List<String> warnings;
  final String notes;

  Map<String, dynamic> toJson() => {
        'experiment_id': experimentId,
        'experiment_title': experimentTitle,
        'sensor_type': sensorType.name,
        'sample_count': sampleCount,
        'duration_seconds': durationSeconds,
        'sampling_rate_hz': samplingRateHz,
        'metrics': metrics,
        'quality': quality.name,
        'jitter_ms': jitterMs,
        'noise_rms': noiseRms,
        'warnings': warnings,
        'notes': notes,
      };

  /// Generates a compact, structured text representation (< 100 tokens)
  /// specifically formatted for the Mentora agent prompt context.
  String toCompactTutorContext() {
    final buffer = StringBuffer();
    buffer.writeln('[Empirical Lab Evidence ($experimentId)]:');
    buffer.writeln(
        '- Setup: $experimentTitle (${sensorType.name}, $sampleCount samples over ${durationSeconds.toStringAsFixed(1)}s at ${samplingRateHz.toStringAsFixed(0)} Hz)');

    final metricEntries = metrics.entries
        .map((e) => '${e.key}=${e.value is double ? (e.value as double).toStringAsFixed(3) : e.value}')
        .join(', ');
    buffer.writeln('- Derived Measurements: $metricEntries');
    buffer.writeln(
        '- Quality Rating: ${quality.displayName} (Jitter: ${jitterMs.toStringAsFixed(1)}ms, Noise: ${noiseRms.toStringAsFixed(3)} ${sensorType.unit})');

    if (warnings.isNotEmpty) {
      buffer.writeln('- Anomaly Warnings: ${warnings.join('; ')}');
    }
    return buffer.toString().trim();
  }
}
