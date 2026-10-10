import 'package:flutter/material.dart';
import 'package:mentora/l10n/app_localizations.dart';

/// Large response card for primary school mode.
///
/// Shows tutor's last response in large, accessible text.
/// 24–32px minimum font, max 3–5 lines with overflow ellipsis.
class LargeResponseCard extends StatelessWidget {
  const LargeResponseCard({
    super.key,
    required this.text,
    this.fontSize = 28,
    this.maxLines = 4,
  });

  final String text;
  final double fontSize;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(180),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        text.isEmpty ? l10n.tapMicToAskQuestion : text,
        textAlign: TextAlign.center,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize.clamp(24, 32),
          fontWeight: FontWeight.w500,
          height: 1.4,
          color: text.isEmpty
              ? Colors.grey.shade400
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}
