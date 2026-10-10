import 'package:flutter/material.dart';
import 'package:mentora/core/theme/idp_theme.dart';

class LabReportsScreen extends StatelessWidget {
  const LabReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reports = [
      _LabReportSummary(
        experimentName: 'Simple Pendulum',
        score: 85,
        completionDate: DateTime.now().subtract(const Duration(days: 1)),
        outcome: 'Longer pendulums have larger periods.',
      ),
    ];

    return Scaffold(
      backgroundColor: IDPColors.background,
      appBar: AppBar(
        title: Text('My Lab Reports', style: IDPTypography.titleMedium.copyWith(color: IDPColors.primary)),
        backgroundColor: IDPColors.surface,
        foregroundColor: IDPColors.primary,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: IDPColors.primary),
        shape: Border(bottom: BorderSide(color: IDPColors.outlineVariant.withValues(alpha: 0.5))),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(IDPSpacing.lg),
        itemCount: reports.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final report = reports[index];
          return _ReportCard(report: report);
        },
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final _LabReportSummary report;

  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(IDPRadius.defaultRadius),
        side: const BorderSide(color: IDPColors.outlineVariant),
      ),
      color: IDPColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(IDPSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: IDPColors.secondaryContainer,
                    borderRadius: BorderRadius.circular(IDPRadius.md),
                  ),
                  child: const Icon(
                    Icons.science_rounded,
                    color: IDPColors.secondary,
                  ),
                ),
                const SizedBox(width: IDPSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        report.experimentName,
                        style: IDPTypography.titleMedium.copyWith(color: IDPColors.onSurface),
                      ),
                      const SizedBox(height: IDPSpacing.xs),
                      Text(
                        'Completed ${_formatDate(report.completionDate)}',
                        style: IDPTypography.labelMedium.copyWith(color: IDPColors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.sm, vertical: IDPSpacing.xs),
                  decoration: BoxDecoration(
                    color: IDPColors.primaryContainer,
                    borderRadius: BorderRadius.circular(IDPRadius.sm),
                  ),
                  child: Text(
                    '${report.score}%',
                    style: IDPTypography.labelMedium.copyWith(
                      color: IDPColors.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: IDPSpacing.md),
            Text(
              report.outcome,
              style: IDPTypography.bodyMedium.copyWith(color: IDPColors.onSurface),
            ),
            const SizedBox(height: IDPSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: IDPColors.outlineVariant),
                      foregroundColor: IDPColors.primary,
                    ),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Opening saved report preview.'),
                        backgroundColor: IDPColors.primary,
                      ),
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Open Report'),
                  ),
                ),
                const SizedBox(width: IDPSpacing.md),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: IDPColors.primary,
                      foregroundColor: IDPColors.onPrimary,
                    ),
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'PDF export is available from completed report view.',
                        ),
                        backgroundColor: IDPColors.secondary,
                      ),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: const Text('Export PDF'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _LabReportSummary {
  final String experimentName;
  final int score;
  final DateTime completionDate;
  final String outcome;

  const _LabReportSummary({
    required this.experimentName,
    required this.score,
    required this.completionDate,
    required this.outcome,
  });
}
