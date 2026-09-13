import 'package:flutter/material.dart';
import '../controllers/experiment_builder_controller.dart';
import '../widgets/rule_editor.dart';
import '../widgets/builder_drafts_screen.dart';

import '../widgets/design_workspace_panel.dart';
import '../widgets/preview_workspace_panel.dart';
import '../widgets/publish_workspace_panel.dart';
import '../widgets/builder_workflow_sidebar.dart';
import '../widgets/experiment_summary_card.dart';
import '../widgets/launch_readiness_card.dart';

import '../storage/builder_draft_manager.dart';
import '../storage/builder_draft_repository.dart';
import '../data/repositories/experiment_manifest_repository.dart';
import '../data/api/experiment_manifest_api_service.dart';
import '../../../network/domain/backend_config.dart';
import '../templates/experiment_templates.dart';
import '../models/builder_analytics.dart';

import '../ai/controllers/ai_generator_controller.dart';
import '../ai/repositories/ai_experiment_repository.dart';
import '../ai/api/ai_experiment_api_service.dart';
import '../ai/widgets/ai_generator_tab.dart';
import '../../presentation/screens/experiment_catalog_screen.dart';

class ExperimentBuilderScreen extends StatefulWidget {
  const ExperimentBuilderScreen({super.key});

  @override
  State<ExperimentBuilderScreen> createState() =>
      _ExperimentBuilderScreenState();
}

