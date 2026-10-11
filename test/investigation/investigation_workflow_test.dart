import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/investigation/analytics/investigation_analytics.dart';
import 'package:mentora/features/experiment/investigation/comparison/trial_comparator.dart';
import 'package:mentora/features/experiment/investigation/conclusions/conclusion_generator.dart';
import 'package:mentora/features/experiment/investigation/models/experiment_trial.dart';
import 'package:mentora/features/experiment/investigation/predictions/prediction_store.dart';
import 'package:mentora/features/experiment/investigation/trials/experiment_trial_manager.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  test('trial creation starts and saves a trial', () {
    final world = _world();
    final analytics = InvestigationAnalytics();
    final manager = ExperimentTrialManager(world: world, analytics: analytics);

    final started = manager.startTrial();
    final saved = manager.stopTrial();

    expect(started.trialNumber, 1);
    expect(saved, isNotNull);
    expect(manager.trials.length, 1);
    expect(analytics.trialsStarted, 1);
    expect(analytics.trialsCompleted, 1);

    world.dispose();
  });

  test('prediction is stored', () {
    final analytics = InvestigationAnalytics();
    final store = PredictionStore(analytics: analytics);

    final prediction = store.submit(
      prompt: 'What happens if length increases?',
      prediction: 'The period increases.',
    );

    expect(store.predictions.single.id, prediction.id);
    expect(store.hasPrediction, true);
    expect(analytics.predictionsSubmitted, 1);
  });

  test('comparison calculates numeric differences', () {
    final analytics = InvestigationAnalytics();
    final comparison = TrialComparator(analytics: analytics).compare(
      _trial(1, {'Length': 1, 'Period': 2}),
      _trial(2, {'Length': 2, 'Period': 3}),
    );

    expect(comparison.differences['Length'], 1);
    expect(comparison.differences['Period'], 1);
    expect(comparison.summary, contains('increased'));
    expect(analytics.comparisonsGenerated, 1);
  });

  test('conclusion is generated from trials', () {
    final analytics = InvestigationAnalytics();
    final conclusion = ConclusionGenerator(analytics: analytics).generate([
      _trial(1, {'Length': 1, 'Period': 2}),
      _trial(2, {'Length': 2, 'Period': 3}),
    ]);

    expect(conclusion, contains('increased'));
    expect(analytics.conclusionsGenerated, 1);
  });
}

dynamic _world() {
  return RuntimeLoader.loadFromManifest({
    'metadata': {'title': 'Investigation Test'},
    'scene': {
      'sceneId': 'investigation_test',
      'name': 'Investigation Test',
      'variables': [
        {'id': 'var_length', 'name': 'Length', 'type': 'number', 'value': 1},
      ],
      'objects': const [],
      'rules': const [],
    },
  });
}

ExperimentTrial _trial(int number, Map<String, dynamic> measurements) {
  return ExperimentTrial(
    trialId: 'trial_$number',
    trialNumber: number,
    startTime: DateTime(2026, 6, 11, 12, number),
    parameterValues: measurements,
    measurements: measurements,
    timestamp: DateTime(2026, 6, 11, 12, number),
  );
}
