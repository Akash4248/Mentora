import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/blueprints/registry/built_in_blueprints.dart';
import 'package:mentora/features/experiment/blueprints/validation/blueprint_validator.dart';

void main() {
  test('built-in blueprints pass validation', () {
    final validator = BlueprintValidator();

    for (final blueprint in BuiltInBlueprints.all()) {
      final result = validator.validate(blueprint);
      expect(result.valid, true, reason: '${blueprint.id}: ${result.errors}');
    }
  });
}
