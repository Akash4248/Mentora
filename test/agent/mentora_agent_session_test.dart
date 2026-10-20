import 'dart:async';

import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/mentora_agent_session.dart';

void main() {
  group('MentoraAgentSession', () {
    test('streams safe text events and completes the turn', () async {
      final session = MentoraAgentSession(
        model: _model,
        streamFunction: (model, context, {cancelToken}) =>
            _textResponse(model, 'Motion is a change in position.'),
      );

      final events = await session.runTurn('Define motion.').toList();

      expect(
        events.whereType<TutorTextDeltaEvent>().map((event) => event.delta),
        ['Motion is a change in position.'],
      );
      expect(
        events.last,
        isA<TutorTurnCompletedEvent>().having(
          (event) => event.text,
          'text',
          'Motion is a change in position.',
        ),
      );
      await session.dispose();
    });

    test('blocks a tool call when Mentora authorization denies it', () async {
      var toolExecutions = 0;
      Map<String, dynamic>? authorizedArguments;
      final registryTool = AgentTool(
        name: 'lookup_definition',
        description: 'Look up a curriculum definition.',
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
          return ToolExecutionResult.text('must not execute');
        },
      );
      final session = MentoraAgentSession(
        model: _model,
        tools: [registryTool],
        authorizeToolCall: (toolName, arguments) async {
          authorizedArguments = arguments;
          return false;
        },
        streamFunction: (model, context, {cancelToken}) {
          if (context.messages.whereType<ToolResultMessage>().isEmpty) {
            return _toolCallResponse(model);
          }
          return _textResponse(model, 'I could not look that up.');
        },
      );

      final events = await session.runTurn('Define motion.').toList();

      expect(toolExecutions, 0);
      expect(authorizedArguments, {'term': 'motion'});
      expect(events.whereType<TutorToolStatusEvent>(), isNotEmpty);
      expect(
        events.whereType<TutorTurnCompletedEvent>().single.text,
        'I could not look that up.',
      );
      await session.dispose();
    });

    test(
      'cancellation reaches the provider and is reported to the caller',
      () async {
        final providerStarted = Completer<void>();
        final providerCancelled = Completer<void>();
        final session = MentoraAgentSession(
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
        );

        final eventsFuture = session.runTurn('Define motion.').toList();
        await providerStarted.future;
        session.cancelCurrentTurn();
        final events = await eventsFuture;

        expect(providerCancelled.isCompleted, isTrue);
        expect(events.whereType<TutorTurnAbortedEvent>(), hasLength(1));
        await session.dispose();
      },
    );

    test('uses prior turns as in-memory conversation context', () async {
      final providerContexts = <List<Message>>[];
      final session = MentoraAgentSession(
        model: _model,
        streamFunction: (model, context, {cancelToken}) {
          providerContexts.add(context.messages);
          return _textResponse(model, 'A concise answer.');
        },
      );

      await session.runTurn('First question.').toList();
      await session.runTurn('Follow-up question.').toList();

      expect(providerContexts, hasLength(2));
      expect(providerContexts[1].whereType<UserMessage>(), hasLength(2));
      expect(
        providerContexts[1].whereType<AssistantMessage>().any(
          (message) => _messageText(message) == 'A concise answer.',
        ),
        isTrue,
      );
      await session.dispose();
    });

    test('enforces the model-turn limit without calling the provider again',
        () async {
      var providerCalls = 0;
      final session = MentoraAgentSession(
        model: _model,
        tools: [_lookupTool((_, _, _) async => ToolExecutionResult.text('ok'))],
        authorizeToolCall: (toolName, arguments) => true,
        maxModelTurns: 1,
        streamFunction: (model, context, {cancelToken}) {
          providerCalls += 1;
          return _toolCallResponse(model);
        },
      );

      final events = await session.runTurn('Define motion.').toList();

      expect(providerCalls, 1);
      expect(events.whereType<TutorTurnFailedEvent>(), hasLength(1));
      await session.dispose();
    });

    test('enforces the tool-call limit before executing excess calls',
        () async {
      var toolExecutions = 0;
      final session = MentoraAgentSession(
        model: _model,
        tools: [
          _lookupTool((_, _, _) async {
            toolExecutions += 1;
            return ToolExecutionResult.text('ok');
          }),
        ],
        authorizeToolCall: (toolName, arguments) => true,
        maxToolCalls: 1,
        streamFunction: (model, context, {cancelToken}) {
          if (context.messages.whereType<ToolResultMessage>().isEmpty) {
            return _multipleToolCallsResponse(model);
          }
          return _textResponse(model, 'The lookup limit was reached.');
        },
      );

      final events = await session.runTurn('Define motion.').toList();

      expect(toolExecutions, 1);
      expect(events.whereType<TutorToolStatusEvent>(), hasLength(4));
      expect(
        events.whereType<TutorTurnCompletedEvent>().single.text,
        'The lookup limit was reached.',
      );
      await session.dispose();
    });

    test('cancels the agent when a tool exceeds its time budget', () async {
      final toolCancelled = Completer<void>();
      final session = MentoraAgentSession(
        model: _model,
        tools: [
          _lookupTool((arguments, cancelToken, onUpdate) {
            cancelToken!.onCancel.then((_) => toolCancelled.complete());
            return Completer<ToolExecutionResult>().future;
          }),
        ],
        authorizeToolCall: (toolName, arguments) => true,
        maxToolDuration: const Duration(milliseconds: 30),
        streamFunction: (model, context, {cancelToken}) =>
            _toolCallResponse(model),
      );

      await session.runTurn('Define motion.').toList();

      expect(toolCancelled.isCompleted, isTrue);
      await session.dispose();
    });

    test('reports the run deadline and aborts the provider', () async {
      final providerStarted = Completer<void>();
      final providerCancelled = Completer<void>();
      final session = MentoraAgentSession(
        model: _model,
        maxRunDuration: const Duration(milliseconds: 50),
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
      );

      final eventsFuture = session.runTurn('Define motion.').toList();
      await providerStarted.future;
      final events = await eventsFuture;

      expect(providerCancelled.isCompleted, isTrue);
      expect(
        events.whereType<TutorTurnFailedEvent>().single.message,
        contains('took too long'),
      );
      await session.dispose();
    });

    test('auto-compresses older conversation history via overWindowRelief without throwing context exhausted', () async {
      const tightModel = Model(
        id: 'tight-model',
        name: 'Tight model',
        api: 'fake',
        provider: 'fake',
        baseUrl: 'https://unused.invalid',
        contextWindow: 450,
        maxTokens: 50,
      );

      final initialMessages = [
        UserMessage.text('Turn 1 Question ' * 10, timestamp: DateTime.now()),
        _assistantMessage(tightModel, content: [TextContent(text: 'Turn 1 Answer ' * 10)]),
        UserMessage.text('Turn 2 Question ' * 10, timestamp: DateTime.now()),
        _assistantMessage(tightModel, content: [TextContent(text: 'Turn 2 Answer ' * 10)]),
      ];

      final session = MentoraAgentSession(
        model: tightModel,
        initialMessages: initialMessages,
        streamFunction: (model, context, {cancelToken}) {
          final response = AssistantMessageEventStream();
          const text = 'Relieved Turn 3 answer';
          final message = _assistantMessage(model, content: [const TextContent(text: text)]);
          response
            ..push(StartEvent(partial: message))
            ..push(TextStartEvent(contentIndex: 0, partial: message))
            ..push(TextDeltaEvent(contentIndex: 0, delta: text, partial: message))
            ..push(TextEndEvent(contentIndex: 0, content: text, partial: message))
            ..push(DoneEvent(reason: StopReason.stop, message: message));
          return response;
        },
      );

      final events = await session.runTurn('Turn 3 Question').toList();
      final turnCompleted = events.whereType<TutorTurnCompletedEvent>().singleOrNull;
      expect(turnCompleted, isNotNull);
      expect(turnCompleted!.text, 'Relieved Turn 3 answer');
      expect(events.whereType<TutorTurnFailedEvent>(), isEmpty);
      await session.dispose();
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

AssistantMessageEventStream _textResponse(Model model, String text) {
  final message = _assistantMessage(model, content: [TextContent(text: text)]);
  return AssistantMessageEventStream()
    ..push(StartEvent(partial: message))
    ..push(TextStartEvent(contentIndex: 0, partial: message))
    ..push(TextDeltaEvent(contentIndex: 0, delta: text, partial: message))
    ..push(TextEndEvent(contentIndex: 0, content: text, partial: message))
    ..push(DoneEvent(reason: StopReason.stop, message: message));
}

AssistantMessageEventStream _toolCallResponse(Model model) {
  final message = _assistantMessage(
    model,
    content: const [
      ToolCall(
        id: 'call-1',
        name: 'lookup_definition',
        arguments: {'term': 'motion', 'unexpected': 'must be removed'},
      ),
    ],
    reason: StopReason.toolUse,
  );
  return AssistantMessageEventStream()
    ..push(DoneEvent(reason: StopReason.toolUse, message: message));
}

AssistantMessageEventStream _multipleToolCallsResponse(Model model) {
  final message = _assistantMessage(
    model,
    content: const [
      ToolCall(
        id: 'call-1',
        name: 'lookup_definition',
        arguments: {'term': 'motion'},
      ),
      ToolCall(
        id: 'call-2',
        name: 'lookup_definition',
        arguments: {'term': 'velocity'},
      ),
    ],
    reason: StopReason.toolUse,
  );
  return AssistantMessageEventStream()
    ..push(DoneEvent(reason: StopReason.toolUse, message: message));
}

AgentTool _lookupTool(AgentToolExecute execute) => AgentTool(
  name: 'lookup_definition',
  description: 'Look up a curriculum definition.',
  parameters: const {
    'type': 'object',
    'properties': {
      'term': {'type': 'string'},
    },
    'required': ['term'],
    'additionalProperties': false,
  },
  execute: execute,
);

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

String _messageText(AssistantMessage message) => message.content
    .whereType<TextContent>()
    .map((content) => content.text)
    .join();
