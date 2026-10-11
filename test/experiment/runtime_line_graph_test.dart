import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/graphs/line_graph_behavior.dart';
import 'package:mentora/features/experiment/runtime/graphs/line_graph_renderer.dart';
import 'package:mentora/features/experiment/runtime/graphs/line_graph_state.dart';
import 'package:mentora/features/experiment/runtime/measurements/runtime_measurement.dart';
import 'package:mentora/features/experiment/runtime/measurements/runtime_measurement_store.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_layout.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_state.dart';
import 'package:mentora/features/experiment/runtime/objects/renderers/runtime_object_renderer_registry.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  group('runtime line graph', () {
    test('measurements convert to graph points', () {
      final store = RuntimeMeasurementStore();
      _addMeasurement(store, 'var_temperature', 'Temperature', 0, 25);
      _addMeasurement(store, 'var_temperature', 'Temperature', 1, 30);
      _addMeasurement(store, 'var_temperature', 'Temperature', 2, 35);

      final state = LineGraphBehavior(
        measurementStore: store,
      ).buildStateForVariable('var_temperature');

      expect(state.sampleCount, 3);
      expect(state.points.map((point) => point.x), [0, 1, 2]);
      expect(state.points.map((point) => point.y), [25, 30, 35]);
    });

    test('graph uses latest 100 sample window', () {
      final store = RuntimeMeasurementStore(historyLimit: 500);
      for (var i = 1; i <= 150; i++) {
        _addMeasurement(
          store,
          'var_temperature',
          'Temperature',
          i.toDouble(),
          i,
        );
      }

      final state = LineGraphBehavior(
        measurementStore: store,
      ).buildStateForVariable('var_temperature');

      expect(state.sampleCount, 100);
      expect(state.points.first.y, 51);
      expect(state.points.last.y, 150);
    });

    test('auto scaling calculates min and max values', () {
      final store = RuntimeMeasurementStore();
      for (final value in [20, 30, 40, 80]) {
        _addMeasurement(
          store,
          'var_temperature',
          'Temperature',
          value.toDouble(),
          value,
        );
      }

      final state = LineGraphBehavior(
        measurementStore: store,
      ).buildStateForVariable('var_temperature');

      expect(state.minY, 20);
      expect(state.maxY, 80);
      expect(state.minX, 20);
      expect(state.maxX, 80);
    });

    test(
      'computed variable graph state uses computed measurement history',
      () async {
        final world = RuntimeLoader.loadFromManifest(
          _manifest(
            variables: [
              _variable('var_mass', 'Mass', 'numberInput', 2),
              _variable('var_accel', 'Acceleration', 'numberInput', 5),
              _variable('var_force', 'Force', 'force', 0, {
                'massVariable': 'var_mass',
                'accelerationVariable': 'var_accel',
              }),
            ],
            objects: [
              {
                'objectId': 'graph_force',
                'name': 'Force Graph',
                'objectType': 'lineGraph',
                'properties': {'linked_variable': 'var_force'},
              },
            ],
          ),
        );

        world.variables.updateVariable('var_mass', 3, source: 'test');
        world.variables.updateVariable('var_mass', 4, source: 'test');
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final state = LineGraphBehavior(
          measurementStore: world.measurementStore,
        ).buildStateForVariable('var_force');

        expect(state.sampleCount, greaterThanOrEqualTo(2));
        expect(state.points.last.y, 20);
        expect(
          RuntimeObjectRendererRegistry().containsRenderer('lineGraph'),
          isTrue,
        );

        world.dispose();
      },
    );

    test('renderer supports no data state', () {
      final renderer = LineGraphRenderer()
        ..initialize()
        ..updateGraphState(const LineGraphState.empty())
        ..update(
          RuntimeObjectState(
            objectId: 'graph_temperature',
            objectType: 'lineGraph',
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
          ),
        );

      renderer.render(_canvas(), const ui.Size(240, 140));

      expect(renderer.graphState.sampleCount, 0);
      expect(renderer.lastRenderTime, isNotNull);
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
    'metadata': {'title': 'Line Graph Runtime Test'},
    'scene': {'variables': variables, 'objects': objects, 'rules': []},
  };
}

Map<String, dynamic> _variable(
  String id,
  String name,
  String type,
  dynamic value, [
  Map<String, dynamic>? metadata,
]) {
  return {
    'id': id,
    'name': name,
    'type': type,
    'value': value,
    if (metadata != null) ...metadata,
  };
}

ui.Canvas _canvas() {
  return ui.Canvas(ui.PictureRecorder());
}
