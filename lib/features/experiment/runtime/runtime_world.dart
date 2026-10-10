import 'dart:async';

import 'bindings/runtime_binding_engine.dart';
import 'bindings/runtime_binding_registry.dart';
import 'experiment_state/runtime_experiment_snapshot.dart';
import 'experiment_state/runtime_experiment_state_manager.dart';
import 'interactions/runtime_interaction_bus.dart';
import 'interactions/runtime_object_variable_adapter.dart';
import 'measurements/runtime_measurement_collector.dart';
import 'measurements/runtime_measurement_store.dart';
import 'objects/behavior/runtime_object_behavior_registry.dart';
import 'objects/renderers/runtime_object_renderer_registry.dart';
import 'objects/runtime_object_lifecycle_manager.dart';
import 'objects/schema/runtime_object_schema_registry.dart';
import 'observations/runtime_observation.dart';
import 'observations/runtime_observation_exporter.dart';
import 'observations/runtime_observation_scheduler.dart';
import 'observations/runtime_observation_store.dart';
import 'persistence/runtime_session.dart';
import 'persistence/runtime_session_manager.dart';
import 'persistence/runtime_session_repository.dart';
import 'variable_store.dart';
import 'object_registry.dart';
import 'rule_engine.dart';
import 'runtime_event_bus.dart';
import 'runtime_event.dart';
import 'simulation_clock.dart';
import 'runtime_analytics.dart';
import 'runtime_profiles.dart';
import 'sensors/runtime_sensor_manager.dart';
import 'simulation/animations/runtime_animation_engine.dart';
import 'simulation/bindings/runtime_visual_binding_engine.dart';
import 'simulation/canvas/runtime_simulation_canvas.dart';
import 'variables/runtime_variable_executor.dart';
import 'visual_templates/registry/runtime_visual_template_registry.dart';
import 'visual_templates/runtime/runtime_visual_template_engine.dart';
import '../visual_presets/composer/simulation_scene_composer.dart';
import '../visual_presets/registry/visual_preset_registry.dart';
import '../visualization_first/runtime/runtime_visualization_state.dart';
import '../visualization_first/runtime/visualization_runtime_coordinator.dart';

/// Canonical experiment runtime (Stack A). Stack B
/// (`BaseExperimentRuntime` shells) is deprecated — route all new code here.
/// Physics (Forge2D via `ExperimentFlameGame`) must only load when
/// [RuntimeProfileManager.requiresPhysicsEngine] is true; see
/// `RuntimePhysicsGate.shouldUsePhysics` in `runtime_profiles.dart`.
/// Lifecycle mirrors `ExperimentRuntime` (start/pause/resume/stop + [exportResults]).
class RuntimeWorld {
  late final VariableStore variables;
  late final RuntimeExperimentStateManager experimentState;
  late final ObjectRegistry objects;
  late final RuntimeObjectSchemaRegistry objectSchemas;
  late final RuntimeObjectBehaviorRegistry objectBehaviors;
  late final RuntimeObjectRendererRegistry objectRenderers;
  late final RuntimeObjectLifecycleManager objectLifecycle;
  late final RuntimeBindingRegistry bindings;
  late final RuntimeBindingEngine bindingEngine;
  late final RuntimeMeasurementStore measurementStore;
  late final RuntimeMeasurementCollector measurementCollector;
  late final RuntimeObservationStore observationStore;
  late final RuntimeObservationScheduler observationScheduler;
  late final RuntimeObservationExporter observationExporter;
  late final RuntimeInteractionBus interactionBus;
  late final RuntimeObjectVariableAdapter objectVariableAdapter;
  late final RuntimeVariableExecutor variableExecutor;
  late final RuntimeSensorManager sensors;
  late final RuntimeSimulationCanvas simulationCanvas;
  late final RuntimeVisualBindingEngine visualBindings;
  late final RuntimeAnimationEngine animationEngine;
  late final RuntimeVisualTemplateRegistry visualTemplateRegistry;
  late final RuntimeVisualTemplateEngine visualTemplates;
  late final VisualPresetRegistry visualPresetRegistry;
  late final SimulationSceneComposer sceneComposer;
  late final RuntimeSessionManager sessions;
  late final VisualizationRuntimeCoordinator visualizationRuntime;
  late final RuleEngine rules;
  late final RuntimeEventBus eventBus;
  late final SimulationClock clock;
  late final RuntimeAnalytics analytics;

