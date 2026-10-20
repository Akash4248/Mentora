/// Compact learning state for the active tutoring session (Memory Tier 2).
///
/// Tracks the trajectory of the ongoing lesson without replaying lengthy chat transcripts.
final class SessionLedger {
  SessionLedger({
    required this.sessionId,
    required this.topic,
    required this.grade,
    this.questionsCount = 0,
    List<String>? keyConceptsTouched,
    this.lastToolUsed,
    this.lastFormulaEvaluated,
    this.activeMastery = 0.0,
    required this.startedAt,
    required this.lastActivityAt,
  }) : keyConceptsTouched = keyConceptsTouched ?? [];

  final String sessionId;
  final String topic;
  final int grade;
  int questionsCount;
  final List<String> keyConceptsTouched;
  String? lastToolUsed;
  String? lastFormulaEvaluated;
  double activeMastery;
  final DateTime startedAt;
  DateTime lastActivityAt;

  void recordQuestion(String question) {
    questionsCount++;
    lastActivityAt = DateTime.now();
  }

  void recordConcept(String concept) {
    final clean = concept.trim();
    if (clean.isNotEmpty && !keyConceptsTouched.contains(clean)) {
      if (keyConceptsTouched.length >= 8) {
        keyConceptsTouched.removeAt(0); // Bound list
      }
      keyConceptsTouched.add(clean);
    }
    lastActivityAt = DateTime.now();
  }

  void recordTool(String toolName, {String? formula}) {
    lastToolUsed = toolName;
    if (formula != null && formula.trim().isNotEmpty) {
      lastFormulaEvaluated = formula.trim();
    }
    lastActivityAt = DateTime.now();
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'topic': topic,
        'grade': grade,
        'questionsCount': questionsCount,
        'keyConceptsTouched': keyConceptsTouched,
        'lastToolUsed': lastToolUsed,
        'lastFormulaEvaluated': lastFormulaEvaluated,
        'activeMastery': activeMastery,
        'startedAt': startedAt.toIso8601String(),
        'lastActivityAt': lastActivityAt.toIso8601String(),
      };

  factory SessionLedger.fromJson(Map<String, dynamic> json) => SessionLedger(
        sessionId: json['sessionId'] as String,
        topic: json['topic'] as String,
        grade: json['grade'] as int? ?? 9,
        questionsCount: json['questionsCount'] as int? ?? 0,
        keyConceptsTouched: List<String>.from(json['keyConceptsTouched'] as List? ?? []),
        lastToolUsed: json['lastToolUsed'] as String?,
        lastFormulaEvaluated: json['lastFormulaEvaluated'] as String?,
        activeMastery: (json['activeMastery'] as num?)?.toDouble() ?? 0.0,
        startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '') ?? DateTime.now(),
        lastActivityAt: DateTime.tryParse(json['lastActivityAt'] as String? ?? '') ?? DateTime.now(),
      );

  @override
  String toString() =>
      'SessionLedger(topic: $topic, questions: $questionsCount, concepts: $keyConceptsTouched)';
}
