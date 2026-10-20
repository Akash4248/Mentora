/// An individual step in a structured worked solution or derivation.
final class SolutionStep {
  const SolutionStep({
    required this.stepNumber,
    required this.title,
    this.formula,
    this.substitution,
    this.calculation,
    required this.explanation,
    this.units,
  });

  /// 1-based sequential step order.
  final int stepNumber;

  /// Human-readable label (e.g. 'Identify Given Values', 'Apply Equation of Motion').
  final String title;

  /// Symbolic formula applied in this step (e.g. 'v = u + at').
  final String? formula;

  /// Numerical substitution (e.g. 'v = 0 + (2)(5)').
  final String? substitution;

  /// Explicit calculated arithmetic (e.g. '0 + 10 = 10').
  final String? calculation;

  /// Pedagogical reasoning explaining why this step is necessary.
  final String explanation;

  /// SI or operational units associated with the result of this step (e.g. 'm/s').
  final String? units;

  Map<String, dynamic> toJson() => {
        'stepNumber': stepNumber,
        'title': title,
        'formula': formula,
        'substitution': substitution,
        'calculation': calculation,
        'explanation': explanation,
        'units': units,
      };

  factory SolutionStep.fromJson(Map<String, dynamic> json) => SolutionStep(
        stepNumber: json['stepNumber'] as int? ?? 1,
        title: json['title'] as String? ?? 'Step',
        formula: json['formula'] as String?,
        substitution: json['substitution'] as String?,
        calculation: json['calculation'] as String?,
        explanation: json['explanation'] as String? ?? '',
        units: json['units'] as String?,
      );

  @override
  String toString() => 'Step $stepNumber: $title ($explanation)';
}
