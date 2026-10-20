import 'dart:async';

import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/mentora_agent_session.dart';
import 'package:mentora/features/chat/application/mentora_tutor_agent_provider.dart';
import 'package:mentora/features/chat/application/tutor_session_coordinator.dart';
import 'package:mentora/features/chat/domain/capability_descriptor.dart';
import 'package:mentora/features/chat/domain/capability_registry.dart';
import 'package:mentora/features/chat/domain/default_capabilities.dart';
import 'package:mentora/features/chat/domain/tutor_stream_event.dart';

void main() {
  group('Tool Execution Cycle & Authorization', () {
    test(
      'executes tool, feeds result to continuation turn, and produces final answer',
      () async {
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
              // Turn 1: Model requests math.calculate
              yield const TutorStreamToolCallEvent(
                id: 'calc_call_1',
                name: 'calculate',
                arguments: {'expression': '100 / 10'},
              );
            } else {
              // Turn 2: Model receives continuation with tool result
              expect(question, contains('[Tool Result (calc_call_1)]:'));
              expect(question, contains('10'));
              yield const TutorStreamChunkEvent('The calculated velocity is ');
              yield const TutorStreamChunkEvent('10 m/s.');
              yield const TutorStreamCompletedEvent(
                fullText: 'The calculated velocity is 10 m/s.',
                source: 'test_model',
              );
            }
          },
        );

        final registry = CapabilityRegistry([DefaultCapabilities.calculate()]);
        final coordinator = TutorSessionCoordinator(
          agentProvider: provider,
          initialTopic: 'Motion',
          initialGrade: 9,
          capabilityRegistry: registry,
        );

        final events = <TutorAgentEvent>[];
        await for (final event in coordinator.submitQuestion(
          'What is the velocity if distance is 100m and time is 10s?',
        )) {
          events.add(event);
        }

        expect(callCount, 2);
        final completed = events.whereType<TutorTurnCompletedEvent>().single;
        expect(completed.text, 'The calculated velocity is 10 m/s.');
        expect(coordinator.state, TutorRunState.completed);

        await coordinator.dispose();
      },
    );

    test('blocks execution when authorization policy denies tool call', () async {
      var callCount = 0;
      var toolExecutions = 0;

      final stateChangingTool = CapabilityDescriptor(
        id: 'notes.delete',
        version: '1.0.0',
        displayName: 'Delete Notes',
        description: 'Deletes notes',
        tier: CapabilityPermissionTier.stateChanging,
        tool: AgentTool(
          name: 'delete_notes',
          description: 'Deletes all notes',
          parameters: const {'type': 'object'},
          execute: (args, ct, onUp) async {
            toolExecutions++;
            return ToolExecutionResult.text('Deleted');
          },
        ),
      );

      final registry = CapabilityRegistry([stateChangingTool]);
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
            yield const TutorStreamToolCallEvent(
              id: 'call_delete',
              name: 'delete_notes',
              arguments: {},
            );
          } else {
            // Turn 2: Model receives denial result
            expect(question, contains('not approved'));
            yield const TutorStreamChunkEvent('Action blocked: not approved.');
            yield const TutorStreamCompletedEvent(
              fullText: 'Action blocked: not approved.',
              source: 'test_model',
            );
          }
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Notes',
        initialGrade: 9,
        capabilityRegistry: registry,
        // Default registry authorization denies stateChanging tools
      );

      final events = <TutorAgentEvent>[];
      await for (final event in coordinator.submitQuestion('Clear my notes.')) {
        events.add(event);
      }

      expect(toolExecutions, 0); // Must NOT execute unauthorized tool
      expect(callCount, 2);
      final completed = events.whereType<TutorTurnCompletedEvent>().single;
      expect(completed.text, contains('Action blocked: not approved.'));
      expect(coordinator.state, TutorRunState.completed);

      await coordinator.dispose();
    });

    test('rejects unknown tool calls safely without crash', () async {
      var callCount = 0;
      final registry = CapabilityRegistry([DefaultCapabilities.calculate()]);
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
            yield const TutorStreamToolCallEvent(
              id: 'call_unregistered',
              name: 'unregistered_tool',
              arguments: {},
            );
          } else {
            expect(question, contains('unregistered_tool'));
            yield const TutorStreamChunkEvent('Tool unregistered_tool is unavailable.');
            yield const TutorStreamCompletedEvent(
              fullText: 'Tool unregistered_tool is unavailable.',
              source: 'test_model',
            );
          }
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Motion',
        initialGrade: 9,
        capabilityRegistry: registry,
      );

      final events = <TutorAgentEvent>[];
      await for (final event in coordinator.submitQuestion('Do something unknown.')) {
        events.add(event);
      }

      expect(callCount, 2);
      final completed = events.whereType<TutorTurnCompletedEvent>().single;
      expect(completed.text, contains('Tool unregistered_tool is unavailable.'));
      expect(coordinator.state, TutorRunState.completed);

      await coordinator.dispose();
    });

    test('cancels active tool run when user cancels the turn', () async {
      final toolStarted = Completer<void>();
      final toolCancelled = Completer<void>();
      final cancelledFuture = Completer<void>();

      final longRunningTool = CapabilityDescriptor(
        id: 'test.slow',
        version: '1.0.0',
        displayName: 'Slow Tool',
        description: 'Simulates slow work',
        tier: CapabilityPermissionTier.readOnly,
        tool: AgentTool(
          name: 'slow_tool',
          description: 'Runs slowly',
          parameters: const {'type': 'object'},
          execute: (args, cancelToken, onUp) async {
            toolStarted.complete();
            if (cancelToken != null) {
              unawaited(
                cancelToken.onCancel.then((_) {
                  if (!toolCancelled.isCompleted) toolCancelled.complete();
                  if (!cancelledFuture.isCompleted) cancelledFuture.complete();
                }),
              );
            }
            await cancelledFuture.future;
            return ToolExecutionResult.text('Finished slow work');
          },
        ),
      );

      final registry = CapabilityRegistry([longRunningTool]);
      final provider = MentoraTutorAgentProvider(
        streamTutor: ({
          required question,
          required topic,
          required grade,
          cancelToken,
          history = const [],
          tools = const [],
        }) async* {
          yield const TutorStreamToolCallEvent(
            id: 'call_slow',
            name: 'slow_tool',
            arguments: {},
          );
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Motion',
        initialGrade: 9,
        capabilityRegistry: registry,
      );

      final events = <TutorAgentEvent>[];
      final turnFuture = coordinator.submitQuestion('Run slow tool').forEach(events.add);

      await toolStarted.future;
      coordinator.cancelActiveTurn();
      await turnFuture;

      expect(toolCancelled.isCompleted, isTrue);
      expect(
        events.any((e) => e is TutorTurnAbortedEvent || e is TutorTurnFailedEvent),
        isTrue,
      );

      await coordinator.dispose();
    });
  });
}
