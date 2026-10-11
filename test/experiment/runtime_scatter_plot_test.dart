import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/engine/display_object_components.dart';
import 'package:mentora/features/experiment/runtime/measurements/runtime_measurement.dart';
import 'package:mentora/features/experiment/runtime/measurements/runtime_measurement_store.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_layout.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_state.dart';
import 'package:mentora/features/experiment/runtime/objects/behavior/runtime_object_behavior_registry.dart';
import 'package:mentora/features/experiment/runtime/objects/renderers/runtime_object_renderer_registry.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';
import 'package:mentora/features/experiment/runtime/runtime_object_factory.dart';
import 'package:mentora/features/experiment/runtime/runtime_validator.dart';
import 'package:mentora/features/experiment/runtime/scatter/scatter_plot_behavior.dart';
import 'package:mentora/features/experiment/runtime/scatter/scatter_plot_renderer.dart';
import 'package:mentora/features/experiment/runtime/scatter/scatter_plot_state.dart';

void main() {
  group('runtime scatter plot', () {
    test('paired measurements create scatter points', () {
      final store = RuntimeMeasurementStore();
      _addMeasurement(store, 'var_time', 'Elapsed Time', 1, 1);
      _addMeasurement(store, 'var_time', 'Elapsed Time', 2, 2);
      _addMeasurement(store, 'var_time', 'Elapsed Time', 3, 3);
      _addMeasurement(store, 'var_distance', 'Distance', 1, 5);
      _addMeasurement(store, 'var_distance', 'Distance', 2, 10);
      _addMeasurement(store, 'var_distance', 'Distance', 3, 15);

      final state = ScatterPlotBehavior(
        measurementStore: store,
      ).buildState(xVariableId: 'var_time', yVariableId: 'var_distance');

      expect(state.pointCount, 3);
      expect(state.points.map((point) => point.x), [1, 2, 3]);
      expect(state.points.map((point) => point.y), [5, 10, 15]);
    });

    test('auto scaling calculates x and y ranges', () {
      final store = RuntimeMeasurementStore();
      for (final value in [2, 4, 6, 8]) {
        _addMeasurement(store, 'var_force', 'Force', value.toDouble(), value);
      }
      for (final value in [1, 3, 5, 7]) {
        _addMeasurement(
          store,
          'var_accel',
          'Acceleration',
          value.toDouble(),
          value,
        );
      }

      final state = ScatterPlotBehavior(
        measurementStore: store,
      ).buildState(xVariableId: 'var_accel', yVariableId: 'var_force');

      expect(state.minX, 1);
      expect(state.maxX, 7);
      expect(state.minY, 2);
      expect(state.maxY, 8);
    });

    test('scatter plot uses latest 100 point window', () {
      final store = RuntimeMeasurementStore(historyLimit: 500);
      for (var i = 1; i <= 150; i++) {
        _addMeasurement(
          store,
          'var_temperature',
          'Temperature',
          i.toDouble(),
          i,
        );
        _addMeasurement(store, 'var_pressure', 'Pressure', i.toDouble(), i * 2);
      }

      final state = ScatterPlotBehavior(
        measurementStore: store,
      ).buildState(xVariableId: 'var_temperature', yVariableId: 'var_pressure');

      expect(state.pointCount, 100);
      expect(state.points.first.x, 51);
      expect(state.points.first.y, 102);
      expect(state.points.last.x, 150);
      expect(state.points.last.y, 300);
    });

    test('pairs only complete x/y measurement samples', () {
      final store = RuntimeMeasurementStore();
      _addMeasurement(store, 'var_x', 'X', 1, 1);
      _addMeasurement(store, 'var_x', 'X', 2, 2);
      _addMeasurement(store, 'var_x', 'X', 3, 3);
      _addMeasurement(store, 'var_y', 'Y', 1, 10);

      final state = ScatterPlotBehavior(
        measurementStore: store,
      ).buildState(xVariableId: 'var_x', yVariableId: 'var_y');

      expect(state.pointCount, 1);
      expect(state.points.single.x, 3);
      expect(state.points.single.y, 10);
    });

    test('renderer supports no data and plotted point state', () {
      final renderer = ScatterPlotRenderer()
        ..initialize()
        ..updateScatterState(ScatterPlotState.empty())
        ..update(_objectState());

      renderer.render(_canvas(), const ui.Size(240, 140));
      expect(renderer.scatterState.pointCount, 0);
      expect(renderer.lastRenderTime, isNotNull);

      renderer.updateScatterState(
        ScatterPlotState(
          points: const [],
          minX: 0,
          maxX: 10,
          minY: 0,
          maxY: 20,
          updatedAt: DateTime.now(),
        ),
      );
      renderer.render(_canvas(), const ui.Size(240, 140));
      expect(renderer.lastScatterRenderTime, isNotNull);
    });

    test('registries and factory support scatterPlot', () {
      RuntimeObjectFactory.registerDefaults();

      expect(
        RuntimeObjectBehaviorRegistry().containsBehavior('scatterPlot'),
        isTrue,
      );
      expect(
        RuntimeObjectRendererRegistry().containsRenderer('scatterPlot'),
        isTrue,
      );
      expect(
        RuntimeObjectFactory.availableCapabilities.any(
          (definition) => definition.type == 'scatterPlot',
        ),
        isTrue,
      );
    });

    test('validation requires x and y variables to exist', () {
      expect(
        () => RuntimeLoader.loadFromManifest(
          _manifest(
            variables: [
              _variable('var_time', 'Elapsed Time', 'elapsedTime', 0),
            ],
            objects: [
              {
                'objectId': 'scatter_distance',
                'objectType': 'scatterPlot',
                'properties': {
                  'xVariable': 'var_time',
                  'yVariable': 'var_missing',
                },
              },
            ],
          ),
        ),
        throwsA(isA<RuntimeValidationException>()),
      );
    });

    test('runtime loader accepts scene-shaped payloads', () {
      final world = RuntimeLoader.loadFromManifest({
        'sceneId': 'scene_shaped_scatter',
        'name': 'Scene Shaped Scatter',
        'variables': [_variable('var_x', 'X', 'numberInput', 0)],
        'objects': const [],
        'rules': const [],
      });

      expect(world.experimentState.state.experimentId, 'scene_shaped_scatter');
      world.dispose();
    });

    test('runtime component updates renderer and scatter analytics', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_temperature', 'Temperature', 'numberInput', 20),
            _variable('var_pressure', 'Pressure', 'numberInput', 100),
          ],
          objects: [
            {
              'objectId': 'scatter_pressure',
              'name': 'Temperature vs Pressure',
              'objectType': 'scatterPlot',
              'properties': {
                'xVariable': 'var_temperature',
                'yVariable': 'var_pressure',
                'width': 240,
                'height': 140,
              },
            },
          ],
        ),
      );

      world.variables.updateVariable('var_temperature', 25, source: 'test');
      world.variables.updateVariable('var_pressure', 105, source: 'test');
      world.variables.updateVariable('var_temperature', 30, source: 'test');
      world.variables.updateVariable('var_pressure', 110, source: 'test');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final component = RuntimeDisplayObjectComponent(
        world.objects.allObjects.single,
        world,
      );
      component.update(0);
      component.render(_canvas());
      await Future<void>.delayed(Duration.zero);

      final renderer = world.objectLifecycle.getRenderer('scatter_pressure');
      expect(renderer, isA<ScatterPlotRenderer>());
      final scatterState = (renderer as ScatterPlotRenderer).scatterState;
      expect(scatterState.pointCount, 2);
      expect(scatterState.points.last.x, 30);
      expect(scatterState.points.last.y, 110);
      expect(world.analytics.scatterPlotUpdates, 1);
      expect(world.analytics.scatterPlotsRendered, 1);
      expect(world.analytics.scatterPointsProcessed, 2);

      world.dispose();
    });
  });
}

