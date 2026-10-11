import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/experience/scenes/scene_definition_v3.dart';
import 'package:mentora/features/experiment/experience/engine/runtime_experience_engine.dart';
import 'package:mentora/features/experiment/experience/lab_v2/widgets/instrument_controls.dart';
import 'package:mentora/features/experiment/experience/models/runtime_experience.dart';
import 'package:mentora/features/experiment/experience/workspace/lab_workspace_analytics.dart';
import 'package:mentora/features/experiment/experience/workspace/runtime_lab_workspace.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  testWidgets('instrument controls update slider state', (tester) async {
    final world = _world();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              InstrumentControls(
                objectRegistry: world.objects,
                eventBus: world.eventBus,
                onRun: () {},
                onReset: () {},
              ),
            ],
          ),
        ),
      ),
    );

    final slider = tester.widget<Slider>(find.byType(Slider));
    slider.onChanged?.call(4);
    await tester.pump();

    expect(world.objects.getObjectState('control_length')?.state['value'], 4);

    world.dispose();
  });

  testWidgets('runtime workspace exposes floating lab sheet labels', (
    tester,
  ) async {
    final world = _world();
    final experience = RuntimeExperience.fromWorld(world);
    final engine = RuntimeExperienceEngine(eventBus: world.eventBus)
      ..load(experience);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1000,
            height: 620,
            child: RuntimeLabWorkspace(sceneDefinition: const SceneDefinitionV3(sceneId: 'test', backgroundAssets: [], actorAssets: [], effectAssets: [], theme: 'default'),
              world: world,
              experience: experience,
              engine: engine,
              onRecordObservation: world.recordObservation,
              onRun: world.start,
              onReset: world.stop,
              analytics: LabWorkspaceAnalytics(),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Readings'), findsNothing);
    expect(find.text('Visuals'), findsNothing);
    expect(find.text('Results'), findsNothing);

    await tester.pump(const Duration(seconds: 4));

    engine.dispose();
    world.dispose();
  });
}

dynamic _world() {
  return RuntimeLoader.loadFromManifest({
    'metadata': {'title': 'Immersive Lab Test'},
    'scene': {
      'sceneId': 'immersive_lab_test',
      'name': 'Immersive Lab Test',
      'variables': [
        {'id': 'var_length', 'name': 'Length', 'type': 'number', 'value': 1},
      ],
      'objects': [
        {
          'id': 'control_length',
          'objectId': 'control_length',
          'type': 'slider',
          'objectType': 'slider',
          'state': {'label': 'Length', 'value': 1, 'min': 0, 'max': 5},
        },
      ],
      'rules': const [],
    },
  });
}
