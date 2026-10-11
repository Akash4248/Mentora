import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/assessment/analytics/assessment_analytics.dart';
import 'package:mentora/features/experiment/assessment/reports/lab_report_builder.dart';
import 'package:mentora/features/experiment/guided_runtime/models/experiment_mission.dart';
import 'package:mentora/features/experiment/investigation/models/experiment_trial.dart';

void main() {
  test('LabReportBuilder includes mission, trials, and conclusion', () {
    final analytics = AssessmentAnalytics();
    final report = LabReportBuilder(analytics: analytics).build(
      title: 'Pendulum Report',
      mission: const ExperimentMission(
        id: 'm1',
        title: 'Pendulum Mission',
        objective: 'Investigate length',
        description: '',
        difficulty: 'Easy',
        estimatedDuration: Duration(minutes: 5),
      ),
      trials: [
        ExperimentTrial(
          trialId: 'trial_1',
          trialNumber: 1,
          startTime: DateTime(2026, 6, 11),
          timestamp: DateTime(2026, 6, 11),
          parameterValues: const {'Length': 1},
        ),
      ],
      conclusion: 'Length increased period.',
    );

    expect(report.mission?.title, 'Pendulum Mission');
    expect(report.trials.length, 1);
    expect(report.conclusion, contains('Length'));
    expect(analytics.reportsGenerated, 1);
  });
}
