import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/engine/display_object_components.dart';
import 'package:mentora/features/experiment/runtime/measurements/runtime_measurement.dart';
import 'package:mentora/features/experiment/runtime/measurements/runtime_measurement_store.dart';
import 'package:mentora/features/experiment/runtime/objects/behavior/runtime_object_behavior_registry.dart';
import 'package:mentora/features/experiment/runtime/objects/renderers/runtime_object_renderer_registry.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';
import 'package:mentora/features/experiment/runtime/runtime_object_factory.dart';
import 'package:mentora/features/experiment/runtime/scientific/bar_chart_behavior.dart';
import 'package:mentora/features/experiment/runtime/scientific/bar_chart_renderer.dart';
import 'package:mentora/features/experiment/runtime/scientific/oscilloscope_behavior.dart';
import 'package:mentora/features/experiment/runtime/scientific/oscilloscope_renderer.dart';
import 'package:mentora/features/experiment/runtime/scientific/runtime_multi_binding.dart';
import 'package:mentora/features/experiment/runtime/scientific/spectrum_analyzer_behavior.dart';
import 'package:mentora/features/experiment/runtime/scientific/spectrum_analyzer_renderer.dart';
import 'package:mentora/features/experiment/runtime/scientific/vector_visualizer_behavior.dart';
import 'package:mentora/features/experiment/runtime/scientific/vector_visualizer_renderer.dart';
import 'package:mentora/features/experiment/runtime/variable_store.dart';

