import 'package:flutter/material.dart';
import '../../../../core/theme/idp_colors.dart';
import '../../../../core/theme/idp_typography.dart';

enum MathLabTool {
  select,
  addPoint,
  addLine,
  surface3D,
  geometry,
  balanceScale,
  socraticSolver,
}

class MathLabToolbar extends StatelessWidget {
  final MathLabTool activeTool;
  final ValueChanged<MathLabTool> onToolSelected;

  const MathLabToolbar({
    super.key,
    required this.activeTool,
    required this.onToolSelected,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final tools = [
      _ToolItem(MathLabTool.select, 'Select', Icons.touch_app_rounded),
      _ToolItem(MathLabTool.addPoint, 'Point', Icons.adjust_rounded),
      _ToolItem(MathLabTool.addLine, 'Vector', Icons.timeline_rounded),
      _ToolItem(MathLabTool.surface3D, '3D Surface', Icons.view_in_ar_rounded),
      _ToolItem(MathLabTool.geometry, 'Geometry', Icons.category_rounded),
      _ToolItem(MathLabTool.balanceScale, 'Balance', Icons.balance_rounded),
      _ToolItem(MathLabTool.socraticSolver, 'Step Solver', Icons.auto_awesome_rounded),
    ];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tools.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final tool = tools[index];
          final isSelected = activeTool == tool.type;

          return Material(
            color: isSelected
                ? const Color(0xFF4F46E5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onToolSelected(tool.type),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      tool.icon,
                      size: 18,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white70 : IDPColors.onSurfaceVariant),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      tool.label,
                      style: IDPTypography.caption.copyWith(
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : IDPColors.onSurfaceVariant),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ToolItem {
  final MathLabTool type;
  final String label;
  final IconData icon;

  _ToolItem(this.type, this.label, this.icon);
}
