import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/lab_experiment_definition.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/sensor_stream_provider.dart';
import 'package:mentora/features/experiment/sensor_lab/domain/sensor_type.dart';

void main() {
  group('Sensor Capability & Catalog Suite', () {
    test('MockSensorStreamProvider accurately reports available and unavailable hardware', () async {
      // Device with only accelerometer (common budget phone scenario)
      final provider = MockSensorStreamProvider(
        availableSensors: {SensorType.accelerometer},
      );

      expect(await provider.isSensorAvailable(SensorType.accelerometer), isTrue);
      expect(await provider.isSensorAvailable(SensorType.gyroscope), isFalse);
      expect(await provider.isSensorAvailable(SensorType.magnetometer), isFalse);
    });

    test('LabExperimentCatalog contains approved NCERT physical experiments with safety guidelines', () {
      expect(LabExperimentCatalog.all, isNotEmpty);

      for (final exp in LabExperimentCatalog.all) {
        expect(exp.id, isNotEmpty);
        expect(exp.title, isNotEmpty);
        expect(exp.subject, isNotEmpty);
        expect(exp.topic, isNotEmpty);
        expect(exp.safetyInstructions, isNotEmpty);
        expect(exp.setupSteps, isNotEmpty);
        expect(exp.requiredSensors, isNotEmpty);
        expect(exp.maxDuration.inSeconds, greaterThan(0));
        expect(exp.maxSamples, greaterThan(0));
      }
    });

    test('LabExperimentCatalog.getById retrieves definitions accurately', () {
      final incline = LabExperimentCatalog.getById('exp_incline_friction');
      expect(incline, isNotNull);
      expect(incline!.title, contains('Incline Plane'));
      expect(incline.requiredSensors, contains(SensorType.accelerometer));
      expect(incline.safetyInstructions.first, contains('Do not slide or drop the phone'));

      final gravity = LabExperimentCatalog.getById('exp_rest_gravity');
      expect(gravity, isNotNull);
      expect(gravity!.title, contains('Gravitational Acceleration'));

      expect(LabExperimentCatalog.getById('non_existent_exp'), isNull);
    });
  });
}
