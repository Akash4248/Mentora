import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/blueprints/experience/guided_experiment_engine.dart';
import 'package:mentora/features/experiment/blueprints/registry/built_in_blueprints.dart';

void main() {
  test('observation progress updates completion percent', () {
    final blueprint = BuiltInBlueprints.all().firstWhere(
      (item) => item.id == 'blueprint_pendulum',
    );
    final engine = GuidedExperimentEngine(blueprint: blueprint)..start();
    final before = engine.progress.completionPercent;

    engine.recordObservationRow();

    expect(engine.progress.observationRows, 1);
    expect(engine.progress.completionPercent, greaterThan(before));
  });

  test('answer submitted updates question progress', () {
    final blueprint = BuiltInBlueprints.all().firstWhere(
      (item) => item.id == 'blueprint_plant_growth',
    );
    final engine = GuidedExperimentEngine(blueprint: blueprint)..start();

    engine.submitAnswer(blueprint.questions.first.id, 'Water');

    expect(engine.questions.isAnswered(blueprint.questions.first.id), true);
    expect(
      engine.progress.answeredQuestions,
      contains(blueprint.questions.first.id),
    );
  });

  test(
    'all objectives, questions, observations, and steps complete blueprint',
    () {
      final blueprint = BuiltInBlueprints.all().firstWhere(
        (item) => item.id == 'blueprint_heart_rate',
      );
      final engine = GuidedExperimentEngine(blueprint: blueprint)..start();

      for (final objective in blueprint.objectives.where(
        (item) => item.required,
      )) {
        engine.completeObjective(objective.title);
      }
      for (var i = 0; i < blueprint.observationTemplate.requiredRows; i++) {
        engine.recordObservationRow();
      }
      for (final question in blueprint.questions.where(
        (item) => item.required,
      )) {
        engine.submitAnswer(question.id, 'Observed answer');
      }
      for (final step in [
        'read',
        'parameter',
        'observation',
        'question',
        'finish',
      ]) {
        engine.completeStep(step);
      }

      expect(engine.complete, true);
      expect(engine.progress.completionPercent, 100);
    },
  );
}
