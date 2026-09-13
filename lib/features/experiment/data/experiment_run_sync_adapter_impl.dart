// ignore_for_file: avoid_print

import 'dart:async';
import 'package:uuid/uuid.dart';

import '../application/orchestrator/experiment_run_sync_adapter.dart';
import 'models/experiment_run_dto.dart';
import 'models/experiment_event_dto.dart';
import 'experiment_sync_queue.dart';
import 'pending_experiment_sync.dart';

class ExperimentRunSyncAdapterImpl implements ExperimentRunSyncAdapter {
  final ExperimentSyncQueue _queue;
  final Uuid _uuid = const Uuid();

  final Map<String, List<ExperimentEventDto>> _eventBatches = {};
  final Map<String, Timer> _batchTimers = {};

  static const int maxBatchSize = 25;
  static const Duration maxBatchInterval = Duration(seconds: 5);

  ExperimentRunSyncAdapterImpl(this._queue);

  @override
  Future<void> createRun(ExperimentRunDto run) async {
    print('[EXPERIMENT_SYNC] RUN_CREATED runId=${run.runId}');
    _queue.enqueue(PendingExperimentSync(
      id: _uuid.v4(),
      operationType: SyncOperationType.createRun,
      runDto: run,
    ));
  }

  @override
  Future<void> appendEvent(String runId, ExperimentEventDto event) async {
    _eventBatches.putIfAbsent(runId, () => []);
    _eventBatches[runId]!.add(event);

    _checkBatch(runId);
  }

  void _checkBatch(String runId) {
    final batch = _eventBatches[runId];
    if (batch == null || batch.isEmpty) return;

    if (batch.length >= maxBatchSize) {
      _flushBatch(runId);
    } else {
      _batchTimers[runId]?.cancel();
      _batchTimers[runId] = Timer(maxBatchInterval, () => _flushBatch(runId));
    }
  }

  void _flushBatch(String runId) {
    _batchTimers[runId]?.cancel();
    _batchTimers.remove(runId);
    final batch = _eventBatches[runId];
    if (batch == null || batch.isEmpty) return;

    final eventsToSync = List<ExperimentEventDto>.from(batch);
    batch.clear();

    print('[EXPERIMENT_SYNC] EVENT_BATCH_SENT count=${eventsToSync.length} runId=$runId');
    _queue.enqueue(PendingExperimentSync(
      id: _uuid.v4(),
      operationType: SyncOperationType.appendEvents,
      runId: runId,
      events: eventsToSync,
    ));
  }

  @override
  Future<void> completeRun(String runId, Map<String, dynamic> metrics) async {
    // Flush any pending events first
    _flushBatch(runId);

    final expId = (metrics['experimentId'] ?? metrics['experiment_id'] ?? 'default_exp').toString();
    final stdId = (metrics['studentId'] ?? metrics['student_id'] ?? 'current_student').toString();

    print('[EXPERIMENT_SYNC] RUN_COMPLETED runId=$runId expId=$expId stdId=$stdId');
    _queue.enqueue(PendingExperimentSync(
      id: _uuid.v4(),
      operationType: SyncOperationType.completeRun,
      runId: runId,
      runDto: ExperimentRunDto(
        runId: runId,
        experimentId: expId,
        studentId: stdId,
        executionMode: metrics['executionMode']?.toString() ?? 'guided',
        startedAt: DateTime.now(),
        status: 'completed',
        metrics: metrics,
      ),
    ));
  }

  @override
  Future<void> syncMetrics() async {
    print('[EXPERIMENT_SYNC] SYNC_METRICS - Flushed local queues');
    await _queue.flush();
  }
}
