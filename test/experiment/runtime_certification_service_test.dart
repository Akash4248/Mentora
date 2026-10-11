import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/application/runtime_certification_service.dart';

void main() {
  test('certifies all built-in experiment templates', () {
    final results = const RuntimeCertificationService()
        .certifyBuiltInTemplates();

    expect(
      results.map((result) => result.templateName),
      containsAll([
        'Free Fall Experiment',
        'Pendulum Motion',
        'Plant Growth',
        'Water Cycle',
        'Heart Rate Monitor',
      ]),
    );
    expect(results, hasLength(5));

    for (final result in results) {
      expect(result.manifestLoaded, isTrue, reason: result.templateName);
      expect(result.objectsCreated, isTrue, reason: result.templateName);
      expect(result.variablesCreated, isTrue, reason: result.templateName);
      expect(result.rulesLoaded, isTrue, reason: result.templateName);
      expect(result.runtimeStarted, isTrue, reason: result.templateName);
      expect(result.simulationVisible, isTrue, reason: result.templateName);
      expect(result.noRuntimeExceptions, isTrue, reason: result.failureReason);
      expect(result.objectCount, greaterThan(0), reason: result.templateName);
      expect(result.variableCount, greaterThan(0), reason: result.templateName);
      expect(result.ruleCount, greaterThan(0), reason: result.templateName);
    }
  });
}
