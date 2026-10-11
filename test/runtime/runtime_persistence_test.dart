import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/measurements/runtime_measurement.dart';
import 'package:mentora/features/experiment/runtime/persistence/runtime_autosave_manager.dart';
import 'package:mentora/features/experiment/runtime/persistence/runtime_session_repository.dart';
import 'package:mentora/features/experiment/runtime/runtime_world.dart';

void main() {
  group('runtime persistence', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('runtime_sessions_');
    });

    tearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    test('saves and reloads variable and object state', () async {
      final repository = FileRuntimeSessionRepository(rootDirectory: directory);
      final world = _world(repository);
      world.variables.updateVariable('var_temperature', 75);
      world.objects.updateObjectState('slider_1', 'value', 75);

      final session = await world.saveSession(sessionId: 'session_temperature');
      final restored = _world(repository);
      await restored.restoreSession(session);
      await Future<void>.delayed(Duration.zero);

      expect(restored.variables.getValue('var_temperature'), 75);
      expect(restored.objects.getObjectState('slider_1')?.state['value'], 75);
      expect(restored.analytics.sessionsLoaded, 1);
    });

    test('restores measurement history for graph objects', () async {
      final repository = FileRuntimeSessionRepository(rootDirectory: directory);
      final world = _world(repository);
      for (var i = 0; i < 100; i++) {
        world.measurementStore.addMeasurement(
          RuntimeMeasurement(
            variableId: 'var_temperature',
            variableName: 'Temperature',
            value: i,
            timestamp: DateTime(2026, 6, 11, 12, 0, i % 60),
            runtimeSeconds: i.toDouble(),
            source: 'test',
          ),
        );
      }

      final session = await world.saveSession(sessionId: 'session_graph');
      final restored = _world(repository);
      await restored.restoreSession(session);

      expect(restored.measurementStore.sampleCount('var_temperature'), 100);
      expect(
        restored.measurementStore
            .getLatestMeasurement('var_temperature')
            ?.value,
        99,
      );
    });

    test('restores observation table rows', () async {
      final repository = FileRuntimeSessionRepository(rootDirectory: directory);
      final world = _world(repository);
      for (var i = 0; i < 10; i++) {
        world.recordObservation(source: 'test');
      }

      final session = await world.saveSession(
        sessionId: 'session_observations',
      );
      final restored = _world(repository);
      await restored.restoreSession(session);

      expect(restored.observationStore.rowCount, 10);
    });

    test('repository lists, recovers, and deletes sessions', () async {
      final repository = FileRuntimeSessionRepository(rootDirectory: directory);
      final world = _world(repository);
      await world.saveSession(sessionId: 'session_a');

      final sessions = await world.listSessions();
      expect(
        sessions.map((session) => session.sessionId),
        contains('session_a'),
      );

      final recovery = await world.recoverySession();
      expect(recovery?.sessionId, 'session_a');

      await world.deleteSession('session_a');
      expect(await world.listSessions(), isEmpty);
      expect(world.analytics.sessionsDeleted, 1);
    });

    test('autosave manager persists and increments autosave count', () async {
      final repository = FileRuntimeSessionRepository(rootDirectory: directory);
      final world = _world(repository);
      final autosave = RuntimeAutosaveManager(
        world: world,
        sessions: world.sessions,
        interval: const Duration(minutes: 1),
      );

      await autosave.saveNow();
      await autosave.saveNow();

      final session = await repository.load(autosave.sessionId!);
      expect(session?.autosaveCount, 2);
      expect(world.analytics.autosavesPerformed, 2);
    });
  });
}

RuntimeWorld _world(RuntimeSessionRepository repository) {
  final world = RuntimeWorld(sessionRepository: repository);
  world.initialize(
    variablesJson: [
      {
        'id': 'var_temperature',
        'name': 'Temperature',
        'type': 'numberInput',
        'value': 25,
      },
    ],
    objectsJson: [
      {
        'objectId': 'slider_1',
        'objectType': 'slider',
        'name': 'Temperature Slider',
        'state': {'label': 'Temperature', 'value': 25, 'min': 0, 'max': 100},
      },
      {
        'objectId': 'graph_1',
        'objectType': 'lineGraph',
        'name': 'Temperature Graph',
        'state': {'label': 'Temperature Graph'},
      },
      {
        'objectId': 'table_1',
        'objectType': 'table',
        'name': 'Observations',
        'state': {'label': 'Observations'},
      },
    ],
    rulesJson: const [],
    runtimeProfile: world.profile,
    curriculumMetadata: const {'id': 'temperature_experiment'},
  );
  world.clock.restore(elapsedTime: 12.5, running: false);
  return world;
}