class _ExperimentBuilderScreenState extends State<ExperimentBuilderScreen>
    with SingleTickerProviderStateMixin {
  late final ExperimentBuilderController _controller;
  late final AiGeneratorController _aiController;

  @override
  void initState() {
    super.initState();
    final config =
        BackendConfig.fromEnvironment() ??
        BackendConfig(baseUrl: 'http://localhost', apiKey: 'dummy');

    // Core Builder Config
    final apiService = ExperimentManifestApiService(config);
    final repo = ExperimentManifestRepositoryImpl(apiService);
    final draftManager = BuilderDraftManager(
      SharedPreferencesBuilderDraftRepository(),
    );

    _controller = ExperimentBuilderController(
      draftManager: draftManager,
      manifestRepository: repo,
    );

    // AI Generator Config
    final aiApiService = AiExperimentApiService(config);
    final aiRepo = AiExperimentRepositoryImpl(aiApiService);

    _aiController = AiGeneratorController(
      aiRepository: aiRepo,
      manifestRepository: repo,
    );
  }

  @override
  void dispose() {
    _aiController.dispose();
    _controller.dispose();
    super.dispose();
  }

  BuilderWorkflowStep _currentStep = BuilderWorkflowStep.create;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Experiment Builder'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 800;

          if (isMobile) {
            return Column(
              children: [
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: _buildWorkspaceForStep(_currentStep),
                  ),
                ),
                BottomNavigationBar(
                  type: BottomNavigationBarType.fixed,
                  backgroundColor: const Color(0xFF0F172A),
                  selectedItemColor: const Color(0xFF3B82F6),
                  unselectedItemColor: const Color(0xFF64748B),
                  currentIndex: BuilderWorkflowStep.values.indexOf(
                    _currentStep,
                  ),
                  onTap: (index) {
                    setState(() {
                      _currentStep = BuilderWorkflowStep.values[index];
                    });
                  },
                  items: const [
                    BottomNavigationBarItem(
                      icon: Icon(Icons.add_circle_outline),
                      label: 'Overview',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.design_services),
                      label: 'Components',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.account_tree),
                      label: 'Interactions',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.play_circle_outline),
                      label: 'Simulation',
                    ),
                    BottomNavigationBarItem(
                      icon: Icon(Icons.publish),
                      label: 'Share',
                    ),
                  ],
                ),
              ],
            );
          }

          // Desktop / Large Tablet Layout
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BuilderWorkflowSidebar(
                currentStep: _currentStep,
                controller: _controller,
                onStepSelected: (step) {
                  setState(() {
                    _currentStep = step;
                  });
                },
              ),
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: _buildWorkspaceForStep(_currentStep),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWorkspaceForStep(BuilderWorkflowStep step) {
    switch (step) {
      case BuilderWorkflowStep.create:
        return _buildCreateWorkspace();
      case BuilderWorkflowStep.design:
        return DesignWorkspacePanel(controller: _controller);
      case BuilderWorkflowStep.logic:
        return RuleEditor(controller: _controller);
      case BuilderWorkflowStep.preview:
        return PreviewWorkspacePanel(controller: _controller);
      case BuilderWorkflowStep.publish:
        return PublishWorkspacePanel(
          controller: _controller,
          onPublished: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ExperimentCatalogScreen(),
              ),
            );
          },
        );
    }
  }

  Widget _buildCreateWorkspace() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            labelColor: Color(0xFF1E293B),
            unselectedLabelColor: Color(0xFF64748B),
            tabs: [
              Tab(text: 'Start'),
              Tab(text: 'Assistant'),
              Tab(text: 'Saved'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ManualCreatePanel(controller: _controller),
                AiGeneratorTab(
                  aiController: _aiController,
                  builderController: _controller,
                ),
                BuilderDraftsScreen(draftManager: _controller.draftManager),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualCreatePanel extends StatelessWidget {
  final ExperimentBuilderController controller;

  const _ManualCreatePanel({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasParts =
            controller.state.variables.isNotEmpty ||
            controller.state.objects.isNotEmpty ||
            controller.state.rules.isNotEmpty;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExperimentSummaryCard(state: controller.state),
              LaunchReadinessCard(validation: controller.currentValidation),
              if (controller.lastTemplateImportReport != null)
                _TemplateImportReportBanner(
                  report: controller.lastTemplateImportReport!,
                ),
              const SizedBox(height: 8),
              const Text(
                'Experiment Overview',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Plan the lab by adding readings, instruments, interactions, and simulation notes. The name, description, and tags are only labels; the lab needs components and interactions to run.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: controller.createManualStarterScene,
                icon: const Icon(Icons.build_circle_outlined),
                label: Text(
                  hasParts ? 'Add Starter Parts' : 'Create Starter Lab',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 12),
              PopupMenuButton<Map<String, dynamic>>(
                onSelected: controller.importTemplate,
                itemBuilder: (context) => ExperimentTemplates.allTemplates.map((
                  template,
                ) {
                  final scene =
                      template['scene'] as Map<String, dynamic>? ?? const {};
                  return PopupMenuItem(
                    value: template,
                    child: Text(scene['name']?.toString() ?? 'Template'),
                  );
                }).toList(),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFCBD5E1)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.file_download_outlined),
                      SizedBox(width: 8),
                      Text('Use Lab Template'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ManualChecklist(controller: controller),
            ],
          ),
        );
      },
    );
  }
}

class _TemplateImportReportBanner extends StatelessWidget {
  final TemplateImportReport report;

  const _TemplateImportReportBanner({required this.report});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        'Template Imported: ${report.templateName} | '
        'Readings: ${report.variables} | '
        'Instruments: ${report.objects} | '
        'Interactions: ${report.rules}',
        style: const TextStyle(
          color: Color(0xFF1E40AF),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ManualChecklist extends StatelessWidget {
  final ExperimentBuilderController controller;

  const _ManualChecklist({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scene = controller.state.scene;
    final variables = controller.state.variables.length;
    final objects = controller.state.objects.length;
    final rules = controller.state.rules.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row('Scene metadata', scene.name.trim().isNotEmpty),
        _row('Readings', variables > 0, '$variables added'),
        _row('Instruments', objects > 0, '$objects added'),
        _row('Interactions', rules > 0, '$rules added'),
      ],
    );
  }

  Widget _row(String label, bool ok, [String? detail]) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        ok ? Icons.check_circle : Icons.radio_button_unchecked,
        color: ok ? Colors.green : const Color(0xFF94A3B8),
      ),
      title: Text(label),
      subtitle: detail == null ? null : Text(detail),
    );
  }
}
