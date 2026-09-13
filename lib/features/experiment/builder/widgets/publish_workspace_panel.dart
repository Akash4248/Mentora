import 'package:flutter/material.dart';
import '../controllers/experiment_builder_controller.dart';
import 'manifest_preview_panel.dart';
import 'builder_validation_panel.dart';

class PublishWorkspacePanel extends StatelessWidget {
  final ExperimentBuilderController controller;
  final VoidCallback? onPublished;

  const PublishWorkspacePanel({
    super.key,
    required this.controller,
    this.onPublished,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final state = controller.state;
        final isValid = controller.validationResult?.isValid ?? false;

        return LayoutBuilder(
          builder: (context, constraints) {
            final isMobile = constraints.maxWidth < 800;

            final summaryPane = SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Experiment Summary',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Review your experiment details before publishing or exporting.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 32),

                  _buildSummaryCard(
                    title: 'Basic Info',
                    icon: Icons.info_outline,
                    children: [
                      _buildDetailRow('Title', state.scene.name),
                      _buildDetailRow(
                        'Description',
                        state.scene.description.isEmpty
                            ? 'No description'
                            : state.scene.description,
                      ),
                      _buildDetailRow('Tags', state.scene.tags.join(', ')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSummaryCard(
                    title: 'Composition',
                    icon: Icons.layers_rounded,
                    children: [
                      _buildDetailRow(
                        'Readings',
                        '${state.variables.length} defined',
                      ),
                      _buildDetailRow(
                        'Instruments',
                        '${state.objects.length} configured',
                      ),
                      _buildDetailRow(
                        'Interactions',
                        '${state.rules.length} active',
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Action Buttons
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Draft saved successfully!'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.save_rounded),
                        label: const Text('Save Draft'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 24,
                          ),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: isValid
                            ? () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Experiment published to local catalog!',
                                    ),
                                  ),
                                );
                                if (onPublished != null) {
                                  onPublished!();
                                }
                              }
                            : null,
                        icon: const Icon(Icons.publish_rounded),
                        label: const Text('Publish Experiment'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 16,
                            horizontal: 24,
                          ),
                          backgroundColor: const Color(0xFF0B6E4F),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );

            final validationPane = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Text(
                    'Readiness Checks',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                isMobile
                    ? SizedBox(
                        height: 300,
                        child: BuilderValidationPanel(controller: controller),
                      )
                    : Expanded(
                        child: BuilderValidationPanel(controller: controller),
                      ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                isMobile
                    ? SizedBox(
                        height: 300,
                        child: ManifestPreviewPanel(controller: controller),
                      )
                    : Expanded(
                        child: ManifestPreviewPanel(controller: controller),
                      ),
              ],
            );

            if (isMobile) {
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summaryPane,
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    validationPane,
                  ],
                ),
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: summaryPane),
                const VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
                Expanded(flex: 1, child: validationPane),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF64748B), size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }
}
