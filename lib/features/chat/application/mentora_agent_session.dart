import 'dart:async';

import 'package:flutter_agent_harness/flutter_agent_harness.dart';

typedef TutorToolAuthorization =
    FutureOr<bool> Function(String toolName, Map<String, dynamic> arguments);

sealed class TutorAgentEvent {
  const TutorAgentEvent();
}

final class TutorTextDeltaEvent extends TutorAgentEvent {
  const TutorTextDeltaEvent(this.delta);

  final String delta;
}

enum TutorToolStatus { started, completed, failed }

final class TutorToolStatusEvent extends TutorAgentEvent {
  const TutorToolStatusEvent({
    required this.label,
    required this.status,
    this.toolName,
    this.output,
  });

  final String label;
  final TutorToolStatus status;
  final String? toolName;
  final String? output;
}

final class TutorTurnCompletedEvent extends TutorAgentEvent {
  const TutorTurnCompletedEvent(this.text);

  final String text;
}

final class TutorTurnFailedEvent extends TutorAgentEvent {
  const TutorTurnFailedEvent(this.message);

  final String message;
}

final class TutorTurnAbortedEvent extends TutorAgentEvent {
  const TutorTurnAbortedEvent();
}

/// Owns one in-memory harness conversation. Mentora remains responsible for
/// transcript persistence, tool authorization, and provider selection.
final class MentoraAgentSession {
  MentoraAgentSession({
    required Model model,
    required StreamFunction streamFunction,
    Iterable<AgentTool> tools = const [],
    TutorToolAuthorization? authorizeToolCall,
    String systemPrompt = '',
    List<Message> initialMessages = const [],
    this.maxModelTurns = 6,
    this.maxToolCalls = 4,
    this.maxRunDuration = const Duration(seconds: 300),
    this.maxToolDuration = const Duration(seconds: 15),
    this.inactivityTimeout = const Duration(seconds: 90),
    this.maxTurnCeiling = const Duration(minutes: 10),
  }) {
    if (maxModelTurns <= 0 || maxToolCalls < 0) {
      throw ArgumentError(
        'The model-turn limit must be positive and the tool-call limit '
        'must not be negative.',
      );
    }
    if (maxRunDuration <= Duration.zero ||
        maxToolDuration <= Duration.zero ||
        inactivityTimeout <= Duration.zero ||
        maxTurnCeiling <= Duration.zero) {
      throw ArgumentError('Durations and timeouts must be greater than zero.');
    }

    final registeredTools = tools.map(_withTimeout).toList(growable: false);
    if (registeredTools.isNotEmpty && authorizeToolCall == null) {
      throw ArgumentError('Tool calls require a Mentora authorization policy.');
    }

    final registry = ToolRegistry(registeredTools);
    if (registry.duplicateNotes.isNotEmpty) {
      throw ArgumentError(registry.duplicateNotes.join('\n'));
    }

    _authorizeToolCall = authorizeToolCall;
    _toolLabels = {
      for (final tool in registeredTools)
        tool.name: tool.label?.trim().isNotEmpty == true
            ? tool.label!.trim()
            : tool.name,
    };

    _agent = Agent(
      model: model,
      systemPrompt: systemPrompt,
      messages: initialMessages,
      toolRegistry: registry,
      toolExecution: ToolExecutionMode.sequential,
      overWindowRelief: _compactOverWindowMessages,
      streamFunction: (activeModel, context, {cancelToken}) {
        if (_modelTurns >= maxModelTurns) {
          return _failureResponse(
            activeModel,
            'The tutor reached the model-turn limit.',
          );
        }
        _modelTurns += 1;
        return streamFunction(activeModel, context, cancelToken: cancelToken);
      },
      beforeToolCall: (context, cancelToken) async {
        if (_toolCalls >= maxToolCalls) {
          return const BeforeToolCallResult(
            block: true,
            reason: 'The tutor reached the tool-call limit.',
          );
        }
        _toolCalls += 1;
        cancelToken?.throwIfCancelled();
        final tool = registry.lookup(context.toolCall.name);
        if (tool == null) {
          return const BeforeToolCallResult(
            block: true,
            reason: 'This action is not available.',
          );
        }
        final validatedArguments = validateToolArguments(
          arguments: context.toolCall.arguments,
          schema: tool.parameters,
          toolName: tool.name,
        );
        final authorized = await _authorizeToolCall!(
          context.toolCall.name,
          Map<String, dynamic>.unmodifiable(
            _projectArguments(validatedArguments, tool.parameters),
          ),
        );
        cancelToken?.throwIfCancelled();
        return authorized
            ? null
            : const BeforeToolCallResult(
                block: true,
                reason: 'This action was not approved.',
              );
      },
    );
    _unsubscribe = _agent.subscribe(_handleAgentEvent);
  }

