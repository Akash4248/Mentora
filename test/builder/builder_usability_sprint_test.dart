import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/builder/controllers/experiment_builder_controller.dart';
import 'package:mentora/features/experiment/builder/data/api/experiment_manifest_api_service.dart';
import 'package:mentora/features/experiment/builder/data/repositories/experiment_manifest_repository.dart';
import 'package:mentora/features/experiment/builder/models/builder_object.dart';
import 'package:mentora/features/experiment/builder/models/builder_rule.dart';
import 'package:mentora/features/experiment/builder/models/builder_scene.dart';
import 'package:mentora/features/experiment/builder/models/builder_variable.dart';
import 'package:mentora/features/experiment/builder/models/experiment_builder_state.dart';
import 'package:mentora/features/experiment/builder/storage/builder_draft.dart';
import 'package:mentora/features/experiment/builder/storage/builder_draft_manager.dart';
import 'package:mentora/features/experiment/builder/storage/builder_draft_repository.dart';
import 'package:mentora/features/experiment/builder/templates/experiment_templates.dart';
import 'package:mentora/features/experiment/builder/validation/builder_validator.dart';
import 'package:mentora/features/experiment/builder/widgets/builder_search_bar.dart';
import 'package:mentora/features/experiment/builder/widgets/design_workspace_panel.dart';
import 'package:mentora/features/experiment/builder/widgets/experiment_summary_card.dart';
import 'package:mentora/features/experiment/builder/widgets/launch_readiness_card.dart';
import 'package:mentora/features/experiment/builder/widgets/rule_editor.dart';
import 'package:mentora/features/experiment/builder/widgets/variable_editor.dart';
import 'package:mentora/features/experiment/builder/wizards/object_wizard_dialog.dart';
import 'package:mentora/features/experiment/builder/wizards/rule_wizard_dialog.dart';
import 'package:mentora/features/experiment/builder/wizards/variable_wizard_dialog.dart';
import 'package:mentora/features/network/domain/backend_config.dart';

