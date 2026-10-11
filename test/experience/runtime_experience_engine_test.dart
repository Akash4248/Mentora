import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/experience/engine/runtime_experience_engine.dart';
import 'package:mentora/features/experiment/experience/models/completion_condition.dart';
import 'package:mentora/features/experiment/experience/models/experiment_step.dart';
import 'package:mentora/features/experiment/experience/models/runtime_experience.dart';
import 'package:mentora/features/experiment/experience/models/step_type.dart';
import 'package:mentora/features/experiment/experience/services/experience_progress_calculator.dart';
import 'package:mentora/features/experiment/experience/services/runtime_label_formatter.dart';
import 'package:mentora/features/experiment/runtime/runtime_event.dart';
import 'package:mentora/features/experiment/runtime/runtime_event_bus.dart';

void main() {
  test('progress calculator returns 0 to 100 percent', () {
    const calculator = ExperienceProgressCalculator();

    expect(calculator.calculate(completedSteps: 0, totalSteps: 5), 0);
    expect(calculator.calculate(completedSteps: 1, totalSteps: 5), 20);
    expect(calculator.calculate(completedSteps: 2, totalSteps: 5), 40);
    expect(calculator.calculate(completedSteps: 5, totalSteps: 5), 100);
  });

  test('SliderChanged completes an interaction step', () async {
    final eventBus = RuntimeEventBus();
    final engine = RuntimeExperienceEngine(eventBus: eventBus)
      ..load(
        _experience([
          const ExperimentStep(
            id: 'control',
            title: 'Use Control',
            instruction: 'Move the slider.',
            type: StepType.interaction,
            completionCondition: ControlUsedCondition(),
          ),
        ]),
      );

    eventBus.emit(_event('SliderChanged', {'objectId': 'slider_1'}));
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.completedSteps, contains('control'));
    expect(engine.state.progress, 100);

    engine.dispose();
    eventBus.dispose();
  });

  test('ObservationRecorded completes an observation step', () async {
    final eventBus = RuntimeEventBus();
    final engine = RuntimeExperienceEngine(eventBus: eventBus)
      ..load(
        _experience([
          const ExperimentStep(
            id: 'observe',
            title: 'Record',
            instruction: 'Record an observation.',
            type: StepType.observation,
            completionCondition: ObservationCondition(),
          ),
        ]),
      );

    eventBus.emit(_event('ObservationRecorded'));
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.completedSteps, contains('observe'));
    expect(engine.state.observationCount, 1);

    engine.dispose();
    eventBus.dispose();
  });

  test('all steps complete emits completed state and analytics', () async {
    final eventBus = RuntimeEventBus();
    final engine = RuntimeExperienceEngine(eventBus: eventBus)
      ..load(
        _experience([
          const ExperimentStep(
            id: 'control',
            title: 'Use Control',
            instruction: 'Move the slider.',
            type: StepType.interaction,
            completionCondition: ControlUsedCondition(),
          ),
          const ExperimentStep(
            id: 'graph',
            title: 'Analyze',
            instruction: 'View the graph.',
            type: StepType.analysis,
            completionCondition: GraphViewedCondition(),
          ),
        ]),
      );

    eventBus.emit(_event('SliderChanged'));
    await Future<void>.delayed(Duration.zero);
    eventBus.emit(_event('GraphUpdated'));
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.isCompleted, true);
    expect(engine.state.progress, 100);
    expect(engine.analytics.experimentsCompleted, 1);
    expect(engine.analytics.stepsCompleted, 2);

    engine.dispose();
    eventBus.dispose();
  });

  test(
    'VariableUpdated, ObservationRecorded, and GraphUpdated advance steps',
    () async {
      final eventBus = RuntimeEventBus();
      final engine = RuntimeExperienceEngine(eventBus: eventBus)
        ..load(
          _experience([
            const ExperimentStep(
              id: 'variable',
              title: 'Change Variable',
              instruction: 'Update temperature.',
              type: StepType.interaction,
              completionCondition: VariableCondition(
                variableId: 'var_temperature',
              ),
            ),
            const ExperimentStep(
              id: 'observation',
              title: 'Record',
              instruction: 'Record an observation.',
              type: StepType.observation,
              completionCondition: ObservationCondition(),
            ),
            const ExperimentStep(
              id: 'graph',
              title: 'Graph',
              instruction: 'View the graph.',
              type: StepType.analysis,
              completionCondition: GraphViewedCondition(),
            ),
          ]),
        );

      eventBus.emit(
        _event('VariableUpdated', {'variableId': 'var_temperature'}),
      );
      await Future<void>.delayed(Duration.zero);
      eventBus.emit(_event('ObservationRecorded'));
      await Future<void>.delayed(Duration.zero);
      eventBus.emit(_event('GraphUpdated'));
      await Future<void>.delayed(Duration.zero);

      expect(engine.state.completedSteps.length, 3);
      expect(engine.state.isCompleted, true);

      engine.dispose();
      eventBus.dispose();
    },
  );

  test('label formatter hides runtime prefixes', () {
    const formatter = RuntimeLabelFormatter();

    expect(formatter.format('var_elapsed_time'), 'Elapsed Time');
    expect(formatter.format('obj_line_graph'), 'Line Graph');
    expect(formatter.format('rule_high_temperature'), 'High Temperature');
  });
}

RuntimeExperience _experience(List<ExperimentStep> steps) {
  return RuntimeExperience(
    id: 'exp_test',
    title: 'Experience Test',
    description: 'Test',
    objective: 'Verify experience behavior.',
    steps: steps,
  );
}

RuntimeEvent _event(
  String message, [
  Map<String, dynamic> metadata = const {},
]) {
  return RuntimeEvent(
    id: '${message}_${DateTime.now().microsecondsSinceEpoch}',
    timestamp: DateTime.now(),
    type: RuntimeEventType.custom,
    message: message,
    metadata: metadata,
  );
}
