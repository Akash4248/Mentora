/// Breakdown of estimated token usage for an active tutor turn.
final class ContextBudgetReport {
  const ContextBudgetReport({
    required this.estimatedInputTokens,
    required this.systemTokens,
    required this.memoryTokens,
    required this.ragTokens,
    required this.historyTokens,
    required this.questionTokens,
    required this.toolSchemaTokens,
    this.reservedOutputTokens = 1024,
    this.maxContextLimit = 2048,
  });

  /// Total estimated input tokens sent to the model.
  final int estimatedInputTokens;

  /// Tokens consumed by base system prompt instructions.
  final int systemTokens;

  /// Tokens consumed by three-tier learner and session memory.
  final int memoryTokens;

  /// Tokens consumed by retrieved curriculum lesson chunks.
  final int ragTokens;

  /// Tokens consumed by recent conversation history turns.
  final int historyTokens;

  /// Tokens consumed by the student's current question.
  final int questionTokens;

  /// Tokens consumed by allowlisted tool schemas.
  final int toolSchemaTokens;

  /// Tokens reserved for the model's generated answer.
  final int reservedOutputTokens;

  /// Hard hardware context window limit (default: 2048 on Android/Linux GGUF).
  final int maxContextLimit;

  /// Total budget requirement = input tokens + reserved output tokens.
  int get totalRequiredTokens => estimatedInputTokens + reservedOutputTokens;

  /// Remaining headroom in the context window.
  int get availableHeadroom => maxContextLimit - totalRequiredTokens;

  /// True if the full request fits safely within the context limit.
  bool get fitsBudget => totalRequiredTokens <= maxContextLimit;

  @override
  String toString() =>
      'ContextBudgetReport(input: $estimatedInputTokens, reserved: $reservedOutputTokens, max: $maxContextLimit, fits: $fitsBudget)';
}
