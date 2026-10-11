import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/investigation/analytics/investigation_analytics.dart';
import 'package:mentora/features/experiment/investigation/trials/experiment_trial_manager.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  test('Start Trial then Save Trial stores a completed trial', () {
    final world = RuntimeLoader.loadFromManifest({
      'metadata': {'title': 'Trial Test'},
      'scene': {
        'sceneId': 'trial_test',
        'name': 'Trial Test',
        'variables': [
          {'id': 'var_length', 'name': 'Length', 'type': 'number', 'value': 2},
        ],
        'objects': const [],
        'rules': const [],
      },
    });
    final analytics = InvestigationAnalytics();
    final manager = ExperimentTrialManager(world: world, analytics: analytics);

    final started = manager.startTrial();
    final saved = manager.stopTrial();

    expect(started.trialNumber, 1);
    expect(saved, isNotNull);
    expect(manager.trials.single.snapshot?.variables['var_length'], 2);
    expect(manager.completedTrialCount, 1);
    expect(analytics.trialsStarted, 1);
    expect(analytics.trialsCompleted, 1);

    world.dispose();
  });
}
