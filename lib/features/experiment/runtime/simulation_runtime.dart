// ignore_for_file: avoid_print

import 'dart:async';
import 'base_experiment_runtime.dart';
import 'runtime_event.dart';
import 'playground/engine/simulation_playground_engine.dart';

@deprecated
class SimulationRuntime extends BaseExperimentRuntime {
  final SimulationPlaygroundEngine _playgroundEngine = SimulationPlaygroundEngine();
  StreamSubscription? _playgroundSubscription;

  @deprecated
  SimulationRuntime(super.plan);

  @override
  Future<void> initialize() async {
    await super.initialize();
    await _playgroundEngine.initialize();

    // Use the injected scene definition if available
    if (plan.sceneDefinition != null) {
      // SimulationPlaygroundEngine doesn't have loadSceneFromModel yet, we need to add it, 
      // or we can convert the model back to json, but wait... 
      // The prompt says: "Inject into SimulationPlaygroundEngine".
      // Let's modify SimulationPlaygroundEngine to accept the PlaygroundScene directly.
      await _playgroundEngine.loadSceneModel(plan.sceneDefinition!);
    } else {
      // Fallback to empty scene if not provided
      final mockScene = {
        'sceneId': plan.experimentId,
        'name': 'Simulation Scene',
        'objects': [],
        'variables': [],
        'rules': []
      };
      await _playgroundEngine.loadScene(mockScene);
    }

    _playgroundSubscription = _playgroundEngine.eventStream.listen((event) {
      emitEvent(
        RuntimeEventType.custom,
        'Playground event: ${event.eventType.name}',
        metadata: {
          'playgroundEventId': event.eventId,
          'playgroundEventType': event.eventType.name,
          'payload': event.payload,
          'timestamp': event.timestamp.toIso8601String(),
        },
      );
    });
  }

  @override
  Future<void> start() async {
    await super.start();
    await _playgroundEngine.start();
  }

  @override
  Future<void> pause() async {
    await super.pause();
    await _playgroundEngine.pause();
  }

  @override
  Future<void> resume() async {
    await super.resume();
    await _playgroundEngine.resume();
  }

  @override
  Future<void> stop() async {
    await _playgroundEngine.stop();
    await super.stop();
  }

  @override
  Future<void> dispose() async {
    await _playgroundSubscription?.cancel();
    await _playgroundEngine.dispose();
    await super.dispose();
  }
}