  RuntimeProfile profile = RuntimeProfile.general;
  Map<String, dynamic> metadata = {};
  RuntimeVisualizationState? visualizationState;
  double _visualElapsed = 0;

  RuntimeWorld({RuntimeSessionRepository? sessionRepository}) {
    eventBus = RuntimeEventBus();
    experimentState = RuntimeExperimentStateManager(eventBus: eventBus)
      ..attach();
    variables = VariableStore(eventBus: eventBus);
    objects = ObjectRegistry();
    objectSchemas = RuntimeObjectSchemaRegistry();
    objectBehaviors = RuntimeObjectBehaviorRegistry();
    objectRenderers = RuntimeObjectRendererRegistry();
    objectLifecycle = RuntimeObjectLifecycleManager(
      schemaRegistry: objectSchemas,
      behaviorRegistry: objectBehaviors,
      rendererRegistry: objectRenderers,
      eventBus: eventBus,
    );
    objects.attachLifecycleManager(objectLifecycle);
    bindings = RuntimeBindingRegistry();
    measurementStore = RuntimeMeasurementStore();
    measurementCollector = RuntimeMeasurementCollector(
      variables: variables,
      eventBus: eventBus,
      store: measurementStore,
      runtimeSecondsProvider: () => clock.elapsedTime,
    );
    observationStore = RuntimeObservationStore();
    observationScheduler = RuntimeObservationScheduler(
      variables: variables,
      store: observationStore,
      eventBus: eventBus,
      runtimeSecondsProvider: () => clock.elapsedTime,
    );
    observationExporter = RuntimeObservationExporter(
      store: observationStore,
      eventBus: eventBus,
    );
    interactionBus = RuntimeInteractionBus(runtimeEventBus: eventBus);
    bindingEngine = RuntimeBindingEngine(
      variables: variables,
      objects: objects,
      registry: bindings,
      eventBus: eventBus,
    );
    objectVariableAdapter = RuntimeObjectVariableAdapter(
      variables: variables,
      objects: objects,
      bindings: bindings,
      interactionBus: interactionBus,
    );
    variableExecutor = RuntimeVariableExecutor(
      variables: variables,
      eventBus: eventBus,
    );
    sensors = RuntimeSensorManager(variables: variables, eventBus: eventBus);
    simulationCanvas = RuntimeSimulationCanvas(eventBus: eventBus);
    visualBindings = RuntimeVisualBindingEngine(
      eventBus: eventBus,
      canvas: simulationCanvas,
    );
    animationEngine = RuntimeAnimationEngine(
      canvas: simulationCanvas,
      eventBus: eventBus,
    );
    visualTemplateRegistry = RuntimeVisualTemplateRegistry();
    visualTemplates = RuntimeVisualTemplateEngine(
      world: this,
      registry: visualTemplateRegistry,
      eventBus: eventBus,
    );
    visualPresetRegistry = VisualPresetRegistry();
    sceneComposer = SimulationSceneComposer(
      registry: visualPresetRegistry,
      eventBus: eventBus,
    );
    sessions = RuntimeSessionManager(
      repository: sessionRepository ?? const FileRuntimeSessionRepository(),
      eventBus: eventBus,
    );
    visualizationRuntime = VisualizationRuntimeCoordinator(
      eventBus: eventBus,
      canvas: simulationCanvas,
      animationEngine: animationEngine,
    );
    clock = SimulationClock();
    analytics = RuntimeAnalytics();
    rules = RuleEngine(variables, eventBus, objects);
    analytics.attach(eventBus);
    eventBus.emit(
      RuntimeEvent(
        id: 'PresetsLoaded_${DateTime.now().microsecondsSinceEpoch}',
        timestamp: DateTime.now(),
        type: RuntimeEventType.custom,
        message: 'PresetsLoaded',
        metadata: {'count': visualPresetRegistry.allPresets().length},
      ),
    );
  }

