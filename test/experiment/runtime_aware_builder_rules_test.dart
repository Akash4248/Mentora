import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/builder/models/builder_object.dart';
import 'package:mentora/features/experiment/builder/models/builder_rule.dart';
import 'package:mentora/features/experiment/builder/models/builder_scene.dart';
import 'package:mentora/features/experiment/builder/models/builder_variable.dart';
import 'package:mentora/features/experiment/builder/models/experiment_builder_state.dart';
import 'package:mentora/features/experiment/builder/storage/builder_draft.dart';
import 'package:mentora/features/experiment/builder/validation/builder_validator.dart';
import 'package:mentora/features/experiment/builder/widgets/rule_dependency_graph.dart';
import 'package:mentora/features/experiment/runtime/runtime_event.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  group('runtime-aware builder rules', () {
    test('draft persistence preserves runtime rule config', () {
      final manifest = _state(
        variables: [_variable('var_temp', 'Temperature', 25)],
        rules: [
          _rule(
            condition: {
              'variableId': 'var_temp',
              'operator': '>=',
              'value': 100,
            },
            actions: [
              {'type': 'show_warning', 'message': 'Water is boiling'},
            ],
          ),
        ],
      ).generateManifestJson();

      final draft = BuilderDraft(
        draftId: 'draft_rule',
        title: 'Rule Draft',
        updatedAt: DateTime(2026, 6, 10),
        manifest: manifest,
      );
      final restored = BuilderDraft.fromJson(draft.toJson());
      final rule = BuilderRule.fromJson(
        Map<String, dynamic>.from(
          (restored.manifest['scene']['rules'] as List<dynamic>).single as Map,
        ),
      );

      expect(rule.runtimeConfig['condition']['variableId'], 'var_temp');
      expect(rule.trigger, 'thresholdCrossed');
      expect(rule.runtimeConfig['actions'], hasLength(1));
      expect(rule.runtimeConfig['actions'][0]['type'], 'show_warning');
    });

    test('trigger persistence survives manifest and runtime load', () {
      final state = _state(
        variables: [_variable('var_pressed', 'Pressed', false)],
        rules: [
          _rule(
            trigger: 'buttonPressed',
            condition: {
              'variableId': 'var_pressed',
              'operator': '==',
              'value': true,
            },
            actions: [
              {'type': 'show_warning', 'message': 'Button pressed'},
            ],
          ),
        ],
      );
      final manifestRule = Map<String, dynamic>.from(
        (state.generateManifestJson()['scene']['rules'] as List<dynamic>).single
            as Map,
      );

      expect(manifestRule['trigger'], 'buttonPressed');
      expect(manifestRule['runtimeConfig']['trigger'], 'buttonPressed');

      final world = RuntimeLoader.loadFromManifest(
        state.generateManifestJson(),
      );
      expect(world.rules.allRules.single['trigger'], 'buttonPressed');
      world.dispose();
    });

    test('manifest generation preserves multi-action rules', () {
      final state = _state(
        variables: [
          _variable('var_temp', 'Temperature', 25),
          _variable('var_alarm', 'Alarm', false),
        ],
        objects: [_object('obj_gauge', 'Gauge', 'gauge')],
        rules: [
          _rule(
            condition: {
              'variableId': 'var_temp',
              'operator': '>=',
              'value': 100,
            },
            actions: [
              {'type': 'show_warning', 'message': 'Hot'},
              {'type': 'hide_object', 'objectId': 'obj_gauge'},
              {
                'type': 'set_variable',
                'variableId': 'var_alarm',
                'value': true,
              },
            ],
          ),
        ],
      );

      final manifestRule = Map<String, dynamic>.from(
        (state.generateManifestJson()['scene']['rules'] as List<dynamic>).single
            as Map,
      );

      expect(manifestRule['action']['type'], 'show_warning');
      expect(manifestRule['trigger'], 'thresholdCrossed');
      expect(manifestRule['actions'], hasLength(3));
      expect(manifestRule['runtimeConfig']['actions'], hasLength(3));
    });

    test('validation detects missing variable and object references', () {
      final result = BuilderValidator().validate(
        _state(
          variables: [_variable('var_temp', 'Temperature', 25)],
          rules: [
            _rule(
              condition: {
                'variableId': 'var_missing',
                'operator': '>=',
                'value': 100,
              },
              actions: [
                {'type': 'hide_object', 'objectId': 'obj_missing'},
              ],
            ),
          ],
        ),
      );

      expect(result.isValid, isFalse);
      expect(result.errors.join('\n'), contains('missing variable'));
      expect(result.errors.join('\n'), contains('missing object'));
    });

    test('validation accepts valid multi-action rule', () {
      final result = BuilderValidator().validate(
        _state(
          variables: [
            _variable('var_temp', 'Temperature', 25),
            _variable('var_alarm', 'Alarm', false),
          ],
          objects: [_object('obj_gauge', 'Gauge', 'gauge')],
          rules: [
            _rule(
              condition: {
                'variableId': 'var_temp',
                'operator': '>=',
                'value': 100,
              },
              actions: [
                {'type': 'show_warning', 'message': 'Hot'},
                {'type': 'hide_object', 'objectId': 'obj_gauge'},
                {
                  'type': 'set_variable',
                  'variableId': 'var_alarm',
                  'value': true,
                },
              ],
            ),
          ],
        ),
      );

      expect(result.isValid, isTrue);
    });

    test('validation rejects unknown trigger and missing set value', () {
      final result = BuilderValidator().validate(
        _state(
          variables: [_variable('var_temp', 'Temperature', 25)],
          rules: [
            _rule(
              trigger: 'any',
              condition: {
                'variableId': 'var_temp',
                'operator': '>=',
                'value': 100,
              },
              actions: [
                {'type': 'set_variable', 'targetVariable': 'var_temp'},
              ],
            ),
          ],
        ),
      );

      expect(result.isValid, isFalse);
      expect(result.errors.join('\n'), contains('unknown trigger'));
      expect(result.errors.join('\n'), contains('value is required'));
    });

    test('dependency graph produces variable rule action chain', () {
      final variables = [_variable('var_temp', 'Temperature', 25)];
      final rules = [
        _rule(
          condition: {'variableId': 'var_temp', 'operator': '>', 'value': 80},
          actions: [
            {'type': 'show_warning', 'message': 'Too hot'},
          ],
        ),
      ];

      final rows = RuleDependencyGraph.buildRows(
        variables: variables,
        rules: rules,
      );

      expect(rows, hasLength(1));
      expect(rows.single.variable, 'Temperature');
      expect(rows.single.rule, 'Runtime Rule');
      expect(rows.single.action, 'show_warning -> Too hot');
    });

    test('validation rejects toggle_variable for non-boolean variable', () {
      final result = BuilderValidator().validate(
        _state(
          variables: [_variable('var_counter', 'Counter', 0)],
          rules: [
            _rule(
              condition: {
                'variableId': 'var_counter',
                'operator': '>=',
                'value': 0,
              },
              actions: [
                {'type': 'toggle_variable', 'variableId': 'var_counter'},
              ],
            ),
          ],
        ),
      );

      expect(result.isValid, isFalse);
      expect(result.errors.join('\n'), contains('boolean variable'));
    });

    test('runtime launch fires multi-action rule correctly', () async {
      final world = RuntimeLoader.loadFromManifest(
        _state(
          variables: [
            _variable('var_temp', 'Temperature', 25),
            _variable('var_alarm', 'Alarm', false),
          ],
          objects: [_object('obj_gauge', 'Gauge', 'gauge')],
          rules: [
            _rule(
              condition: {
                'variableId': 'var_temp',
                'operator': '>=',
                'value': 100,
              },
              actions: [
                {'type': 'show_warning', 'message': 'Water is boiling'},
                {'type': 'hide_object', 'objectId': 'obj_gauge'},
                {
                  'type': 'set_variable',
                  'variableId': 'var_alarm',
                  'value': true,
                },
              ],
            ),
          ],
        ).generateManifestJson(),
      );
      final warningMessages = <String>[];
      final subscription = world.eventBus.stream.listen((event) {
        if (event.type == RuntimeEventType.warning) {
          warningMessages.add(event.message);
        }
      });

      world.variables.updateVariable('var_temp', 100, source: 'test');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(warningMessages, contains('Water is boiling'));
      expect(world.objects.getObjectState('obj_gauge')?.visible, isFalse);
      expect(world.variables.getValue('var_alarm'), isTrue);
      expect(world.analytics.rulesFired, 1);
      expect(world.analytics.actionsExecuted, 3);
      expect(world.analytics.builderRulesLoaded, 1);
      expect(world.analytics.builderRulesValidated, 1);
      expect(world.analytics.builderActionsConfigured, 3);

      await subscription.cancel();
      world.dispose();
    });
  });
}

