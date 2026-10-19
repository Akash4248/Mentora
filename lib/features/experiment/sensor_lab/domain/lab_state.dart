import 'sensor_sample.dart';

/// Lifecycle state for an active science laboratory session.
enum LabLifecycleState {
  uninitialized,
  ready,
  calibrating,
  recording,
  analyzing,
  completed,
  error;

  bool get isActive => this == LabLifecycleState.calibrating || this == LabLifecycleState.recording;
}

/// Real-time status update emitted for the UI presentation layer.
class LabStatusUpdate {
  const LabStatusUpdate({
    required this.state,
    this.sampleCount = 0,
    this.elapsed = Duration.zero,
    this.latestSample,
    this.errorMessage,
  });

  final LabLifecycleState state;
  final int sampleCount;
  final Duration elapsed;
  final SensorSample? latestSample;
  final String? errorMessage;

  LabStatusUpdate copyWith({
    LabLifecycleState? state,
    int? sampleCount,
    Duration? elapsed,
    SensorSample? latestSample,
    String? errorMessage,
  }) {
    return LabStatusUpdate(
      state: state ?? this.state,
      sampleCount: sampleCount ?? this.sampleCount,
      elapsed: elapsed ?? this.elapsed,
      latestSample: latestSample ?? this.latestSample,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
