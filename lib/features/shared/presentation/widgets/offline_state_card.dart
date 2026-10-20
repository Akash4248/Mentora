import 'package:flutter/material.dart';
import 'package:mentora/l10n/app_localizations.dart';

class OfflineStateCard extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const OfflineStateCard({
    super.key,
    this.message = '',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final resolvedMessage = message.isEmpty ? l10n.offlineMessage : message;
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off, color: Colors.orange.shade700),
          const SizedBox(width: 16),
          Expanded(child: Text(resolvedMessage, style: TextStyle(color: Colors.orange.shade900))),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(l10n.retry),
            ),
        ],
      ),
    );
  }
}
