import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';
import 'package:mentora/features/experiment/runtime/runtime_event.dart';

void main() {
  group('Runtime rule system', () {
    test(
      'builder-style threshold rule shows warning when variable changes',
      () async {
        final world = RuntimeLoader.loadFromManifest(
          _manifest(
            variables: [_variable('var_temperature', 'Temperature', 25)],
            objects: [
              _object('slider_temperature', 'slider', {
                'linked_variable': 'var_temperature',
              }),
              _object('gauge_temperature', 'gauge', {
                'linked_variable': 'var_temperature',
              }),
            ],
            rules: [
              _rule(
                'rule_boiling',
                'Boiling Warning',
                {
                  'variableId': 'var_temperature',
                  'operator': '>=',
                  'value': 100,
                },
                {'type': 'show_warning', 'message': 'Water is boiling!'},
              ),
            ],
          ),
        );
        final warnings = <RuntimeEvent>[];
        final subscription = world.eventBus.stream.listen((event) {
          if (event.type == RuntimeEventType.warning) warnings.add(event);
        });

        world.objectVariableAdapter.changeSlider('slider_temperature', 100);
        await Future<void>.delayed(Duration.zero);

        expect(warnings.single.message, 'Water is boiling!');
        expect(world.analytics.rulesEvaluated, 1);
        expect(world.analytics.rulesPassed, 1);
        expect(world.analytics.rulesFired, 1);
        expect(world.analytics.actionsExecuted, 1);
        expect(world.analytics.warningsGenerated, 1);
        expect(world.rules.ruleStates.single.fireCount, 1);

        await subscription.cancel();
        world.dispose();
      },
    );

    test('rule hides object when boolean variable changes', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [_variable('var_show_gauge', 'ShowGauge', true)],
          objects: [
            _object('toggle_show', 'toggle', {
              'linked_variable': 'var_show_gauge',
            }),
            _object('gauge_temperature', 'gauge', {
              'linked_variable': 'var_show_gauge',
            }),
          ],
          rules: [
            _rule(
              'rule_hide_gauge',
              'Hide Gauge',
              {
                'variableId': 'var_show_gauge',
                'operator': '==',
                'value': false,
              },
              {'type': 'hide_object', 'objectId': 'gauge_temperature'},
            ),
          ],
        ),
      );

      world.objectVariableAdapter.setToggle('toggle_show', false);
      await Future<void>.delayed(Duration.zero);

      expect(world.objects.getObjectState('gauge_temperature')?.visible, false);
      expect(world.analytics.rulesFired, 1);
      expect(world.analytics.actionsExecuted, 1);

      world.dispose();
    });

    test(
      'rule set_variable action mutates variable and updates display binding',
      () async {
        final world = RuntimeLoader.loadFromManifest(
          _manifest(
            variables: [
              _variable('var_counter_trigger', 'CounterTrigger', false),
              _variable('var_counter', 'Counter', 0),
            ],
            objects: [
              _object('button_counter', 'button', {
                'linked_variable': 'var_counter_trigger',
              }),
              _object('counter_display', 'numericDisplay', {
                'linked_variable': 'var_counter',
              }),
            ],
            rules: [
              _rule(
                'rule_set_counter',
                'Set Counter',
                {
                  'variableId': 'var_counter_trigger',
                  'operator': '==',
                  'value': true,
                },
                {
                  'type': 'set_variable',
                  'variableId': 'var_counter',
                  'value': 1,
                },
              ),
            ],
          ),
        );

        world.objectVariableAdapter.pressButton('button_counter');
        await Future<void>.delayed(Duration.zero);

        expect(world.variables.getValue('var_counter'), 1);
        expect(
          world.objects.getObjectState('counter_display')?.state['value'],
          1,
        );
        expect(world.analytics.rulesFired, 1);
        expect(world.analytics.actionsExecuted, 1);

        world.dispose();
      },
    );

    test('toggle_variable action flips boolean variable', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [
            _variable('var_alarm_trigger', 'AlarmTrigger', false),
            _variable('var_alarm', 'Alarm', false),
          ],
          objects: [
            _object('toggle_alarm_trigger', 'toggle', {
              'linked_variable': 'var_alarm_trigger',
            }),
          ],
          rules: [
            _rule(
              'rule_toggle_alarm',
              'Toggle Alarm',
              {
                'variableId': 'var_alarm_trigger',
                'operator': '==',
                'value': true,
              },
              {'type': 'toggle_variable', 'variableId': 'var_alarm'},
            ),
          ],
        ),
      );

      world.objectVariableAdapter.setToggle('toggle_alarm_trigger', true);
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_alarm'), true);
      expect(world.analytics.rulesFired, 1);
      expect(world.analytics.actionsExecuted, 1);

      world.dispose();
    });
  });
}

Map<String, dynamic> _manifest({
  required List<Map<String, dynamic>> variables,
  required List<Map<String, dynamic>> objects,
  required List<Map<String, dynamic>> rules,
}) {
  return {
    'scene': {
      'sceneId': 'runtime_rule_test',
      'name': 'Runtime Rule Test',
      'variables': variables,
      'objects': objects,
      'rules': rules,
    },
  };
}

Map<String, dynamic> _variable(String id, String name, dynamic value) {
  return {'id': id, 'name': name, 'type': 'numberInput', 'value': value};
}

Map<String, dynamic> _object(
  String objectId,
  String objectType,
  Map<String, dynamic> properties,
) {
  return {
    'objectId': objectId,
    'name': objectId,
    'objectType': objectType,
    'properties': properties,
  };
}

Map<String, dynamic> _rule(
  String ruleId,
  String name,
  Map<String, dynamic> condition,
  Map<String, dynamic> action,
) {
  return {
    'ruleId': ruleId,
    'name': name,
    'trigger': 'any',
    'condition': condition,
    'action': action,
    'description': name,
  };
}
