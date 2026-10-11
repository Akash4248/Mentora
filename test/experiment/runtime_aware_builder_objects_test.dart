import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/builder/models/builder_object.dart';
import 'package:mentora/features/experiment/builder/models/builder_scene.dart';
import 'package:mentora/features/experiment/builder/models/builder_variable.dart';
import 'package:mentora/features/experiment/builder/models/experiment_builder_state.dart';
import 'package:mentora/features/experiment/builder/storage/builder_draft.dart';
import 'package:mentora/features/experiment/builder/validation/builder_validator.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';
import 'package:mentora/features/experiment/runtime/scatter/scatter_plot_renderer.dart';

void main() {
  group('runtime-aware builder objects', () {
    test('gauge config survives save load manifest and runtime', () {
      final state = _state(
        variables: [_variable('var_temp', 'Temperature', 25)],
        objects: [
          BuilderObject(
            id: 'obj_gauge',
            name: 'Temperature Gauge',
            type: 'gauge',
            properties: {'linked_variable': 'var_temp'},
            runtimeConfig: {
              'min': 0,
              'max': 100,
              'unit': 'C',
              'warningThreshold': 80,
            },
          ),
        ],
      );

      final manifest = state.generateManifestJson();
      final loadedObject = BuilderObject.fromJson(
        Map<String, dynamic>.from(
          (manifest['scene']['objects'] as List<dynamic>).single as Map,
        ),
      );
      final world = RuntimeLoader.loadFromManifest(manifest);
      final runtimeState = world.objects.getObjectState('obj_gauge');

      expect(loadedObject.runtimeConfig['min'], 0);
      expect(loadedObject.runtimeConfig['max'], 100);
      expect(loadedObject.runtimeConfig['unit'], 'C');
      expect(loadedObject.runtimeConfig['warningThreshold'], 80);
      expect(runtimeState?.state['min'], 0);
      expect(runtimeState?.state['max'], 100);
      expect(runtimeState?.state['unit'], 'C');
      expect(runtimeState?.state['warningThreshold'], 80);

      world.dispose();
    });

    test('scatter plot x and y variables survive full pipeline', () async {
      final state = _state(
        variables: [
          _variable('var_time', 'Elapsed Time', 0),
          _variable('var_distance', 'Distance', 0),
        ],
        objects: [
          BuilderObject(
            id: 'obj_scatter',
            name: 'Distance vs Time',
            type: 'scatterPlot',
            properties: {'xVariable': 'var_time', 'yVariable': 'var_distance'},
            runtimeConfig: {
              'xVariable': 'var_time',
              'yVariable': 'var_distance',
            },
          ),
        ],
      );

      final manifest = state.generateManifestJson();
      final draft = BuilderDraft(
        draftId: 'draft_scatter',
        title: 'Scatter Draft',
        updatedAt: DateTime(2026, 6, 10),
        manifest: manifest,
      );
      final reloadedDraft = BuilderDraft.fromJson(draft.toJson());
      final reloadedObject = BuilderObject.fromJson(
        Map<String, dynamic>.from(
          (reloadedDraft.manifest['scene']['objects'] as List<dynamic>).single
              as Map,
        ),
      );
      final world = RuntimeLoader.loadFromManifest(reloadedDraft.manifest);

      expect(reloadedObject.runtimeConfig['xVariable'], 'var_time');
      expect(reloadedObject.runtimeConfig['yVariable'], 'var_distance');
      expect(
        world.objects.get('obj_scatter')?['properties']['xVariable'],
        'var_time',
      );
      expect(
        world.objects.get('obj_scatter')?['properties']['yVariable'],
        'var_distance',
      );
      expect(
        world.objectLifecycle.getRenderer('obj_scatter'),
        isA<ScatterPlotRenderer>(),
      );

      world.dispose();
    });

    test('draft persistence preserves runtimeConfig', () {
      final manifest = _state(
        variables: [_variable('var_velocity', 'Velocity', 12)],
        objects: [
          BuilderObject(
            id: 'obj_numeric',
            name: 'Velocity Display',
            type: 'numericDisplay',
            properties: {'linked_variable': 'var_velocity'},
            runtimeConfig: {'label': 'Velocity', 'unit': 'm/s', 'precision': 2},
          ),
        ],
      ).generateManifestJson();

      final restored = BuilderDraft.fromJson(
        BuilderDraft(
          draftId: 'draft_numeric',
          title: 'Numeric Draft',
          updatedAt: DateTime(2026, 6, 10),
          manifest: manifest,
        ).toJson(),
      );
      final object = BuilderObject.fromJson(
        Map<String, dynamic>.from(
          (restored.manifest['scene']['objects'] as List<dynamic>).single
              as Map,
        ),
      );

      expect(object.runtimeConfig['label'], 'Velocity');
      expect(object.runtimeConfig['unit'], 'm/s');
      expect(object.runtimeConfig['precision'], 2);
      expect(object.toJson()['runtimeConfig']['precision'], 2);
      expect(object.toJson()['properties']['precision'], 2);
      expect(object.toJson()['state']['precision'], 2);
    });

    test('builder validator checks runtime config rules', () {
      final validator = BuilderValidator();

      final invalidGauge = validator.validate(
        _state(
          variables: [_variable('var_temp', 'Temperature', 25)],
          objects: [
            BuilderObject(
              id: 'obj_gauge',
              name: 'Bad Gauge',
              type: 'gauge',
              properties: {'linked_variable': 'var_temp'},
              runtimeConfig: {'min': 100, 'max': 0, 'warningThreshold': 120},
            ),
          ],
        ),
      );
      expect(invalidGauge.isValid, isFalse);
      expect(invalidGauge.errors.join('\n'), contains('min must be less'));

      final invalidScatter = validator.validate(
        _state(
          variables: [_variable('var_time', 'Elapsed Time', 0)],
          objects: [
            BuilderObject(
              id: 'obj_scatter',
              name: 'Bad Scatter',
              type: 'scatterPlot',
              properties: const {},
              runtimeConfig: {'xVariable': 'var_time', 'yVariable': 'var_time'},
            ),
          ],
        ),
      );
      expect(invalidScatter.isValid, isFalse);
      expect(invalidScatter.errors.join('\n'), contains('must differ'));

      final invalidTable = validator.validate(
        _state(
          variables: const [],
          objects: [
            BuilderObject(
              id: 'obj_table',
              name: 'Bad Table',
              type: 'table',
              properties: const {},
              runtimeConfig: {'maxRows': 0, 'autoRecord': true},
            ),
          ],
        ),
      );
      expect(invalidTable.isValid, isFalse);
      expect(invalidTable.errors.join('\n'), contains('maxRows'));
    });

    test('line graph runtime config variable is accepted by runtime', () {
      final state = _state(
        variables: [_variable('var_temp', 'Temperature', 25)],
        objects: [
          BuilderObject(
            id: 'obj_line',
            name: 'Temperature Graph',
            type: 'lineGraph',
            properties: {'linked_variable': 'var_temp'},
            runtimeConfig: {
              'variableId': 'var_temp',
              'historyWindow': 100,
              'xAxis': 'Time',
              'yAxis': 'Temperature',
            },
          ),
        ],
      );

      final validation = BuilderValidator().validate(state);
      final manifest = state.generateManifestJson();
      final world = RuntimeLoader.loadFromManifest(manifest);
      final object = world.objects.get('obj_line');

      expect(validation.isValid, isTrue);
      expect(object?['properties']['variableId'], 'var_temp');
      expect(object?['runtimeConfig']['historyWindow'], 100);

      world.dispose();
    });
  });
}

ExperimentBuilderState _state({
  required List<BuilderVariable> variables,
  required List<BuilderObject> objects,
}) {
  return ExperimentBuilderState(
    scene: BuilderScene(
      id: 'runtime_config_scene',
      name: 'Runtime Config Scene',
      description: 'Runtime-aware builder object certification.',
      tags: const ['runtime-config'],
    ),
    variables: variables,
    objects: objects,
    rules: const [],
  );
}

BuilderVariable _variable(String id, String name, dynamic value) {
  return BuilderVariable(
    id: id,
    name: name,
    type: 'numberInput',
    defaultValue: value,
    description: name,
  );
}
