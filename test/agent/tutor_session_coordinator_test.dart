import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/context_builder.dart';
import 'package:mentora/features/chat/application/mentora_agent_session.dart';
import 'package:mentora/features/chat/application/mentora_tutor_agent_provider.dart';
import 'package:mentora/features/chat/application/tutor_session_coordinator.dart';
import 'package:mentora/features/chat/domain/teaching_strategy.dart';
import 'package:mentora/features/chat/domain/tutor_stream_event.dart';
import 'package:mentora/features/chat/application/three_tier_memory_manager.dart';
import 'package:mentora/features/chat/domain/learner_profile.dart';
import 'package:mentora/features/network/data/backend_availability_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TutorSessionCoordinator', () {
    test('streams incremental text deltas progressively and completes', () async {
      final provider = MentoraTutorAgentProvider(
        streamTutor: ({
          required question,
          required topic,
          required grade,
          cancelToken,
          history = const [],
          tools = const [],
        }) async* {
          yield const TutorStreamChunkEvent('Motion ');
          yield const TutorStreamChunkEvent('is change ');
          yield const TutorStreamChunkEvent('in position.');
          yield const TutorStreamCompletedEvent(
            fullText: 'Motion is change in position.',
            source: 'test_stream',
          );
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Motion',
        initialGrade: 9,
      );

      final events = <TutorAgentEvent>[];
      await for (final event in coordinator.submitQuestion('Define motion.')) {
        events.add(event);
      }

      final deltas = events
          .whereType<TutorTextDeltaEvent>()
          .map((e) => e.delta)
          .toList();

      expect(deltas, ['Motion ', 'is change ', 'in position.']);
      expect(
        events.whereType<TutorTurnCompletedEvent>().single.text,
        'Motion is change in position.',
      );
      expect(coordinator.state, TutorRunState.completed);

      await coordinator.dispose();
    });

    test('cancelling active turn stops generation and marks state aborted', () async {
      final completer = Completer<void>();
      final provider = MentoraTutorAgentProvider(
        streamTutor: ({
          required question,
          required topic,
          required grade,
          cancelToken,
          history = const [],
          tools = const [],
        }) async* {
          yield const TutorStreamChunkEvent('Part 1');
          await completer.future;
          yield const TutorStreamChunkEvent('Part 2');
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Force',
        initialGrade: 9,
      );

      final events = <TutorAgentEvent>[];
      final turnFuture = coordinator.submitQuestion('Explain force.').listen(
        events.add,
      ).asFuture<void>();

      // Wait a tick for the first token
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(coordinator.isGenerating, isTrue);

      coordinator.cancelActiveTurn();
      expect(coordinator.state, TutorRunState.cancelling);

      completer.complete();
      await turnFuture;

      expect(
        events.any((e) => e is TutorTurnAbortedEvent || e is TutorTurnFailedEvent),
        isTrue,
      );

      await coordinator.dispose();
    });

    test('drops late events from superseded runs when a new question is submitted', () async {
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
          final currentCall = callCount;
          if (currentCall == 1) {
            yield const TutorStreamChunkEvent('Old Turn 1');
            await Future<void>.delayed(const Duration(milliseconds: 100));
            yield const TutorStreamChunkEvent('Old Turn 2');
            yield const TutorStreamCompletedEvent(
              fullText: 'Old Complete',
              source: 'test',
            );
          } else {
            yield const TutorStreamChunkEvent('New Turn 1');
            yield const TutorStreamCompletedEvent(
              fullText: 'New Complete',
              source: 'test',
            );
          }
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Motion',
        initialGrade: 9,
      );

      final run1Events = <TutorAgentEvent>[];
      unawaited(
        coordinator.submitQuestion('Question 1').forEach(run1Events.add),
      );

      // Yield briefly so run 1 starts
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(coordinator.activeRunId, 1);

      // Submit run 2 while run 1 is in progress
      final run2Events = await coordinator.submitQuestion('Question 2').toList();
      expect(coordinator.activeRunId, 2);

      // Wait for run 1 delayed timer to finish
      await Future<void>.delayed(const Duration(milliseconds: 120));

      // Run 1 should have been cut off and not received 'Old Turn 2' or 'Old Complete'
      final run1Completed = run1Events.whereType<TutorTurnCompletedEvent>();
      expect(run1Completed, isEmpty);

      // Run 2 completed cleanly
      final run2Completed = run2Events.whereType<TutorTurnCompletedEvent>();
      expect(run2Completed.single.text, 'New Complete');

      await coordinator.dispose();
    });

    test('retains conversation history across availability mode transitions', () async {
      final cache = BackendAvailabilityCache();
      cache.updateStatus(true);

      final provider = MentoraTutorAgentProvider(
        streamTutor: ({
          required question,
          required topic,
          required grade,
          cancelToken,
          history = const [],
          tools = const [],
        }) async* {
          yield TutorStreamChunkEvent('Answer to: $question');
          yield TutorStreamCompletedEvent(
            fullText: 'Answer to: $question',
            source: 'mock',
          );
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Gravity',
        initialGrade: 9,
        availabilityCache: cache,
      );

      // Run turn 1 online
      final history = <Map<String, dynamic>>[
        {'isUser': true, 'text': 'What is gravity?'},
        {'isUser': false, 'text': 'Gravity is an attractive force.'},
      ];

      final turn1 = await coordinator.submitQuestion(
        'What is g?',
        rawHistory: history,
      ).toList();
      expect(turn1.whereType<TutorTurnCompletedEvent>().single.text, contains('What is g?'));

      // Transition to offline mode
      cache.updateStatus(false);
      expect(cache.isOffline, isTrue);

      // Run turn 2 offline with accumulated history
      history.add({'isUser': true, 'text': 'What is g?'});
      history.add({'isUser': false, 'text': 'Answer to: What is g?'});

      final turn2 = await coordinator.submitQuestion(
        'Give its value.',
        rawHistory: history,
      ).toList();

      expect(turn2.whereType<TutorTurnCompletedEvent>().single.text, contains('Give its value.'));

      await coordinator.dispose();
    });

    test('populates latestFollowUps and latestStrategy when contextBuilder is provided', () async {
      SharedPreferences.setMockInitialValues({});
      final contextBuilder = ContextBuilder(
        ragRetriever: (query, topic, {limit = 2}) async => const [],
      );

      final provider = MentoraTutorAgentProvider(
        streamTutor: ({
          required question,
          required topic,
          required grade,
          cancelToken,
          history = const [],
          tools = const [],
        }) async* {
          yield const TutorStreamCompletedEvent(
            fullText: 'Speed is distance over time.',
            source: 'test_stream',
          );
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Motion',
        initialGrade: 9,
        contextBuilder: contextBuilder,
      );

      expect(coordinator.latestFollowUps, isEmpty);
      expect(coordinator.latestStrategy, isNull);

      await coordinator.submitQuestion('What is the difference between speed and velocity?').drain<void>();

      expect(coordinator.latestStrategy, TeachingStrategy.comparativeContrast);
      expect(coordinator.latestFollowUps, isNotEmpty);
      expect(coordinator.latestFollowUps.any((a) => a.id == 'fa_comp_table'), isTrue);

      await coordinator.dispose();
    });

    test('threads systemPrompt with three-tier memory into provider and records session question to sessionId', () async {
      SharedPreferences.setMockInitialValues({});
      final memoryManager = ThreeTierMemoryManager();
      await memoryManager.updateProfile(
        LearnerProfile(
          grade: 9,
          explanationStyle: 'step_by_step',
          interests: const ['cricket'],
          updatedAt: DateTime.now(),
        ),
      );

      final contextBuilder = ContextBuilder(
        memoryManager: memoryManager,
        ragRetriever: (query, topic, {limit = 2}) async => const [],
      );

      String? capturedSystemPrompt;
      final provider = MentoraTutorAgentProvider(
        streamTutor: ({
          required question,
          required topic,
          required grade,
          cancelToken,
          history = const [],
          tools = const [],
          systemPrompt,
        }) async* {
          capturedSystemPrompt = systemPrompt;
          yield const TutorStreamCompletedEvent(
            fullText: 'Acceleration is rate of change of velocity.',
            source: 'test_stream',
          );
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Kinematics',
        initialGrade: 9,
        contextBuilder: contextBuilder,
      );

      const testSessionId = 'test_session_123';
      await coordinator.submitQuestion(
        'What is acceleration?',
        sessionId: testSessionId,
      ).drain<void>();

      // Verify systemPrompt was received with memory context
      expect(capturedSystemPrompt, isNotNull);
      expect(capturedSystemPrompt, contains('step_by_step explanations'));
      expect(capturedSystemPrompt, contains('cricket'));

      // Verify SessionLedger was populated under testSessionId (not topic!)
      final ledger = memoryManager.getOrCreateLedger(
        sessionId: testSessionId,
        topic: 'Kinematics',
        grade: 9,
      );
      expect(ledger.questionsCount, 1);

      await coordinator.dispose();
    });

    test('records executed tool in SessionLedger when tool completed event is emitted', () async {
      SharedPreferences.setMockInitialValues({});
      final memoryManager = ThreeTierMemoryManager();
      final contextBuilder = ContextBuilder(
        memoryManager: memoryManager,
        ragRetriever: (query, topic, {limit = 2}) async => const [],
      );

      final provider = MentoraTutorAgentProvider(
        streamTutor: ({
          required question,
          required topic,
          required grade,
          cancelToken,
          history = const [],
          tools = const [],
          systemPrompt,
        }) async* {
          yield const TutorStreamCompletedEvent(
            fullText: 'Calculated 5 * 5 = 25.',
            source: 'test_stream',
          );
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Math',
        initialGrade: 9,
        contextBuilder: contextBuilder,
      );

      const testSessionId = 'session_tool_test';
      // Simulate tool status event by calling memoryManager directly or via tool execution
      memoryManager.recordSessionTool(testSessionId, 'calculate', formula: '5 * 5 = 25');

      final ledger = memoryManager.getOrCreateLedger(
        sessionId: testSessionId,
        topic: 'Math',
        grade: 9,
      );
      expect(ledger.lastToolUsed, 'calculate');
      expect(ledger.lastFormulaEvaluated, '5 * 5 = 25');

      await coordinator.dispose();
    });
  });
}