void main() {
  group('builder usability sprint', () {
    test('template import populates builder state and report', () {
      final controller = _controller();

      for (final template in ExperimentTemplates.allTemplates) {
        controller.importTemplate(template);

        expect(controller.state.variables.length, greaterThan(0));
        expect(controller.state.objects.length, greaterThan(0));
        expect(controller.state.rules.length, greaterThan(0));
        expect(controller.lastTemplateImportReport?.populated, isTrue);
      }
      expect(
        controller.analytics.templatesImported,
        ExperimentTemplates.allTemplates.length,
      );

      controller.dispose();
    });

    test('summary card model updates from state', () {
      final summary = ExperimentSummaryCard.summarize(
        _state(
          variables: [
            _variable('var_accel_1', 'Accelerometer', 'accelerometer', {}),
            _variable('var_temp', 'Temperature', 'numberInput', 25),
          ],
          rules: [_rule('rule_1', 'var_temp')],
        ),
      );

      expect(summary.variables, 2);
      expect(summary.rules, 1);
      expect(summary.sensors, 1);
    });

    test('readiness card reflects validation state', () {
      final ready = LaunchReadinessCard.fromValidation(
        BuilderValidator().validate(
          _state(
            variables: [
              _variable('var_temp', 'Temperature', 'numberInput', 25),
            ],
            rules: [_rule('rule_1', 'var_temp')],
          ),
        ),
      );
      final warning = LaunchReadinessCard.fromValidation(
        BuilderValidator().validate(
          _state(
            variables: [
              _variable('var_temp', 'Temperature', 'numberInput', 25),
            ],
            rules: [_rule('rule_1', 'var_missing')],
          ),
        ),
      );

      expect(ready.level, LaunchReadinessLevel.ready);
      expect(warning.level, LaunchReadinessLevel.warning);
    });

    test('search filtering works for variables and rules', () {
      final variables = [
        _variable('var_temp', 'Temperature', 'numberInput', 25),
        _variable('var_speed', 'Speed', 'numberInput', 1),
      ];
      final rules = [
        _rule('rule_temp', 'var_temp', name: 'Temperature Warning'),
        _rule('rule_speed', 'var_speed', name: 'Speed Warning'),
      ];

      final filteredVariables = BuilderSearchBar.filter(
        variables,
        'temp',
        (variable) => [variable.name, variable.id, variable.type],
      );
      final filteredRules = BuilderSearchBar.filter(
        rules,
        'speed',
        (rule) => [rule.name, rule.id, rule.trigger],
      );

      expect(filteredVariables.single.id, 'var_temp');
      expect(filteredRules.single.id, 'rule_speed');
    });

    testWidgets('large variable list can reach the last item', (tester) async {
      final controller = _controller();
      for (var i = 1; i <= 100; i++) {
        controller.addVariable(
          _variable('var_$i', 'Variable $i', 'numberInput', i),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: VariableEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Variable 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Variable 100'),
        500,
        scrollable: _scrollableIn(
          const PageStorageKey<String>('builder_variables_list'),
        ),
      );

      expect(find.text('Variable 100'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('large object list can reach the last item in Design tabs', (
      tester,
    ) async {
      final controller = _controller();
      for (var i = 1; i <= 100; i++) {
        controller.addObject(_object('obj_$i', 'Object $i', 'numericDisplay'));
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 720,
              child: DesignWorkspacePanel(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tabController = DefaultTabController.of(
        tester.element(find.byType(TabBar)),
      );
      tabController.animateTo(2);
      await tester.pumpAndSettle();

      expect(find.text('Object 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Object 100'),
        500,
        scrollable: _scrollableIn(
          const PageStorageKey<String>('builder_objects_list'),
        ),
      );

      expect(find.text('Object 100'), findsOneWidget);

      controller.dispose();
    });

    testWidgets('large rule list can reach the last item', (tester) async {
      final controller = _controller();
      for (var i = 1; i <= 100; i++) {
        controller.addRule(_rule('rule_$i', 'var_$i', name: 'Rule $i'));
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 640,
              child: RuleEditor(controller: controller),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rule 1'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Rule 100'),
        500,
        scrollable: _scrollableIn(
          const PageStorageKey<String>('builder_rules_list'),
        ),
      );

      expect(find.text('Rule 100'), findsOneWidget);

      controller.dispose();
    });

    testWidgets(
      'variable type selection step scrolls to the last computed type',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: VariableWizardDialog()),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Calculated Value'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        await tester.scrollUntilVisible(
          find.text('Energy'),
          300,
          scrollable: _scrollableIn(
            const PageStorageKey<String>('variable_wizard_step_scroll'),
          ),
        );

        expect(find.text('Energy'), findsOneWidget);
      },
    );

    testWidgets('object selection step scrolls to the last object type', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ObjectWizardDialog(
            availableVariables: [
              _variable('var_1', 'Variable 1', 'numberInput', 1),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Vector Visualizer'),
        300,
        scrollable: _scrollableIn(
          const PageStorageKey<String>('object_wizard_step_scroll'),
        ),
      );

      expect(find.text('Vector Visualizer'), findsOneWidget);
    });

    testWidgets('logic selection step scrolls to the last rule type', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: RuleWizardDialog(
            availableVariables: [
              _variable('var_1', 'Variable 1', 'numberInput', 1),
            ],
            availableObjects: [_object('obj_1', 'Object 1', 'numericDisplay')],
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Data Collection'),
        300,
        scrollable: _scrollableIn(
          const PageStorageKey<String>('rule_wizard_step_scroll'),
        ),
      );

      expect(find.text('Data Collection'), findsOneWidget);
    });
  });
}

Finder _scrollableIn(Key key) {
  return find
      .descendant(of: find.byKey(key), matching: find.byType(Scrollable))
      .last;
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

ExperimentBuilderState _state({
  required List<BuilderVariable> variables,
  List<BuilderRule> rules = const [],
}) {
  return ExperimentBuilderState(
    scene: BuilderScene(
      id: 'ux_scene',
      name: 'UX Scene',
      description: 'Builder UX test scene',
      tags: const ['ux'],
    ),
    variables: variables,
    objects: const [],
    rules: rules,
  );
}

BuilderVariable _variable(String id, String name, String type, dynamic value) {
  return BuilderVariable(
    id: id,
    name: name,
    type: type,
    defaultValue: value,
    description: name,
  );
}

BuilderObject _object(String id, String name, String type) {
  return BuilderObject(id: id, name: name, type: type, properties: const {});
}

BuilderRule _rule(String id, String variableId, {String name = 'Rule'}) {
  return BuilderRule(
    id: id,
    name: name,
    trigger: 'thresholdCrossed',
    condition: {'variableId': variableId, 'operator': '>', 'value': 10},
    actions: [
      {'type': 'show_warning', 'message': 'Warning'},
    ],
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