  final int maxModelTurns;
  final int maxToolCalls;
  final Duration maxRunDuration;
  final Duration maxToolDuration;
  final Duration inactivityTimeout;
  final Duration maxTurnCeiling;

  late final Agent _agent;
  late final void Function() _unsubscribe;
  late final TutorToolAuthorization? _authorizeToolCall;
  late final Map<String, String> _toolLabels;
  StreamController<TutorAgentEvent>? _activeController;
  Timer? _runTimer;
  DateTime? _turnStartTime;
  var _modelTurns = 0;
  var _toolCalls = 0;
  var _runTimedOut = false;
  var _disposed = false;

  bool get isRunning => _activeController != null;

  /// Starts a turn and returns privacy-filtered events for the chat UI.
  ///
  /// Tool arguments, raw tool results, provider payloads, and hidden reasoning
  /// are intentionally not part of this UI event contract.
  Stream<TutorAgentEvent> runTurn(String prompt, {String? systemPrompt}) {
    if (_disposed) throw StateError('The tutor session has been disposed.');
    if (_activeController != null) {
      throw StateError('A tutor turn is already running.');
    }
    if (prompt.trim().isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'Must not be empty.');
    }

    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      _agent.state.systemPrompt = systemPrompt.trim();
    }

    _modelTurns = 0;
    _toolCalls = 0;
    _runTimedOut = false;
    _turnStartTime = DateTime.now();
    final controller = StreamController<TutorAgentEvent>(sync: true);
    _activeController = controller;
    controller.onCancel = cancelCurrentTurn;
    _runTimer = Timer(maxRunDuration, () {
      _runTimedOut = true;
      _agent.abort();
    });
    unawaited(_run(prompt, controller));
    return controller.stream;
  }

  void _resetInactivityTimer() {
    if (_runTimedOut || _disposed || _activeController == null) return;
    if (_turnStartTime != null &&
        DateTime.now().difference(_turnStartTime!) >= maxTurnCeiling) {
      _runTimedOut = true;
      _agent.abort();
      return;
    }
    _runTimer?.cancel();
    final effectiveTimeout =
        maxRunDuration < inactivityTimeout ? maxRunDuration : inactivityTimeout;
    _runTimer = Timer(effectiveTimeout, () {
      _runTimedOut = true;
      _agent.abort();
    });
  }

  void cancelCurrentTurn() {
    _agent.abort();
  }

  static Future<List<Message>?> _compactOverWindowMessages(List<Message> messages) async {
    if (messages.isEmpty) return null;

    if (messages.length <= 2) {
      final truncated = <Message>[];
      for (final m in messages) {
        if (m is AssistantMessage) {
          final text = m.content.whereType<TextContent>().map((c) => c.text).join();
          if (text.length > 400) {
            truncated.add(AssistantMessage(
              content: [TextContent(text: '${text.substring(0, 400)}…')],
              api: m.api,
              provider: m.provider,
              model: m.model,
              usage: m.usage,
              stopReason: m.stopReason,
              timestamp: m.timestamp,
            ));
            continue;
          }
        }
        truncated.add(m);
      }
      return truncated;
    }

    final recent = messages.sublist(messages.length - 2);
    final older = messages.sublist(0, messages.length - 2);

    final summaryLines = <String>[];
    for (final m in older) {
      String role = 'Student';
      String text = '';
      if (m is UserMessage) {
        role = 'Student';
        final content = m.content;
        if (content is String) {
          text = content;
        } else if (content is List<ContentBlock>) {
          text = content.whereType<TextContent>().map((c) => c.text).join();
        }
      } else if (m is AssistantMessage) {
        role = 'Tutor';
        text = m.content.whereType<TextContent>().map((c) => c.text).join();
      } else if (m is ToolResultMessage) {
        continue;
      }
      text = text.trim();
      if (text.isEmpty) continue;

      text = text.replaceAll(RegExp(r'```[\s\S]*?(?:```|$)'), '[diagram]');
      final snippet = text.length > 100 ? '${text.substring(0, 100)}…' : text;
      summaryLines.add('$role: $snippet');
    }

    final summaryBlock = summaryLines.isNotEmpty
        ? '[Compacted Conversation History Summary]:\n${summaryLines.join('\n')}'
        : '[Prior history compacted]';

    return [
      UserMessage.text(summaryBlock, timestamp: DateTime.now()),
      ...recent,
    ];
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    cancelCurrentTurn();
    await _agent.waitForIdle();
    _runTimer?.cancel();
    _runTimer = null;
    _turnStartTime = null;
    _unsubscribe();
  }

  Future<void> _run(
    String prompt,
    StreamController<TutorAgentEvent> controller,
  ) async {
    try {
      await _agent.prompt(prompt);
    } catch (error, stackTrace) {
      if (!controller.isClosed) controller.addError(error, stackTrace);
    } finally {
      _runTimer?.cancel();
      _runTimer = null;
      _turnStartTime = null;
      if (identical(_activeController, controller)) {
        _activeController = null;
      }
      if (!controller.isClosed) await controller.close();
    }
  }

  void _handleAgentEvent(AgentEvent event, CancelToken cancelToken) {
    final controller = _activeController;
    if (controller == null || controller.isClosed) return;

    _resetInactivityTimer();

    switch (event) {
      case MessageUpdateEvent(
        assistantMessageEvent: TextDeltaEvent(:final delta),
      ):
        controller.add(TutorTextDeltaEvent(delta));
      case ToolExecutionStartEvent(:final toolName):
        controller.add(
          TutorToolStatusEvent(
            label: _toolLabels[toolName] ?? 'Learning tool',
            status: TutorToolStatus.started,
            toolName: toolName,
          ),
        );
      case ToolExecutionEndEvent(:final toolName, :final result, :final isError):
        final outText = result.content
            .whereType<TextContent>()
            .map((c) => c.text)
            .join();
        controller.add(
          TutorToolStatusEvent(
            label: _toolLabels[toolName] ?? 'Learning tool',
            status: isError
                ? TutorToolStatus.failed
                : TutorToolStatus.completed,
            toolName: toolName,
            output: outText.isNotEmpty ? outText : null,
          ),
        );
      case AgentEndEvent(:final messages):
        _emitTurnResult(controller, messages);
      default:
        break;
    }
  }

  void _emitTurnResult(
    StreamController<TutorAgentEvent> controller,
    List<Message> messages,
  ) {
    final assistantMessages = messages.whereType<AssistantMessage>().toList();
    if (assistantMessages.isEmpty) {
      controller.add(
        const TutorTurnFailedEvent('The tutor returned no answer.'),
      );
      return;
    }

    final answer = assistantMessages.last;
    if (_runTimedOut) {
      controller.add(
        const TutorTurnFailedEvent(
          'The tutor took too long to respond. Please try again.',
        ),
      );
    } else if (answer.stopReason == StopReason.aborted) {
      controller.add(const TutorTurnAbortedEvent());
    } else if (answer.stopReason == StopReason.error) {
      controller.add(
        TutorTurnFailedEvent(
          answer.errorMessage ?? 'The tutor could not complete this response.',
        ),
      );
    } else {
      controller.add(
        TutorTurnCompletedEvent(
          answer.content
              .whereType<TextContent>()
              .map((content) => content.text)
              .join(),
        ),
      );
    }
  }

  AgentTool _withTimeout(AgentTool tool) {
    return AgentTool(
      name: tool.name,
      description: tool.description,
      parameters: tool.parameters,
      executionMode: tool.executionMode,
      label: tool.label,
      tier: tool.tier,
      execute: (arguments, cancelToken, onUpdate) async {
        cancelToken?.throwIfCancelled();
        try {
          final safeArguments = _projectArguments(arguments, tool.parameters);
          final result = await tool
              .execute(safeArguments, cancelToken, onUpdate)
              .timeout(maxToolDuration);
          cancelToken?.throwIfCancelled();
          return result;
        } on TimeoutException {
          _agent.abort();
          rethrow;
        }
      },
    );
  }
}

