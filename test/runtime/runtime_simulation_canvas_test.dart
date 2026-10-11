import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';
import 'package:mentora/features/experiment/runtime/runtime_analytics.dart';
import 'package:mentora/features/experiment/runtime/runtime_event.dart';
import 'package:mentora/features/experiment/runtime/simulation/actors/runtime_actor_registry.dart';
import 'package:mentora/features/experiment/runtime/simulation/bindings/runtime_visual_binding_engine.dart';
import 'package:mentora/features/experiment/runtime/simulation/canvas/runtime_simulation_canvas.dart';
import 'package:mentora/features/experiment/runtime/simulation/renderers/runtime_canvas_renderer.dart';
import 'package:mentora/features/experiment/runtime/runtime_event_bus.dart';

void main() {
  test('actor registry creates generic actor types only', () {
    final registry = RuntimeActorRegistry();

    for (final type in [
      'circle',
      'rectangle',
      'line',
      'arrow',
      'text',
      'image',
      'particle',
    ]) {
      final actor = registry.create({'id': '${type}_1', 'type': type});
      expect(actor.type, type);
      expect(actor.id, '${type}_1');
    }
  });

  test('visual binding updates actor property from variable updates', () async {
    final eventBus = RuntimeEventBus();
    final canvas = RuntimeSimulationCanvas(eventBus: eventBus)
      ..initialize([
        {'id': 'ball', 'type': 'circle', 'positionX': 0},
      ]);
    final engine =
        RuntimeVisualBindingEngine(eventBus: eventBus, canvas: canvas)
          ..initialize([
            {
              'id': 'bind_x',
              'variableId': 'var_x',
              'actorId': 'ball',
              'property': 'positionX',
            },
          ]);
    final analytics = RuntimeAnalytics();
    analytics.attach(eventBus);
    eventBus.emit(
      RuntimeEvent(
        id: 'variable_update_test',
        timestamp: DateTime.now(),
        type: RuntimeEventType.custom,
        message: 'VariableUpdated',
        metadata: {'variableId': 'var_x', 'newValue': 42},
      ),
    );

    await Future<void>.delayed(Duration.zero);

    expect(canvas.actor('ball')?.positionX, 42);
    expect(analytics.visualBindingsResolved, 1);

    engine.dispose();
    analytics.dispose();
    eventBus.dispose();
  });

  testWidgets('runtime canvas renderer paints visible actors', (tester) async {
    final canvas = RuntimeSimulationCanvas()
      ..initialize([
        {
          'id': 'label',
          'type': 'text',
          'positionX': 50,
          'positionY': 50,
          'text': 'Temperature',
        },
      ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: RuntimeCanvasView(canvas: canvas)),
      ),
    );

    expect(find.byType(RuntimeCanvasView), findsOneWidget);
    expect(canvas.actorCount, 1);
  });

  test(
    'world initializes simulation canvas, bindings, and animations',
    () async {
      final world = RuntimeLoader.loadFromManifest({
        'metadata': {'title': 'Simulation Test'},
        'scene': {
          'sceneId': 'sim_test',
          'name': 'Simulation Test',
          'variables': [
            {'id': 'var_x', 'name': 'X', 'type': 'number', 'value': 0},
          ],
          'objects': const [],
          'rules': const [],
          'actors': [
            {'id': 'ball', 'type': 'circle', 'positionX': 0},
          ],
          'visualBindings': [
            {'variableId': 'var_x', 'actorId': 'ball', 'property': 'positionX'},
          ],
          'animations': [
            {
              'id': 'spin',
              'actorId': 'ball',
              'type': 'rotate',
              'duration': 1,
              'speed': 3.14,
            },
          ],
        },
      });

      expect(world.simulationCanvas.actorCount, 1);
      expect(world.visualBindings.bindingCount, 1);
      expect(world.animationEngine.animationCount, 1);

      world.variables.updateVariable('var_x', 88);
      await Future<void>.delayed(Duration.zero);
      expect(world.simulationCanvas.actor('ball')?.positionX, 88);

      world.start();
      world.tick(0.5);
      expect(world.simulationCanvas.actor('ball')?.rotation, greaterThan(0));

      world.dispose();
    },
  );
}
