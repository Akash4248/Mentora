import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_variable.dart';
import 'package:mentora/features/experiment/runtime/models/variable_source.dart';
import 'package:mentora/features/experiment/runtime/models/variable_update_strategy.dart';
import 'package:mentora/features/experiment/runtime/runtime_event_bus.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';
import 'package:mentora/features/experiment/runtime/variable_store.dart';
import 'package:mentora/features/experiment/builder/templates/experiment_templates.dart';

void main() {
  group('RuntimeVariable', () {
    test('maps manifest variable type to source and update strategy', () {
      final sensor = RuntimeVariable.fromJson({
        'id': 'var_accel',
        'name': 'Acceleration',
        'type': 'accelerometer',
        'value': {'x': 0, 'y': 0, 'z': 0},
      });
      final constant = RuntimeVariable.fromJson({
        'id': 'var_gravity',
        'name': 'Gravity',
        'type': 'customConstant',
        'value': 9.8,
      });
      final manual = RuntimeVariable.fromJson({
        'id': 'var_temp',
        'name': 'Temperature',
        'type': 'numberInput',
        'value': 25,
      });

      expect(sensor.source, VariableSource.sensor);
      expect(sensor.updateStrategy, VariableUpdateStrategy.continuous);
      expect(constant.source, VariableSource.constant);
      expect(constant.updateStrategy, VariableUpdateStrategy.manual);
      expect(manual.source, VariableSource.manual);
      expect(manual.updateStrategy, VariableUpdateStrategy.eventDriven);
      expect(manual.isInitialized, isTrue);
    });

    test('serializes, copies, and describes debug state', () {
      final variable = RuntimeVariable.fromJson({
        'id': 'var_temp',
        'name': 'Temperature',
        'type': 'numberInput',
        'value': 25,
        'description': 'Atmospheric Temperature',
      });
      final updated = variable.copyWith(value: 30);

      expect(updated.value, 30);
      expect(updated.id, variable.id);
      expect(updated.toJson()['source'], 'manual');
      expect(updated.debugDescription(), contains('Temperature'));
      expect(updated.debugDescription(), contains('eventDriven'));
    });
  });

  group('VariableStore', () {
    test(
      'registers, updates, removes, and emits variable lifecycle events',
      () async {
        final bus = RuntimeEventBus();
        final events = <String>[];
        final subscription = bus.stream.listen((event) {
          events.add(event.message);
        });
        final store = VariableStore(eventBus: bus);

        store.registerVariable(
          RuntimeVariable.fromJson({
            'id': 'var_temp',
            'name': 'Temperature',
            'type': 'numberInput',
            'value': 25,
          }),
        );
        store.updateVariable('var_temp', 30, source: 'test');
        store.removeVariable('var_temp');

        await Future<void>.delayed(Duration.zero);

        expect(events, contains('VariableRegistered'));
        expect(events, contains('VariableUpdated'));
        expect(events, contains('VariableChanged'));
        expect(events, contains('VariableRemoved'));
        expect(store.containsVariable('var_temp'), isFalse);

        await subscription.cancel();
        store.dispose();
        bus.dispose();
      },
    );

    test('notifies variable subscribers on update', () {
      final store = VariableStore();
      RuntimeVariable? observed;
      store.registerVariable(
        RuntimeVariable.fromJson({
          'id': 'var_speed',
          'name': 'Speed',
          'type': 'numberInput',
          'value': 0,
        }),
      );

      store.subscribe('var_speed', (variable) {
        observed = variable;
      });
      store.updateVariable('var_speed', 12);

      expect(observed?.id, 'var_speed');
      expect(observed?.value, 12);
      store.dispose();
    });
  });

  group('RuntimeLoader variable migration', () {
    test('loads built-in templates into RuntimeVariable objects', () {
      for (final template in ExperimentTemplates.allTemplates) {
        final world = RuntimeLoader.loadFromManifest(template);

        expect(world.variables.getAllVariables(), isNotEmpty);
        expect(
          world.variables.getAllVariables().every(
            (variable) => variable.isInitialized,
          ),
          isTrue,
        );
        expect(
          world.variables.allVariables.length,
          world.variables.getAllVariables().length,
        );

        world.dispose();
      }
    });

    test('manual variable update increments runtime analytics', () async {
      final world = RuntimeLoader.loadFromManifest(
        ExperimentTemplates.heartRate,
      );
      final eventMessages = <String>[];
      final subscription = world.eventBus.stream.listen((event) {
        eventMessages.add(event.message);
      });

      world.variables.updateVariable('var_pulse', 72, source: 'test');
      await Future<void>.delayed(Duration.zero);

      expect(eventMessages, contains('VariableUpdated'));
      expect(world.analytics.variableUpdates, 1);

      await subscription.cancel();
      world.dispose();
    });
  });
}