void _addMeasurement(
  RuntimeMeasurementStore store,
  String variableId,
  String variableName,
  double runtimeSeconds,
  dynamic value,
) {
  store.addMeasurement(
    RuntimeMeasurement(
      variableId: variableId,
      variableName: variableName,
      value: value,
      timestamp: DateTime.now(),
      runtimeSeconds: runtimeSeconds,
      source: 'test',
    ),
  );
}

Map<String, dynamic> _manifest({
  required List<Map<String, dynamic>> variables,
  List<Map<String, dynamic>> objects = const [],
}) {
  return {
    'metadata': {'title': 'Scatter Plot Runtime Test'},
    'scene': {'variables': variables, 'objects': objects, 'rules': []},
  };
}

Map<String, dynamic> _variable(
  String id,
  String name,
  String type,
  dynamic value,
) {
  return {'id': id, 'name': name, 'type': type, 'value': value};
}

RuntimeObjectState _objectState() {
  return RuntimeObjectState(
    objectId: 'scatter_test',
    objectType: 'scatterPlot',
    state: const {},
    visible: true,
    updatedAt: DateTime.now(),
    layout: const RuntimeObjectLayout(
      x: 0,
      y: 0,
      width: 240,
      height: 140,
      alignment: 'center',
    ),
  );
}

ui.Canvas _canvas() {
  return ui.Canvas(ui.PictureRecorder());
}
