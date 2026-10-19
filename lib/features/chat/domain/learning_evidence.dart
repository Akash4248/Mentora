/// Origin of learning evidence for strict attribution.
enum EvidenceSourceType {
  /// Direct verbatim or paraphrased statements explicitly made by the student.
  /// Example: "I don't understand how velocity can be negative."
  directStudentStatement,

  /// Objective heuristic or assessment observations derived by the tutoring system.
  /// Example: "Student answered quiz question on acceleration incorrectly twice."
  systemObservation,
}

/// Attributable evidence of concept mastery or confusion (Memory Tier 3).
final class LearningEvidence {
  const LearningEvidence({
    required this.id,
    required this.topic,
    required this.concept,
    required this.sourceType,
    required this.observation,
    required this.isMastery,
    required this.timestamp,
  });

  /// Stable unique ID for this evidence record.
  final String id;

  /// High-level topic (e.g. 'Motion', 'Gravitation').
  final String topic;

  /// Specific sub-concept (e.g. 'Negative Acceleration', 'Universal Law of Gravitation').
  final String concept;

  /// Source attribution: direct statement vs. system observation.
  final EvidenceSourceType sourceType;

  /// Factual observation text. Never stores raw sensor dumps.
  final String observation;

  /// True if evidence demonstrates mastery; false if it documents confusion/struggle.
  final bool isMastery;

  /// Timestamp of the observation.
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'topic': topic,
        'concept': concept,
        'sourceType': sourceType.name,
        'observation': observation,
        'isMastery': isMastery,
        'timestamp': timestamp.toIso8601String(),
      };

  factory LearningEvidence.fromJson(Map<String, dynamic> json) => LearningEvidence(
        id: json['id'] as String,
        topic: json['topic'] as String,
        concept: json['concept'] as String,
        sourceType: json['sourceType'] == 'directStudentStatement'
            ? EvidenceSourceType.directStudentStatement
            : EvidenceSourceType.systemObservation,
        observation: json['observation'] as String,
        isMastery: json['isMastery'] as bool? ?? false,
        timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      );

  @override
  String toString() =>
      'LearningEvidence($concept, mastery: $isMastery, source: ${sourceType.name}: "$observation")';
}
