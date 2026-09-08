import 'package:flutter/material.dart';
import '../../application/knowledge_gap_resolver.dart';

class ConceptDependencyTreeView extends StatelessWidget {
  final KnowledgeGapAnalysis gapAnalysis;
  final Function(ConceptNode)? onConceptTap;

  const ConceptDependencyTreeView({
    super.key,
    required this.gapAnalysis,
    this.onConceptTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasGaps = gapAnalysis.missingPrerequisites.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasGaps ? Colors.amber.shade700.withAlpha(128) : Colors.green.shade700.withAlpha(128),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasGaps ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                color: hasGaps ? Colors.amber.shade700 : Colors.green.shade600,
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Prerequisite Readiness: ${(gapAnalysis.readinessScore * 100).toInt()}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            gapAnalysis.remediationStrategy,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'CONCEPT DEPENDENCY TREE',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 10),

          // Prerequisite nodes
          if (gapAnalysis.missingPrerequisites.isNotEmpty) ...[
            ...gapAnalysis.missingPrerequisites.map((node) {
              return _buildConceptNodeTile(
                context,
                node: node,
                isMastered: false,
                isTarget: false,
              );
            }),
            Center(
              child: Icon(
                Icons.arrow_downward_rounded,
                color: theme.colorScheme.outline,
                size: 20,
              ),
            ),
          ],

          // Target node
          _buildConceptNodeTile(
            context,
            node: ConceptNode(
              conceptId: gapAnalysis.targetConceptId,
              name: gapAnalysis.targetConceptName,
              subject: 'Physics',
              grade: 11,
              chapterId: '',
              difficulty: 'target',
              summary: 'Target topic to master',
              learningObjectives: [],
            ),
            isMastered: !hasGaps,
            isTarget: true,
          ),
        ],
      ),
    );
  }

  Widget _buildConceptNodeTile(
    BuildContext context, {
    required ConceptNode node,
    required bool isMastered,
    required bool isTarget,
  }) {
    final theme = Theme.of(context);

    Color badgeColor;
    String badgeText;
    if (isTarget) {
      badgeColor = theme.colorScheme.primary;
      badgeText = 'Target Concept';
    } else if (isMastered) {
      badgeColor = Colors.green.shade600;
      badgeText = 'Mastered';
    } else {
      badgeColor = Colors.amber.shade800;
      badgeText = 'Prerequisite Gap';
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isTarget ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
          width: isTarget ? 2 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: badgeColor.withAlpha(40),
          child: Icon(
            isTarget
                ? Icons.ads_click_rounded
                : isMastered
                    ? Icons.check_rounded
                    : Icons.menu_book_rounded,
            color: badgeColor,
          ),
        ),
        title: Text(
          node.name,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: isTarget ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        subtitle: Text(
          node.summary.isNotEmpty ? node.summary : badgeText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall,
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withAlpha(30),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            badgeText,
            style: theme.textTheme.labelSmall?.copyWith(
              color: badgeColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        onTap: () => onConceptTap?.call(node),
      ),
    );
  }
}
