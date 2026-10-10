// ignore_for_file: avoid_print

import 'dart:async';
import 'package:uuid/uuid.dart';

import '../application/experiment_execution_plan.dart';
import 'runtime_event.dart';
import 'runtime_metrics.dart';
import 'runtime_session.dart';

/// DEPRECATED Stack B shim. Canonical runtime is [RuntimeWorld].
/// Kept only for the (currently unreachable) [ExperimentExecutionOrchestrator];
/// do not use in new code.
@deprecated
abstract class BaseExperimentRuntime {
  final ExperimentExecutionPlan plan;
  
  late final RuntimeSession session;
  late final RuntimeMetrics metrics;
  
  final StreamController<RuntimeEvent> _eventController = StreamController<RuntimeEvent>.broadcast();
  Stream<RuntimeEvent> get eventStream => _eventController.stream;

  final Uuid _uuid = const Uuid();

  BaseExperimentRuntime(this.plan) {
    print('[EXPERIMENT] RUNTIME_CREATED');
    print('[EXPERIMENT] MODE=${plan.selectedMode.name}');
  }

  Future<void> initialize() async {
    metrics = RuntimeMetrics();
    session = RuntimeSession(
      sessionId: _uuid.v4(),
      experimentId: plan.experimentId,
      executionMode: plan.selectedMode,
      metrics: metrics,
    );
    
    print('[EXPERIMENT] SESSION_CREATED');
    emitEvent(RuntimeEventType.sessionCreated, 'Session initialized.');
  }

  Future<void> start() async {
    session.start();
    print('[EXPERIMENT] SESSION_STARTED');
    emitEvent(RuntimeEventType.sessionStarted, 'Session started.');
  }

  Future<void> pause() async {
    session.pause();
    print('[EXPERIMENT] SESSION_PAUSED');
    emitEvent(RuntimeEventType.sessionPaused, 'Session paused.');
  }

  Future<void> resume() async {
    session.resume();
    print('[EXPERIMENT] SESSION_RESUMED');
    emitEvent(RuntimeEventType.sessionResumed, 'Session resumed.');
  }

  Future<void> stop() async {
    session.stop();
    print('[EXPERIMENT] SESSION_STOPPED');
    emitEvent(RuntimeEventType.sessionStopped, 'Session stopped.');
    
    print('[EXPERIMENT] SESSION_COMPLETED');
    emitEvent(RuntimeEventType.sessionCompleted, 'Session completed.');
    
    metrics.complete();
  }

  Future<void> dispose() async {
    print('[EXPERIMENT] RUNTIME_DISPOSED');
    await _eventController.close();
  }

  void emitEvent(RuntimeEventType type, String message, {Map<String, dynamic>? metadata}) {
    final event = RuntimeEvent(
      id: _uuid.v4(),
      timestamp: DateTime.now(),
      type: type,
      message: message,
      metadata: metadata,
    );
    session.events.add(event);
    _eventController.add(event);
    recordMetric(type);
  }

  void recordMetric(RuntimeEventType type) {
    metrics.recordEvent();
    if (type == RuntimeEventType.error) {
      metrics.recordError();
    } else if (type == RuntimeEventType.warning) {
      metrics.recordWarning();
    } else if (type == RuntimeEventType.measurementReceived) {
      metrics.recordMeasurement();
    }
  }
}
