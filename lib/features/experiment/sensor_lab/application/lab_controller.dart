import 'dart:async';
import 'package:flutter/foundation.dart';

import '../domain/lab_analysis_summary.dart';
import '../domain/lab_experiment_definition.dart';
import '../domain/lab_state.dart';
import '../domain/sensor_sample.dart';
import '../domain/sensor_stream_provider.dart';
import 'signal_analyzer.dart';

/// Single orchestrator for sensor hardware access, sampling lifecycles,
/// memory-bounded buffer storage, and safety timeouts.
///
/// Ensures strict architectural isolation: the AI tutor never receives
/// raw sensor handles or unvalidated hardware streams.
class LabController {
  LabController({
    SensorStreamProvider? sensorProvider,
    SignalAnalyzer? signalAnalyzer,
  })  : _sensorProvider = sensorProvider ?? const DeviceSensorStreamProvider(),
        _signalAnalyzer = signalAnalyzer ?? const SignalAnalyzer();

  final SensorStreamProvider _sensorProvider;
  final SignalAnalyzer _signalAnalyzer;

  final ValueNotifier<LabStatusUpdate> _statusNotifier =
      ValueNotifier<LabStatusUpdate>(const LabStatusUpdate(state: LabLifecycleState.uninitialized));

  final StreamController<SensorSample> _liveSampleController =
      StreamController<SensorSample>.broadcast();

  final List<SensorSample> _samples = [];
  LabExperimentDefinition? _activeExperiment;
  LabAnalysisSummary? _latestSummary;
  StreamSubscription<SensorSample>? _sensorSubscription;
  Timer? _maxDurationTimer;
  Timer? _tickerTimer;
  DateTime? _recordingStartTime;
  bool _disposed = false;

  ValueListenable<LabStatusUpdate> get statusListenable => _statusNotifier;
  LabLifecycleState get state => _statusNotifier.value.state;
  LabExperimentDefinition? get activeExperiment => _activeExperiment;
  LabAnalysisSummary? get latestSummary => _latestSummary;
  Stream<SensorSample> get liveSampleStream => _liveSampleController.stream;
  List<SensorSample> get recordedSamples => List.unmodifiable(_samples);

  /// Initializes the controller for a given experiment and verifies sensor hardware availability.
  Future<bool> initialize(LabExperimentDefinition experiment) async {
    if (_disposed) throw StateError('LabController has been disposed.');
    _activeExperiment = experiment;
    _latestSummary = null;
    _samples.clear();

    // Verify platform hardware sensor support
    for (final sensor in experiment.requiredSensors) {
      final available = await _sensorProvider.isSensorAvailable(sensor);
      if (!available) {
        _statusNotifier.value = LabStatusUpdate(
          state: LabLifecycleState.error,
          errorMessage: 'Required sensor (${sensor.displayName}) is not supported on this device.',
        );
        return false;
      }
    }

    _statusNotifier.value = const LabStatusUpdate(state: LabLifecycleState.ready);
    return true;
  }

  /// Begins recording physical sensor measurements.
  Future<void> startRecording() async {
    if (_disposed) throw StateError('LabController has been disposed.');
    final experiment = _activeExperiment;
    if (experiment == null) {
      throw StateError('Cannot start recording: No experiment has been initialized.');
    }
    if (state != LabLifecycleState.ready && state != LabLifecycleState.completed) {
      throw StateError('Cannot start recording from state: $state');
    }

    _samples.clear();
    _recordingStartTime = DateTime.now();

    _statusNotifier.value = LabStatusUpdate(
      state: LabLifecycleState.recording,
      sampleCount: 0,
      elapsed: Duration.zero,
    );

    final primarySensor = experiment.requiredSensors.first;
    final stream = _sensorProvider.getSensorStream(
      primarySensor,
      samplingPeriod: const Duration(milliseconds: 20), // 50 Hz
    );

    _sensorSubscription = stream.listen(
      _onSampleReceived,
      onError: (Object error) {
        _statusNotifier.value = LabStatusUpdate(
          state: LabLifecycleState.error,
          errorMessage: 'Sensor stream interrupted: $error',
        );
        _stopRecordingInternals();
      },
    );

    // Safety timeout: automatically stop recording if maxDuration is exceeded
    _maxDurationTimer?.cancel();
    _maxDurationTimer = Timer(experiment.maxDuration, () {
      if (state == LabLifecycleState.recording) {
        stopRecording();
      }
    });

    // 10Hz UI ticker for elapsed duration updates
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (state == LabLifecycleState.recording && _recordingStartTime != null) {
        final elapsed = DateTime.now().difference(_recordingStartTime!);
        _statusNotifier.value = _statusNotifier.value.copyWith(elapsed: elapsed);
      }
    });
  }

  void _onSampleReceived(SensorSample sample) {
    if (state != LabLifecycleState.recording) return;

    final experiment = _activeExperiment;
    if (experiment == null) return;

    _samples.add(sample);
    if (!_liveSampleController.isClosed) {
      _liveSampleController.add(sample);
    }

    final elapsed = _recordingStartTime != null
        ? DateTime.now().difference(_recordingStartTime!)
        : Duration.zero;

    _statusNotifier.value = LabStatusUpdate(
      state: LabLifecycleState.recording,
      sampleCount: _samples.length,
      elapsed: elapsed,
      latestSample: sample,
    );

    // Memory bounding: enforce max sample capacity limit
    if (_samples.length >= experiment.maxSamples) {
      stopRecording();
    }
  }

  /// Explicit user-initiated action: stops active recording and triggers mathematical signal analysis.
  Future<LabAnalysisSummary> stopRecording() async {
    if (_disposed) throw StateError('LabController has been disposed.');
    final experiment = _activeExperiment;
    if (experiment == null) {
      throw StateError('No active experiment to analyze.');
    }

    _stopRecordingInternals();
    _statusNotifier.value = _statusNotifier.value.copyWith(state: LabLifecycleState.analyzing);

    // Deterministic mathematical analysis
    final summary = _signalAnalyzer.analyze(
      samples: _samples,
      definition: experiment,
    );
    _latestSummary = summary;

    _statusNotifier.value = LabStatusUpdate(
      state: LabLifecycleState.completed,
      sampleCount: _samples.length,
      elapsed: _statusNotifier.value.elapsed,
      latestSample: _samples.lastOrNull,
    );

    return summary;
  }

  /// Aborts active recording without generating analysis results.
  void cancelRecording() {
    _stopRecordingInternals();
    _samples.clear();
    _statusNotifier.value = const LabStatusUpdate(state: LabLifecycleState.ready);
  }

  void _stopRecordingInternals() {
    _sensorSubscription?.cancel();
    _sensorSubscription = null;
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    _tickerTimer?.cancel();
    _tickerTimer = null;
  }

  /// Disposes resources, subscriptions, and timers cleanly.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _stopRecordingInternals();
    await _liveSampleController.close();
    _statusNotifier.dispose();
  }
}
