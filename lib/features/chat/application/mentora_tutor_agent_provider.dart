import 'dart:async';

import 'package:dio/dio.dart' as dio;
import 'package:flutter_agent_harness/flutter_agent_harness.dart';

import '../../network/services/mentora_backend_client.dart';
import 'mentora_agent_session.dart';

typedef TutorQuery = Future<Map<String, dynamic>> Function({
  required String question,
  required String topic,
  required int grade,
  dio.CancelToken? cancelToken,
});

final class MentoraTutorAgentProvider {
  MentoraTutorAgentProvider({
    MentoraBackendClient? backendClient,
    TutorQuery? queryTutor,
  }) : _queryTutor =
           queryTutor ?? (backendClient ?? MentoraBackendClient()).queryAiTutor;

  static const _model = Model(
    id: 'mentora-routed-model',
    name: 'Mentora Tutor',
    api: 'mentora-routed',
    provider: 'mentora',
    baseUrl: 'app://mentora/inference',
    contextWindow: 8192,
    maxTokens: 1024,
  );

  final TutorQuery _queryTutor;

  MentoraAgentSession createSession({
    required String topic,
    required int grade,
    List<Message> initialMessages = const [],
  }) {
    return MentoraAgentSession(
      model: _model,
      initialMessages: initialMessages,
      systemPrompt:
          'You are Mentora, a clear and patient school tutor for grade $grade. '
          'Teach the current topic, answer the latest question, and use prior '
          'conversation context when it helps. Do not reveal private reasoning.',
      maxRunDuration: const Duration(seconds: 130),
      streamFunction: (model, context, {cancelToken}) {
        final response = AssistantMessageEventStream();
        unawaited(
          _runProvider(
            response: response,
            model: model,
            context: context,
            topic: topic,
            grade: grade,
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
      final result = await _queryTutor(
        question: _renderQuestion(context),
        topic: topic,
        grade: grade,
        cancelToken: requestCancelToken,
      );
      cancelToken?.throwIfCancelled();

      final answer = (result['answer'] ?? result['response'] ?? '')
          .toString()
          .trim();
      final source = (result['source'] as String? ?? '').toLowerCase();
      if (_isFailureSource(source)) {
        _pushFailure(
          response,
          model,
          answer.isEmpty ? 'The tutor could not complete this response.' : answer,
        );
        return;
      }
      if (answer.isEmpty) {
        _pushFailure(response, model, 'The tutor returned an empty response.');
        return;
      }

      final message = _assistantMessage(model, text: answer);
      response
        ..push(StartEvent(partial: message))
        ..push(TextStartEvent(contentIndex: 0, partial: message))
        ..push(TextDeltaEvent(
          contentIndex: 0,
          delta: answer,
          partial: message,
        ))
        ..push(TextEndEvent(
          contentIndex: 0,
          content: answer,
          partial: message,
        ))
        ..push(DoneEvent(reason: StopReason.stop, message: message));
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

  String _renderQuestion(Context context) {
    final messages = context.messages
        .where((message) => message is UserMessage || message is AssistantMessage)
        .toList();
    final recentMessages = messages.length > 12
        ? messages.sublist(messages.length - 12)
        : messages;
    final transcript = <String>[];

    for (final message in recentMessages) {
      final text = _messageText(message).trim();
      if (text.isEmpty) continue;
      final role = message is UserMessage ? 'Student' : 'Tutor';
      transcript.add('$role: ${_truncate(text, 1800)}');
    }

    final currentQuestion = recentMessages.isEmpty
        ? ''
        : _messageText(recentMessages.last).trim();
    final contextLines = transcript.length > 1
        ? transcript.sublist(0, transcript.length - 1)
        : const <String>[];
    final instructions = context.systemPrompt?.trim() ?? '';

    return [
      if (instructions.isNotEmpty) 'Tutoring instructions: $instructions',
      if (contextLines.isNotEmpty)
        'Recent conversation for context:\n${contextLines.join('\n')}',
      'Current student question: ${_truncate(currentQuestion, 4000)}',
    ].join('\n\n');
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
    String? errorMessage,
    StopReason stopReason = StopReason.stop,
  }) => AssistantMessage(
    content: text == null ? const [] : [TextContent(text: text)],
    api: model.api,
    provider: model.provider,
    model: model.id,
    usage: Usage.zero,
    stopReason: stopReason,
    errorMessage: errorMessage,
    timestamp: DateTime.now(),
  );
}
