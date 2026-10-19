import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/context_builder.dart';
import 'package:mentora/features/chat/application/deterministic_fast_path_router.dart';
import 'package:mentora/features/chat/application/three_tier_memory_manager.dart';
import 'package:mentora/features/chat/domain/capability_registry.dart';
import 'package:mentora/features/chat/domain/default_capabilities.dart';
import 'package:mentora/features/chat/domain/grounding_chunk.dart';
import 'package:mentora/features/chat/domain/router_decision.dart';
import 'package:mentora/features/chat/domain/teaching_strategy.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ContextBuilder', () {
    late CapabilityRegistry registry;
    late ThreeTierMemoryManager memoryManager;
    late ContextBuilder builder;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      registry = CapabilityRegistry([
        DefaultCapabilities.calculate(),
        DefaultCapabilities.lookupSimulation(),
      ]);
      memoryManager = ThreeTierMemoryManager();

      builder = ContextBuilder(
        router: const DeterministicFastPathRouter(),
        registry: registry,
        memoryManager: memoryManager,
        ragRetriever: (query, topic, {limit = 2}) async {
          return const [
            GroundingChunk(
              id: 'chunk_ncert_motion_1',
              chapterId: 'chap_motion',
              sourceTitle: 'NCERT Class 9 Physics: Motion',
              content: 'Inertia is the natural tendency of an object to resist a change in its state of rest or of uniform motion.',
              tokenCount: 25,
            ),
          ];
        },
      );
    });

    test('conceptual query yields 0 tools, grounds in textbook, and fits context budget', () async {
      final context = await builder.build(
        question: 'What is inertia?',
        topic: 'Motion',
        grade: 9,
      );

      // Route must be conceptual explanation
      expect(context.decision.route, TutorRoute.conceptualExplanation);

      // Zero unnecessary tools must be exposed to avoid context bloat
      expect(context.selectedTools, isEmpty);

      // Textbook grounding must be present with attribution
      expect(context.groundingChunks.length, 1);
      expect(
        context.systemPrompt,
        contains('Source: NCERT Class 9 Physics: Motion (Chapter: chap_motion)'),
      );
      expect(
        context.systemPrompt,
        contains('Inertia is the natural tendency of an object'),
      );

      // Teaching strategy and pedagogical directive
      expect(context.strategy, TeachingStrategy.conceptualIntuition);
      expect(context.followUpActions, isNotEmpty);
      expect(context.systemPrompt, contains('Pedagogical Directive: Explain the core principle clearly'));

      // Context budget accounting
      expect(context.budgetReport.fitsBudget, isTrue);
      expect(context.budgetReport.estimatedInputTokens, greaterThan(0));
      expect(context.budgetReport.estimatedInputTokens, lessThan(1000));
      expect(context.budgetReport.reservedOutputTokens, 1024);
      expect(context.budgetReport.availableHeadroom, greaterThan(0));
    });

    test('numerical calculation query selects only calculate tool within budget', () async {
      final context = await builder.build(
        question: 'Calculate 15 * 4 + 10',
        topic: 'Motion',
        grade: 9,
      );

      expect(context.decision.route, TutorRoute.calculation);
      expect(context.strategy, TeachingStrategy.workedProblem);
      expect(context.followUpActions, isNotEmpty);
      expect(context.systemPrompt, contains('Pedagogical Directive: Structure the solution into clear steps'));
      expect(context.selectedTools.length, 1);
      expect(context.selectedTools.first.name, 'calculate');

      expect(context.budgetReport.toolSchemaTokens, greaterThan(0));
      expect(context.budgetReport.fitsBudget, isTrue);
    });

    test('bounds dialogue history strictly to last 2 turns, capped at 300 chars each', () async {
      final longText = 'A' * 500;
      final rawHistory = [
        'Turn 1: Old question',
        'Turn 2: Old answer',
        'Turn 3: Medium question',
        'Turn 4: $longText',
      ];

      final context = await builder.build(
        question: 'Explain inertia',
        topic: 'Motion',
        grade: 9,
        rawHistory: rawHistory,
      );

      expect(context.recentTurns.length, 2);
      expect(context.recentTurns.first, 'Turn 3: Medium question');
      expect(context.recentTurns.last.length, lessThanOrEqualTo(302)); // 300 chars + ellipsis
      expect(context.recentTurns.last, endsWith('…'));
      expect(context.systemPrompt, isNot(contains('Turn 1: Old question')));
    });

    test('omits irrelevant memory and incorporates user profile preferences', () async {
      final profile = await memoryManager.getProfile();
      await memoryManager.updateProfile(
        profile.copyWith(
          explanationStyle: 'step_by_step',
          interests: ['space'],
        ),
      );

      final context = await builder.build(
        question: 'What is acceleration?',
        topic: 'Motion',
        grade: 9,
        sessionId: 'sess_123',
      );

      expect(context.systemPrompt, contains('step_by_step'));
      expect(context.systemPrompt, contains('space'));
    });
  });
}
