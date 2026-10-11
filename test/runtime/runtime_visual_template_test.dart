import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';
import 'package:mentora/features/experiment/runtime/visual_templates/registry/runtime_visual_template_registry.dart';

void main() {
  test('registry resolves object types to visual templates', () {
    final registry = RuntimeVisualTemplateRegistry();

    expect(
      registry.templateFor('numericDisplay')?.name,
      'NumericDisplayVisualTemplate',
    );
    expect(registry.templateFor('gauge')?.name, 'GaugeVisualTemplate');
    expect(
      registry.templateFor('progressBar')?.name,
      'ProgressBarVisualTemplate',
    );
    expect(registry.templateFor('lineGraph')?.name, 'LineGraphVisualTemplate');
    expect(
      registry.templateFor('vectorVisualizer')?.name,
      'VectorVisualizerVisualTemplate',
    );
  });

  test('numeric display object generates three actors', () {
    final world = _worldWithObjects([
      {
        'id': 'obj_temperature_display',
        'type': 'numericDisplay',
        'runtimeConfig': {
          'label': 'Temperature',
          'unit': 'C',
          'variableId': 'var_temperature',
        },
        'state': {'value': 25.3},
      },
    ]);

    final group = world.visualTemplates.groups.single;
    expect(group.templateName, 'NumericDisplayVisualTemplate');
    expect(group.actorIds.length, 3);
    expect(
      world.simulationCanvas.actor('obj_temperature_display_value'),
      isNotNull,
    );

    world.dispose();
  });

  test('gauge value change updates generated needle rotation', () {
    final world = _worldWithObjects([
      {
        'id': 'obj_temperature_gauge',
        'type': 'gauge',
        'runtimeConfig': {
          'label': 'Temperature',
          'min': 0,
          'max': 100,
          'variableId': 'var_temperature',
        },
        'state': {'value': 0},
      },
    ]);

    final initialRotation = world.simulationCanvas
        .actor('obj_temperature_gauge_needle')
        ?.rotation;
    world.objects.updateObjectState('obj_temperature_gauge', 'value', 100);
    final updatedRotation = world.simulationCanvas
        .actor('obj_temperature_gauge_needle')
        ?.rotation;

    expect(updatedRotation, isNot(equals(initialRotation)));

    world.dispose();
  });

  test('progress bar value change updates generated fill width', () {
    final world = _worldWithObjects([
      {
        'id': 'obj_progress',
        'type': 'progressBar',
        'runtimeConfig': {'min': 0, 'max': 100, 'variableId': 'var_progress'},
        'state': {'value': 25},
      },
    ]);

    final initialWidth = world.simulationCanvas
        .actor('obj_progress_bar_fill')
        ?.state['width'];
    world.objects.updateObjectState('obj_progress', 'value', 80);
    final updatedWidth = world.simulationCanvas
        .actor('obj_progress_bar_fill')
        ?.state['width'];

    expect(updatedWidth, greaterThan(initialWidth as double));

    world.dispose();
  });

  test('line graph template generates graph layer', () {
    final world = _worldWithObjects([
      {
        'id': 'obj_line_graph',
        'type': 'lineGraph',
        'runtimeConfig': {'variableId': 'var_temperature'},
      },
    ]);

    expect(world.simulationCanvas.actor('obj_line_graph_layer'), isNotNull);
    expect(world.visualTemplates.groups.single.actorIds.length, 4);

    world.dispose();
  });

  test('vector visualizer object generates updating arrow', () {
    final world = _worldWithObjects([
      {
        'id': 'obj_vector',
        'type': 'vectorVisualizer',
        'runtimeConfig': {'variableId': 'var_vector'},
        'state': {
          'value': {'x': 1, 'y': 0},
        },
      },
    ]);

    final initialWidth = world.simulationCanvas
        .actor('obj_vector_arrow')
        ?.state['width'];
    world.objects.updateObjectState('obj_vector', 'value', {'x': 3, 'y': 4});
    final updatedWidth = world.simulationCanvas
        .actor('obj_vector_arrow')
        ?.state['width'];

    expect(updatedWidth, greaterThan(initialWidth as double));

    world.dispose();
  });

  test(
    'runtime world initialize populates simulation canvas from objects',
    () async {
      final world = _worldWithObjects([
        {
          'id': 'obj_gauge',
          'type': 'gauge',
          'runtimeConfig': {'variableId': 'var_temperature'},
          'state': {'value': 50},
        },
        {
          'id': 'obj_bar',
          'type': 'progressBar',
          'runtimeConfig': {'variableId': 'var_progress'},
          'state': {'value': 50},
        },
      ]);

      expect(world.simulationCanvas.actorCount, greaterThanOrEqualTo(8));
      expect(world.visualTemplates.groupCount, 2);
      await Future<void>.delayed(Duration.zero);
      expect(world.analytics.visualTemplatesGenerated, 2);

      world.dispose();
    },
  );
}

dynamic _worldWithObjects(List<Map<String, dynamic>> objects) {
  return RuntimeLoader.loadFromManifest({
    'metadata': {'title': 'Visual Template Test'},
    'scene': {
      'sceneId': 'visual_template_test',
      'name': 'Visual Template Test',
      'variables': [
        {
          'id': 'var_temperature',
          'name': 'Temperature',
          'type': 'number',
          'value': 0,
        },
        {
          'id': 'var_progress',
          'name': 'Progress',
          'type': 'number',
          'value': 0,
        },
        {
          'id': 'var_vector',
          'name': 'Vector',
          'type': 'vector',
          'value': {'magnitude': 1, 'direction': 0},
        },
      ],
      'objects': objects,
      'rules': const [],
    },
  });
}
