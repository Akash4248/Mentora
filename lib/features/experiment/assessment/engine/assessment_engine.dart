import '../analytics/assessment_analytics.dart';
import '../models/assessment_result.dart';
import '../models/experiment_assessment.dart';

class AssessmentEngine {
  final AssessmentAnalytics analytics;

  const AssessmentEngine({required this.analytics});

  AssessmentResult evaluate({
    required ExperimentAssessment assessment,
    required Map<String, String> answers,
  }) {
    analytics.assessmentsStarted++;
    final correctness = <String, bool>{};
    var earned = 0.0;
    var possible = 0.0;
    for (final question in assessment.questions) {
      final answer = answers[question.id] ?? '';
      if (!question.isAutoGradable()) {
        correctness[question.id] = false;
        continue;
      }
      possible += question.points;
      final correct = question.isCorrect(answer);
      correctness[question.id] = correct;
      if (correct) earned += question.points;
    }
    final score = possible <= 0 ? 0.0 : (earned / possible) * 100;
    final passed = score >= assessment.passingScore;
    analytics.recordAssessmentScore(score);
    return AssessmentResult(
      assessmentId: assessment.id,
      answers: Map.unmodifiable(answers),
      correctness: correctness,
      score: score,
      passingScore: assessment.passingScore,
      passed: passed,
      feedback: passed
          ? 'Assessment passed.'
          : 'Review the experiment evidence and try again.',
      evaluatedAt: DateTime.now(),
    );
  }
}
