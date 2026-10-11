import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_layout.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_state.dart';
import 'package:mentora/features/experiment/runtime/objects/renderers/gauge_renderer.dart';
import 'package:mentora/features/experiment/runtime/objects/renderers/numeric_display_renderer.dart';
import 'package:mentora/features/experiment/runtime/objects/renderers/progress_bar_renderer.dart';
import 'package:mentora/features/experiment/runtime/objects/renderers/text_display_renderer.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  group('runtime display objects', () {
    test('numeric display renders formatted runtime state', () {
      final renderer = NumericDisplayRenderer()..initialize();
      final state = _state(
        objectType: 'numericDisplay',
        state: const {
          'label': 'Temperature',
          'value': 75,
          'unit': 'C',
          'precision': 1,
        },
      );

      renderer.update(state);
      _render(renderer.render);

      expect(renderer.lastLabel, 'Temperature');
      expect(renderer.lastFormattedValue, '75.0 C');
      expect(renderer.lastRenderTime, isNotNull);
    });

    test('text display prioritizes formattedText, then text, then value', () {
      final renderer = TextDisplayRenderer()..initialize();

      renderer.update(
        _state(
          objectType: 'textDisplay',
          state: const {
            'label': 'Current Status',
            'text': 'Water Heating',
            'formattedText': 'Water Boiling',
            'value': 'Fallback',
          },
        ),
      );
      _render(renderer.render);

      expect(renderer.lastLabel, 'Current Status');
      expect(renderer.lastRenderedText, 'Water Boiling');
      expect(renderer.lastRenderTime, isNotNull);
    });

    test('gauge visualizes normalized values from runtime state', () {
      final renderer = GaugeRenderer()..initialize();

      renderer.update(
        _state(
          objectType: 'gauge',
          state: const {
            'label': 'Temperature',
            'value': 75,
            'min': 0,
            'max': 100,
            'unit': 'C',
            'warningThreshold': 90,
          },
        ),
      );
      _render(renderer.render);

      expect(renderer.lastNormalizedValue, 0.75);
      expect(renderer.lastValueLabel, '75 C');
      expect(renderer.lastRenderTime, isNotNull);
    });

    test('progress bar clamps completion to 0..1', () {
      final renderer = ProgressBarRenderer()..initialize();

      renderer.update(
        _state(
          objectType: 'progressBar',
          state: const {'value': 120, 'min': 0, 'max': 100},
        ),
      );
      _render(renderer.render);

      expect(renderer.lastProgress, 1);
      expect(renderer.lastPercentLabel, '100%');
      expect(renderer.lastRenderTime, isNotNull);
    });

    test('visibility false prevents rendering', () {
      final renderer = NumericDisplayRenderer()..initialize();

      renderer.update(
        _state(
          objectType: 'numericDisplay',
          visible: false,
          state: const {'value': 25, 'unit': 'C'},
        ),
      );
      _render(renderer.render);

      expect(renderer.lastRenderSkipped, isTrue);
      expect(renderer.lastRenderTime, isNull);
    });

    test(
      'slider binding updates display object states for direct visuals',
      () async {
        final world = RuntimeLoader.loadFromManifest({
          'metadata': {'title': 'Display Runtime Test'},
          'scene': {
            'variables': [
              {
                'id': 'var_temperature',
                'name': 'Temperature',
                'type': 'number',
                'value': 25,
                'unit': 'C',
              },
            ],
            'objects': [
              {
                'objectId': 'slider_temperature',
                'objectType': 'slider',
                'properties': {'linked_variable': 'var_temperature'},
                'state': {'value': 25, 'min': 0, 'max': 100},
              },
              {
                'objectId': 'numeric_temperature',
                'objectType': 'numericDisplay',
                'properties': {'valueVariable': 'var_temperature'},
                'state': {
                  'label': 'Temperature',
                  'value': 25,
                  'unit': 'C',
                  'precision': 0,
                },
              },
              {
                'objectId': 'gauge_temperature',
                'objectType': 'gauge',
                'properties': {'valueVariable': 'var_temperature'},
                'state': {'value': 25, 'min': 0, 'max': 100, 'unit': 'C'},
              },
              {
                'objectId': 'progress_temperature',
                'objectType': 'progressBar',
                'properties': {'valueVariable': 'var_temperature'},
                'state': {'value': 25, 'min': 0, 'max': 100},
              },
            ],
            'rules': [],
          },
        });

        world.objectVariableAdapter.changeSlider('slider_temperature', 75);
        await Future<void>.delayed(Duration.zero);

        expect(
          world.objects.getObjectState('numeric_temperature')?.state['value'],
          75,
        );
        expect(
          world.objects.getObjectState('gauge_temperature')?.state['value'],
          75,
        );
        expect(
          world.objects.getObjectState('progress_temperature')?.state['value'],
          75,
        );

        final gauge = world.objectLifecycle.getRenderer('gauge_temperature');
        final progress = world.objectLifecycle.getRenderer(
          'progress_temperature',
        );
        gauge?.render(_canvas(), const ui.Size(180, 120));
        progress?.render(_canvas(), const ui.Size(180, 96));

        expect((gauge as GaugeRenderer).lastNormalizedValue, 0.75);
        expect((progress as ProgressBarRenderer).lastProgress, 0.75);

        world.dispose();
      },
    );
  });
}

RuntimeObjectState _state({
  required String objectType,
  required Map<String, dynamic> state,
  bool visible = true,
}) {
  return RuntimeObjectState(
    objectId: '${objectType}_1',
    objectType: objectType,
    state: state,
    visible: visible,
    updatedAt: DateTime.now(),
    layout: const RuntimeObjectLayout(
      x: 0,
      y: 0,
      width: 180,
      height: 96,
      alignment: 'center',
    ),
  );
}

void _render(void Function(ui.Canvas canvas, ui.Size size) render) {
  render(_canvas(), const ui.Size(180, 120));
}

ui.Canvas _canvas() {
  return ui.Canvas(ui.PictureRecorder());
}
