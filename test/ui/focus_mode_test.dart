import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/experience/scenes/scene_definition_v3.dart';
import 'package:mentora/features/experiment/experience/engine/runtime_experience_engine.dart';
import 'package:mentora/features/experiment/experience/models/runtime_experience.dart';
import 'package:mentora/features/experiment/experience/workspace/lab_workspace_analytics.dart';
import 'package:mentora/features/experiment/experience/workspace/runtime_lab_workspace.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  testWidgets('student mode starts immersive with collapsed lab sheet', (
    tester,
  ) async {
    final world = _world();
    final experience = RuntimeExperience.fromWorld(world);
    final analytics = LabWorkspaceAnalytics();
    final engine = RuntimeExperienceEngine(eventBus: world.eventBus)
      ..load(experience);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 500,
            child: RuntimeLabWorkspace(sceneDefinition: const SceneDefinitionV3(sceneId: 'test', backgroundAssets: [], actorAssets: [], effectAssets: [], theme: 'default'),
              world: world,
              experience: experience,
              engine: engine,
              onRecordObservation: world.recordObservation,
              onRun: world.start,
              onReset: world.stop,
              analytics: analytics,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Readings'), findsNothing);
    expect(find.byIcon(Icons.fullscreen), findsNothing);
    expect(analytics.visibleCanvasPercentage, greaterThanOrEqualTo(0.8));

    engine.dispose();
    world.dispose();
  });
}

dynamic _world() {
  return RuntimeLoader.loadFromManifest({
    'metadata': {'title': 'Focus Test'},
    'scene': {
      'sceneId': 'focus_test',
      'name': 'Focus Test',
      'variables': [
        {'id': 'var_a', 'name': 'A', 'type': 'number', 'value': 1},
      ],
      'objects': const [],
      'rules': const [],
    },
  });
}
