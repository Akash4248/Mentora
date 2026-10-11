import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/guided_runtime/conditions/task_completion_condition.dart';
import 'package:mentora/features/experiment/guided_runtime/engine/task_validator.dart';
import 'package:mentora/features/experiment/runtime/runtime_profiles.dart';
import 'package:mentora/features/experiment/runtime/runtime_world.dart';

void main() {
  test('VariableReachedValueCondition completes when value reaches target', () {
    final world = RuntimeWorld()
      ..initialize(
        variablesJson: const [
          {'id': 'var_length', 'name': 'Length', 'value': 1},
        ],
        objectsJson: const [],
        rulesJson: const [],
        runtimeProfile: RuntimeProfile.general,
        curriculumMetadata: const {'title': 'Test'},
      );

    world.variables.updateVariable('var_length', 2.2);

    final complete = TaskValidator().validate(
      const VariableReachedValueCondition(
        variableId: 'var_length',
        targetValue: 2,
      ),
      world,
    );

    expect(complete, isTrue);
  });

  test('ObservationCreatedCondition completes from observation store rows', () {
    final world = RuntimeWorld()
      ..initialize(
        variablesJson: const [
          {'id': 'var_temp', 'name': 'Temperature', 'value': 75},
        ],
        objectsJson: const [],
        rulesJson: const [],
        runtimeProfile: RuntimeProfile.general,
        curriculumMetadata: const {'title': 'Test'},
      );

    world.recordObservation();

    final complete = TaskValidator().validate(
      const ObservationCreatedCondition(),
      world,
    );

    expect(complete, isTrue);
  });
}
