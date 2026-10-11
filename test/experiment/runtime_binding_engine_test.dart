import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/builder/templates/experiment_templates.dart';
import 'package:mentora/features/experiment/runtime/bindings/runtime_binding_engine.dart';
import 'package:mentora/features/experiment/runtime/bindings/runtime_binding_registry.dart';
import 'package:mentora/features/experiment/runtime/object_registry.dart';
import 'package:mentora/features/experiment/runtime/runtime_event_bus.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';
import 'package:mentora/features/experiment/runtime/variable_store.dart';

void main() {
  group('RuntimeBindingEngine', () {
    test('updates object state when a bound variable changes', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [_variable('var_temperature', 'temperature', 25)],
          objects: [
            _object('gauge_1', 'gauge', {'valueVariable': 'var_temperature'}),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final updatesBefore = world.analytics.objectsUpdated;
      world.variables.updateVariable('var_temperature', 100, source: 'test');
      await Future<void>.delayed(Duration.zero);

      expect(world.objects.getObjectState('gauge_1')?.state['value'], 100);
      expect(world.analytics.objectsUpdated - updatesBefore, 1);
      world.dispose();
    });

    test('updates multiple object states from one variable', () async {
      final world = RuntimeLoader.loadFromManifest(
        _manifest(
          variables: [_variable('var_temperature', 'temperature', 25)],
          objects: [
            _object('gauge_1', 'gauge', {'valueVariable': 'var_temperature'}),
            _object('counter_1', 'counter', {
              'valueVariable': 'var_temperature',
            }),
            _object('numeric_1', 'numericDisplay', {
              'valueVariable': 'var_temperature',
            }),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final updatesBefore = world.analytics.objectsUpdated;
      world.variables.updateVariable('var_temperature', 80, source: 'test');
      await Future<void>.delayed(Duration.zero);

      expect(world.objects.getObjectState('gauge_1')?.state['value'], 80);
      expect(world.objects.getObjectState('counter_1')?.state['value'], 80);
      expect(world.objects.getObjectState('numeric_1')?.state['value'], 80);
      expect(world.analytics.objectsUpdated - updatesBefore, 3);
      world.dispose();
    });

    test('emits BindingFailed for a missing variable', () async {
      final eventBus = RuntimeEventBus();
      final variables = VariableStore(eventBus: eventBus);
      final objects = ObjectRegistry();
      final registry = RuntimeBindingRegistry();
      final engine = RuntimeBindingEngine(
        variables: variables,
        objects: objects,
        registry: registry,
        eventBus: eventBus,
      );
      final messages = <String>[];
      final subscription = eventBus.stream.listen((event) {
        messages.add(event.message);
      });

      objects.initialize([
        _object('gauge_1', 'gauge', {'valueVariable': 'var_missing'}),
      ]);
      engine.initialize([
        _object('gauge_1', 'gauge', {'valueVariable': 'var_missing'}),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(messages, contains('BindingFailed'));
      expect(registry.allBindings().single.active, isFalse);

      await subscription.cancel();
      engine.dispose();
      variables.dispose();
      objects.dispose();
      eventBus.dispose();
    });

    test('discovers bindings for every built-in template without crashing', () {
      for (final template in ExperimentTemplates.allTemplates) {
        final world = RuntimeLoader.loadFromManifest(template);

        final objects = template['scene']?['objects'] as List?;
        if (objects != null && objects.isNotEmpty) {
          final hasBindingProperties = objects.any((obj) {
            final props = obj['properties'] as Map?;
            if (props == null) return false;
            return props.keys.any((key) =>
                const [
                  'variableId',
                  'valueVariable',
                  'sourceVariable',
                  'boundVariable',
                  'linkedVariable',
                  'linked_variable'
                ].contains(key) ||
                (key.toString().endsWith('_var') && key.toString().length > 4));
          });
          if (hasBindingProperties) {
            expect(
              world.bindings.allBindings(),
              isNotEmpty,
              reason: template['scene']?['name']?.toString(),
            );
          } else {
            expect(
              world.bindings.allBindings(),
              isEmpty,
              reason: template['scene']?['name']?.toString(),
            );
          }
        } else {
          expect(
            world.bindings.allBindings(),
            isEmpty,
            reason: template['scene']?['name']?.toString(),
          );
        }

        world.dispose();
      }
    });
  });
}

Map<String, dynamic> _manifest({
  required List<Map<String, dynamic>> variables,
  required List<Map<String, dynamic>> objects,
}) {
  return {
    'scene': {
      'sceneId': 'binding_test',
      'name': 'Binding Test',
      'variables': variables,
      'objects': objects,
      'rules': <Map<String, dynamic>>[],
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