  void initialize({
    required List<Map<String, dynamic>> variablesJson,
    required List<Map<String, dynamic>> objectsJson,
    required List<Map<String, dynamic>> rulesJson,
    required RuntimeProfile runtimeProfile,
    required Map<String, dynamic> curriculumMetadata,
  }) {
    profile = runtimeProfile;
    metadata = curriculumMetadata;
    variables.initialize(variablesJson);
    experimentState.initialize(
      experimentId: _experimentIdFromMetadata(curriculumMetadata),
      variables: variablesJson.length,
      objects: objectsJson.length,
      rules: rulesJson.length,
    );
    measurementCollector.initialize();
    variableExecutor.initialize();
    sensors.initialize();
    objects.initialize(objectsJson);
    bindingEngine.initialize(objectsJson);
    simulationCanvas.initialize(
      _simulationActors(objectsJson, curriculumMetadata),
    );
    visualBindings.initialize(_visualBindings(objectsJson, curriculumMetadata));
    animationEngine.initialize(_animations(curriculumMetadata));
    visualTemplates.initialize();
    _composeVisualPreset(curriculumMetadata);
    visualizationState = visualizationRuntime.initialize(curriculumMetadata);
    rules.initialize(rulesJson);
    clock.reset();
    analytics.recordLaunch();
  }

  void tick(double dt) {
    if (clock.isRunning) {
      clock.tick(dt);
      _visualElapsed = clock.elapsedTime;
      analytics.addTimeSpent(dt);
      experimentState.tick(dt);
      variableExecutor.tick(dt);
      observationScheduler.tick(dt);
      rules.evaluateContinuousRules(dt);
    } else {
      _visualElapsed += dt;
    }
    animationEngine.tick(
      dt,
      _visualElapsed,
    );
  }

  void start() {
    clock.start();
    experimentState.start();
    unawaited(sensors.start());
  }

  void pause() {
    clock.pause();
    experimentState.pause();
    sensors.pause();
  }

  void resume() {
    clock.start();
    experimentState.resume();
    unawaited(sensors.resume());
  }

  void stop() {
    clock.reset();
    experimentState.stop();
    unawaited(sensors.stop());
  }

  void complete() {
    experimentState.complete();
  }

  void fail([String? reason]) {
    experimentState.fail(reason);
  }

  RuntimeObservation recordObservation({String source = 'manual'}) {
    return observationScheduler.recordObservation(source: source);
  }

  RuntimeExperimentSnapshot createSnapshot() {
    return RuntimeExperimentSnapshot(
      variables: variables.allRuntimeVariables,
      objectStates: objects.allObjectStates,
      measurementsCount: measurementStore.trackedVariableIds.fold<int>(
        0,
        (count, variableId) => count + measurementStore.sampleCount(variableId),
      ),
      observationsCount: observationStore.rowCount,
      state: experimentState.state,
    );
  }

  Future<RuntimeSession> saveSession({String? sessionId}) {
    return sessions.save(this, sessionId: sessionId);
  }

  Future<void> restoreSession(RuntimeSession session) {
    return sessions.restore(this, session);
  }

  Future<void> restoreSessionById(String sessionId) async {
    final session = await sessions.load(sessionId);
    if (session != null) await restoreSession(session);
  }

  Future<void> deleteSession(String sessionId) {
    return sessions.delete(
      sessionId,
      experimentId: experimentState.state.experimentId,
    );
  }