void main() {
  group('runtime scientific objects', () {
    test('vector visualizer calculates magnitude and direction', () {
      final variables = VariableStore()
        ..initialize([
          _variable('var_accel', 'Acceleration', 'accelerometer', {
            'x': 2,
            'y': 4,
            'z': 1,
          }),
        ]);
      final state = VectorVisualizerBehavior(
        variables: variables,
        objectJson: {
          'objectId': 'vec_1',
          'objectType': 'vectorVisualizer',
          'properties': {'linked_variable': 'var_accel', 'unit': 'm/s2'},
        },
      ).buildState();

      expect(state.x, 2);
      expect(state.y, 4);
      expect(state.z, 1);
      expect(state.magnitude, closeTo(math.sqrt(21), 0.0001));
      expect(
        state.direction,
        closeTo(math.atan2(4, 2) * 180 / math.pi, 0.0001),
      );

      variables.dispose();
    });

    test('oscilloscope keeps latest 200 samples', () {
      final store = RuntimeMeasurementStore(historyLimit: 500);
      for (var i = 0; i < 240; i++) {
        _addMeasurement(store, 'var_audio', 'Audio', i.toDouble(), i);
      }

      final state = OscilloscopeBehavior(
        measurementStore: store,
        objectJson: {
          'objectId': 'scope_1',
          'objectType': 'oscilloscope',
          'properties': {'linked_variable': 'var_audio', 'sampleRate': 100},
        },
      ).buildState();

      expect(state.sampleCount, 200);
      expect(state.samples.first, 40);
      expect(state.samples.last, 239);
      expect(state.timeWindow, 2);
    });

    test('spectrum analyzer generates DFT bins and peak frequency', () {
      final store = RuntimeMeasurementStore(historyLimit: 128);
      const sampleRate = 8.0;
      for (var i = 0; i < 8; i++) {
        final value = math.sin(2 * math.pi * i / 8);
        _addMeasurement(store, 'var_wave', 'Wave', i.toDouble(), value);
      }

      final state = SpectrumAnalyzerBehavior(
        measurementStore: store,
        objectJson: {
          'objectId': 'spectrum_1',
          'objectType': 'spectrumAnalyzer',
          'properties': {
            'linked_variable': 'var_wave',
            'sampleRate': sampleRate,
            'bins': 8,
          },
        },
      ).buildState();

      expect(state.binCount, 4);
      expect(state.amplitudes, isNotEmpty);
      expect(state.peakFrequency, closeTo(1, 0.0001));
    });

    test('bar chart reads multiple variables and scales values', () {
      final variables = VariableStore()
        ..initialize([
          _variable('var_a', 'Plant A', 'numberInput', 10),
          _variable('var_b', 'Plant B', 'numberInput', 25),
          _variable('var_c', 'Plant C', 'numberInput', 15),
        ]);

      final state = BarChartBehavior(
        variables: variables,
        objectJson: {
          'objectId': 'bars_1',
          'objectType': 'barChart',
          'properties': {
            'variables': ['var_a', 'var_b', 'var_c'],
          },
        },
      ).buildState();

      expect(state.labels, ['Plant A', 'Plant B', 'Plant C']);
      expect(state.values, [10, 25, 15]);
      expect(state.min, 10);
      expect(state.max, 25);

      variables.dispose();
    });

    test('multi-binding extracts vector and bar bindings', () {
      final binding = RuntimeMultiBinding.fromObjectJson({
        'objectId': 'scientific_1',
        'objectType': 'barChart',
        'properties': {
          'xVariable': 'var_x',
          'yVariable': 'var_y',
          'zVariable': 'var_z',
          'variables': ['var_a', 'var_b'],
        },
      });

      expect(binding.variableForRole('x'), 'var_x');
      expect(binding.variableForRole('y'), 'var_y');
      expect(binding.variableForRole('z'), 'var_z');
      expect(binding.variablesForPrefix('bar_'), ['var_a', 'var_b']);
    });

    test('registries and factory support scientific objects', () {
      RuntimeObjectFactory.registerDefaults();

      for (final type in const [
        'vectorVisualizer',
        'oscilloscope',
        'spectrumAnalyzer',
        'barChart',
      ]) {
        expect(RuntimeObjectBehaviorRegistry().containsBehavior(type), isTrue);
        expect(RuntimeObjectRendererRegistry().containsRenderer(type), isTrue);
        expect(
          RuntimeObjectFactory.availableCapabilities.any(
            (definition) => definition.type == type,
          ),
          isTrue,
        );
      }
    });

    test(
      'runtime component updates scientific renderer states and analytics',
      () async {
        final world = RuntimeLoader.loadFromManifest(
          _manifest(
            variables: [
              _variable('var_accel', 'Acceleration', 'accelerometer', {
                'x': 3,
                'y': 4,
                'z': 0,
              }),
              _variable('var_audio', 'Audio', 'microphone', -999),
              _variable('var_a', 'Plant A', 'numberInput', 10),
              _variable('var_b', 'Plant B', 'numberInput', 20),
            ],
            objects: [
              _object('vector_1', 'vectorVisualizer', {
                'linked_variable': 'var_accel',
                'unit': 'm/s2',
              }),
              _object('scope_1', 'oscilloscope', {
                'linked_variable': 'var_audio',
                'sampleRate': 20,
              }),
              _object('spectrum_1', 'spectrumAnalyzer', {
                'linked_variable': 'var_audio',
                'sampleRate': 20,
                'bins': 8,
              }),
              _object('bars_1', 'barChart', {
                'variables': ['var_a', 'var_b'],
              }),
            ],
          ),
        );

        for (var i = 0; i < 8; i++) {
          world.variables.updateVariable(
            'var_audio',
            math.sin(2 * math.pi * i / 8),
            source: 'test',
          );
          await Future<void>.delayed(Duration.zero);
        }

        for (final object in world.objects.allObjects) {
          final component = RuntimeDisplayObjectComponent(object, world);
          component.update(0);
          component.render(_canvas());
        }
        await Future<void>.delayed(Duration.zero);

        expect(
          world.objectLifecycle.getRenderer('vector_1'),
          isA<VectorVisualizerRenderer>(),
        );
        expect(
          (world.objectLifecycle.getRenderer('vector_1')
                  as VectorVisualizerRenderer)
              .vectorState
              .magnitude,
          5,
        );
        expect(
          (world.objectLifecycle.getRenderer('scope_1') as OscilloscopeRenderer)
              .oscilloscopeState
              .sampleCount,
          8,
        );
        expect(
          (world.objectLifecycle.getRenderer('spectrum_1')
                  as SpectrumAnalyzerRenderer)
              .spectrumState
              .binCount,
          4,
        );
        expect(
          (world.objectLifecycle.getRenderer('bars_1') as BarChartRenderer)
              .barChartState
              .barCount,
          2,
        );
        expect(world.analytics.vectorUpdates, 1);
        expect(world.analytics.waveformUpdates, 1);
        expect(world.analytics.fftComputations, 1);
        expect(world.analytics.barChartUpdates, 1);
        expect(world.analytics.scientificRenderCount, 4);

        world.dispose();
      },
    );
  });
}

Map<String, dynamic> _manifest({
  required List<Map<String, dynamic>> variables,
  required List<Map<String, dynamic>> objects,
}) {
  return {
    'scene': {
      'sceneId': 'scientific_runtime',
      'name': 'Scientific Runtime',
      'variables': variables,
      'objects': objects,
      'rules': const [],
    },
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

Map<String, dynamic> _object(
  String id,
  String type,
  Map<String, dynamic> properties,
) {
  return {
    'objectId': id,
    'name': id,
    'objectType': type,
    'properties': properties,
    'width': 260,
    'height': 150,
  };
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

ui.Canvas _canvas() {
  return ui.Canvas(ui.PictureRecorder());
}
