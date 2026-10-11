import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/builder/templates/experiment_templates.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_layout.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_state.dart';
import 'package:mentora/features/experiment/runtime/objects/behavior/runtime_object_behavior_registry.dart';
import 'package:mentora/features/experiment/runtime/objects/renderers/runtime_object_renderer_registry.dart';
import 'package:mentora/features/experiment/runtime/objects/runtime_object_lifecycle_manager.dart';
import 'package:mentora/features/experiment/runtime/objects/schema/runtime_object_schema_registry.dart';
import 'package:mentora/features/experiment/runtime/runtime_event_bus.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  const p0ObjectTypes = [
    'numericDisplay',
    'textDisplay',
    'gauge',
    'progressBar',
    'button',
    'slider',
  ];

  group('Runtime object foundation', () {
    test('schema registry registers all P0 schemas', () {
      final registry = RuntimeObjectSchemaRegistry();

      for (final objectType in p0ObjectTypes) {
        expect(registry.containsSchema(objectType), isTrue);
      }
      expect(registry.getSchema('numericDisplay')?.defaultState['value'], 0);
    });

    test('behavior registry creates all P0 behaviors', () {
      final registry = RuntimeObjectBehaviorRegistry();

      for (final objectType in p0ObjectTypes) {
        final behavior = registry.createBehavior(objectType);
        expect(behavior, isNotNull);
        behavior?.dispose();
      }
    });

    test('renderer registry creates all P0 renderers', () {
      final registry = RuntimeObjectRendererRegistry();

      for (final objectType in p0ObjectTypes) {
        final renderer = registry.createRenderer(objectType);
        expect(renderer, isNotNull);
        renderer?.dispose();
      }
    });

    test('lifecycle manager applies schema, behavior, and renderer', () async {
      final eventBus = RuntimeEventBus();
      final lifecycle = RuntimeObjectLifecycleManager(
        schemaRegistry: RuntimeObjectSchemaRegistry(),
        behaviorRegistry: RuntimeObjectBehaviorRegistry(),
        rendererRegistry: RuntimeObjectRendererRegistry(),
        eventBus: eventBus,
      );

      final initialized = lifecycle.initializeObject(
        RuntimeObjectState(
          objectId: 'numeric_1',
          objectType: 'numericDisplay',
          state: const {'value': 42},
          visible: true,
          updatedAt: DateTime.now(),
          layout: const RuntimeObjectLayout(
            x: 0,
            y: 0,
            width: 180,
            height: 96,
            alignment: 'center',
          ),
        ),
      );
      lifecycle.onStateUpdated(initialized.withProperty('value', 64));
      await Future<void>.delayed(Duration.zero);

      final status = lifecycle.getStatus('numeric_1');
      expect(initialized.state['unit'], '');
      expect(initialized.state['precision'], 1);
      expect(status?.schemaLoaded, isTrue);
      expect(status?.behaviorLoaded, isTrue);
      expect(status?.rendererLoaded, isTrue);
      expect(status?.isValid, isTrue);

      lifecycle.dispose();
      eventBus.dispose();
    });

    test('built-in templates load without runtime object crashes', () {
      for (final template in ExperimentTemplates.allTemplates) {
        final world = RuntimeLoader.loadFromManifest(template);

        expect(world.objects.allObjectStates, isNotNull);
        expect(
          world.objectLifecycle.getAllStatuses().length,
          world.objects.allObjectStates.length,
        );

        world.dispose();
      }
    });
  });
}
