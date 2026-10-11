import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/assessment/models/assessment_result.dart';
import 'package:mentora/features/experiment/assessment/rubrics/assessment_rubric.dart';
import 'package:mentora/features/experiment/assessment/rubrics/rubric_grader.dart';
import 'package:mentora/features/experiment/investigation/models/experiment_trial.dart';

void main() {
  test('RubricGrader combines trial completion and question accuracy', () {
    final score = RubricGrader().grade(
      rubric: AssessmentRubric.defaultRubric(),
      trials: [
        ExperimentTrial(
          trialId: 'trial_1',
          trialNumber: 1,
          startTime: DateTime(2026, 6, 11),
          timestamp: DateTime(2026, 6, 11),
        ),
        ExperimentTrial(
          trialId: 'trial_2',
          trialNumber: 2,
          startTime: DateTime(2026, 6, 11),
          timestamp: DateTime(2026, 6, 11),
        ),
      ],
      assessmentResult: AssessmentResult(
        assessmentId: 'a1',
        answers: const {},
        correctness: const {},
        score: 80,
        passingScore: 70,
        passed: true,
        feedback: '',
        evaluatedAt: DateTime(2026, 6, 11),
      ),
    );

    expect(score, greaterThan(60));
  });
}
