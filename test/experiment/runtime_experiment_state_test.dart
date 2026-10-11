import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/experiment_state/runtime_experiment_status.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  group('runtime experiment state', () {
    test('lifecycle transitions update experiment status', () {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_temperature', 'Temperature', 'numberInput', 25),
          ],
        ),
      );

      expect(
        world.experimentState.state.status,
        RuntimeExperimentStatus.prepared,
      );

      world.start();
      expect(
        world.experimentState.state.status,
        RuntimeExperimentStatus.running,
      );

      world.pause();
      expect(
        world.experimentState.state.status,
        RuntimeExperimentStatus.paused,
      );

      world.resume();
      expect(
        world.experimentState.state.status,
        RuntimeExperimentStatus.running,
      );

      world.stop();
      expect(
        world.experimentState.state.status,
        RuntimeExperimentStatus.stopped,
      );

      world.dispose();
    });

    test('metrics accumulate measurements and observations', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_temperature', 'Temperature', 'numberInput', 25),
          ],
        ),
      );

      world.start();
      world.variables.updateVariable('var_temperature', 30, source: 'test');
      world.variables.updateVariable('var_temperature', 35, source: 'test');
      world.variables.updateVariable('var_temperature', 40, source: 'test');
      world.recordObservation();
      world.recordObservation();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = world.experimentState.state;
      expect(state.status, RuntimeExperimentStatus.running);
      expect(state.measurements, 3);
      expect(state.observations, 2);
      expect(state.metrics.variables, 1);

      world.dispose();
    });

    test('warning and rule metrics update from rule execution', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_temperature', 'Temperature', 'numberInput', 25),
          ],
          rules: [
            {
              'ruleId': 'rule_temperature_warning',
              'name': 'Temperature Warning',
              'trigger': 'variableChanged',
              'condition': {
                'variableId': 'var_temperature',
                'operator': '>',
                'value': 100,
              },
              'action': {
                'type': 'show_warning',
                'message': 'Temperature is high',
              },
            },
          ],
        ),
      );

      world.start();
      world.variables.updateVariable('var_temperature', 120, source: 'test');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(world.experimentState.state.warnings, 1);
      expect(world.experimentState.state.rulesTriggered, 1);

      world.dispose();
    });

    test('completion event moves status to completed', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_temperature', 'Temperature', 'numberInput', 25),
          ],
        ),
      );

      world.start();
      world.tick(2);
      world.complete();
      await Future<void>.delayed(Duration.zero);

      expect(
        world.experimentState.state.status,
        RuntimeExperimentStatus.completed,
      );
      expect(world.experimentState.state.completedAt, isNotNull);
      expect(world.analytics.experimentsCompleted, 1);
      expect(world.analytics.averageRuntime, greaterThanOrEqualTo(2));

      world.dispose();
    });

    test(
      'failure event moves status to failed and updates analytics',
      () async {
        final world = RuntimeLoader.loadFromManifest(
          _manifest(
            variables: [
              _variable('var_temperature', 'Temperature', 'numberInput', 25),
            ],
          ),
        );

        world.start();
        world.fail('certification failure');
        await Future<void>.delayed(Duration.zero);

        expect(
          world.experimentState.state.status,
          RuntimeExperimentStatus.failed,
        );
        expect(world.analytics.experimentsFailed, 1);

        world.dispose();
      },
    );

    test(
      'snapshot captures variables object state counts and status',
      () async {
        final world = RuntimeLoader.loadFromManifest(
          _manifest(
            variables: [
              _variable('var_temperature', 'Temperature', 'numberInput', 25),
            ],
            objects: [
              {
                'objectId': 'display_temperature',
                'objectType': 'numericDisplay',
                'properties': {'valueVariable': 'var_temperature'},
              },
            ],
          ),
        );

        world.start();
        world.variables.updateVariable('var_temperature', 30, source: 'test');
        world.recordObservation();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final snapshot = world.createSnapshot();

        expect(snapshot.variables, contains('var_temperature'));
        expect(snapshot.objectStates, hasLength(1));
        expect(snapshot.measurementsCount, 1);
        expect(snapshot.observationsCount, 1);
        expect(snapshot.state.status, RuntimeExperimentStatus.running);
        expect(snapshot.toJson()['status'], 'running');

        world.dispose();
      },
    );
  });
}

Map<String, dynamic> _manifest({
  required List<Map<String, dynamic>> variables,
  List<Map<String, dynamic>> objects = const [],
  List<Map<String, dynamic>> rules = const [],
}) {
  return {
    'metadata': {'title': 'Experiment State Runtime Test'},
    'scene': {
      'sceneId': 'experiment_state_test',
      'name': 'Experiment State Runtime Test',
      'variables': variables,
      'objects': objects,
      'rules': rules,
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
