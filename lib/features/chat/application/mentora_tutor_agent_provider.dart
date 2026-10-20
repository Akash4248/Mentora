import 'dart:async';

import 'package:dio/dio.dart' as dio;
import 'package:flutter_agent_harness/flutter_agent_harness.dart';

import '../../network/services/mentora_backend_client.dart';
import '../domain/tutor_stream_event.dart';
import 'mentora_agent_session.dart';

typedef TutorQuery = Future<Map<String, dynamic>> Function({
  required String question,
  required String topic,
  required int grade,
  dio.CancelToken? cancelToken,
});

typedef TutorStreamQuery = Stream<TutorStreamEvent> Function({
  required String question,
  required String topic,
  required int grade,
  dio.CancelToken? cancelToken,
  List<String> history,
  List<AgentTool> tools,
  String? systemPrompt,
});

final class MentoraTutorAgentProvider {
  MentoraTutorAgentProvider({
    MentoraBackendClient? backendClient,
    TutorQuery? queryTutor,
    Function? streamTutor,
  }) : _streamTutor = streamTutor != null
            ? _normalizeStreamTutor(streamTutor)
            : (queryTutor != null
                ? _adaptLegacyQuery(queryTutor)
                : (backendClient ?? MentoraBackendClient()).streamAiTutor);

  static TutorStreamQuery _normalizeStreamTutor(Function streamTutor) {
    if (streamTutor is TutorStreamQuery) {
      return streamTutor;
    }
    return ({
      required String question,
      required String topic,
      required int grade,
      dio.CancelToken? cancelToken,
      List<String> history = const [],
      List<AgentTool> tools = const [],
      String? systemPrompt,
    }) {
      try {
        final res = (streamTutor as dynamic)(
          question: question,
          topic: topic,
          grade: grade,
          cancelToken: cancelToken,
          history: history,
          tools: tools,
          systemPrompt: systemPrompt,
        );
        return res as Stream<TutorStreamEvent>;
      } on NoSuchMethodError {
        final res = (streamTutor as dynamic)(
          question: question,
          topic: topic,
          grade: grade,
          cancelToken: cancelToken,
          history: history,
          tools: tools,
        );
        return res as Stream<TutorStreamEvent>;
      }
    };
  }

  // Native Android runtime uses 2048 token KV cache by default (DEFAULT_CONTEXT_SIZE)
  static const _model = Model(
    id: 'mentora-routed-model',
    name: 'Mentora Tutor',
    api: 'mentora-routed',
    provider: 'mentora',
    baseUrl: 'app://mentora/inference',
    contextWindow: 2048,
    maxTokens: 1024,
  );

  final TutorStreamQuery _streamTutor;

  MentoraAgentSession createSession({
    required String topic,
    required int grade,
    List<Message> initialMessages = const [],
    Iterable<AgentTool> tools = const [],
    TutorToolAuthorization? authorizeToolCall,
    String? systemPrompt,
  }) {
    final toolList = tools.toList(growable: false);
    return MentoraAgentSession(
      model: _model,
      initialMessages: initialMessages,
      tools: toolList,
      authorizeToolCall: authorizeToolCall,
      systemPrompt: systemPrompt ??
          'You are Mentora, a clear and patient school tutor for grade $grade. '
          'Teach the current topic, answer the latest question, and use prior '
          'conversation context when it helps. Do not reveal private reasoning.',
      maxRunDuration: const Duration(seconds: 300),
      inactivityTimeout: const Duration(seconds: 90),
      streamFunction: (model, context, {cancelToken}) {
        final response = AssistantMessageEventStream();
        unawaited(
          _runProvider(
            response: response,
            model: model,
            context: context,
            topic: topic,
            grade: grade,
            tools: toolList,
            cancelToken: cancelToken,
          ),
        );
        return response;
      },
    );
  }

