import 'package:flutter/material.dart';
import '../../../../core/theme/idp_colors.dart';
import '../../../../core/theme/idp_theme.dart';
import '../../application/three_tier_memory_manager.dart';
import '../../domain/learner_profile.dart';
import '../../domain/learning_evidence.dart';
import '../../domain/session_ledger.dart';
import '../../data/local/chat_memory_policy_repository.dart';

class ChatMemoryPolicySheet extends StatefulWidget {
  const ChatMemoryPolicySheet({
    super.key,
    required this.policy,
    required this.onPolicyChanged,
    this.memoryManager,
    this.sessionId,
    this.topic,
  });

  final ChatMemoryPolicy policy;
  final Function({
    int? shortTermWindow,
    bool? semanticRecallEnabled,
    int? semanticTopK,
    SessionResetPolicy? resetPolicy,
    int? inactivityMinutes,
  }) onPolicyChanged;
  final ThreeTierMemoryManager? memoryManager;
  final String? sessionId;
  final String? topic;

  @override
  State<ChatMemoryPolicySheet> createState() => _ChatMemoryPolicySheetState();
}

class _ChatMemoryPolicySheetState extends State<ChatMemoryPolicySheet> {
  LearnerProfile? _profile;
  List<LearningEvidence> _evidence = const [];
  SessionLedger? _ledger;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMemoryData();
  }

  Future<void> _loadMemoryData() async {
    final manager = widget.memoryManager;
    if (manager == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final profile = await manager.getProfile();
      final evidence = await manager.getEvidence(topicFilter: widget.topic);
      SessionLedger? ledger;
      if (widget.sessionId != null) {
        ledger = manager.getOrCreateLedger(
          sessionId: widget.sessionId!,
          topic: widget.topic ?? 'General',
          grade: profile.grade,
        );
      }

      if (mounted) {
        setState(() {
          _profile = profile;
          _evidence = evidence;
          _ledger = ledger;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateExplanationStyle(String style) async {
    final current = _profile;
    final manager = widget.memoryManager;
    if (current == null || manager == null) return;

    final updated = current.copyWith(
      explanationStyle: style,
      updatedAt: DateTime.now(),
    );
    await manager.updateProfile(updated);
    if (mounted) {
      setState(() => _profile = updated);
    }
  }

  Future<void> _deleteEvidence(String id) async {
    final manager = widget.memoryManager;
    if (manager == null) return;
    await manager.removeEvidence(id);
    final refreshed = await manager.getEvidence(topicFilter: widget.topic);
    if (mounted) {
      setState(() => _evidence = refreshed);
    }
  }

  Future<void> _clearAllEvidence() async {
    final manager = widget.memoryManager;
    if (manager == null) return;
    await manager.clearEvidence();
    if (mounted) {
      setState(() => _evidence = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasMemoryManager = widget.memoryManager != null;

    if (!hasMemoryManager) {
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
            _buildHeader(context),
            const Divider(),
            const SizedBox(height: IDPSpacing.sm),
            _buildHistorySettings(),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.fromLTRB(IDPSpacing.lg, IDPSpacing.lg, IDPSpacing.lg, IDPSpacing.md),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(IDPRadius.xl)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            const SizedBox(height: IDPSpacing.xs),
            const TabBar(
              labelColor: IDPColors.primary,
              unselectedLabelColor: IDPColors.textSecondary,
              indicatorColor: IDPColors.primary,
              indicatorWeight: 3,
              labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(icon: Icon(Icons.psychology_outlined, size: 20), text: 'Learner Memory'),
                Tab(icon: Icon(Icons.tune_rounded, size: 20), text: 'History Policy'),
              ],
            ),
            const SizedBox(height: IDPSpacing.sm),
            Expanded(
              child: TabBarView(
                children: [
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildMemoryTiersView(),
                  SingleChildScrollView(child: _buildHistorySettings()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_stories_rounded, color: IDPColors.primary, size: 22),
            const SizedBox(width: 8),
            Text(
              'Memory & Learning Policy',
              style: IDPTypography.titleMedium.copyWith(
                fontWeight: FontWeight.bold,
                color: IDPColors.onSurface,
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildMemoryTiersView() {
    final profile = _profile;
    final ledger = _ledger;
    final evidence = _evidence;

    return ListView(
      children: [
        // Tier 1: Learner Profile
        Card(
          elevation: 0,
          color: const Color(0xFFF8FAFC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(IDPSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Tier 1: Learner Profile',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: IDPColors.primary),
                    ),
                    if (profile != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: IDPColors.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Grade ${profile.grade}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: IDPColors.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Preferred Explanation Style:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: IDPColors.textSecondary),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  children: ['balanced', 'concise', 'step_by_step'].map((style) {
                    final isSelected = profile?.explanationStyle == style;
                    return ChoiceChip(
                      label: Text(
                        style == 'step_by_step'
                            ? 'Step-by-Step'
                            : style[0].toUpperCase() + style.substring(1),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : IDPColors.textPrimary,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: IDPColors.primary,
                      backgroundColor: Colors.white,
                      onSelected: (_) => _updateExplanationStyle(style),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: IDPSpacing.sm),

        // Tier 2: Active Session Ledger
        Card(
          elevation: 0,
          color: const Color(0xFFF8FAFC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(IDPSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.bolt_rounded, size: 18, color: Colors.orange),
                    SizedBox(width: 6),
                    Text(
                      'Tier 2: Active Session Ledger',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: IDPColors.textPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildStatBadge('Questions Asked', '${ledger?.questionsCount ?? 0}'),
                    const SizedBox(width: 8),
                    _buildStatBadge('Last Tool', ledger?.lastToolUsed ?? 'None'),
                  ],
                ),
                if (ledger != null && ledger.lastFormulaEvaluated != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Last Computed: ${ledger.lastFormulaEvaluated}',
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: IDPColors.textPrimary),
                  ),
                ],
                if (ledger != null && ledger.keyConceptsTouched.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Concepts Explored This Session:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: IDPColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: ledger.keyConceptsTouched.map((concept) {
                      return Chip(
                        label: Text(concept, style: const TextStyle(fontSize: 11)),
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        visualDensity: VisualDensity.compact,
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: IDPSpacing.sm),

        // Tier 3: Learning Evidence
        Card(
          elevation: 0,
          color: const Color(0xFFF8FAFC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(IDPSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.bookmark_added_rounded, size: 18, color: IDPColors.primary),
                        SizedBox(width: 6),
                        Text(
                          'Tier 3: Learning Evidence',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: IDPColors.textPrimary),
                        ),
                      ],
                    ),
                    if (evidence.isNotEmpty)
                      TextButton(
                        onPressed: _clearAllEvidence,
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: const Text('Clear All', style: TextStyle(fontSize: 11, color: Colors.red)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (evidence.isEmpty)
                  const Text(
                    'No learning evidence recorded yet for this topic. Mentora automatically notes struggle and mastery points as you learn.',
                    style: TextStyle(fontSize: 12, color: IDPColors.textSecondary),
                  )
                else
                  ...evidence.map((item) {
                    final isMastered = item.isMastery;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isMastered ? const Color(0xFFBBF7D0) : const Color(0xFFFED7AA),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isMastered ? Icons.check_circle_rounded : Icons.help_outline_rounded,
                            size: 16,
                            color: isMastered ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.concept,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                Text(
                                  item.observation,
                                  style: const TextStyle(fontSize: 11, color: IDPColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _deleteEvidence(item.id),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatBadge(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: IDPColors.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: IDPColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistorySettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
            [4, 8, 12, 16].contains(widget.policy.shortTermWindow)
                ? widget.policy.shortTermWindow
                : 8
          },
          onSelectionChanged: (val) {
            widget.onPolicyChanged(shortTermWindow: val.first);
          },
        ),
        const SizedBox(height: IDPSpacing.md),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Semantic Context Recall'),
          subtitle: const Text('Uses local vector RAG to recall relevant past notes'),
          value: widget.policy.semanticRecallEnabled,
          activeThumbColor: IDPColors.primary,
          onChanged: (val) {
            widget.onPolicyChanged(
              semanticRecallEnabled: val,
              semanticTopK: val ? (widget.policy.semanticTopK == 0 ? 2 : widget.policy.semanticTopK) : 0,
            );
          },
        ),
      ],
    );
  }
}