Map<String, dynamic> _projectArguments(
  Map<String, dynamic> arguments,
  Map<String, dynamic> schema,
) {
  final properties = schema['properties'];
  if (properties is! Map) return const {};

  return {
    for (final entry in arguments.entries)
      if (properties[entry.key] is Map)
        entry.key: _projectValue(
          entry.value,
          Map<String, dynamic>.from(properties[entry.key] as Map),
        ),
  };
}

Object? _projectValue(Object? value, Map<String, dynamic> schema) {
  if (value is Map<String, dynamic>) {
    return _projectArguments(value, schema);
  }
  if (value is List) {
    final items = schema['items'];
    if (items is Map) {
      final itemSchema = Map<String, dynamic>.from(items);
      return value.map((item) => _projectValue(item, itemSchema)).toList();
    }
    return const <Object?>[];
  }
  return value;
}

AssistantMessageEventStream _failureResponse(Model model, String message) {
  final assistantMessage = AssistantMessage(
    content: const [],
    api: model.api,
    provider: model.provider,
    model: model.id,
    usage: Usage.zero,
    stopReason: StopReason.error,
    errorMessage: message,
    timestamp: DateTime.now(),
  );
  return AssistantMessageEventStream()
    ..push(ErrorEvent(reason: StopReason.error, error: assistantMessage));
}
