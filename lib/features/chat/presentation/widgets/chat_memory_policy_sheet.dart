import 'package:flutter/material.dart';
import '../../../../core/theme/idp_colors.dart';
import '../../../../core/theme/idp_typography.dart';
import '../../../../core/theme/idp_theme.dart';
import '../../data/local/chat_memory_policy_repository.dart';

class ChatMemoryPolicySheet extends StatelessWidget {
  const ChatMemoryPolicySheet({
    super.key,
    required this.policy,
    required this.onPolicyChanged,
  });

  final ChatMemoryPolicy policy;
  final Function({
    int? shortTermWindow,
    bool? semanticRecallEnabled,
    int? semanticTopK,
    SessionResetPolicy? resetPolicy,
    int? inactivityMinutes,
  }) onPolicyChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(IDPSpacing.lg),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(IDPRadius.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🧠 Conversation Memory Policy',
                style: IDPTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.bold,
                  color: IDPColors.onSurface,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const Divider(),
          const SizedBox(height: IDPSpacing.sm),
          Text(
            'Short-Term History Window',
            style: IDPTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: IDPSpacing.xs),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('4 Msgs')),
              ButtonSegment(value: 8, label: Text('8 Msgs')),
              ButtonSegment(value: 12, label: Text('12 Msgs')),
              ButtonSegment(value: 16, label: Text('16 Msgs')),
            ],
            selected: {
              [4, 8, 12, 16].contains(policy.shortTermWindow)
                  ? policy.shortTermWindow
                  : 8
            },
            onSelectionChanged: (val) {
              onPolicyChanged(shortTermWindow: val.first);
            },
          ),
          const SizedBox(height: IDPSpacing.md),
          SwitchListTile(
            title: const Text('Semantic Context Recall'),
            subtitle: const Text('Uses local vector RAG to recall relevant past notes'),
            value: policy.semanticRecallEnabled,
            activeColor: IDPColors.primary,
            onChanged: (val) {
              onPolicyChanged(
                semanticRecallEnabled: val,
                semanticTopK: val ? (policy.semanticTopK == 0 ? 2 : policy.semanticTopK) : 0,
              );
            },
          ),
          const SizedBox(height: IDPSpacing.md),
        ],
      ),
    );
  }
}
