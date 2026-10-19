import '../domain/teaching_strategy.dart';
import 'unit_validator.dart';

final class GuardValidationResult {
  const GuardValidationResult({
    required this.isApproved,
    this.detectedErrors = const [],
    this.warnings = const [],
    required this.inspectedText,
  });

  final bool isApproved;
  final List<String> detectedErrors;
  final List<String> warnings;
  final String inspectedText;

  @override
  String toString() =>
      'GuardValidationResult(approved: $isApproved, errors: $detectedErrors, warnings: $warnings)';
}

/// Validates that generated tutor responses comply with educational accuracy policies,
/// dimensional consistency, and non-hallucinated unit assertions.
final class LearningAccuracyGuard {
  const LearningAccuracyGuard({
    UnitValidator? unitValidator,
  }) : _unitValidator = unitValidator ?? const UnitValidator();

  final UnitValidator _unitValidator;

  /// Inspects a tutor response for factual accuracy, dimensional correctness,
  /// and pedagogical adherence.
  GuardValidationResult inspect({
    required String question,
    required String responseText,
    required TeachingStrategy strategy,
  }) {
    final errors = <String>[];
    final warnings = <String>[];
    final cleanResponse = responseText.trim();

    if (cleanResponse.isEmpty) {
      return const GuardValidationResult(
        isApproved: false,
        detectedErrors: ['Response is empty'],
        inspectedText: '',
      );
    }

    // 1. Dimensional / Unit Check on claimed final answers
    final finalAnswerMatch = RegExp(
      r'(?:answer|velocity|speed|acceleration|force|distance|mass|time)\s*(?:is|=|:)\s*(\d+(?:\.\d+)?)\s*([a-zA-Z\/²\^\-]+)',
      caseSensitive: false,
    ).firstMatch(cleanResponse);

    if (finalAnswerMatch != null) {
      final value = double.tryParse(finalAnswerMatch.group(1)!);
      final rawUnit = finalAnswerMatch.group(2)!;
      final matchedQuantity = finalAnswerMatch.group(0)!.split(RegExp(r'is|=|:')).first.trim();

      final report = _unitValidator.validate(
        quantity: matchedQuantity,
        unit: rawUnit,
        value: value,
      );

      if (!report.isValid && report.errorMessage != null) {
        errors.add(report.errorMessage!);
      }
    }

    // 2. Strategy-specific validation checks
    if (strategy == TeachingStrategy.workedProblem) {
      // Must contain numbers or formulas
      if (!RegExp(r'\d+').hasMatch(cleanResponse)) {
        warnings.add('Worked problem response lacks explicit numerical steps');
      }
    }

    if (strategy == TeachingStrategy.factualDefinition) {
      // Definitions should be direct and not overly verbose
      if (cleanResponse.length > 2500) {
        warnings.add('Definition response exceeds recommended concise length');
      }
    }

    return GuardValidationResult(
      isApproved: errors.isEmpty,
      detectedErrors: errors,
      warnings: warnings,
      inspectedText: cleanResponse,
    );
  }
}
