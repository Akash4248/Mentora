import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/follow_up_action_generator.dart';
import 'package:mentora/features/chat/application/learning_accuracy_guard.dart';
import 'package:mentora/features/chat/application/teaching_strategy_selector.dart';
import 'package:mentora/features/chat/application/unit_validator.dart';
import 'package:mentora/features/chat/domain/router_decision.dart';
import 'package:mentora/features/chat/domain/solution_step.dart';
import 'package:mentora/features/chat/domain/teaching_strategy.dart';
import 'package:mentora/features/chat/domain/worked_solution_contract.dart';

void main() {
  group('Mentora 2.0 Teaching Quality Evaluation Suite', () {
    const strategySelector = TeachingStrategySelector();
    const actionGenerator = FollowUpActionGenerator();
    const unitValidator = UnitValidator();
    const accuracyGuard = LearningAccuracyGuard(unitValidator: unitValidator);

    group('Scenario 1: Factual Definition Queries', () {
      const question = 'What is the SI unit of force?';

      test('selects factualDefinition strategy and produces accurate directive', () {
        final strategy = strategySelector.selectStrategy(
          question: question,
          topic: 'Forces',
          route: TutorRoute.conceptualExplanation,
        );
        expect(strategy, TeachingStrategy.factualDefinition);

        final directive = strategySelector.instructionForStrategy(strategy);
        expect(directive, contains('concise, textbook-accurate definition'));
        expect(directive, contains('Do not force unnecessary analogies'));
      });

      test('validates simulated model response against accuracy guard', () {
        const response = r'''
The SI unit of force is the **Newton** (symbol: **N**).
One Newton is defined as the force required to accelerate a mass of 1 kilogram at the rate of 1 meter per second squared ($1\text{ N} = 1\text{ kg}\cdot\text{m/s}^2$).
''';
        final guardResult = accuracyGuard.inspect(
          question: question,
          responseText: response,
          strategy: TeachingStrategy.factualDefinition,
        );

        expect(guardResult.isApproved, isTrue);
        expect(guardResult.detectedErrors, isEmpty);
      });

      test('generates follow-up actions targeting analogies, worked problems, and quick quizzes', () {
        final followUps = actionGenerator.generateFollowUps(
          question: question,
          topic: 'Forces',
          strategy: TeachingStrategy.factualDefinition,
        );

        expect(followUps.length, 3);
        expect(followUps.any((a) => a.id == 'fa_fact_analogy'), isTrue);
        expect(followUps.any((a) => a.id == 'fa_fact_worked'), isTrue);
        expect(followUps.any((a) => a.id == 'fa_fact_quiz'), isTrue);
      });
    });

    group('Scenario 2: Worked Numerical Problem Queries', () {
      const question = 'A vehicle starts from rest and accelerates at 2 m/s^2 for 5 seconds. Find its final velocity.';

      test('selects workedProblem strategy with step-by-step directive', () {
        final strategy = strategySelector.selectStrategy(
          question: question,
          topic: 'Motion',
          route: TutorRoute.calculation,
        );
        expect(strategy, TeachingStrategy.workedProblem);

        final directive = strategySelector.instructionForStrategy(strategy);
        expect(directive, contains('1. State Given parameters with SI units'));
        expect(directive, contains('5. State Final Answer clearly with proper SI units.'));
      });

      test('validates structured WorkedSolution contract', () {
        const solution = WorkedSolution(
          problemStatement: question,
          givenParameters: {
            'Initial velocity (u)': '0 m/s',
            'Acceleration (a)': '2 m/s²',
            'Time (t)': '5 s',
          },
          targetVariable: 'Final velocity (v)',
          steps: [
            SolutionStep(
              stepNumber: 1,
              title: 'Identify the applicable kinematic formula',
              formula: 'v = u + at',
              explanation: 'Since acceleration is constant and initial velocity, acceleration, and time are known.',
            ),
            SolutionStep(
              stepNumber: 2,
              title: 'Substitute the given values',
              substitution: 'v = 0 + (2 \\times 5)',
              explanation: 'Substitute u = 0 m/s, a = 2 m/s², and t = 5 s.',
            ),
            SolutionStep(
              stepNumber: 3,
              title: 'Compute final result',
              calculation: 'v = 10',
              explanation: 'Multiplying 2 by 5 yields 10.',
              units: 'm/s',
            ),
          ],
          finalAnswer: '10',
          finalUnits: 'm/s',
        );

        expect(solution.isValid(), isTrue);

        final markdown = solution.toMarkdown();
        expect(markdown, contains('### Step-by-Step Solution'));
        expect(markdown, contains('Initial velocity (u) = `0 m/s`'));
        expect(markdown, contains(r'\text{Formula: } v = u + at'));
        expect(markdown, contains(r'Final velocity (v) = 10\text{ m/s}'));

        // Validate ground truth kinematics calculation
        final computedV = unitValidator.calculateKinematics(
          formula: 'v = u + at',
          parameters: {'u': 0.0, 'a': 2.0, 't': 5.0},
        );
        expect(computedV, 10.0);
      });

      test('accuracy guard flags responses with invalid physical units (hallucination guard)', () {
        // Hallucinated unit: claiming velocity = 10 Joules
        const badResponse = 'After substitution, the final velocity is 10 Joules.';
        final guardResult = accuracyGuard.inspect(
          question: question,
          responseText: badResponse,
          strategy: TeachingStrategy.workedProblem,
        );

        expect(guardResult.isApproved, isFalse);
        expect(guardResult.detectedErrors.first, contains('Dimensional mismatch'));
      });
    });

    group('Scenario 3: Stepwise Derivation Queries', () {
      const question = 'Derive the second equation of motion s = ut + 1/2 at^2';

      test('selects stepwiseDerivation strategy and enforces physical laws per algebraic step', () {
        final strategy = strategySelector.selectStrategy(
          question: question,
          topic: 'Motion',
          route: TutorRoute.derivation,
        );
        expect(strategy, TeachingStrategy.stepwiseDerivation);

        final directive = strategySelector.instructionForStrategy(strategy);
        expect(directive, contains('rigorous, step-by-step mathematical derivation'));
        expect(directive, contains('clearly state the physical law or mathematical definition'));
      });

      test('parses simulated derivation text with structured markdown steps', () {
        const text = r'''
### Step 1: Define average velocity
Average velocity is defined as the arithmetic mean of initial and final velocity under uniform acceleration:
$$v_{avg} = \frac{u + v}{2}$$

### Step 2: Express displacement in terms of average velocity
Displacement is given by:
$$s = v_{avg} \times t = \frac{u + v}{2} \times t$$

### Step 3: Substitute first equation of motion
From $v = u + at$, substitute $v$ into the displacement equation:
$$s = \frac{u + (u + at)}{2} \times t = ut + \frac{1}{2}at^2$$
''';
        final parsed = WorkedSolution.tryParseFromText(
          text: text,
          question: question,
        );

        expect(parsed, isNotNull);
        expect(parsed!.steps.length, 3);
        expect(parsed.steps[0].title, 'Define average velocity');
        expect(parsed.steps[1].title, 'Express displacement in terms of average velocity');
        expect(parsed.steps[2].title, 'Substitute first equation of motion');
      });
    });

    group('Scenario 4: Comparative Contrast Queries', () {
      const question = 'What is the difference between mass and weight?';

      test('selects comparativeContrast strategy and demands scalar vs vector comparison', () {
        final strategy = strategySelector.selectStrategy(
          question: question,
          topic: 'Gravitation',
          route: TutorRoute.conceptualExplanation,
        );
        expect(strategy, TeachingStrategy.comparativeContrast);

        final directive = strategySelector.instructionForStrategy(strategy);
        expect(directive, contains('Scalar vs. Vector nature'));
        expect(directive, contains('SI units'));
        expect(directive, contains('Key Physical Difference'));
      });

      test('generates follow-up actions for deep comparison', () {
        final followUps = actionGenerator.generateFollowUps(
          question: question,
          topic: 'Gravitation',
          strategy: TeachingStrategy.comparativeContrast,
        );

        expect(followUps.length, 2);
        expect(followUps.any((a) => a.id == 'fa_comp_table'), isTrue);
        expect(followUps.any((a) => a.id == 'fa_comp_example'), isTrue);
      });
    });

    group('Scenario 5: Physical Hallucination Guard (Critical Correction Verification)', () {
      test('guarantees that projectile peak calculation is 11.025 m (not 11.25 m) at g=9.8', () {
        // u = 14.7 m/s, g = 9.8 m/s^2, t = 1.5 s
        final peakH = unitValidator.calculateKinematics(
          formula: 's = ut + 0.5at^2',
          parameters: {'u': 14.7, 'a': -9.8, 't': 1.5},
        );
        // Correct peak: 11.025 m
        expect(peakH, closeTo(11.025, 1e-4));
        expect(peakH, isNot(closeTo(11.25, 0.1)));
      });

      test('guarantees net force is m*a, rejecting hardcoded 9.8 N for general mass', () {
        final fFor5kg = unitValidator.calculateKinematics(
          formula: 'F = m * a',
          parameters: {'m': 5.0, 'a': 9.8},
        );
        // Net force for 5 kg must be 49 N, not 9.8 N
        expect(fFor5kg, 49.0);
      });

      test('guard detects dimensional mismatch when power is expressed in Joules', () {
        final report = unitValidator.validate(
          quantity: 'power',
          unit: 'J',
          value: 100.0,
        );
        expect(report.isValid, isFalse);
        expect(report.errorMessage, contains('Dimensional mismatch'));
      });

      test('guard detects physical violation on negative mass or negative time', () {
        final massReport = unitValidator.validate(
          quantity: 'mass',
          unit: 'kg',
          value: -10.0,
        );
        expect(massReport.isValid, isFalse);

        final timeReport = unitValidator.validate(
          quantity: 'time',
          unit: 's',
          value: -5.0,
        );
        expect(timeReport.isValid, isFalse);
      });
    });
  });
}
