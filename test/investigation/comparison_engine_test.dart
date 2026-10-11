import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/investigation/analytics/investigation_analytics.dart';
import 'package:mentora/features/experiment/investigation/comparison/trial_comparison_engine.dart';
import 'package:mentora/features/experiment/investigation/models/experiment_trial.dart';

void main() {
  test('TrialComparisonEngine detects row differences', () {
    final engine = TrialComparisonEngine(analytics: InvestigationAnalytics());

    final comparison = engine.compare(
      _trial(1, {'Length': 1, 'Period': 2}),
      _trial(2, {'Length': 2, 'Period': 3}),
    );

    expect(comparison.results.length, 2);
    expect(comparison.results.first.difference, 1);
    expect(comparison.summary, contains('increased'));
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
