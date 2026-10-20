/// User-correctable, stable learner profile and explicit preferences (Memory Tier 1).
final class LearnerProfile {
  const LearnerProfile({
    this.studentName,
    this.grade = 9,
    this.preferredLanguage = 'en',
    this.explanationStyle = 'balanced',
    this.interests = const [],
    required this.updatedAt,
  });

  /// Optional name or nickname of the learner.
  final String? studentName;

  /// Current NCERT grade level (typically 9 or 10).
  final int grade;

  /// Preferred language code ('en', 'kn', etc.).
  final String preferredLanguage;

  /// Preferred explanation style: 'balanced', 'concise', or 'step_by_step'.
  final String explanationStyle;

  /// Learning interests used for personalized analogies (e.g. ['cricket', 'space']).
  final List<String> interests;

  /// Timestamp when the profile was last modified.
  final DateTime updatedAt;

  factory LearnerProfile.defaultProfile({int grade = 9}) => LearnerProfile(
        grade: grade,
        preferredLanguage: 'en',
        explanationStyle: 'balanced',
        interests: const [],
        updatedAt: DateTime.now(),
      );

  LearnerProfile copyWith({
    String? studentName,
    int? grade,
    String? preferredLanguage,
    String? explanationStyle,
    List<String>? interests,
    DateTime? updatedAt,
  }) {
    return LearnerProfile(
      studentName: studentName ?? this.studentName,
      grade: grade ?? this.grade,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      explanationStyle: explanationStyle ?? this.explanationStyle,
      interests: interests ?? this.interests,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'studentName': studentName,
        'grade': grade,
        'preferredLanguage': preferredLanguage,
        'explanationStyle': explanationStyle,
        'interests': interests,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LearnerProfile.fromJson(Map<String, dynamic> json) => LearnerProfile(
        studentName: json['studentName'] as String?,
        grade: json['grade'] as int? ?? 9,
        preferredLanguage: json['preferredLanguage'] as String? ?? 'en',
        explanationStyle: json['explanationStyle'] as String? ?? 'balanced',
        interests: List<String>.from(json['interests'] as List? ?? []),
        updatedAt: json['updatedAt'] != null
            ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
            : DateTime.now(),
      );

  @override
  String toString() =>
      'LearnerProfile(grade: $grade, lang: $preferredLanguage, style: $explanationStyle, interests: $interests)';
}