  Future<List<RuntimeSession>> listSessions() {
    return sessions.list(experimentId: experimentState.state.experimentId);
  }

  Future<RuntimeSession?> recoverySession() {
    return sessions.recoveryForExperiment(experimentState.state.experimentId);
  }

  /// Export a portable snapshot (observations + measurements + state).
  Future<Map<String, dynamic>> exportResults() async {
    final snapshot = createSnapshot();
    return {
      'experimentId': experimentState.state.experimentId,
      'variables': snapshot.variables,
      'objectStates': snapshot.objectStates,
      'measurementsCount': snapshot.measurementsCount,
      'observationsCount': snapshot.observationsCount,
      'status': snapshot.state.status.name,
      'profile': profile.name,
    };
  }

  void dispose() {
    analytics.dispose();
    experimentState.dispose();
    rules.dispose();
    variableExecutor.dispose();
    unawaited(sensors.dispose());
    measurementCollector.dispose();
    objectLifecycle.dispose();
    visualTemplates.dispose();
    visualizationRuntime.dispose();
    animationEngine.dispose();
    visualBindings.dispose();
    simulationCanvas.dispose();
    bindingEngine.dispose();
    interactionBus.dispose();
    eventBus.dispose();
    variables.dispose();
    objects.dispose();
    clock.dispose();
  }

  String _experimentIdFromMetadata(Map<String, dynamic> metadata) {
    return metadata['id']?.toString() ??
        metadata['sceneId']?.toString() ??
        metadata['title']?.toString() ??
        metadata['name']?.toString() ??
        'experiment';
  }

  List<Map<String, dynamic>> _simulationActors(
    List<Map<String, dynamic>> objectsJson,
    Map<String, dynamic> metadata,
  ) {
    final explicitActors = _listFromMetadata(metadata, const [
      'simulationActors',
      'actors',
    ]);
    if (explicitActors.isNotEmpty) return explicitActors;
    return objectsJson
        .where((object) {
          final type = object['type']?.toString();
          final actor = object['actor'];
          return actor is Map || _genericActorTypes.contains(type);
        })
        .map((object) {
          final actor = object['actor'] is Map
              ? Map<String, dynamic>.from(object['actor'] as Map)
              : <String, dynamic>{};
          return {
            'id': actor['id'] ?? object['id'],
            'type': actor['type'] ?? object['type'],
            ...actor,
          };
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _visualBindings(
    List<Map<String, dynamic>> objectsJson,
    Map<String, dynamic> metadata,
  ) {
    final explicitBindings = _listFromMetadata(metadata, const [
      'visualBindings',
      'simulationBindings',
    ]);
    final objectBindings = <Map<String, dynamic>>[];
    for (final object in objectsJson) {
      final bindings = object['visualBindings'];
      if (bindings is List) {
        for (final binding in bindings) {
          if (binding is Map) {
            objectBindings.add({
              'actorId': object['id'],
              ...Map<String, dynamic>.from(binding),
            });
          }
        }
      }
    }
    return [...explicitBindings, ...objectBindings];
  }

  List<Map<String, dynamic>> _animations(Map<String, dynamic> metadata) {
    return _listFromMetadata(metadata, const [
      'animations',
      'simulationAnimations',
    ]);
  }

  List<Map<String, dynamic>> _listFromMetadata(
    Map<String, dynamic> metadata,
    List<String> keys,
  ) {
    for (final key in keys) {
      final raw = metadata[key];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList(growable: false);
      }
    }
    return const [];
  }

  static const _genericActorTypes = {
    'circle',
    'rectangle',
    'line',
    'arrow',
    'text',
    'image',
    'particle',
  };

  void _composeVisualPreset(Map<String, dynamic> metadata) {
    final presetId = metadata['visualPreset']?.toString();
    if (presetId == null || presetId.isEmpty) return;
    sceneComposer.composePresetById(presetId, this);
  }
}
