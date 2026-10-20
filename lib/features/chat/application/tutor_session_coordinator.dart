// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';

import '../../network/data/backend_availability_cache.dart';
import '../domain/capability_registry.dart';
import '../domain/follow_up_action.dart';
import '../domain/teaching_strategy.dart';
import 'context_builder.dart';
import 'mentora_agent_session.dart';
import 'mentora_tutor_agent_provider.dart';
import 'tutor_evaluation_logger.dart';

enum TutorRunState {
  idle,
  connecting,
  generating,
  cancelling,
  completed,
  failed,
  aborted,
}

/// Single owner of the tutor execution lifecycle, active run ID, and session state.
///
/// Ensures seamless switching between online and offline models, drops late events
/// from superseded turns, provides cancellation propagation, and guarantees that
/// only one turn runs at a time.
final class TutorSessionCoordinator {
  TutorSessionCoordinator({
    required MentoraTutorAgentProvider agentProvider,
    required String initialTopic,
    required int initialGrade,
    BackendAvailabilityCache? availabilityCache,
    CapabilityRegistry? capabilityRegistry,
    ContextBuilder? contextBuilder,
    Iterable<AgentTool> tools = const [],
    TutorToolAuthorization? authorizeToolCall,
  }) : _agentProvider = agentProvider,
       _topic = initialTopic,
       _grade = initialGrade,
       _capabilityRegistry = capabilityRegistry,
       _contextBuilder = contextBuilder,
       _tools = capabilityRegistry?.resolveTools() ?? tools,
       _authorizeToolCall = authorizeToolCall ?? capabilityRegistry?.authorizeCall,
       _availabilityCache = availabilityCache ?? BackendAvailabilityCache() {
    _lastKnownOnlineState = _availabilityCache.isOnline;
    _availabilityCache.statusNotifier.addListener(_onAvailabilityChanged);
  }

  final MentoraTutorAgentProvider _agentProvider;
  final BackendAvailabilityCache _availabilityCache;
  final CapabilityRegistry? _capabilityRegistry;
  final ContextBuilder? _contextBuilder;
  final Iterable<AgentTool> _tools;
  final TutorToolAuthorization? _authorizeToolCall;

  String _topic;
  int _grade;
  bool? _lastKnownOnlineState;

  MentoraAgentSession? _activeSession;
  int _activeRunId = 0;
  bool _disposed = false;

  final ValueNotifier<TutorRunState> _stateNotifier =
      ValueNotifier<TutorRunState>(TutorRunState.idle);

  ValueListenable<TutorRunState> get stateNotifier => _stateNotifier;
  TutorRunState get state => _stateNotifier.value;
  int get activeRunId => _activeRunId;
  CapabilityRegistry? get capabilityRegistry => _capabilityRegistry;
  ContextBuilder? get contextBuilder => _contextBuilder;
  bool get isGenerating =>
      _stateNotifier.value == TutorRunState.generating ||
      _stateNotifier.value == TutorRunState.cancelling;

  List<FollowUpAction> _latestFollowUps = const [];
  TeachingStrategy? _latestStrategy;

  List<FollowUpAction> get latestFollowUps => _latestFollowUps;
  TeachingStrategy? get latestStrategy => _latestStrategy;

  /// Updates topic and grade for the tutor session.
  void updateTopicAndGrade({required String topic, required int grade}) {
    if (_topic == topic && _grade == grade) return;
    _topic = topic;
    _grade = grade;
    _invalidateSession();
  }