ExperimentBuilderState _state({
  required List<BuilderVariable> variables,
  List<BuilderObject> objects = const [],
  List<BuilderRule> rules = const [],
}) {
  return ExperimentBuilderState(
    scene: BuilderScene(
      id: 'runtime_rule_scene',
      name: 'Runtime Rule Scene',
      description: 'Runtime-aware builder rule certification.',
      tags: const ['runtime-rule'],
    ),
    variables: variables,
    objects: objects,
    rules: rules,
  );
}

BuilderVariable _variable(String id, String name, dynamic value) {
  return BuilderVariable(
    id: id,
    name: name,
    type: value is bool ? 'toggle' : 'numberInput',
    defaultValue: value,
    description: name,
  );
}

BuilderObject _object(String id, String name, String type) {
  return BuilderObject(id: id, name: name, type: type, properties: const {});
}

BuilderRule _rule({
  String trigger = 'thresholdCrossed',
  required Map<String, dynamic> condition,
  required List<Map<String, dynamic>> actions,
}) {
  return BuilderRule(
    id: 'rule_runtime',
    name: 'Runtime Rule',
    trigger: trigger,
    condition: condition,
    actions: actions,
    description: 'Runtime-aware rule.',
    runtimeConfig: {
      'trigger': trigger,
      'condition': condition,
      'actions': actions,
    },
  );
}
