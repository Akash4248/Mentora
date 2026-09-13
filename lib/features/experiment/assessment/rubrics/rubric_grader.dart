import '../../investigation/models/experiment_trial.dart';
import '../models/assessment_result.dart';
import 'assessment_rubric.dart';

class RubricGrader {
  double grade({
    required AssessmentRubric rubric,
    required List<ExperimentTrial> trials,
    AssessmentResult? assessmentResult,
  }) {
    final obsTrials = trials.where((t) => t.observations.isNotEmpty).length;
    final observationScore = trials.isEmpty ? 0.0 : (obsTrials / trials.length) * 100.0;
    final trialScore = trials.length >= 2
        ? 100.0
        : trials.isEmpty
            ? 0.0
            : 50.0;
    final questionScore = assessmentResult?.score ?? 0.0;
    final total = observationScore * rubric.normalizedWeight('observation_quality') +
        trialScore * rubric.normalizedWeight('trial_completion') +
        questionScore * rubric.normalizedWeight('question_accuracy');
    return total.clamp(0.0, 100.0);
  }
}
