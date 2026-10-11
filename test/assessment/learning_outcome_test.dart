import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/assessment/analytics/assessment_analytics.dart';
import 'package:mentora/features/experiment/assessment/engine/learning_outcome_evaluator.dart';
import 'package:mentora/features/experiment/assessment/models/assessment_result.dart';
import 'package:mentora/features/experiment/assessment/models/learning_outcome.dart';
import 'package:mentora/features/experiment/assessment/models/learning_outcome_result.dart';

void main() {
  test('Score 80 percent produces achieved outcome', () {
    final analytics = AssessmentAnalytics();
    final outcomes = LearningOutcomeEvaluator(analytics: analytics).evaluate(
      outcomes: const [
        LearningOutcome(
          id: 'outcome_1',
          description: 'Understands trend',
          skill: 'analysis',
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
      missionCompleted: true,
      completedTrials: 2,
    );

    expect(outcomes.single.status, LearningOutcomeStatus.achieved);
    expect(analytics.outcomesAchieved, 1);
  });
}
