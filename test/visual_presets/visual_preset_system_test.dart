import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/blueprints/loader/blueprint_runtime_converter.dart';
import 'package:mentora/features/experiment/blueprints/registry/built_in_blueprints.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';
import 'package:mentora/features/experiment/visual_presets/composer/simulation_scene_composer.dart';
import 'package:mentora/features/experiment/visual_presets/registry/visual_preset_registry.dart';

void main() {
  test('registry looks up built-in visual presets', () {
    final registry = VisualPresetRegistry();

    expect(registry.find('pendulum')?.name, 'Pendulum Preset');
    expect(registry.find('freeFall')?.name, 'Free Fall Preset');
    expect(registry.find('heartRate')?.name, 'Heart Rate Preset');
    expect(registry.find('waterCycle')?.name, 'Water Cycle Preset');
    expect(registry.find('plantGrowth')?.name, 'Plant Growth Preset');
  });

  test('pendulum preset generates actors', () {
    final world = _worldFromBlueprint('blueprint_pendulum');

    expect(world.simulationCanvas.actor('preset_pendulum_anchor'), isNotNull);
    expect(world.simulationCanvas.actor('preset_pendulum_bob'), isNotNull);
    expect(world.simulationCanvas.actor('preset_pendulum_rod'), isNotNull);

    world.dispose();
  });

  test('free fall height update changes actor position', () async {
    final manifest = _manifestWithHeightVariable();
    final world = RuntimeLoader.loadFromManifest(manifest);
    final before = world.simulationCanvas
        .actor('preset_free_fall_object')
        ?.positionY;

    world.variables.updateVariable('var_height', 100);
    await Future<void>.delayed(Duration.zero);
    final after = world.simulationCanvas
        .actor('preset_free_fall_object')
        ?.positionY;

    expect(after, isNot(equals(before)));

    world.dispose();
  });

  test('heart rate changes pulse ring scale', () async {
    final world = _worldFromBlueprint('blueprint_heart_rate');
    final before = world.simulationCanvas
        .actor('preset_heart_pulse_ring')
        ?.scale;

    world.variables.updateVariable('var_pulse', 160);
    await Future<void>.delayed(Duration.zero);
    final after = world.simulationCanvas
        .actor('preset_heart_pulse_ring')
        ?.scale;

    expect(after, greaterThan(before!));

    world.dispose();
  });

  test('water cycle preset generates full scene', () {
    final world = _worldFromBlueprint('blueprint_water_cycle');

    expect(world.simulationCanvas.actor('preset_water_ocean'), isNotNull);
    expect(world.simulationCanvas.actor('preset_water_cloud'), isNotNull);
    expect(world.simulationCanvas.actor('preset_water_sun'), isNotNull);
    expect(world.simulationCanvas.actor('preset_water_evap_arrow'), isNotNull);

    world.dispose();
  });

  test('composer converts blueprint into scene', () {
    final blueprint = BuiltInBlueprints.all().firstWhere(
      (item) => item.id == 'blueprint_plant_growth',
    );
    final world = _worldFromBlueprint('blueprint_plant_growth');
    final composer = SimulationSceneComposer(
      registry: VisualPresetRegistry(),
      eventBus: world.eventBus,
    );

    final scene = composer.composeBlueprint(blueprint, world);

    expect(scene?.presetId, 'plantGrowth');
    expect(scene?.actors.length, greaterThanOrEqualTo(5));
    expect(scene?.bindings.length, greaterThanOrEqualTo(2));

    world.dispose();
  });

  test(
    'runtime integration builds preset scene from blueprint manifest',
    () async {
      final world = _worldFromBlueprint('blueprint_pendulum');

      expect(world.metadata['visualPreset'], 'pendulum');
      expect(world.simulationCanvas.actor('preset_pendulum_rod'), isNotNull);
      await Future<void>.delayed(Duration.zero);
      expect(world.analytics.presetSceneBuilds, greaterThanOrEqualTo(1));

      world.dispose();
    },
  );
}

dynamic _worldFromBlueprint(String blueprintId) {
  final blueprint = BuiltInBlueprints.all().firstWhere(
    (item) => item.id == blueprintId,
  );
  final manifest = BlueprintRuntimeConverter().toManifest(blueprint);
  return RuntimeLoader.loadFromManifest(manifest);
}

Map<String, dynamic> _manifestWithHeightVariable() {
  return {
    'metadata': {'title': 'Free Fall Height Test', 'visualPreset': 'freeFall'},
    'scene': {
      'sceneId': 'free_fall_height_test',
      'name': 'Free Fall Height Test',
      'variables': [
        {'id': 'var_height', 'name': 'Height', 'type': 'number', 'value': 0},
      ],
      'objects': const [],
      'rules': const [],
    },
  };
}
