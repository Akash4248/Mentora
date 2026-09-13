// ignore_for_file: avoid_print

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../domain/models/experiment_models.dart';
import '../../application/orchestrator/experiment_execution_state.dart';
import '../../runtime/runtime_world.dart';
import '../../runtime/runtime_loader.dart';
import '../../builder/templates/experiment_templates.dart';
import '../../runtime/runtime_event.dart';

class RuntimeUiError {
  final String title;
  final String detail;
  final DateTime timestamp;

  const RuntimeUiError({
    required this.title,
    required this.detail,
    required this.timestamp,
  });
}

class ExperimentPlayerController extends ChangeNotifier {
  RuntimeWorld? _world;
  RuntimeWorld? get world => _world;

  Map<String, dynamic> _rawManifestData = {};
  Map<String, dynamic> get rawManifestData => _rawManifestData;

  ExperimentExecutionState _state = ExperimentExecutionState.idle;
  ExperimentExecutionState get state => _state;

  final List<RuntimeEvent> _events = [];
  List<RuntimeEvent> get events => List.unmodifiable(_events);

  RuntimeUiError? _lastError;
  RuntimeUiError? get lastError => _lastError;

  StreamSubscription<RuntimeEvent>? _eventSubscription;
  bool _disposed = false;

  Future<void> prepare(
    ExperimentManifest manifest, {
    Map<String, dynamic>? payload,
  }) async {
    try {
      _lastError = null;
      _state = ExperimentExecutionState.preparing;
      notifyListeners();

      print('[EXPERIMENT] LOADING_LOCAL_MANIFEST');
      Map<String, dynamic> templateData = {};

      if (payload != null && payload.isNotEmpty) {
        if (!payload.containsKey('scene')) {
          templateData = {'scene': payload};
        } else {
          templateData = payload;
        }
      } else {
        // Look up template data to load scene details
        final match = ExperimentTemplates.allTemplates.firstWhere(
          (t) =>
              (t['scene']?['sceneId'] == manifest.id) ||
              (t['metadata']?['title'] == manifest.title) ||
              (manifest.id.contains(
                t['scene']?['sceneId']?.split('_')[0] ?? '',
              )),
          orElse: () => <String, dynamic>{},
        );

        if (match.isNotEmpty) {
          templateData = match;
        } else {
          templateData = manifest.toJson();
        }
      }

      _rawManifestData = templateData;
      _world = RuntimeLoader.loadFromManifest(templateData);

      if (_disposed) return;
      _state = ExperimentExecutionState.starting;

      _eventSubscription = _world!.eventBus.stream.listen((event) {
        _events.insert(0, event);
        if (_events.length > 100) _events.removeLast();
        if (!_disposed) notifyListeners();
      });
      _emitLifecycleEvent(RuntimeEventType.sessionCreated, 'Runtime Prepared');

      notifyListeners();
    } catch (e) {
      print('[EXPERIMENT_UI] PREPARE_ERROR error=$e');
      _lastError = RuntimeUiError(
        title: 'Experiment failed to start.',
        detail: _friendlyErrorDetail(e),
        timestamp: DateTime.now(),
      );
      _state = ExperimentExecutionState.failed;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> start() async {
    if (_world == null) {
      _lastError = RuntimeUiError(
        title: 'Experiment failed to start.',
        detail: 'Runtime was not initialized.',
        timestamp: DateTime.now(),
      );
      _state = ExperimentExecutionState.failed;
      if (!_disposed) notifyListeners();
      return;
    }
    print('[EXPERIMENT_UI] PLAYER_STARTED');
    _world?.start();
    _state = ExperimentExecutionState.running;
    if (!_disposed) notifyListeners();
  }

  Future<void> pause() async {
    if (_world == null) return;
    print('[EXPERIMENT_UI] PLAYER_PAUSED');
    _world?.pause();
    _state = ExperimentExecutionState.paused;
    if (!_disposed) notifyListeners();
  }

  Future<void> resume() async {
    if (_world == null) return;
    print('[EXPERIMENT_UI] PLAYER_RESUMED');
    _world?.resume();
    _state = ExperimentExecutionState.running;
    if (!_disposed) notifyListeners();
  }

  Future<void> stop() async {
    if (_world == null) return;
    print('[EXPERIMENT_UI] PLAYER_STOPPED');
    _world?.stop();
    _state = ExperimentExecutionState.completed;
    if (!_disposed) notifyListeners();
  }

  void _emitLifecycleEvent(RuntimeEventType type, String message) {
    _world?.eventBus.emit(
      RuntimeEvent(
        id: '${type.name}_${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        type: type,
        message: message,
      ),
    );
  }

  String _friendlyErrorDetail(Object error) {
    final raw = error.toString();
    if (raw.contains('not prepared') || raw.contains('not initialized')) {
      return 'Runtime was not initialized.';
    }
    if (raw.contains('Manifest must contain')) {
      return 'Manifest data is incomplete.';
    }
    if (raw.contains('undefined variable')) {
      return raw.replaceAll('RuntimeValidationException: ', '');
    }
    if (raw.contains('Circular dependency')) {
      return 'Rules contain a circular dependency.';
    }
    return raw.replaceAll('RuntimeValidationException: ', '');
  }

  @override
  void dispose() {
    _disposed = true;
    _eventSubscription?.cancel();
    _world?.dispose();
    super.dispose();
  }
}
