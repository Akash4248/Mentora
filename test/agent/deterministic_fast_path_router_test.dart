import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/deterministic_fast_path_router.dart';
import 'package:mentora/features/chat/domain/router_decision.dart';

void main() {
  group('DeterministicFastPathRouter', () {
    const router = DeterministicFastPathRouter();

    test('routes calculation requests with math.calculate capability', () {
      final queries = [
        'Calculate 15 * 4 + 10',
        'Compute 100 / 10',
        'Evaluate sqrt(144) / 3',
        'What is 45 + 32?',
        'Solve the numerical for force when mass is 5kg and acceleration is 2m/s',
        'Distance is 150m, time is 5s, find speed',
      ];

      for (final query in queries) {
        final decision = router.route(question: query, topic: 'Physics', grade: 9);
        expect(
          decision.route,
          TutorRoute.calculation,
          reason: 'Failed for query: "$query"',
        );
        expect(
          decision.selectedCapabilityIds,
          contains('math.calculate'),
          reason: 'Failed capability for: "$query"',
        );
        expect(decision.confidence, greaterThanOrEqualTo(0.9));
      }
    });

    test('distinguishes formula definitions from calculations (no false positives)', () {
      final nonCalcQueries = [
        'What is the formula of acceleration?',
        'State the formula for kinetic energy',
        'Give the formula relating distance, velocity, and time',
        'Define formula in physics',
      ];

      for (final query in nonCalcQueries) {
        final decision = router.route(question: query, topic: 'Physics', grade: 9);
        expect(
          decision.route,
          isNot(TutorRoute.calculation),
          reason: 'Mistakenly routed as calculation: "$query"',
        );
        expect(
          decision.selectedCapabilityIds,
          isEmpty,
          reason: 'Exposed unnecessary calculation tool for: "$query"',
        );
      }
    });

    test('routes derivation inquiries without tools', () {
      final derivationQueries = [
        'Derive the first equation of motion',
        'Show the derivation of v = u + at',
        'Prove that s = ut + 1/2 at^2',
        'Step-by-step derivation of kinetic energy formula',
      ];

      for (final query in derivationQueries) {
        final decision = router.route(question: query, topic: 'Motion', grade: 9);
        expect(
          decision.route,
          TutorRoute.derivation,
          reason: 'Failed for derivation query: "$query"',
        );
        expect(decision.selectedCapabilityIds, isEmpty);
        expect(decision.confidence, greaterThanOrEqualTo(0.85));
      }
    });

    test('routes simulation lookup inquiries with simulation.lookup capability', () {
      final simQueries = [
        'Show me a simulation for motion',
        'Interactive simulation of simple pendulum',
        'Open simulation for gravity and free fall',
        'Find simulation on force and friction',
        'Is there an interactive lab for pendulum?',
      ];

      for (final query in simQueries) {
        final decision = router.route(question: query, topic: 'Motion', grade: 9);
        expect(
          decision.route,
          TutorRoute.simulationLookup,
          reason: 'Failed for sim query: "$query"',
        );
        expect(
          decision.selectedCapabilityIds,
          contains('simulation.lookup'),
          reason: 'Failed capability for: "$query"',
        );
      }
    });

    test('does not misroute semantic definitions of simulation', () {
      final decision = router.route(
        question: 'What does simulation mean in science?',
        topic: 'Science',
        grade: 9,
      );
      expect(decision.route, isNot(TutorRoute.simulationLookup));
      expect(decision.selectedCapabilityIds, isEmpty);
    });

    test('routes phone sensor lab inquiries without tools', () {
      final labQueries = [
        'Can I test gravity using my phone sensor?',
        'Start accelerometer experiment with phone',
        'Measure with phone gyroscope',
        'How to do phone toss experiment?',
      ];

      for (final query in labQueries) {
        final decision = router.route(question: query, topic: 'Motion', grade: 9);
        expect(
          decision.route,
          TutorRoute.labRoute,
          reason: 'Failed for lab query: "$query"',
        );
        expect(decision.selectedCapabilityIds, isEmpty);
      }
    });

    test('routes conceptual inquiries with zero tool schemas', () {
      final conceptualQueries = [
        'What is inertia?',
        'Define uniform motion',
        'Explain why an apple falls from a tree',
        'Why does a moving bicycle stop when pedaling stops?',
        'Difference between speed and velocity',
        'State Newton\'s third law of motion',
      ];

      for (final query in conceptualQueries) {
        final decision = router.route(question: query, topic: 'Motion', grade: 9);
        expect(
          decision.route,
          TutorRoute.conceptualExplanation,
          reason: 'Failed for conceptual query: "$query"',
        );
        expect(
          decision.selectedCapabilityIds,
          isEmpty,
          reason: 'Must NOT expose tools for pure conceptual question: "$query"',
        );
      }
    });

    test('falls back gracefully to generalFactual on ambiguous query', () {
      final decision = router.route(
        question: 'Can you help me understand today\'s lesson?',
        topic: 'Science',
        grade: 9,
      );
      expect(decision.route, TutorRoute.generalFactual);
      expect(decision.confidence, 0.50);
      expect(decision.selectedCapabilityIds, isEmpty);
    });

    test('routes inquiries about supported tools to all capabilities', () {
      final toolQueries = [
        'what tools do u support?',
        'what tools do you support?',
        'list your tools',
        'what capabilities do you have?',
      ];

      for (final query in toolQueries) {
        final decision = router.route(question: query, topic: 'Science', grade: 9);
        expect(decision.route, TutorRoute.generalFactual);
        expect(decision.selectedCapabilityIds, contains('math.calculate'));
        expect(decision.selectedCapabilityIds, contains('simulation.lookup'));
        expect(decision.selectedCapabilityIds, contains('lab.propose'));
        expect(decision.selectedCapabilityIds, contains('visual.render'));
      }
    });

    test('routes visualization inquiries with visual.render capability', () {
      final visualQueries = [
        'show me how kirchoff\'s law works',
        'visualize projectile motion',
        'draw circuit for resistors in series',
        'show ray diagram for concave mirror',
        'visualize a simple circuit',
        'give me the visuals for bionomial',
        'provide a visual for ray optics',
        'give the visuals for series resistors',
      ];

      for (final query in visualQueries) {
        final decision = router.route(question: query, topic: 'Physics', grade: 9);
        expect(decision.route, TutorRoute.visualization, reason: 'Failed for: $query');
        expect(decision.selectedCapabilityIds, contains('visual.render'));
      }
    });
  });
}