  Future<void> _runProvider({
    required AssistantMessageEventStream response,
    required Model model,
    required Context context,
    required String topic,
    required int grade,
    required List<AgentTool> tools,
    required CancelToken? cancelToken,
  }) async {
    final requestCancelToken = dio.CancelToken();
    if (cancelToken != null) {
      unawaited(
        cancelToken.onCancel.then((_) {
          requestCancelToken.cancel('Tutor turn cancelled.');
        }),
      );
    }

    try {
      cancelToken?.throwIfCancelled();
      final latestQuestion = _extractLatestUserQuestion(context);
      final history = _extractRecentHistory(context);

      var hasStarted = false;
      final accumulated = StringBuffer();

      await for (final event in _streamTutor(
        question: latestQuestion,
        topic: topic,
        grade: grade,
        cancelToken: requestCancelToken,
        history: history,
        tools: tools,
        systemPrompt: context.systemPrompt,
      )) {
        cancelToken?.throwIfCancelled();
        switch (event) {
          case TutorStreamChunkEvent(:final chunk):
            if (chunk.isEmpty) continue;
            if (!hasStarted) {
              hasStarted = true;
              final partial = _assistantMessage(model, text: '');
              response
                ..push(StartEvent(partial: partial))
                ..push(TextStartEvent(contentIndex: 0, partial: partial));
            }
            accumulated.write(chunk);
            final partial = _assistantMessage(model, text: accumulated.toString());
            response.push(
              TextDeltaEvent(
                contentIndex: 0,
                delta: chunk,
                partial: partial,
              ),
            );
          case TutorStreamToolCallEvent(:final id, :final name, :final arguments):
            final toolCall = ToolCall(
              id: id,
              name: name,
              arguments: arguments,
            );
            final contentIndex = hasStarted ? 1 : 0;
            if (!hasStarted) {
              hasStarted = true;
              final initialPartial = _assistantMessage(
                model,
                content: const [],
                stopReason: StopReason.toolUse,
              );
              response.push(StartEvent(partial: initialPartial));
            }
            final callPartial = _assistantMessage(
              model,
              content: [
                if (accumulated.isNotEmpty)
                  TextContent(text: accumulated.toString()),
                toolCall,
              ],
              stopReason: StopReason.toolUse,
            );
            response
              ..push(ToolCallStartEvent(
                contentIndex: contentIndex,
                partial: callPartial,
              ))
              ..push(ToolCallEndEvent(
                contentIndex: contentIndex,
                toolCall: toolCall,
                partial: callPartial,
              ))
              ..push(DoneEvent(
                reason: StopReason.toolUse,
                message: callPartial,
              ));
            return;
          case TutorStreamCompletedEvent(:final fullText, :final source):
            if (_isFailureSource(source)) {
              _pushFailure(
                response,
                model,
                fullText.isEmpty ? 'The tutor could not complete this response.' : fullText,
              );
              return;
            }
            final answer = fullText.trim().isNotEmpty
                ? fullText.trim()
                : accumulated.toString().trim();
            if (answer.isEmpty) {
              _pushFailure(response, model, 'The tutor returned an empty response.');
              return;
            }
            if (!hasStarted) {
              hasStarted = true;
              final partial = _assistantMessage(model, text: '');
              response
                ..push(StartEvent(partial: partial))
                ..push(TextStartEvent(contentIndex: 0, partial: partial));
            }
            final finalMsg = _assistantMessage(model, text: answer);
            response
              ..push(TextEndEvent(contentIndex: 0, content: answer, partial: finalMsg))
              ..push(DoneEvent(reason: StopReason.stop, message: finalMsg));
            return;
          case TutorStreamErrorEvent(:final error, :final aborted):
            _pushFailure(response, model, error, aborted: aborted);
            return;
        }
      }
    } on CancelledException {
      _pushFailure(
        response,
        model,
        'Tutor response cancelled.',
        aborted: true,
      );
    } on dio.DioException catch (error) {
      final aborted = dio.CancelToken.isCancel(error);
      _pushFailure(
        response,
        model,
        aborted
            ? 'Tutor response cancelled.'
            : 'Tutor inference failed: ${error.message ?? error}',
        aborted: aborted,
      );
    } catch (error) {
      _pushFailure(response, model, 'Tutor inference failed: $error');
    }
  }

  static TutorStreamQuery _adaptLegacyQuery(TutorQuery query) {
    return ({
      required String question,
      required String topic,
      required int grade,
      dio.CancelToken? cancelToken,
      List<String> history = const [],
      List<AgentTool> tools = const [],
      String? systemPrompt,
    }) async* {
      try {
        final queryPrompt = history.isNotEmpty
            ? '${history.join('\n')}\n$question'
            : question;
        final result = await query(
          question: queryPrompt,
          topic: topic,
          grade: grade,
          cancelToken: cancelToken,
        );
        final answer = (result['answer'] ?? result['response'] ?? '').toString();
        final source = (result['source'] as String? ?? 'legacy_query').toLowerCase();
        final hasAudio = result['hasAudio'] as bool? ?? false;
        yield TutorStreamChunkEvent(answer);
        yield TutorStreamCompletedEvent(
          fullText: answer,
          source: source,
          hasAudio: hasAudio,
        );
      } catch (e) {
        final isCancel = cancelToken?.isCancelled == true ||
            (e is dio.DioException && dio.CancelToken.isCancel(e));
        yield TutorStreamErrorEvent(e.toString(), aborted: isCancel);
      }
    };
  }

