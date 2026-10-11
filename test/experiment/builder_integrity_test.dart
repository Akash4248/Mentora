import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/builder/controllers/experiment_builder_controller.dart';
import 'package:mentora/features/experiment/builder/data/api/experiment_manifest_api_service.dart';
import 'package:mentora/features/experiment/builder/data/repositories/experiment_manifest_repository.dart';
import 'package:mentora/features/experiment/builder/models/builder_object.dart';
import 'package:mentora/features/experiment/builder/models/builder_rule.dart';
import 'package:mentora/features/experiment/builder/models/builder_variable.dart';
import 'package:mentora/features/experiment/builder/storage/builder_draft.dart';
import 'package:mentora/features/experiment/builder/storage/builder_draft_manager.dart';
import 'package:mentora/features/experiment/builder/storage/builder_draft_repository.dart';
import 'package:mentora/features/experiment/builder/templates/experiment_templates.dart';
import 'package:mentora/features/experiment/builder/validation/builder_validator.dart';
import 'package:mentora/features/network/domain/backend_config.dart';

void main() {
  test('all built-in templates have valid references', () {
    final validator = BuilderValidator();
    final controller = _controller();

    for (final template in ExperimentTemplates.allTemplates) {
      controller.loadFromManifest(template);
      final result = validator.validate(controller.state);

      expect(result.errors, isEmpty, reason: template['scene']?['name']);
      expect(controller.state.objects, isNotEmpty);
      expect(controller.state.variables, isNotEmpty);
      expect(controller.state.rules, isNotEmpty);
    }

    controller.dispose();
  });

  test('deleting a variable removes dependent objects and rules', () {
    final controller = _controller();
    final variable = BuilderVariable(
      id: 'var_temperature',
      name: 'Temperature',
      type: 'numberInput',
      defaultValue: 25,
      description: 'Temperature',
    );
    final object = BuilderObject(
      id: 'obj_gauge',
      name: 'Temperature Gauge',
      type: 'gauge',
      properties: {'linked_variable': variable.id},
    );
    final rule = BuilderRule(
      id: 'rule_high_temp',
      name: 'High Temperature',
      condition: {'variableId': variable.id, 'operator': '>', 'value': 75},
      action: {'type': 'show_warning'},
      description: 'Warns on high temperature.',
    );

    controller.addVariable(variable);
    controller.addObject(object);
    controller.addRule(rule);
    controller.deleteVariable(variable.id);

    expect(controller.state.variables, isEmpty);
    expect(controller.state.objects, isEmpty);
    expect(controller.state.rules, isEmpty);
    expect(controller.currentValidation.errors, isEmpty);

    controller.dispose();
  });
}

ExperimentBuilderController _controller() {
  final config = BackendConfig(baseUrl: 'http://localhost', apiKey: 'test');
  return ExperimentBuilderController(
    draftManager: BuilderDraftManager(_MemoryDraftRepository()),
    manifestRepository: ExperimentManifestRepositoryImpl(
      ExperimentManifestApiService(config),
    ),
  );
}

class _MemoryDraftRepository implements BuilderDraftRepository {
  final List<BuilderDraft> _drafts = [];

  @override
  Future<void> deleteDraft(String draftId) async {
    _drafts.removeWhere((draft) => draft.draftId == draftId);
  }

  @override
  Future<List<BuilderDraft>> getDrafts() async => List.of(_drafts);

  @override
  Future<void> saveDraft(BuilderDraft draft) async {
    final index = _drafts.indexWhere((item) => item.draftId == draft.draftId);
    if (index >= 0) {
      _drafts[index] = draft;
    } else {
      _drafts.add(draft);
    }
  }
}
