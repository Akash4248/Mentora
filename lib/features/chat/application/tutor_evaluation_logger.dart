import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../config/app_environment.dart';

/// Record of an individual tool call executed during an AI tutor turn.
class ToolExecutionRecord {
  final String toolName;
  final Map<String, dynamic> arguments;
  String? output;
  String status; // 'started', 'completed', 'failed'
  final DateTime startedAt;
  DateTime? completedAt;
  int durationMs;

  ToolExecutionRecord({
    required this.toolName,
    required this.arguments,
    this.output,
    this.status = 'started',
    DateTime? startedAt,
    this.durationMs = 0,
  }) : startedAt = startedAt ?? DateTime.now();

  void complete({String? result, int? elapsedMs}) {
    completedAt = DateTime.now();
    status = 'completed';
    output = result;
    durationMs = elapsedMs ?? completedAt!.difference(startedAt).inMilliseconds;
  }

  void fail({String? error, int? elapsedMs}) {
    completedAt = DateTime.now();
    status = 'failed';
    output = error;
    durationMs = elapsedMs ?? completedAt!.difference(startedAt).inMilliseconds;
  }

  Map<String, dynamic> toMap() => {
        'toolName': toolName,
        'arguments': arguments,
        'output': output,
        'status': status,
        'durationMs': durationMs,
      };
}

/// Evaluation record for an entire tutor turn, capturing tool execution count,
/// latencies, arguments, strategy, and answer quality.
class TutorTurnEvaluation {
  final String sessionId;
  final int grade;
  final String topic;
  final String question;
  final String? strategy;
  final DateTime startedAt;
  DateTime? endedAt;
  int totalDurationMs;
  final List<ToolExecutionRecord> toolCalls = [];
  String finalAnswer = '';
  String? error;

  TutorTurnEvaluation({
    required this.sessionId,
    required this.grade,
    required this.topic,
    required this.question,
    this.strategy,
    DateTime? startedAt,
  })  : startedAt = startedAt ?? DateTime.now(),
        totalDurationMs = 0;

  ToolExecutionRecord startToolCall({
    required String toolName,
    required Map<String, dynamic> arguments,
  }) {
    final record = ToolExecutionRecord(
      toolName: toolName,
      arguments: arguments,
    );
    toolCalls.add(record);

    AppEnvironment.log(
      'TUTOR',
      '[TOOL_START #${toolCalls.length}] $toolName args=${jsonEncode(arguments)}',
    );
    return record;
  }

  void completeToolCall({
    required String toolName,
    String? output,
  }) {
    final record = toolCalls.reversed.firstWhere(
      (r) => r.toolName == toolName && r.status == 'started',
      orElse: () {
        final fallback = ToolExecutionRecord(toolName: toolName, arguments: {});
        toolCalls.add(fallback);
        return fallback;
      },
    );
    record.complete(result: output);

    AppEnvironment.log(
      'TUTOR',
      '[TOOL_END] $toolName status=completed (${record.durationMs}ms) output=${_truncate(output ?? '', 80)}',
    );
  }

  void failToolCall({
    required String toolName,
    String? error,
  }) {
    final record = toolCalls.reversed.firstWhere(
      (r) => r.toolName == toolName && r.status == 'started',
      orElse: () {
        final fallback = ToolExecutionRecord(toolName: toolName, arguments: {});
        toolCalls.add(fallback);
        return fallback;
      },
    );
    record.fail(error: error);

    AppEnvironment.log(
      'TUTOR',
      '[TOOL_FAIL] $toolName status=failed (${record.durationMs}ms) error=${_truncate(error ?? '', 80)}',
    );
  }

  void finishTurn({required String answer, String? err}) {
    endedAt = DateTime.now();
    totalDurationMs = endedAt!.difference(startedAt).inMilliseconds;
    finalAnswer = answer;
    error = err;
    logSummary();
  }

  void logSummary() {
    final duration = totalDurationMs;
    final toolCount = toolCalls.length;
    final estimatedTokens = (finalAnswer.length / 4.0).ceil();
    final answerPreview = _truncate(finalAnswer.replaceAll('\n', ' '), 250);

    // 1. One-line grep-friendly machine log
    AppEnvironment.log(
      'EVAL',
      'TURN_COMPLETE | session=$sessionId | grade=$grade | topic=$topic | '
      'tools=$toolCount | durationMs=${duration}ms | answerChars=${finalAnswer.length} '
      '| tokens~$estimatedTokens | question="${_truncate(question, 60)}"',
    );

    // 2. High-visibility ASCII evaluation box for developer / examiner inspection
    final buffer = StringBuffer();
    buffer.writeln('\n==================== [TUTOR EVALUATION REPORT] ====================');
    buffer.writeln('Session ID      : $sessionId');
    buffer.writeln('Grade / Topic   : Class $grade | $topic');
    if (strategy != null) {
      buffer.writeln('Pedagogy Strategy: $strategy');
    }
    buffer.writeln('Student Question: "$question"');
    buffer.writeln('Turn Latency    : ${duration}ms');
    buffer.writeln('Tool Calls Made : $toolCount');

    if (toolCalls.isEmpty) {
      buffer.writeln('  (No external tools called — pure conceptual / conversational path)');
    } else {
      for (var i = 0; i < toolCalls.length; i++) {
        final t = toolCalls[i];
        buffer.writeln('  [${i + 1}] ${t.toolName} (${t.status.toUpperCase()}, ${t.durationMs}ms)');
        buffer.writeln('      Args   : ${jsonEncode(t.arguments)}');
        if (t.output != null && t.output!.isNotEmpty) {
          buffer.writeln('      Result : ${_truncate(t.output!, 150)}');
        }
      }
    }

    buffer.writeln('Answer Metrics  : ${finalAnswer.length} chars (~$estimatedTokens tokens)');
    if (error != null) {
      buffer.writeln('Turn Error      : ⚠️ $error');
    }
    buffer.writeln('Answer Preview  : "$answerPreview"');
    buffer.writeln('===================================================================');

    debugPrint(buffer.toString());
  }

  static String _truncate(String text, int maxLength) {
    final clean = text.trim();
    if (clean.length <= maxLength) return clean;
    return '${clean.substring(0, maxLength)}…';
  }
}
