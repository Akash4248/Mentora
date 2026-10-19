import 'dart:async';

import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('flutter_agent_harness compatibility', () {
    test(
      'streams a final assistant response through an injected provider',
      () async {
        final agent = Agent(
          model: _model,
          streamFunction: (model, context, {cancelToken}) {
            return _completedResponse(model, const [
              TextContent(text: 'Motion is a change in position.'),
            ]);
          },
          toolExecutor: _unexpectedToolExecutor,
        );

        await agent.prompt('Define motion.');

        expect(
          _assistantText(agent.state.messages),
          'Motion is a change in position.',
        );
        expect(agent.state.errorMessage, isNull);
      },
    );

    test(
      'executes a registered tool and supplies its result to the next turn',
      () async {
        var toolExecutions = 0;
        var nextTurnReceivedToolResult = false;
        final registry = ToolRegistry([
          AgentTool(
            name: 'lookup_definition',
            description: 'Look up an approved curriculum definition.',
            parameters: const {
              'type': 'object',
              'properties': {
                'term': {'type': 'string'},
              },
              'required': ['term'],
              'additionalProperties': false,
            },
            execute: (arguments, cancelToken, onUpdate) async {
              toolExecutions += 1;
              expect(arguments, {'term': 'motion'});
              return ToolExecutionResult.text('Motion is change in position.');
            },
          ),
        ]);

        final agent = Agent(
          model: _model,
          toolRegistry: registry,
          toolExecution: ToolExecutionMode.sequential,
          streamFunction: (model, context, {cancelToken}) {
            final results = context.messages.whereType<ToolResultMessage>();
            if (results.isEmpty) {
              return _completedResponse(model, const [
                ToolCall(
                  id: 'call-1',
                  name: 'lookup_definition',
                  arguments: {'term': 'motion'},
                ),
              ], reason: StopReason.toolUse);
            }

            nextTurnReceivedToolResult = results.any(
              (result) =>
                  result.toolCallId == 'call-1' &&
                  result.content.whereType<TextContent>().any(
                    (content) =>
                        content.text == 'Motion is change in position.',
                  ),
            );
            return _completedResponse(model, const [
              TextContent(
                text: 'Motion is change in position. [Source: curriculum]',
              ),
            ]);
          },
        );

        await agent.prompt('Define motion.');

        expect(toolExecutions, 1);
        expect(nextTurnReceivedToolResult, isTrue);
        expect(
          _assistantText(agent.state.messages),
          'Motion is change in position. [Source: curriculum]',
        );
      },
    );

    test('surfaces provider failures in agent state', () async {
      final agent = Agent(
        model: _model,
        streamFunction: (model, context, {cancelToken}) {
          throw StateError('Provider unavailable');
        },
        toolExecutor: _unexpectedToolExecutor,
      );

      await agent.prompt('Define motion.');

      expect(agent.state.errorMessage, contains('Provider unavailable'));
      expect(
        agent.state.messages.whereType<AssistantMessage>().last.stopReason,
        StopReason.error,
      );
    });

    test('propagates abort to the provider stream', () async {
      final providerStarted = Completer<void>();
      final providerCancelled = Completer<void>();
      final agent = Agent(
        model: _model,
        streamFunction: (model, context, {cancelToken}) {
          final response = AssistantMessageEventStream();
          providerStarted.complete();
          cancelToken!.onCancel.then((_) {
            providerCancelled.complete();
            response.push(
              ErrorEvent(
                reason: StopReason.aborted,
                error: _assistantMessage(
                  model,
                  reason: StopReason.aborted,
                  errorMessage: 'Cancelled',
                ),
              ),
            );
          });
          return response;
        },
        toolExecutor: _unexpectedToolExecutor,
      );

      final run = agent.prompt('Define motion.');
      await providerStarted.future;
      agent.abort();
      await run;

      expect(providerCancelled.isCompleted, isTrue);
      expect(
        agent.state.messages.whereType<AssistantMessage>().last.stopReason,
        StopReason.aborted,
      );
    });
  });
}

const _model = Model(
  id: 'fake-model',
  name: 'Fake model',
  api: 'fake',
  provider: 'fake',
  baseUrl: 'https://unused.invalid',
  contextWindow: 4096,
  maxTokens: 512,
);

Future<ToolExecutionResult> _unexpectedToolExecutor(
  ToolCall call,
  CancelToken? cancelToken,
  ToolUpdateCallback? onUpdate,
) async {
  throw StateError('Unexpected tool call: ${call.name}');
}

AssistantMessageEventStream _completedResponse(
  Model model,
  List<ContentBlock> content, {
  StopReason reason = StopReason.stop,
}) {
  final message = _assistantMessage(model, content: content, reason: reason);
  return AssistantMessageEventStream()
    ..push(DoneEvent(reason: reason, message: message));
}

AssistantMessage _assistantMessage(
  Model model, {
  List<ContentBlock> content = const [],
  StopReason reason = StopReason.stop,
  String? errorMessage,
}) {
  return AssistantMessage(
    content: content,
    api: model.api,
    provider: model.provider,
    model: model.id,
    usage: Usage.zero,
    stopReason: reason,
    errorMessage: errorMessage,
    timestamp: DateTime.utc(2026),
  );
}

String _assistantText(List<Message> messages) {
  final assistant = messages.whereType<AssistantMessage>().last;
  return assistant.content
      .whereType<TextContent>()
      .map((content) => content.text)
      .join();
}
