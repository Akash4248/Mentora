import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/guided_runtime/conditions/task_completion_condition.dart';
import 'package:mentora/features/experiment/guided_runtime/engine/guided_experiment_engine.dart';
import 'package:mentora/features/experiment/guided_runtime/models/experiment_mission.dart';
import 'package:mentora/features/experiment/guided_runtime/models/experiment_question.dart';
import 'package:mentora/features/experiment/guided_runtime/models/experiment_task.dart';
import 'package:mentora/features/experiment/runtime/runtime_event.dart';
import 'package:mentora/features/experiment/runtime/runtime_profiles.dart';
import 'package:mentora/features/experiment/runtime/runtime_world.dart';

void main() {
  test('Task1 complete activates Task2', () async {
    final world = _world();
    final engine =
        GuidedExperimentEngine(runtime: world, eventBus: world.eventBus)
          ..loadMission(
            const ExperimentMission(
              id: 'mission',
              title: 'Mission',
              objective: 'Objective',
              description: '',
              difficulty: 'Easy',
              estimatedDuration: Duration(minutes: 5),
              tasks: [
                ExperimentTask(
                  id: 'control',
                  title: 'Use control',
                  description: '',
                  condition: ControlUsedCondition(),
                ),
                ExperimentTask(
                  id: 'observe',
                  title: 'Observe',
                  description: '',
                  condition: ObservationCreatedCondition(),
                ),
              ],
            ),
          );

    engine.startMission();
    world.eventBus.emit(_event('SliderChanged', {'objectId': 'slider_1'}));
    await pumpEventQueue();

    expect(engine.state.completedTasks, contains('control'));
    expect(engine.state.currentTask?.id, 'observe');
  });

  test('Mission completes when all tasks complete', () async {
    final world = _world();
    final engine =
        GuidedExperimentEngine(runtime: world, eventBus: world.eventBus)
          ..loadMission(
            const ExperimentMission(
              id: 'mission',
              title: 'Mission',
              objective: 'Objective',
              description: '',
              difficulty: 'Easy',
              estimatedDuration: Duration(minutes: 5),
              tasks: [
                ExperimentTask(
                  id: 'control',
                  title: 'Use control',
                  description: '',
                  condition: ControlUsedCondition(),
                ),
              ],
            ),
          );

    world.eventBus.emit(_event('ButtonPressed', {'objectId': 'button_1'}));
    await pumpEventQueue();

    expect(engine.state.missionCompleted, isTrue);
    expect(engine.analytics.missionsCompleted, 1);
  });

  test('Question answer marks question condition complete', () {
    final world = _world();
    final engine =
        GuidedExperimentEngine(runtime: world, eventBus: world.eventBus)
          ..loadMission(
            const ExperimentMission(
              id: 'mission',
              title: 'Mission',
              objective: 'Objective',
              description: '',
              difficulty: 'Easy',
              estimatedDuration: Duration(minutes: 5),
              tasks: [
                ExperimentTask(
                  id: 'question_task',
                  title: 'Answer',
                  description: '',
                  condition: QuestionAnsweredCondition(questionId: 'q1'),
                ),
              ],
              questions: [
                ExperimentQuestion(
                  id: 'q1',
                  question: 'What changes?',
                  type: ExperimentQuestionType.multipleChoice,
                  options: ['A', 'B'],
                  correctAnswer: 'A',
                ),
              ],
            ),
          );

    final correct = engine.answerQuestion('q1', 'A');

    expect(correct, isTrue);
    expect(engine.state.missionCompleted, isTrue);
    expect(engine.analytics.questionsCorrect, 1);
  });
}

RuntimeWorld _world() {
  final world = RuntimeWorld();
  world.initialize(
    variablesJson: const [
      {'id': 'var_length', 'name': 'Length', 'value': 1},
    ],
    objectsJson: const [],
    rulesJson: const [],
    runtimeProfile: RuntimeProfile.general,
    curriculumMetadata: const {'title': 'Test'},
  );
  return world;
}

RuntimeEvent _event(String message, Map<String, dynamic> metadata) {
  return RuntimeEvent(
    id: '${message}_test',
    timestamp: DateTime.now(),
    type: RuntimeEventType.custom,
    message: message,
    metadata: metadata,
  );
}
