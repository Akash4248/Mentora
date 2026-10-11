import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/blueprints/loader/blueprint_runtime_converter.dart';
import 'package:mentora/features/experiment/blueprints/registry/built_in_blueprints.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  test('blueprint converts to runtime manifest', () {
    final blueprint = BuiltInBlueprints.all().firstWhere(
      (item) => item.id == 'blueprint_pendulum',
    );
    final manifest = BlueprintRuntimeConverter().toManifest(blueprint);

    expect(manifest['scene'], isA<Map>());
    expect(manifest['metadata']['experience'], isA<Map>());
    expect(
      (manifest['scene']['objects'] as List).any((object) {
        return object['objectType'] == 'slider';
      }),
      true,
    );
  });

  test('parameter update writes variable default into manifest', () {
    final blueprint = BuiltInBlueprints.all().firstWhere(
      (item) => item.id == 'blueprint_pendulum',
    );
    final manifest = BlueprintRuntimeConverter().toManifest(
      blueprint,
      parameterValues: {'param_angle': 30},
    );
    final variables = manifest['scene']['variables'] as List;
    final angle = variables.firstWhere((item) => item['id'] == 'var_angle');

    expect(angle['value'], 30);
  });

  test('converted blueprint loads into RuntimeWorld', () {
    final blueprint = BuiltInBlueprints.all().firstWhere(
      (item) => item.id == 'blueprint_heart_rate',
    );
    final manifest = BlueprintRuntimeConverter().toManifest(blueprint);
    final world = RuntimeLoader.loadFromManifest(manifest);

    expect(world.variables.containsVariable('heart_rate'), true);
    expect(
      world.objects.allObjectStates.any(
        (state) => state.objectType == 'slider',
      ),
      true,
    );

    world.dispose();
  });
}
