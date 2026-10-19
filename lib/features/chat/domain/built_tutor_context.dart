import 'package:flutter_agent_harness/flutter_agent_harness.dart';

import 'context_budget_report.dart';
import 'follow_up_action.dart';
import 'grounding_chunk.dart';
import 'learner_profile.dart';
import 'learning_evidence.dart';
import 'router_decision.dart';
import 'session_ledger.dart';
import 'teaching_strategy.dart';

/// Fully assembled, budgeted context package for an active tutoring turn.
final class BuiltTutorContext {
  const BuiltTutorContext({
    required this.systemPrompt,
    required this.cleanQuestion,
    required this.recentTurns,
    required this.groundingChunks,
    required this.learnerProfile,
    this.sessionLedger,
    this.evidence = const [],
    this.selectedTools = const [],
    required this.decision,
    required this.strategy,
    this.followUpActions = const [],
    required this.budgetReport,
  });

  /// The formatted system instructions including NCERT grounding and memory.
  final String systemPrompt;

  /// The pedagogical strategy chosen for this turn.
  final TeachingStrategy strategy;

  /// Tailored follow-up action suggestions.
  final List<FollowUpAction> followUpActions;

  /// The sanitized, isolated student question.
  final String cleanQuestion;

  /// Strictly bounded recent dialogue turns (max 2 turns).
  final List<String> recentTurns;

  /// Grounding textbook chunks with non-fabricated source metadata.
  final List<GroundingChunk> groundingChunks;

  /// Active learner profile (Tier 1).
  final LearnerProfile learnerProfile;

  /// Active session ledger (Tier 2), if available.
  final SessionLedger? sessionLedger;

  /// Active learning evidence (Tier 3), if relevant.
  final List<LearningEvidence> evidence;

  /// Tailored, allowlisted harness tools selected specifically for this turn.
  final List<AgentTool> selectedTools;

  /// The first-pass routing decision.
  final RouterDecision decision;

  /// Token accounting and safety audit report.
  final ContextBudgetReport budgetReport;

  @override
  String toString() =>
      'BuiltTutorContext(route: ${decision.route.name}, tools: ${selectedTools.map((t) => t.name).toList()}, fits: ${budgetReport.fitsBudget})';
}
