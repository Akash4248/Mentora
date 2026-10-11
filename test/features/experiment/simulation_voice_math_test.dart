import 'package:flutter_test/flutter_test.dart';

import 'package:mentora/features/experiment/assessment/analytics/assessment_analytics.dart';
import 'package:mentora/features/experiment/assessment/engine/assessment_engine.dart';
import 'package:mentora/features/experiment/assessment/models/assessment_question.dart';
import 'package:mentora/features/experiment/assessment/models/assessment_result.dart';
import 'package:mentora/features/experiment/assessment/models/experiment_assessment.dart';
import 'package:mentora/features/experiment/assessment/rubrics/assessment_rubric.dart';
import 'package:mentora/features/experiment/assessment/rubrics/rubric_grader.dart';
import 'package:mentora/features/experiment/investigation/models/experiment_trial.dart';
import 'package:mentora/features/experiment/presentation/runtime_workspace/runtime_orientation_lock.dart';
import 'package:mentora/features/experiment/runtime/observations/runtime_observation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssessmentEngine Security & Auto-Pass Fixes', () {
    late AssessmentEngine engine;
    late AssessmentAnalytics analytics;

    setUp(() {
      analytics = AssessmentAnalytics();
      engine = AssessmentEngine(analytics: analytics);
    });

    test('Zero possible points returns score 0.0 instead of 100.0 auto-pass', () {
      final assessment = ExperimentAssessment(
        id: 'zero_pt_assessment',
        title: 'Zero Point Test',
        description: 'Test description',
        passingScore: 70.0,
        questions: const [],
      );

      final result = engine.evaluate(
        assessment: assessment,
        answers: {},
      );

      expect(result.score, equals(0.0));
      expect(result.passed, isFalse);
    });

    test('Non-auto-gradable question does NOT receive free credit automatically', () {
      final freeTextQuestion = AssessmentQuestion(
        id: 'q_reflection',
        prompt: 'What did you observe?',
        type: AssessmentQuestionType.observationReflection,
        points: 10,
      );

      final assessment = ExperimentAssessment(
        id: 'reflection_assessment',
        title: 'Reflection Test',
        description: 'Test description',
        passingScore: 70.0,
        questions: [freeTextQuestion],
      );

      final result = engine.evaluate(
        assessment: assessment,
        answers: {'q_reflection': 'I saw a pendulum move.'},
      );

      expect(result.correctness['q_reflection'], isFalse);
      expect(result.score, equals(0.0));
    });
  });

  group('RubricGrader Proportionality & Clamping', () {
    late RubricGrader grader;
    late AssessmentRubric rubric;

    setUp(() {
      grader = RubricGrader();
      rubric = AssessmentRubric.defaultRubric();
    });

    test('Observation score scales proportionally to trials with observations', () {
      final trial1 = ExperimentTrial(
        trialId: '1',
        trialNumber: 1,
        startTime: DateTime.now(),
        timestamp: DateTime.now(),
        observations: [
          RuntimeObservation(
            id: 'obs_1',
            runtimeSeconds: 1.5,
            timestamp: DateTime.now(),
            values: const {'note': 'Measured length'},
            source: 'sensor',
          ),
        ],
      );
      final trial2 = ExperimentTrial(
        trialId: '2',
        trialNumber: 2,
        startTime: DateTime.now(),
        timestamp: DateTime.now(),
        observations: const [],
      );

      final result = grader.grade(
        rubric: rubric,
        trials: [trial1, trial2],
      );

      // 1 out of 2 trials has observations -> observationScore = 50.0
      // 2 trials completed -> trialScore = 100.0
      // questionScore = 0.0
      // Default criteria weights: observation_quality=0.3, trial_completion=0.3, question_accuracy=0.4
      // Expected total = 50*0.3 + 100*0.3 + 0 = 15 + 30 = 45.0
      expect(result, equals(45.0));
    });

    test('Grade output is strictly clamped between 0 and 100', () {
      final trial1 = ExperimentTrial(
        trialId: '1',
        trialNumber: 1,
        startTime: DateTime.now(),
        timestamp: DateTime.now(),
        observations: [
          RuntimeObservation(
            id: 'obs_1',
            runtimeSeconds: 1.0,
            timestamp: DateTime.now(),
            values: const {'a': 'b'},
            source: 'sensor',
          ),
        ],
      );
      final trial2 = ExperimentTrial(
        trialId: '2',
        trialNumber: 2,
        startTime: DateTime.now(),
        timestamp: DateTime.now(),
        observations: [
          RuntimeObservation(
            id: 'obs_2',
            runtimeSeconds: 2.0,
            timestamp: DateTime.now(),
            values: const {'c': 'd'},
            source: 'sensor',
          ),
        ],
      );

      final mockResult = AssessmentResult(
        assessmentId: 'test',
        answers: const {},
        correctness: const {},
        score: 100.0,
        passingScore: 70.0,
        passed: true,
        feedback: 'Good',
        evaluatedAt: DateTime.now(),
      );

      final grade = grader.grade(
        rubric: rubric,
        trials: [trial1, trial2],
        assessmentResult: mockResult,
      );

      expect(grade, equals(100.0));
      expect(grade, greaterThanOrEqualTo(0.0));
      expect(grade, lessThanOrEqualTo(100.0));
    });
  });

  group('RuntimeOrientationLock Reference Counting', () {
    test('Overlapping landscape locks do not restore portrait prematurely', () async {
      await RuntimeOrientationLock.lockLandscape();
      await RuntimeOrientationLock.lockLandscape();

      // First screen disposes and calls restore()
      await RuntimeOrientationLock.restore();

      // Second screen disposes and calls restore()
      await RuntimeOrientationLock.restore();
    });
  });
}
