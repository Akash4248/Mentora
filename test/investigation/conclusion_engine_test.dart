import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/investigation/analytics/investigation_analytics.dart';
import 'package:mentora/features/experiment/investigation/conclusions/conclusion_engine.dart';
import 'package:mentora/features/experiment/investigation/models/experiment_trial.dart';

void main() {
  test('ConclusionEngine generates deterministic trend conclusion', () {
    final conclusion = ConclusionEngine(analytics: InvestigationAnalytics())
        .generate(
          trials: [
            _trial(1, {'Length': 1}),
            _trial(2, {'Length': 2}),
            _trial(3, {'Length': 3}),
          ],
        );

    expect(conclusion, contains('Length increased'));
  });
}

ExperimentTrial _trial(int number, Map<String, dynamic> values) {
  return ExperimentTrial(
    trialId: 'trial_$number',
    trialNumber: number,
    startTime: DateTime(2026, 6, 11, 12, number),
    timestamp: DateTime(2026, 6, 11, 12, number),
    parameterValues: values,
    measurements: values,
  );
}
