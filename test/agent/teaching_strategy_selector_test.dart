import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/follow_up_action_generator.dart';
import 'package:mentora/features/chat/application/teaching_strategy_selector.dart';
import 'package:mentora/features/chat/domain/router_decision.dart';
import 'package:mentora/features/chat/domain/teaching_strategy.dart';

void main() {
  group('TeachingStrategySelector', () {
    const selector = TeachingStrategySelector();

    test('selects comparativeContrast for comparison cues', () {
      final queries = [
        'What is the difference between speed and velocity?',
        'Compare and contrast mass and weight',
        'Distinguish between distance and displacement',
        'Speed vs velocity in physics',
      ];

      for (final q in queries) {
        final strategy = selector.selectStrategy(
          question: q,
          topic: 'Motion',
          route: TutorRoute.conceptualExplanation,
        );
        expect(strategy, TeachingStrategy.comparativeContrast, reason: 'Failed for: $q');
      }
    });

    test('selects stepwiseDerivation for derivation cues and routes', () {
      final queries = [
        'Derive the second equation of motion s = ut + 1/2 at^2',
        'Prove that kinetic energy is 1/2 m v^2',
        'Show the derivation of v = u + at',
      ];

      for (final q in queries) {
        final strategy = selector.selectStrategy(
          question: q,
          topic: 'Motion',
          route: TutorRoute.derivation,
        );
        expect(strategy, TeachingStrategy.stepwiseDerivation, reason: 'Failed for: $q');
      }
    });

    test('selects workedProblem for numerical queries with numbers and units', () {
      final queries = [
        'A car accelerates from 0 to 20 m/s in 5 s. Calculate the acceleration.',
        'Find the net force acting on a 10 kg block moving at 3 m/s^2',
        'Calculate work done if a force of 50 N moves a box by 4 m',
      ];

      for (final q in queries) {
        final strategy = selector.selectStrategy(
          question: q,
          topic: 'Motion',
          route: TutorRoute.calculation,
        );
        expect(strategy, TeachingStrategy.workedProblem, reason: 'Failed for: $q');
      }
    });

    test('selects factualDefinition for direct definitions and units', () {
      final queries = [
        'Define inertia',
        'What is the definition of momentum?',
        'What is the SI unit of force?',
        'State the formula for pressure',
      ];

      for (final q in queries) {
        final strategy = selector.selectStrategy(
          question: q,
          topic: 'Force and Laws of Motion',
          route: TutorRoute.conceptualExplanation,
        );
        expect(strategy, TeachingStrategy.factualDefinition, reason: 'Failed for: $q');
      }
    });

    test('selects conceptualIntuition for open-ended conceptual inquiries', () {
      final queries = [
        'Why do passengers lean forward when a bus applies brakes?',
        'How does gravity keep planets in orbit?',
        'Explain what happens to friction when surfaces get smoother',
      ];

      for (final q in queries) {
        final strategy = selector.selectStrategy(
          question: q,
          topic: 'Force and Laws of Motion',
          route: TutorRoute.conceptualExplanation,
        );
        expect(strategy, TeachingStrategy.conceptualIntuition, reason: 'Failed for: $q');
      }
    });

    test('emits rich pedagogical directives for each strategy', () {
      for (final s in TeachingStrategy.values) {
        final directive = selector.instructionForStrategy(s);
        expect(directive, isNotEmpty);
        expect(directive, contains('Pedagogical Directive:'));
      }
      expect(
        selector.instructionForStrategy(TeachingStrategy.workedProblem),
        contains('1. State Given parameters with SI units'),
      );
      expect(
        selector.instructionForStrategy(TeachingStrategy.comparativeContrast),
        contains('Scalar vs. Vector nature'),
      );
    });
  });

  group('FollowUpActionGenerator', () {
    const generator = FollowUpActionGenerator();

    test('generates 2-3 tailored follow-up actions for each strategy', () {
      for (final strategy in TeachingStrategy.values) {
        final followUps = generator.generateFollowUps(
          question: 'What is momentum?',
          topic: 'Laws of Motion',
          strategy: strategy,
        );

        expect(followUps.length, inInclusiveRange(2, 3));
        for (final action in followUps) {
          expect(action.id, isNotEmpty);
          expect(action.label, isNotEmpty);
          expect(action.intentQuery, isNotEmpty);
          expect(action.intentQuery, contains('Laws of Motion'));
        }
      }
    });
  });
}
