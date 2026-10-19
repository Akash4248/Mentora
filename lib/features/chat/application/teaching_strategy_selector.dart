import '../domain/router_decision.dart';
import '../domain/teaching_strategy.dart';

/// Selects an adaptive teaching strategy based on student question structure,
/// semantic intent cues, and first-pass route classification.
final class TeachingStrategySelector {
  const TeachingStrategySelector();

  /// Identifies the recommended teaching strategy for an inquiry.
  TeachingStrategy selectStrategy({
    required String question,
    required String topic,
    required TutorRoute route,
  }) {
    final clean = question.trim().toLowerCase();

    // 1. Explicit comparison requests
    if (_isComparativeQuery(clean)) {
      return TeachingStrategy.comparativeContrast;
    }

    // 2. Mathematical or physical derivations
    if (route == TutorRoute.derivation || _isDerivationQuery(clean)) {
      return TeachingStrategy.stepwiseDerivation;
    }

    // 3. Worked numerical problems
    if (route == TutorRoute.calculation || _isWorkedProblemQuery(clean)) {
      return TeachingStrategy.workedProblem;
    }

    // 4. Direct factual definitions and unit queries
    if (_isFactualDefinitionQuery(clean)) {
      return TeachingStrategy.factualDefinition;
    }

    // 5. Default conceptual explanations and intuitions
    return TeachingStrategy.conceptualIntuition;
  }

  /// Formats explicit pedagogical instructions corresponding to the selected strategy.
  String instructionForStrategy(TeachingStrategy strategy) {
    switch (strategy) {
      case TeachingStrategy.factualDefinition:
        return 'Pedagogical Directive: Provide a concise, textbook-accurate definition. State the primary formula and standard SI units if applicable. Do not force unnecessary analogies or multi-step derivations.';

      case TeachingStrategy.conceptualIntuition:
        return 'Pedagogical Directive: Explain the core principle clearly. Include an intuitive real-world analogy. Explicitly state the limitation of the analogy so the student is not misled. Conclude with a conceptual observation check.';

      case TeachingStrategy.workedProblem:
        return 'Pedagogical Directive: Structure the solution into clear steps:\n1. State Given parameters with SI units\n2. State the applicable Formula\n3. Show Substitution\n4. Show Calculation\n5. State Final Answer clearly with proper SI units.';

      case TeachingStrategy.stepwiseDerivation:
        return 'Pedagogical Directive: Provide a rigorous, step-by-step mathematical derivation. For each algebraic step, clearly state the physical law or mathematical definition being applied.';

      case TeachingStrategy.comparativeContrast:
        return 'Pedagogical Directive: Contrast the two concepts clearly using parallel bullet points or a Markdown table comparing: Definition, Scalar vs. Vector nature, SI units, and Key Physical Difference.';
    }
  }

  bool _isComparativeQuery(String clean) {
    return clean.contains('difference between') ||
        clean.contains('distinguish between') ||
        clean.contains('compare and contrast') ||
        clean.contains('versus') ||
        clean.contains(' vs ') ||
        clean.contains('how does it differ from');
  }

  bool _isDerivationQuery(String clean) {
    return clean.startsWith('derive') ||
        clean.contains('derivation of') ||
        clean.contains('prove that');
  }

  bool _isWorkedProblemQuery(String clean) {
    final hasNumber = RegExp(r'\d+').hasMatch(clean);
    final hasUnit = RegExp(r'\b(?:m|s|m\/s|km|hr|kg|n|joules|j|watts|w)\b').hasMatch(clean);
    final hasSolveCommand = clean.contains('calculate') ||
        clean.contains('compute') ||
        clean.contains('solve') ||
        clean.contains('find the');

    return (hasSolveCommand && hasNumber) || (hasNumber && hasUnit);
  }

  bool _isFactualDefinitionQuery(String clean) {
    if (clean.contains('why') || clean.contains('how does')) {
      return false; // Conceptual inquiry
    }

    return clean.startsWith('define') ||
        clean.startsWith('what is the definition of') ||
        clean.startsWith('what is the si unit of') ||
        clean.startsWith('what is meant by') ||
        clean.startsWith('state the formula for');
  }
}
