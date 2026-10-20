import 'teaching_strategy.dart';

/// Context-sensitive suggested learning action presented to the student after a turn.
final class FollowUpAction {
  const FollowUpAction({
    required this.id,
    required this.label,
    required this.intentQuery,
    this.targetStrategy,
  });

  /// Stable unique identifier for UI keying.
  final String id;

  /// Human-readable pill/button label (e.g. "Explain more simply", "Show another example").
  final String label;

  /// The concrete question or instruction triggered when the student selects this action.
  final String intentQuery;

  /// Suggested pedagogical strategy for the follow-up turn.
  final TeachingStrategy? targetStrategy;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'intentQuery': intentQuery,
        'targetStrategy': targetStrategy?.name,
      };

  factory FollowUpAction.fromJson(Map<String, dynamic> json) => FollowUpAction(
        id: json['id'] as String,
        label: json['label'] as String,
        intentQuery: json['intentQuery'] as String,
        targetStrategy: json['targetStrategy'] != null
            ? TeachingStrategy.values.asNameMap()[json['targetStrategy'] as String]
            : null,
      );

  @override
  String toString() => 'FollowUpAction("$label" -> "$intentQuery")';
}
