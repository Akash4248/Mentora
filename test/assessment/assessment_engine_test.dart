import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/assessment/analytics/assessment_analytics.dart';
import 'package:mentora/features/experiment/assessment/engine/assessment_engine.dart';
import 'package:mentora/features/experiment/assessment/models/assessment_question.dart';
import 'package:mentora/features/experiment/assessment/models/experiment_assessment.dart';

void main() {
  test('Assessment questions calculate score and pass state', () {
    final assessment = ExperimentAssessment(
      id: 'assessment_1',
      title: 'Assessment',
      description: '',
      passingScore: 70,
      questions: const [
        AssessmentQuestion(
          id: 'q1',
          prompt: 'Trend?',
          type: AssessmentQuestionType.multipleChoice,
          options: ['Increasing', 'Decreasing'],
          correctAnswer: 'Increasing',
        ),
        AssessmentQuestion(
          id: 'q2',
          prompt: 'Stable?',
          type: AssessmentQuestionType.trueFalse,
          correctAnswer: 'False',
        ),
      ],
    );

    final analytics = AssessmentAnalytics();
    final result = AssessmentEngine(analytics: analytics).evaluate(
      assessment: assessment,
      answers: const {'q1': 'Increasing', 'q2': 'False'},
    );

    expect(result.score, 100);
    expect(result.passed, isTrue);
    expect(analytics.assessmentsCompleted, 1);
  });
}