  String _extractLatestUserQuestion(Context context) {
    var baseQuestion = '';
    final userMessages = context.messages.whereType<UserMessage>().toList();
    if (userMessages.isNotEmpty) {
      final text = _messageText(userMessages.last).trim();
      if (text.isNotEmpty) {
        baseQuestion = _truncate(text, 1000);
      }
    }

    final trailingToolResults = <String>[];
    for (var i = context.messages.length - 1; i >= 0; i--) {
      final msg = context.messages[i];
      if (msg is ToolResultMessage) {
        final resultText = msg.content
            .whereType<TextContent>()
            .map((c) => c.text)
            .join();
        if (resultText.isNotEmpty) {
          trailingToolResults.insert(
            0,
            '[Tool Result (${msg.toolCallId})]: $resultText',
          );
        }
      } else if (msg is AssistantMessage) {
        break;
      }
    }

    if (trailingToolResults.isNotEmpty) {
      final resultsSummary = trailingToolResults.join('\n');
      if (baseQuestion.isNotEmpty) {
        return '$baseQuestion\n\n$resultsSummary\n\nPlease answer the question incorporating the tool result above.';
      }
      return '$resultsSummary\n\nPlease proceed with the answer incorporating the tool result above.';
    }

    return baseQuestion;
  }

  List<String> _extractRecentHistory(Context context) {
    final messages = context.messages
        .where((m) => m is UserMessage || m is AssistantMessage)
        .toList();
    if (messages.length <= 1) return const [];

    // Exclude the current question (the last message) and any duplicate of it
    final currentQuestionText = messages.last is UserMessage
        ? _messageText(messages.last).trim()
        : '';
    final historyMessages = messages
        .sublist(0, messages.length - 1)
        .where((m) => !(m is UserMessage && _messageText(m).trim() == currentQuestionText))
        .toList();
    // Take strictly the last 2 turns
    final recent = historyMessages.length > 2
        ? historyMessages.sublist(historyMessages.length - 2)
        : historyMessages;

    final historyLines = <String>[];
    for (final msg in recent) {
      final text = _messageText(msg).trim();
      if (text.isEmpty) continue;
      final role = msg is UserMessage ? 'Student' : 'Tutor';
      historyLines.add('$role: ${_truncate(text, 300)}');
    }
    return historyLines;
  }

  String _messageText(Message message) {
    if (message is UserMessage) {
      final content = message.content;
      if (content is String) return content;
      if (content is List<ContentBlock>) {
        return content.whereType<TextContent>().map((block) => block.text).join();
      }
      return '';
    }
    if (message is AssistantMessage) {
      return message.content
          .whereType<TextContent>()
          .map((block) => block.text)
          .join();
    }
    return '';
  }

  bool _isFailureSource(String source) =>
      source.endsWith('_error') ||
      source.endsWith('_timeout') ||
      source.endsWith('_failed') ||
      source.contains('no_local_model') ||
      source.contains('config_incomplete') ||
      source.contains('empty_response');

  String _truncate(String value, int maxLength) =>
      value.length <= maxLength
      ? value
      : '${value.substring(0, maxLength)}…';

  void _pushFailure(
    AssistantMessageEventStream response,
    Model model,
    String message, {
    bool aborted = false,
  }) {
    final error = _assistantMessage(
      model,
      errorMessage: message,
      stopReason: aborted ? StopReason.aborted : StopReason.error,
    );
    response.push(
      ErrorEvent(
        reason: aborted ? StopReason.aborted : StopReason.error,
        error: error,
      ),
    );
  }

  AssistantMessage _assistantMessage(
    Model model, {
    String? text,
    List<ContentBlock>? content,
    String? errorMessage,
    StopReason stopReason = StopReason.stop,
  }) => AssistantMessage(
    content: content ?? (text == null ? const [] : [TextContent(text: text)]),
    api: model.api,
    provider: model.provider,
    model: model.id,
    usage: Usage.zero,
    stopReason: stopReason,
    errorMessage: errorMessage,
    timestamp: DateTime.now(),
  );
}
