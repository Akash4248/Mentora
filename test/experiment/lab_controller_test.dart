import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/sensor_lab/application/lab_controller.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/lab_experiment_definition.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/lab_state.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/sensor_sample.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/sensor_stream_provider.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/sensor_type.dart';

void main() {
  group('LabController Lifecycle & Safety Bounds Suite', () {
    late MockSensorStreamProvider mockProvider;
    late LabController controller;

    setUp(() {
      mockProvider = MockSensorStreamProvider(
        availableSensors: {SensorType.accelerometer, SensorType.userAccelerometer},
      );
      controller = LabController(sensorProvider: mockProvider);
    });

    tearDown(() async {
      await controller.dispose();
    });

    test('starts uninitialized and transitions to ready upon valid initialization', () async {
      expect(controller.state, LabLifecycleState.uninitialized);

      final ok = await controller.initialize(LabExperimentCatalog.inclineFriction);
      expect(ok, isTrue);
      expect(controller.state, LabLifecycleState.ready);
      expect(controller.activeExperiment?.id, 'exp_incline_friction');
    });

    test('transitions to error state when required sensor is unavailable on hardware', () async {
      final limitedProvider = MockSensorStreamProvider(
        availableSensors: {SensorType.gyroscope}, // Missing accelerometer
      );
      final limitedController = LabController(sensorProvider: limitedProvider);

      final ok = await limitedController.initialize(LabExperimentCatalog.inclineFriction);
      expect(ok, isFalse);
      expect(limitedController.state, LabLifecycleState.error);
      expect(
        limitedController.statusListenable.value.errorMessage,
        contains('Required sensor'),
      );

      await limitedController.dispose();
    });

    test('full recording lifecycle: startRecording, sample collection, stopRecording and analysis', () async {
      final now = DateTime.now();
      final syntheticSamples = List.generate(
        30,
        (i) => SensorSample(
          x: 0.0,
          y: 4.9,
          z: 8.487,
          timestamp: now.add(Duration(milliseconds: i * 20)),
        ),
      );

      final providerWithSamples = MockSensorStreamProvider(
        availableSensors: {SensorType.accelerometer},
        samplesToEmit: syntheticSamples,
        emitInterval: const Duration(milliseconds: 5),
      );

      final testController = LabController(sensorProvider: providerWithSamples);
      await testController.initialize(LabExperimentCatalog.inclineFriction);

      final streamSamples = <SensorSample>[];
      final sub = testController.liveSampleStream.listen(streamSamples.add);

      await testController.startRecording();
      expect(testController.state, LabLifecycleState.recording);

      // Allow samples to stream in
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final summary = await testController.stopRecording();
      expect(testController.state, LabLifecycleState.completed);
      expect(summary.sampleCount, greaterThanOrEqualTo(25));
      expect(summary.metrics, contains('tilt_angle_deg'));
      expect(testController.recordedSamples.length, greaterThanOrEqualTo(25));
      expect(streamSamples, isNotEmpty);

      await sub.cancel();
      await testController.dispose();
    });

    test('memory bounds enforcement: automatically stops when maxSamples is reached', () async {
      const boundedExp = LabExperimentDefinition(
        id: 'exp_bounded',
        title: 'Bounded Test',
        subject: 'Physics',
        topic: 'Test',
        description: 'Test',
        safetyInstructions: ['Safe'],
        setupSteps: ['Step 1'],
        requiredSensors: [SensorType.accelerometer],
        maxSamples: 15, // Low cap for test
      );

      final now = DateTime.now();
      final infiniteSamples = List.generate(
        100,
        (i) => SensorSample(x: 0, y: 0, z: 9.8, timestamp: now.add(Duration(milliseconds: i * 10))),
      );

      final fastProvider = MockSensorStreamProvider(
        availableSensors: {SensorType.accelerometer},
        samplesToEmit: infiniteSamples,
        emitInterval: const Duration(milliseconds: 2),
      );

      final testController = LabController(sensorProvider: fastProvider);
      await testController.initialize(boundedExp);

      await testController.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Must be stopped automatically and capped strictly at maxSamples
      expect(testController.state, LabLifecycleState.completed);
      expect(testController.recordedSamples.length, 15);

      await testController.dispose();
    });

    test('duration bounds enforcement: automatically stops when maxDuration expires', () async {
      const tightDurationExp = LabExperimentDefinition(
        id: 'exp_tight',
        title: 'Tight Duration Test',
        subject: 'Physics',
        topic: 'Test',
        description: 'Test',
        safetyInstructions: ['Safe'],
        setupSteps: ['Step 1'],
        requiredSensors: [SensorType.accelerometer],
        maxDuration: Duration(milliseconds: 60), // Tight timeout
      );

      await controller.initialize(tightDurationExp);
      await controller.startRecording();
      expect(controller.state, LabLifecycleState.recording);

      // Wait for safety timeout to trigger
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(controller.state, LabLifecycleState.completed);
      expect(controller.latestSummary, isNotNull);
    });

    test('cancelRecording discards samples and safely resets state to ready', () async {
      await controller.initialize(LabExperimentCatalog.inclineFriction);
      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      controller.cancelRecording();
      expect(controller.state, LabLifecycleState.ready);
      expect(controller.recordedSamples, isEmpty);
      expect(controller.latestSummary, isNull);
    });

    test('safe repeated runs: can execute multiple recording cycles without state leakage', () async {
      await controller.initialize(LabExperimentCatalog.inclineFriction);

      // Run 1
      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final sum1 = await controller.stopRecording();
      expect(testState(controller.state), LabLifecycleState.completed);

      // Run 2
      await controller.startRecording();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final sum2 = await controller.stopRecording();
      expect(testState(controller.state), LabLifecycleState.completed);

      expect(sum1.sampleCount, greaterThan(0));
      expect(sum2.sampleCount, greaterThan(0));
    });
  });
}

LabLifecycleState testState(LabLifecycleState s) => s;
