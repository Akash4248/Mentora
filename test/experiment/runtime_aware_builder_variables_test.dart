import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/builder/models/builder_object.dart';
import 'package:mentora/features/experiment/builder/models/builder_scene.dart';
import 'package:mentora/features/experiment/builder/models/builder_variable.dart';
import 'package:mentora/features/experiment/builder/models/experiment_builder_state.dart';
import 'package:mentora/features/experiment/builder/storage/builder_draft.dart';
import 'package:mentora/features/experiment/builder/validation/builder_validator.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  group('runtime-aware builder variables', () {
    test('draft persistence preserves variable runtime config', () {
      final manifest = _state(
        variables: [
          _variable(
            id: 'var_countdown',
            name: 'Countdown',
            type: 'countdown',
            value: 60,
            runtimeConfig: {'startValue': 60, 'autoStart': true},
          ),
        ],
      ).generateManifestJson();

      final draft = BuilderDraft(
        draftId: 'draft_timer',
        title: 'Timer Draft',
        updatedAt: DateTime(2026, 6, 10),
        manifest: manifest,
      );
      final restored = BuilderDraft.fromJson(draft.toJson());
      final variable = BuilderVariable.fromJson(
        Map<String, dynamic>.from(
          (restored.manifest['scene']['variables'] as List<dynamic>).single
              as Map,
        ),
      );

      expect(variable.runtimeConfig['startValue'], 60);
      expect(variable.runtimeConfig['autoStart'], true);
      expect(variable.toJson()['running'], true);
    });

    test('manifest generation preserves computed variable config', () {
      final state = _state(
        variables: [
          _variable(id: 'var_a', name: 'A', type: 'numberInput', value: 10),
          _variable(id: 'var_b', name: 'B', type: 'numberInput', value: 20),
          _variable(
            id: 'var_average',
            name: 'Average',
            type: 'average',
            value: 0,
            runtimeConfig: {
              'dependencies': ['var_a', 'var_b'],
            },
          ),
        ],
      );

      final manifest = state.generateManifestJson();
      final variable = Map<String, dynamic>.from(
        (manifest['scene']['variables'] as List<dynamic>).last as Map,
      );

      expect(variable['runtimeConfig']['dependencies'], ['var_a', 'var_b']);
      expect(variable['dependencies'], ['var_a', 'var_b']);
    });

    test('dependency validation detects missing dependency', () {
      final result = BuilderValidator().validate(
        _state(
          variables: [
            _variable(
              id: 'var_force',
              name: 'Force',
              type: 'force',
              value: 0,
              runtimeConfig: {
                'massVariable': 'var_mass',
                'accelerationVariable': 'var_accel',
              },
            ),
            _variable(
              id: 'var_accel',
              name: 'Acceleration',
              type: 'numberInput',
              value: 5,
            ),
          ],
        ),
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.join('\n'),
        contains('Force variable references missing variable var_mass'),
      );
    });

    test('dependency validation detects circular dependency', () {
      final result = BuilderValidator().validate(
        _state(
          variables: [
            _variable(
              id: 'var_base',
              name: 'Base',
              type: 'numberInput',
              value: 1,
            ),
            _variable(
              id: 'var_a',
              name: 'A',
              type: 'average',
              value: 0,
              runtimeConfig: {
                'dependencies': ['var_b', 'var_base'],
              },
            ),
            _variable(
              id: 'var_b',
              name: 'B',
              type: 'average',
              value: 0,
              runtimeConfig: {
                'dependencies': ['var_a', 'var_base'],
              },
            ),
          ],
        ),
      );

      expect(result.isValid, isFalse);
      expect(
        result.errors.join('\n'),
        contains('Circular dependency detected'),
      );
    });

    test(
      'runtime launch computes force from builder-authored config',
      () async {
        final world = RuntimeLoader.loadFromManifest(
          _state(
            variables: [
              _variable(
                id: 'var_mass',
                name: 'Mass',
                type: 'numberInput',
                value: 2,
              ),
              _variable(
                id: 'var_accel',
                name: 'Acceleration',
                type: 'numberInput',
                value: 5,
              ),
              _variable(
                id: 'var_force',
                name: 'Force',
                type: 'force',
                value: 0,
                runtimeConfig: {
                  'massVariable': 'var_mass',
                  'accelerationVariable': 'var_accel',
                },
              ),
            ],
          ).generateManifestJson(),
        );

        expect(world.variables.getValue('var_force'), 10);

        world.variables.updateVariable('var_mass', 4, source: 'test');
        await Future<void>.delayed(Duration.zero);

        expect(world.variables.getValue('var_force'), 20);
        world.dispose();
      },
    );

    test('runtime launch computes distance and energy from config', () async {
      final world = RuntimeLoader.loadFromManifest(
        _state(
          variables: [
            _variable(
              id: 'var_speed',
              name: 'Speed',
              type: 'numberInput',
              value: 3,
            ),
            _variable(
              id: 'var_time',
              name: 'Elapsed Time',
              type: 'elapsedTime',
              value: 0,
              runtimeConfig: {'startValue': 0},
            ),
            _variable(
              id: 'var_distance',
              name: 'Distance',
              type: 'distance',
              value: 0,
              runtimeConfig: {
                'speedVariable': 'var_speed',
                'timeVariable': 'var_time',
              },
            ),
            _variable(
              id: 'var_power',
              name: 'Power',
              type: 'numberInput',
              value: 2,
            ),
            _variable(
              id: 'var_energy',
              name: 'Energy',
              type: 'energy',
              value: 0,
              runtimeConfig: {
                'powerVariable': 'var_power',
                'timeVariable': 'var_time',
              },
            ),
          ],
        ).generateManifestJson(),
      );

      world.start();
      world.tick(4);
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_distance'), 12);
      expect(world.variables.getValue('var_energy'), 8);
      world.dispose();
    });

    test('runtime launch computes power from force and velocity config', () {
      final world = RuntimeLoader.loadFromManifest(
        _state(
          variables: [
            _variable(
              id: 'var_force',
              name: 'Force',
              type: 'numberInput',
              value: 10,
            ),
            _variable(
              id: 'var_velocity',
              name: 'Velocity',
              type: 'numberInput',
              value: 3,
            ),
            _variable(
              id: 'var_power',
              name: 'Power',
              type: 'power',
              value: 0,
              runtimeConfig: {
                'forceVariable': 'var_force',
                'velocityVariable': 'var_velocity',
              },
            ),
          ],
        ).generateManifestJson(),
      );

      expect(world.variables.getValue('var_power'), 30);
      world.dispose();
    });
  });
}

ExperimentBuilderState _state({
  required List<BuilderVariable> variables,
  List<BuilderObject> objects = const [],
}) {
  return ExperimentBuilderState(
    scene: BuilderScene(
      id: 'runtime_variable_scene',
      name: 'Runtime Variable Scene',
      description: 'Runtime-aware builder variable certification.',
      tags: const ['runtime-variable'],
    ),
    variables: variables,
    objects: objects,
    rules: const [],
  );
}

BuilderVariable _variable({
  required String id,
  required String name,
  required String type,
  required dynamic value,
  Map<String, dynamic> runtimeConfig = const {},
}) {
  return BuilderVariable(
    id: id,
    name: name,
    type: type,
    defaultValue: value,
    description: name,
    runtimeConfig: runtimeConfig,
  );
}
