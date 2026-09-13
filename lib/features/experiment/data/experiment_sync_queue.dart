import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'pending_experiment_sync.dart';
import 'experiment_api_service.dart';

class ExperimentSyncQueue {
  final Queue<PendingExperimentSync> _queue = Queue<PendingExperimentSync>();
  final ExperimentApiService _apiService;
  bool _isFlushing = false;
  static const String _storageKey = 'mentora_pending_experiment_sync_queue_v1';

  ExperimentSyncQueue(this._apiService) {
    _loadPersistedQueue();
  }

  Future<void> _loadPersistedQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List list = jsonDecode(raw);
        for (final item in list) {
          _queue.add(PendingExperimentSync.fromJson(Map<String, dynamic>.from(item)));
        }
        print('[EXPERIMENT_SYNC] RESTORED_PERSISTED items=${_queue.length}');
        _attemptFlush();
      }
    } catch (e) {
      print('[EXPERIMENT_SYNC] LOAD_PERSISTED_FAILED error=$e');
    }
  }

  Future<void> _persistQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _queue.map((e) => e.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(list));
    } catch (e) {
      print('[EXPERIMENT_SYNC] PERSIST_FAILED error=$e');
    }
  }

  void enqueue(PendingExperimentSync syncOp) {
    _queue.add(syncOp);
    _persistQueue();
    print('[EXPERIMENT_SYNC] QUEUED_OFFLINE id=${syncOp.id} type=${syncOp.operationType.name}');
    _attemptFlush();
  }

  PendingExperimentSync? dequeue() {
    if (_queue.isEmpty) return null;
    final item = _queue.removeFirst();
    _persistQueue();
    return item;
  }

  void retry(PendingExperimentSync syncOp) {
    syncOp.retryCount++;
    _queue.addFirst(syncOp);
    _persistQueue();
  }

  Future<void> flush() async {
    await _attemptFlush();
  }

  Future<void> _attemptFlush() async {
    if (_isFlushing || _queue.isEmpty) return;
    _isFlushing = true;
    print('[EXPERIMENT_SYNC] FLUSH_START items=${_queue.length}');

    try {
      while (_queue.isNotEmpty) {
        final current = dequeue()!;
        try {
          switch (current.operationType) {
            case SyncOperationType.createRun:
              await _apiService.createRun(current.runDto!);
              break;
            case SyncOperationType.appendEvents:
              await _apiService.appendEvents(current.runId!, current.events!);
              break;
            case SyncOperationType.completeRun:
              await _apiService.completeRun(current.runId!, current.runDto!.metrics!);
              break;
          }
          print('[EXPERIMENT_SYNC] FLUSH_SUCCESS id=${current.id}');
        } catch (e) {
          print('[EXPERIMENT_SYNC] FLUSH_FAILED id=${current.id} retryCount=${current.retryCount} error=$e');
          if (current.retryCount < 3) {
            retry(current);
          } else {
            print('[EXPERIMENT_SYNC] MAX_RETRIES_REACHED dropping id=${current.id}');
          }
          // Stop flushing on network failure to maintain order
          break;
        }
      }
    } finally {
      _isFlushing = false;
    }
  }
}
