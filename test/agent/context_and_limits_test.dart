import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/context_builder.dart';
import 'package:mentora/features/chat/application/mentora_agent_session.dart';
import 'package:mentora/features/chat/application/mentora_tutor_agent_provider.dart';
import 'package:mentora/features/chat/application/tutor_session_coordinator.dart';
import 'package:mentora/features/chat/domain/tutor_stream_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Context and Tool Limits Suite', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('enforces max tool-call limit per turn without executing runaway tool cycles', () async {
      var toolExecutions = 0;
      final fastTool = AgentTool(
        name: 'fast_tool',
        description: 'Test fast tool',
        parameters: const {'type': 'object'},
        execute: (arguments, cancelToken, onUpdate) async {
          toolExecutions++;
          return ToolExecutionResult.text('Result $toolExecutions');
        },
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
          // Model attempts to call tool infinitely
          yield const TutorStreamToolCallEvent(
            id: 'infinite_call',
            name: 'fast_tool',
            arguments: {},
          );
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Limits',
        initialGrade: 9,
        tools: [fastTool],
        authorizeToolCall: (name, args) => true,
      );

      final events = await coordinator.submitQuestion('Run tool').toList();

      // In MentoraAgentSession, maxToolCalls is bounded to 4
      expect(toolExecutions, lessThanOrEqualTo(4));
      expect(
        events.any((e) => e is TutorTurnFailedEvent || e is TutorTurnCompletedEvent || e is TutorTurnAbortedEvent),
        isTrue,
      );

      await coordinator.dispose();
    });

    test('cancels agent execution when tool exceeds its allowed time budget', () async {
      final hangingTool = AgentTool(
        name: 'hanging_tool',
        description: 'A tool that hangs',
        parameters: const {'type': 'object'},
        execute: (arguments, cancelToken, onUpdate) async {
          // Hangs for 5 seconds
          await Future<void>.delayed(const Duration(seconds: 5));
          return ToolExecutionResult.text('Done');
        },
      );

      const model = Model(
        id: 'test-model',
        name: 'Test model',
        api: 'test',
        provider: 'test',
        baseUrl: 'https://test.invalid',
        contextWindow: 2048,
        maxTokens: 512,
      );

      // Session with a tight tool timeout of 50ms
      final session = MentoraAgentSession(
        model: model,
        tools: [hangingTool],
        authorizeToolCall: (name, args) => true,
        maxToolDuration: const Duration(milliseconds: 50),
        streamFunction: (model, context, {cancelToken}) {
          if (context.messages.whereType<ToolResultMessage>().isEmpty) {
            final message = AssistantMessage(
              content: const [
                ToolCall(
                  id: 'call_hang',
                  name: 'hanging_tool',
                  arguments: {},
                ),
              ],
              api: model.api,
              provider: model.provider,
              model: model.id,
              usage: Usage.zero,
              stopReason: StopReason.toolUse,
              timestamp: DateTime.utc(2026),
            );
            return AssistantMessageEventStream()
              ..push(DoneEvent(reason: StopReason.toolUse, message: message));
          }
          final message = AssistantMessage(
            content: const [TextContent(text: 'Done')],
            api: model.api,
            provider: model.provider,
            model: model.id,
            usage: Usage.zero,
            stopReason: StopReason.stop,
            timestamp: DateTime.utc(2026),
          );
          return AssistantMessageEventStream()
            ..push(DoneEvent(reason: StopReason.stop, message: message));
        },
      );

      final events = await session.runTurn('Run hanging tool').toList();
      expect(events.any((e) => e is TutorTurnAbortedEvent || e is TutorTurnFailedEvent), isTrue);

      await session.dispose();
    });

    test('verifies context budget bounds, history clipping, and token accounting', () async {
      final builder = ContextBuilder(
        maxContextLimit: 2048,
        reservedOutputTokens: 1024,
        ragRetriever: (q, t, {limit = 2}) async => const [],
      );

      final longTurns = List.generate(10, (i) => 'Turn $i: ${"x" * 500}');

      final context = await builder.build(
        question: 'What is mass?',
        topic: 'Physics',
        grade: 9,
        rawHistory: longTurns,
      );

      // Must strictly keep only the last 2 turns
      expect(context.recentTurns.length, 2);
      // Each turn capped at <= 300 chars + ellipsis
      for (final t in context.recentTurns) {
        expect(t.length, lessThanOrEqualTo(302));
      }

      // Context token accounting
      final budget = context.budgetReport;
      expect(budget.fitsBudget, isTrue);
      expect(budget.maxContextLimit, 2048);
      expect(budget.reservedOutputTokens, 1024);
      expect(budget.availableHeadroom, greaterThan(0));
      expect(budget.estimatedInputTokens + budget.reservedOutputTokens, lessThanOrEqualTo(2048));
    });
  });
}