  /// Submits a question and yields filtered progressive tutor events.
  ///
  /// Automatically aborts any in-flight turn, advances the run ID, and rejects
  /// any late events from superseded runs.
  Stream<TutorAgentEvent> submitQuestion(
    String question, {
    String? sessionId,
    List<Map<String, dynamic>> rawHistory = const [],
    List<Message> initialMessages = const [],
  }) async* {
    if (_disposed) {
      throw StateError('TutorSessionCoordinator has already been disposed.');
    }
    if (question.trim().isEmpty) {
      throw ArgumentError.value(question, 'question', 'Must not be empty.');
    }

    // Cancel existing run if currently generating
    if (isGenerating || _activeSession?.isRunning == true) {
      cancelActiveTurn();
      _invalidateSession();
    }

    final currentRunId = ++_activeRunId;
    _stateNotifier.value = TutorRunState.generating;

    // Filter out active question and placeholder messages so history strictly contains prior turns
    final cleanQuestion = question.trim();
    final sanitizedRawHistory = <Map<String, dynamic>>[];
    for (var i = 0; i < rawHistory.length; i++) {
      final entry = rawHistory[i];
      final text = (entry['text'] as String? ?? '').trim();
      if (text.isEmpty ||
          text.startsWith('Welcome to Grade ') ||
          text.startsWith('Thinking…') ||
          text == 'Thinking…') {
        continue;
      }
      if (i >= rawHistory.length - 2 &&
          entry['isUser'] == true &&
          text == cleanQuestion) {
        continue;
      }
      sanitizedRawHistory.add(entry);
    }

    String? resolvedSystemPrompt;
    // Resolve context, pedagogical strategy, and follow-ups if contextBuilder is configured
    if (_contextBuilder != null) {
      final stringHistory = sanitizedRawHistory
          .map((e) => (e['text'] as String? ?? '').trim())
          .toList(growable: false);
      try {
        final built = await _contextBuilder.build(
          question: question,
          topic: _topic,
          grade: _grade,
          sessionId: sessionId,
          rawHistory: stringHistory,
        );
        _latestFollowUps = built.followUpActions;
        _latestStrategy = built.strategy;
        resolvedSystemPrompt = built.systemPrompt;
      } catch (_) {}
    }

    // Convert raw history to harness messages if provided
    final messages = initialMessages.isNotEmpty
        ? initialMessages
        : _convertHistoryToMessages(sanitizedRawHistory);

    final session = _ensureSession(messages);
    final evaluation = TutorTurnEvaluation(
      sessionId: sessionId ?? _topic,
      grade: _grade,
      topic: _topic,
      question: question,
      strategy: _latestStrategy?.name,
    );

    try {
      await for (final event in session.runTurn(question, systemPrompt: resolvedSystemPrompt)) {
        if (_activeRunId != currentRunId) {
          // A newer run started or turn was cancelled: drop late events
          return;
        }

        switch (event) {
          case TutorTextDeltaEvent():
            yield event;
          case TutorTurnCompletedEvent(:final text):
            _stateNotifier.value = TutorRunState.completed;
            evaluation.finishTurn(answer: text);
            final activeSessionId = sessionId ?? _topic;
            _contextBuilder?.memoryManager.recordSessionQuestion(activeSessionId, question);
            yield event;
          case TutorTurnAbortedEvent():
            _stateNotifier.value = TutorRunState.aborted;
            evaluation.finishTurn(answer: '', err: 'Aborted by user');
            yield event;
          case TutorTurnFailedEvent(:final message):
            _stateNotifier.value = TutorRunState.failed;
            evaluation.finishTurn(answer: '', err: message);
            yield event;
          case TutorToolStatusEvent(:final status, :final toolName, :final label, :final output):
            final tName = toolName ?? label;
            if (status == TutorToolStatus.started) {
              evaluation.startToolCall(toolName: tName, arguments: {});
            } else if (status == TutorToolStatus.completed) {
              evaluation.completeToolCall(toolName: tName, output: output);
              final activeSessionId = sessionId ?? _topic;
              _contextBuilder?.memoryManager.recordSessionTool(
                activeSessionId,
                tName,
                formula: tName == 'calculate' ? output : null,
              );
            } else if (status == TutorToolStatus.failed) {
              evaluation.failToolCall(toolName: tName, error: output);
            }
            yield event;
        }
      }
    } catch (error) {
      if (_activeRunId == currentRunId) {
        _stateNotifier.value = TutorRunState.failed;
        evaluation.finishTurn(answer: '', err: error.toString());
        yield TutorTurnFailedEvent('Tutor execution error: $error');
      }
    } finally {
      if (_activeRunId == currentRunId &&
          _stateNotifier.value == TutorRunState.generating) {
        _stateNotifier.value = TutorRunState.idle;
      }
    }
  }

  /// Cancels the currently active turn.
  void cancelActiveTurn() {
    if (!isGenerating) return;
    _stateNotifier.value = TutorRunState.cancelling;
    _activeSession?.cancelCurrentTurn();
  }

  /// Disposes the coordinator and its underlying agent session.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _availabilityCache.statusNotifier.removeListener(_onAvailabilityChanged);
    cancelActiveTurn();
    await _activeSession?.dispose();
    _activeSession = null;
    _stateNotifier.dispose();
  }

  void _onAvailabilityChanged() {
    final currentOnline = _availabilityCache.isOnline;
    if (_lastKnownOnlineState != currentOnline) {
      _lastKnownOnlineState = currentOnline;
      // Invalidate cached session so the next turn configures the active model mode
      if (!isGenerating) {
        _invalidateSession();
      }
    }
  }

  void _invalidateSession() {
    final old = _activeSession;
    _activeSession = null;
    if (old != null) {
      unawaited(old.dispose());
    }
  }

  MentoraAgentSession _ensureSession(List<Message> history) {
    var session = _activeSession;
    if (session == null) {
      // Keep strictly the last 6 turns of conversation history for the new session
      final recentHistory = history.length > 6
          ? history.sublist(history.length - 6)
          : history;

      session = _agentProvider.createSession(
        topic: _topic,
        grade: _grade,
        initialMessages: recentHistory,
        tools: _tools,
        authorizeToolCall: _authorizeToolCall,
      );
      _activeSession = session;
    }
    return session;
  }

  List<Message> _convertHistoryToMessages(List<Map<String, dynamic>> raw) {
    if (raw.isEmpty) return const [];
    final messages = <Message>[];
    for (final entry in raw) {
      final text = (entry['text'] as String? ?? '').trim();
      if (text.isEmpty || text.startsWith('Welcome to Grade ') || text.startsWith('Thinking…')) {
        continue;
      }
      final isUser = entry['isUser'] == true;
      final timestamp = DateTime.now();
      if (isUser) {
        messages.add(UserMessage.text(text, timestamp: timestamp));
      } else {
        messages.add(
          AssistantMessage(
            content: [TextContent(text: text)],
            api: 'mentora-routed',
            provider: 'mentora',
            model: 'mentora-default',
            usage: Usage.zero,
            stopReason: StopReason.stop,
            timestamp: timestamp,
          ),
        );
      }
    }
    return messages;
  }
}
