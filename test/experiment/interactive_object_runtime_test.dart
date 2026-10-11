import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  group('Interactive object runtime', () {
    test('slider updates VariableStore and bound display objects', () async {
      final world = RuntimeLoader.loadFromManifest(_interactiveManifest());
      await Future<void>.delayed(Duration.zero);

      world.objectVariableAdapter.changeSlider('slider_temperature', 75);
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_temperature'), 75);
      expect(
        world.objects.getObjectState('slider_temperature')?.state['value'],
        75,
      );
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
      expect(world.analytics.sliderInteractions, 1);

      world.dispose();
    });

    test('toggle tap path changes a boolean variable', () async {
      final world = RuntimeLoader.loadFromManifest(_interactiveManifest());
      await Future<void>.delayed(Duration.zero);

      world.objectVariableAdapter.setToggle('toggle_power', true);
      await Future<void>.delayed(Duration.zero);

      expect(world.variables.getValue('var_power'), isTrue);
      expect(
        world.objects.getObjectState('toggle_power')?.state['value'],
        true,
      );
      expect(world.analytics.toggleInteractions, 1);

      world.dispose();
    });

    test('button press emits events and updates bound variable', () async {
      final world = RuntimeLoader.loadFromManifest(_interactiveManifest());
      final messages = <String>[];
      final subscription = world.eventBus.stream.listen((event) {
        messages.add(event.message);
      });
      await Future<void>.delayed(Duration.zero);

      world.objectVariableAdapter.pressButton('button_start');
      world.objectVariableAdapter.releaseButton('button_start');
      await Future<void>.delayed(Duration.zero);

      expect(messages, contains('ButtonPressed'));
      expect(messages, contains('ButtonReleased'));
      expect(world.variables.getValue('var_start'), isFalse);
      expect(
        world.objects.getObjectState('button_start')?.state['pressed'],
        false,
      );
      expect(
        world.objects.getObjectState('button_start')?.state['pressCount'],
        1,
      );
      expect(world.analytics.buttonInteractions, 2);

      await subscription.cancel();
      world.dispose();
    });
  });
}

Map<String, dynamic> _interactiveManifest() {
  return {
    'scene': {
      'sceneId': 'interactive_certification',
      'name': 'Interactive Certification',
      'variables': [
        {
          'id': 'var_temperature',
          'name': 'Temperature',
          'type': 'numberInput',
          'value': 25,
        },
        {'id': 'var_power', 'name': 'Power', 'type': 'toggle', 'value': false},
        {'id': 'var_start', 'name': 'Start', 'type': 'toggle', 'value': false},
      ],
      'objects': [
        _object('slider_temperature', 'slider', {
          'linked_variable': 'var_temperature',
        }),
        _object('numeric_temperature', 'numericDisplay', {
          'linked_variable': 'var_temperature',
        }),
        _object('gauge_temperature', 'gauge', {
          'linked_variable': 'var_temperature',
        }),
        _object('progress_temperature', 'progressBar', {
          'linked_variable': 'var_temperature',
        }),
        _object('toggle_power', 'toggle', {'linked_variable': 'var_power'}),
        _object('button_start', 'button', {'linked_variable': 'var_start'}),
      ],
      'rules': <Map<String, dynamic>>[],
    },
  };
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
