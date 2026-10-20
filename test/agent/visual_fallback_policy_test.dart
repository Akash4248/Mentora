import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/visual_fallback_policy.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';

void main() {
  group('VisualFallbackPolicy', () {
    const policy = VisualFallbackPolicy();

    test('deterministically matches PhET simulation queries when model omitted block', () {
      final cases = [
        ('Show me bending light simulation', 'phet-bending-light'),
        ('I want to see forces and motion interactive lab', 'phet-forces-motion'),
        ('Can we practice balancing chemical equations?', 'phet-balancing-chemical-equations'),
        ('Help me build an atom', 'phet-build-an-atom'),
        ('Open fraction matcher game', 'phet-fraction-matcher'),
      ];

      for (final (query, expectedId) in cases) {
        final fallback = policy.matchDeterministicFallback(
          question: query,
          existingIntents: const [],
        );

        expect(fallback, isNotNull, reason: 'Failed to match: $query');
        expect(fallback!.type, VisualType.simulationLauncher);
        expect(fallback.scenario, expectedId);
        expect(fallback.inputs['simulation_id'], expectedId);
      }
    });

    test('deterministically matches upward ball toss query to motion.trajectory', () {
      final fallback = policy.matchDeterministicFallback(
        question: 'What is the trajectory of a ball thrown upward?',
        existingIntents: const [],
      );

      expect(fallback, isNotNull);
      expect(fallback!.type, VisualType.motionTrajectory);
      expect(fallback.scenario, 'vertical_toss');
      expect(fallback.inputs['initial_velocity_mps'], 14.7);
      expect(fallback.focus?['kind'], 'apex');
    });

    test('deduplicates: returns null if an intent is already declared by the model', () {
      const existing = VisualIntent(
        schemaVersion: 1,
        type: VisualType.simulationLauncher,
        scenario: 'phet-bending-light',
        inputs: {'simulation_id': 'phet-bending-light'},
      );

      final fallback = policy.matchDeterministicFallback(
        question: 'Show me bending light simulation',
        existingIntents: [existing],
      );

      expect(fallback, isNull);
    });

    test('returns null for general conceptual questions without visual cue', () {
      final fallback = policy.matchDeterministicFallback(
        question: 'What is Newton’s third law of motion?',
        existingIntents: const [],
      );

      expect(fallback, isNull);
    });
  });
}
