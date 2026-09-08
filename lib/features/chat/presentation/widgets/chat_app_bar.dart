import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/idp_colors.dart';
import '../../../../core/theme/idp_typography.dart';
import '../../../../core/theme/idp_theme.dart';
import '../../../home/presentation/mentora_home_screen.dart';

class ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatAppBar({
    super.key,
    required this.title,
    required this.subtitle,
    required this.activeModel,
    required this.isOfflineMode,
    this.onOpenMemoryPolicy,
    this.onOpenDiagnostics,
  });

  final String title;
  final String subtitle;
  final String activeModel;
  final bool isOfflineMode;
  final VoidCallback? onOpenMemoryPolicy;
  final VoidCallback? onOpenDiagnostics;

  @override
  Size get preferredSize => const Size.fromHeight(68.0);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IDPSpacing.containerMargin,
        vertical: IDPSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(
            color: IDPColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, color: IDPColors.onSurface),
                    ),
                    const SizedBox(width: IDPSpacing.xs),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: IDPTypography.titleMd.copyWith(
                              color: IDPColors.primary,
                              height: 1.1,
                            ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: IDPColors.secondaryFixedDim,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: IDPSpacing.xs),
                              Expanded(
                                child: Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: IDPTypography.caption.copyWith(
                                    color: IDPColors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.home_rounded, color: IDPColors.primary),
                    tooltip: 'Home Dashboard',
                    onPressed: () {
                      Navigator.pushAndRemoveUntil(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MentoraHomeScreen(initialTabIndex: 0),
                        ),
                        (route) => false,
                      );
                    },
                  ),
                  if (onOpenMemoryPolicy != null)
                    IconButton(
                      icon: const Icon(Icons.tune_rounded, color: IDPColors.onSurfaceVariant),
                      tooltip: 'Memory Policy Settings',
                      onPressed: onOpenMemoryPolicy,
                    ),
                  const SizedBox(width: IDPSpacing.xs),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: IDPColors.primaryContainer,
                      border: Border.all(color: IDPColors.primary, width: 1.5),
                    ),
                    child: const Icon(
                      Icons.smart_toy_rounded,
                      color: IDPColors.primary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
