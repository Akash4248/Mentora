import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/builder/templates/experiment_templates.dart';
import 'package:mentora/features/experiment/experience/lab_v2/stage/experiment_asset_registry.dart';
import 'package:mentora/features/experiment/experience/lab_v2/stage/scene_definition_resolver.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  group('Experiment-first runtime redesign', () {
    test('built-in templates resolve to recognizable experiment scenes', () {
      final expected = {
        'Free Fall Experiment': (
          scene: 'freeFall',
          anchors: {'height_scale', 'drop_zone', 'ground'},
        ),
        'Heart Rate Monitor': (
          scene: 'heartRate',
          anchors: {'heart', 'pulse_ring', 'ecg'},
        ),
        'Pendulum Motion': (
          scene: 'pendulum',
          anchors: {'support', 'measurement'},
        ),
        'Plant Growth': (
          scene: 'plantGrowth',
          anchors: {'sun', 'plant', 'soil'},
        ),
        'Water Cycle': (
          scene: 'waterCycle',
          anchors: {'sun', 'cloud', 'rain', 'water'},
        ),
      };

      for (final template in ExperimentTemplates.allTemplates) {
        final world = RuntimeLoader.loadFromManifest(template);
        final title = template['scene']?['name']?.toString() ?? '';
        final scene = const SceneDefinitionResolver().resolve(world);
        final expectedScene = expected[title]!;

        expect(scene.id, expectedScene.scene, reason: title);
        expect(scene.primaryObject, isNotEmpty, reason: title);
        expect(scene.primaryVariable, isNotEmpty, reason: title);
        expect(scene.primaryOutcome, isNotEmpty, reason: title);
        expect(scene.assetIds, isNotEmpty, reason: title);
        expect(
          scene.anchors.map((anchor) => anchor.id).toSet(),
          containsAll(expectedScene.anchors),
          reason: title,
        );
        world.dispose();
      }
    });

    test('scene assets are registered for all scene definitions', () {
      final registry = const ExperimentAssetRegistry();

      for (final template in ExperimentTemplates.allTemplates) {
        final world = RuntimeLoader.loadFromManifest(template);
        final scene = const SceneDefinitionResolver().resolve(world);
        final assets = registry.assetsFor(scene.assetIds);

        expect(assets.length, scene.assetIds.length, reason: scene.id);
        for (final asset in assets) {
          expect(asset.path, startsWith('assets/experiment_scenes/'));
          expect(asset.path.split('/'), hasLength(4));
          expect(asset.path, endsWith('.svg'));
          expect(asset.label, isNotEmpty);
        }
        world.dispose();
      }
    });
  });
}
