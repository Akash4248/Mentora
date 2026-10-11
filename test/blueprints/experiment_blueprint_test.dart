import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/blueprints/loader/blueprint_loader.dart';
import 'package:mentora/features/experiment/blueprints/registry/built_in_blueprints.dart';

void main() {
  test('built-in blueprints load from current experiment templates', () {
    final loader = BlueprintLoader();
    final registry = loader.loadBuiltIns();

    expect(registry.allBlueprints().length, 6);
    expect(
      registry.findBlueprint('blueprint_pendulum')?.name,
      contains('Pendulum'),
    );
    expect(
      registry.findBlueprint('blueprint_free_fall')?.manifest['scene'],
      isA<Map>(),
    );
  });

  test('blueprint serializes and deserializes', () {
    final blueprint = BuiltInBlueprints.all().first;
    final restored = BlueprintLoader().fromJson(blueprint.toJson());

    expect(restored.id, blueprint.id);
    expect(restored.parameters.length, blueprint.parameters.length);
    expect(
      restored.observationTemplate.columns,
      blueprint.observationTemplate.columns,
    );
  });
}
