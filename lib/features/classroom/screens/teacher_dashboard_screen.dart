import 'package:flutter/material.dart';
import '../controllers/teacher_dashboard_controller.dart';
import 'teacher_review_screen.dart';
import '../../shared/presentation/widgets/empty_state_card.dart';
import '../../../core/theme/idp_colors.dart';
import '../../../core/widgets/idp_core_widgets.dart';

class TeacherDashboardScreen extends StatelessWidget {
  final TeacherDashboardController controller;

  const TeacherDashboardScreen({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: IDPColors.background,
        appBar: AppBar(
          title: const Text('Teacher Dashboard', style: IDPTypography.titleMedium),
          backgroundColor: IDPColors.surface,
          foregroundColor: IDPColors.onSurface,
          elevation: 0,
          bottom: const TabBar(
            labelColor: IDPColors.primary,
            unselectedLabelColor: IDPColors.textSecondary,
            indicatorColor: IDPColors.primary,
            tabs: [
              Tab(text: 'Sessions'),
              Tab(text: 'Assignments'),
              Tab(text: 'Submissions'),
            ],
          ),
        ),
        body: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            return TabBarView(
              children: [
                _buildSessionsTab(context),
                _buildAssignmentsTab(context),
                _buildSubmissionsTab(context),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: IDPColors.primary,
          onPressed: () => _createNewSession(context),
          tooltip: 'New Session',
          child: const Icon(Icons.add_rounded, color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildSessionsTab(BuildContext context) {
    if (controller.activeSessions.isEmpty) {
      return const EmptyStateCard(
        title: 'No Active Sessions',
        message: 'Tap the + button to create a new classroom session.',
        icon: Icons.school_outlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(IDPSpacing.md),
      itemCount: controller.activeSessions.length,
      itemBuilder: (context, index) {
        final session = controller.activeSessions[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: IDPSpacing.sm),
          child: IDPCard(
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: IDPColors.primaryContainer,
                  child: Icon(Icons.school_rounded, color: IDPColors.primary),
                ),
                const SizedBox(width: IDPSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.topic, style: IDPTypography.titleSmall),
                      const SizedBox(height: IDPSpacing.xs / 2),
                      Text(
                        'ID: ${session.id} | Students: ${session.connectedStudents.length}',
                        style: IDPTypography.bodySmall.copyWith(color: IDPColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: IDPColors.error),
                  tooltip: 'Close Session',
                  onPressed: () => controller.closeSession(session.id),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAssignmentsTab(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(IDPSpacing.md),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: IDPColors.primary,
                padding: const EdgeInsets.symmetric(vertical: IDPSpacing.md),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IDPRadius.defaultRadius)),
              ),
              onPressed: () => _distributeNewAssignment(context),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Distribute Draft Experiment', style: IDPTypography.labelLarge),
            ),
          ),
        ),
        const Divider(color: IDPColors.divider),
        Expanded(
          child: controller.assignments.isEmpty
              ? const EmptyStateCard(
                  title: 'No Assignments',
                  message: 'Distribute a draft experiment to a session.',
                  icon: Icons.assignment_outlined,
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(IDPSpacing.md),
                  itemCount: controller.assignments.length,
                  itemBuilder: (context, index) {
                    final assign = controller.assignments[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: IDPSpacing.sm),
                      child: IDPCard(
                        child: Row(
                          children: [
                            const CircleAvatar(
                              backgroundColor: IDPColors.primaryContainer,
                              child: Icon(Icons.assignment_rounded, color: IDPColors.primary),
                            ),
                            const SizedBox(width: IDPSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(assign.title, style: IDPTypography.titleSmall),
                                  const SizedBox(height: IDPSpacing.xs / 2),
                                  Text('Session: ${assign.sessionId}', style: IDPTypography.bodySmall.copyWith(color: IDPColors.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSubmissionsTab(BuildContext context) {
    if (controller.submissions.isEmpty) {
      return const EmptyStateCard(
        title: 'No Submissions',
        message: 'Waiting for students to complete their assignments.',
        icon: Icons.inbox_outlined,
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(IDPSpacing.md),
      itemCount: controller.submissions.length,
      itemBuilder: (context, index) {
        final sub = controller.submissions[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: IDPSpacing.sm),
          child: IDPCard(
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => TeacherReviewScreen(submission: sub),
              ));
            },
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: IDPColors.secondaryContainer,
                  child: Icon(Icons.check_circle_rounded, color: IDPColors.secondary),
                ),
                const SizedBox(width: IDPSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${sub.studentName} - ${sub.status}', style: IDPTypography.titleSmall),
                      const SizedBox(height: IDPSpacing.xs / 2),
                      Text('Assignment: ${sub.assignmentId}', style: IDPTypography.bodySmall.copyWith(color: IDPColors.textSecondary)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: IDPColors.textHint),
              ],
            ),
          ),
        );
      },
    );
  }

  void _createNewSession(BuildContext context) {
    final tc = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Session', style: IDPTypography.titleSmall),
        content: TextField(
          controller: tc,
          decoration: InputDecoration(
            hintText: 'Topic (e.g. Physics Lab B)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(IDPRadius.defaultRadius)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: IDPColors.primary),
            onPressed: () {
              if (tc.text.isNotEmpty) {
                controller.createSession(tc.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _distributeNewAssignment(BuildContext context) {
    if (controller.activeSessions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Create a session first!')));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Experiment drafts are not available.')),
    );
  }
}

