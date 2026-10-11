import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/objects/renderers/runtime_object_renderer_registry.dart';
import 'package:mentora/features/experiment/runtime/observations/table_behavior.dart';
import 'package:mentora/features/experiment/runtime/observations/table_renderer.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_layout.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_state.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  group('runtime observation and table system', () {
    test('manual record captures current runtime variables', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_temperature', 'Temperature', 'numberInput', 25),
          ],
        ),
      );

      world.recordObservation();
      world.variables.updateVariable('var_temperature', 30, source: 'test');
      await Future<void>.delayed(Duration.zero);
      world.recordObservation();
      world.variables.updateVariable('var_temperature', 35, source: 'test');
      await Future<void>.delayed(Duration.zero);
      world.recordObservation();
      await Future<void>.delayed(Duration.zero);

      final rows = world.observationStore.getObservations();
      expect(rows, hasLength(3));
      expect(rows.map((row) => row.values['Temperature']), [25, 30, 35]);
      expect(world.analytics.observationsRecorded, 3);
      expect(world.analytics.observationRows, 3);

      world.dispose();
    });

    test('interval mode records rows automatically', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [_variable('var_time', 'Elapsed Time', 'elapsedTime', 0)],
        ),
      );

      world.observationScheduler.configureInterval(seconds: 1);
      world.clock.start();
      world.tick(1);
      world.tick(1);
      world.tick(1);
      await Future<void>.delayed(Duration.zero);

      expect(world.observationStore.rowCount, 3);
      expect(
        world.observationStore.getObservations().map(
          (row) => row.values['Elapsed Time'],
        ),
        [1.0, 2.0, 3.0],
      );

      world.dispose();
    });

    test(
      'exportJson returns flat observation rows and emits analytics',
      () async {
        final world = RuntimeLoader.loadFromManifest(
          _manifest(
            variables: [
              _variable('var_temperature', 'Temperature', 'numberInput', 25),
            ],
          ),
        );

        world.recordObservation();
        final exported = world.observationExporter.exportJson();
        await Future<void>.delayed(Duration.zero);

        expect(exported, hasLength(1));
        expect(exported.single['runtimeSeconds'], 0);
        expect(exported.single['Temperature'], 25);
        expect(world.analytics.observationExports, 1);

        world.dispose();
      },
    );

    test('table behavior builds columns and rows from observations', () {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_temperature', 'Temperature', 'numberInput', 25),
            _variable('var_force', 'Force', 'numberInput', 42),
          ],
        ),
      );

      world.recordObservation();
      final state = TableBehavior(
        observationStore: world.observationStore,
      ).buildState();

      expect(state.columns, ['Time', 'Temperature', 'Force']);
      expect(state.rowCount, 1);
      expect(state.rows.single['Temperature'], 25);
      expect(state.latestObservation?['Force'], 42);

      world.dispose();
    });

    test('table renderer supports no observations and data rows', () {
      final renderer = TableRenderer()
        ..initialize()
        ..update(
          RuntimeObjectState(
            objectId: 'table_1',
            objectType: 'table',
            state: const {},
            visible: true,
            updatedAt: DateTime.now(),
            layout: const RuntimeObjectLayout(
              x: 0,
              y: 0,
              width: 260,
              height: 160,
              alignment: 'center',
            ),
          ),
        );

      renderer.render(_canvas(), const ui.Size(260, 160));
      expect(renderer.lastRenderTime, isNotNull);

      renderer.updateTableState(
        const TableState(
          columns: ['Time', 'Temperature'],
          rows: [
            {'Time': 1.0, 'Temperature': 25},
            {'Time': 2.0, 'Temperature': 30},
          ],
          rowCount: 2,
          latestObservation: {'Time': 2.0, 'Temperature': 30},
        ),
      );
      renderer.render(_canvas(), const ui.Size(260, 160));
      expect(renderer.tableState.rowCount, 2);
    });

    test(
      'table renderer is registered with runtime object renderer registry',
      () {
        expect(
          RuntimeObjectRendererRegistry().containsRenderer('table'),
          isTrue,
        );
      },
    );
  });
}

Map<String, dynamic> _manifest({
  required List<Map<String, dynamic>> variables,
  List<Map<String, dynamic>> objects = const [],
}) {
  return {
    'metadata': {'title': 'Observation Runtime Test'},
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

ui.Canvas _canvas() {
  return ui.Canvas(ui.PictureRecorder());
}
