import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/context_builder.dart';
import 'package:mentora/features/chat/application/deterministic_fast_path_router.dart';
import 'package:mentora/features/chat/application/learning_accuracy_guard.dart';
import 'package:mentora/features/chat/application/mentora_agent_session.dart';
import 'package:mentora/features/chat/application/mentora_tutor_agent_provider.dart';
import 'package:mentora/features/chat/application/three_tier_memory_manager.dart';
import 'package:mentora/features/chat/application/tutor_session_coordinator.dart';
import 'package:mentora/features/chat/application/unit_validator.dart';
import 'package:mentora/features/chat/application/visual_fallback_policy.dart';
import 'package:mentora/features/chat/application/visual_resolver.dart';
import 'package:mentora/features/chat/application/visual_stream_parser.dart';
import 'package:mentora/features/chat/domain/capability_registry.dart';
import 'package:mentora/features/chat/domain/default_capabilities.dart';
import 'package:mentora/features/chat/domain/grounding_chunk.dart';
import 'package:mentora/features/chat/domain/router_decision.dart';
import 'package:mentora/features/chat/domain/teaching_strategy.dart';
import 'package:mentora/features/chat/domain/tutor_stream_event.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Mentora 2.0 Core End-to-End Regression Suite', () {
    late CapabilityRegistry registry;
    late ThreeTierMemoryManager memoryManager;
    late ContextBuilder contextBuilder;
    const streamParser = VisualStreamParser();
    const visualResolver = VisualResolver();
    const fallbackPolicy = VisualFallbackPolicy();
    const unitValidator = UnitValidator();
    const accuracyGuard = LearningAccuracyGuard(unitValidator: unitValidator);

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      registry = CapabilityRegistry([
        DefaultCapabilities.calculate(),
        DefaultCapabilities.lookupSimulation(),
      ]);
      memoryManager = ThreeTierMemoryManager();
      contextBuilder = ContextBuilder(
        router: const DeterministicFastPathRouter(),
        registry: registry,
        memoryManager: memoryManager,
        ragRetriever: (query, topic, {limit = 2}) async => const [
          GroundingChunk(
            id: 'chunk_laws_motion',
            chapterId: 'chap_laws',
            sourceTitle: 'NCERT Class 9 Physics: Laws of Motion',
            content: 'An object remains in a state of rest or of uniform motion unless acted upon by an external unbalanced force.',
            tokenCount: 28,
          ),
        ],
      );
    });

    test('E2E Flow 1: Factual Definition Inquiry', () async {
      // 1. Build context
      final context = await contextBuilder.build(
        question: 'Define inertia and state its SI unit.',
        topic: 'Laws of Motion',
        grade: 9,
      );

      // Verify routing and pedagogical strategy
      expect(context.decision.route, TutorRoute.conceptualExplanation);
      expect(context.strategy, TeachingStrategy.factualDefinition);
      expect(context.selectedTools, isEmpty); // Zero unnecessary tool schemas
      expect(context.systemPrompt, contains('concise, textbook-accurate definition'));

      // 2. Execute session via provider
      final provider = MentoraTutorAgentProvider(
        streamTutor: ({
          required question,
          required topic,
          required grade,
          cancelToken,
          history = const [],
          tools = const [],
        }) async* {
          yield const TutorStreamChunkEvent('Inertia is the natural tendency of an object ');
          yield const TutorStreamChunkEvent('to resist changes in its state of motion or rest. ');
          yield const TutorStreamChunkEvent('It is quantified by mass, with SI unit kilogram (kg).');
          yield const TutorStreamCompletedEvent(
            fullText: 'Inertia is the natural tendency of an object to resist changes in its state of motion or rest. It is quantified by mass, with SI unit kilogram (kg).',
            source: 'test_provider',
          );
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Laws of Motion',
        initialGrade: 9,
        contextBuilder: contextBuilder,
      );

      final events = await coordinator.submitQuestion('Define inertia and state its SI unit.').toList();
      final completed = events.whereType<TutorTurnCompletedEvent>().single;

      // 3. Parse stream and verify zero leaked visual artifacts
      final parsed = streamParser.parse(completed.text);
      expect(parsed.visualIntents, isEmpty);
      expect(parsed.proseText, completed.text);

      // 4. Verify accuracy guard
      final guard = accuracyGuard.inspect(
        question: 'Define inertia and state its SI unit.',
        responseText: parsed.proseText,
        strategy: context.strategy,
      );
      expect(guard.isApproved, isTrue);

      await coordinator.dispose();
    });

    test('E2E Flow 2: Numerical Calculation Problem with Tool Execution', () async {
      // 1. Build context
      final context = await contextBuilder.build(
        question: 'Calculate 25 * 4 + 15',
        topic: 'Work and Energy',
        grade: 9,
      );

      expect(context.decision.route, TutorRoute.calculation);
      expect(context.strategy, TeachingStrategy.workedProblem);
      expect(context.selectedTools.length, 1);
      expect(context.selectedTools.first.name, 'calculate');

      // 2. Execute tool calling cycle
      var callCount = 0;
      final provider = MentoraTutorAgentProvider(
        streamTutor: ({
          required question,
          required topic,
          required grade,
          cancelToken,
          history = const [],
          tools = const [],
        }) async* {
          callCount++;
          if (callCount == 1) {
            // Model calls tool first
            yield const TutorStreamToolCallEvent(
              id: 'call_calc_1',
              name: 'calculate',
              arguments: {'expression': '25 * 4 + 15'},
            );
          } else {
            // Then outputs final answer after receiving tool execution result
            yield const TutorStreamChunkEvent('The calculated result is 115.');
            yield const TutorStreamCompletedEvent(
              fullText: 'The calculated result is 115.',
              source: 'test_provider',
            );
          }
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Work and Energy',
        initialGrade: 9,
        capabilityRegistry: registry,
        contextBuilder: contextBuilder,
      );

      final events = await coordinator.submitQuestion('Calculate 25 * 4 + 15').toList();
      expect(events.any((e) => e is TutorToolStatusEvent && e.label == 'Calculating formula'), isTrue);
      expect(events.whereType<TutorTurnCompletedEvent>().single.text, contains('115'));

      await coordinator.dispose();
    });

    test('E2E Flow 3: Upward Ball Toss with Visual Trajectory Resolution', () async {
      const question = 'What happens to a ball tossed upwards at 14.7 m/s?';
      final context = await contextBuilder.build(
        question: question,
        topic: 'Motion',
        grade: 9,
      );
      expect(context.budgetReport.fitsBudget, isTrue);

      // Simulated model response with embedded mentora-visual block
      const modelResponse = r'''
When a ball is tossed upwards with an initial velocity of $14.7\text{ m/s}$, gravity decelerates it at $9.8\text{ m/s}^2$.

```mentora-visual
{
  "schema_version": 1,
  "type": "motion.trajectory",
  "scenario": "vertical_toss",
  "inputs": {
    "initial_velocity_mps": 14.7,
    "gravity_mps2": 9.8,
    "mass_kg": 1.0
  },
  "focus": {
    "kind": "apex"
  },
  "title": "Vertical Toss Trajectory"
}
```

At the highest point, its vertical velocity becomes zero before it falls back down.
''';

      // 1. Parse streaming visual block
      final parsed = streamParser.parse(modelResponse);
      expect(parsed.visualIntents.length, 1);
      expect(parsed.visualIntents.first.type, VisualType.motionTrajectory);

      // Verify prose is clean
      expect(parsed.proseText, isNot(contains('```mentora-visual')));
      expect(parsed.proseText, contains('When a ball is tossed upwards'));

      // 2. Resolve payload via KinematicsEngine
      final payload = visualResolver.resolve(parsed.visualIntents.first);
      expect(payload, isA<TrajectoryVisualPayload>());

      final traj = (payload as TrajectoryVisualPayload).trajectory;
      expect(traj.timeToApexSeconds, 1.5);
      expect(traj.peakHeightMeters, 11.025); // Ground truth verified
      expect(traj.totalFlightTimeSeconds, 3.0);
      expect(traj.netForceAtPeakNewtons, 9.8);
    });

    test('E2E Flow 4: PhET Simulation Query with Fallback Matching & Deduplication', () async {
      const question = 'Can you show me the bending light simulation?';

      // Model forgot to emit visual block
      const modelTextWithoutVisual = 'Bending light demonstrates refraction when light passes into a denser medium.';
      final parsed = streamParser.parse(modelTextWithoutVisual);
      expect(parsed.visualIntents, isEmpty);

      // Fallback policy attaches verified simulation card deterministically
      final fallbackIntent = fallbackPolicy.matchDeterministicFallback(
        question: question,
        existingIntents: parsed.visualIntents,
      );

      expect(fallbackIntent, isNotNull);
      expect(fallbackIntent!.type, VisualType.simulationLauncher);
      expect(fallbackIntent.scenario, 'phet-bending-light');

      // Resolve simulation metadata
      final resolved = visualResolver.resolve(fallbackIntent);
      expect(resolved, isA<SimulationVisualPayload>());
      final sim = resolved as SimulationVisualPayload;
      expect(sim.title, 'Bending Light');
      expect(sim.subject, 'Physics');

      // Deduplication check: if intent is now present, fallback matcher returns null
      final twinFallback = fallbackPolicy.matchDeterministicFallback(
        question: question,
        existingIntents: [fallbackIntent],
      );
      expect(twinFallback, isNull);
    });

    test('E2E Flow 5: Ambiguous Query Graceful Recovery', () async {
      final context = await contextBuilder.build(
        question: 'tell me more',
        topic: 'Gravitation',
        grade: 9,
      );

      expect(context.decision.route, TutorRoute.generalFactual);
      expect(context.selectedTools, isEmpty);
      expect(context.budgetReport.fitsBudget, isTrue);
    });
  });
}
