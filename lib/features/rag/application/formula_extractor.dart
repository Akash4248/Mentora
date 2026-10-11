import '../domain/chunk_v2.dart';

/// Extracts mathematical formulas from text while preserving context
class FormulaExtractor {
  // LaTeX patterns: $...$ or \[...\]                           
  static final _latexPattern =
      RegExp(r'(?:\$+|\\\\?[\[\(])(.+?)(?:\$+|\\\\?[\]\)])');

  // Inline math: 2x + 3 = 7, a², b³, etc.
  static final _inlineMathPattern = RegExp(
    r'[a-zA-Z]\s*[+\-×÷*]\s*\d+|[a-zA-Z]²|[a-zA-Z]³|\d+\.\d+|√\d+',
  );

  // Note: Equation context pattern available for future enhancement

  // Simple algebraic equation: variable = expression
  static final _simpleEquationPattern = RegExp(
    r'([a-zA-Z_]\w*)\s*=\s*([^;\n.]+)',
  );

  /// Extract formulas from text preserving positions and context
  static List<Formula> extractFormulas(String text) {
    final formulas = <Formula>[];

    // Extract LaTeX formulas
    for (final match in _latexPattern.allMatches(text)) {
      final original = match.group(0) ?? '';
      final inner = match.group(1) ?? '';
      final position = match.start;

      formulas.add(
        Formula(
          original: original,
          latex: inner,
          type: _classifyFormula(original),
          variables: _extractVariables(original),
          position: position,
        ),
      );
    }

    // Extract inline math expressions (if not already in LaTeX)
    for (final match in _inlineMathPattern.allMatches(text)) {
      // Check if this overlap with any LaTeX formula
      if (formulas.any((f) => _overlaps(f.position, match.start))) {
        continue;
      }

      final original = match.group(0) ?? '';
      final position = match.start;

      formulas.add(
        Formula(
          original: original,
          type: _classifyFormula(original),
          variables: _extractVariables(original),
          position: position,
        ),
      );
    }

    // Extract simple algebraic equations
    for (final match in _simpleEquationPattern.allMatches(text)) {
      // Skip if already captured
      if (formulas.any((f) => _overlaps(f.position, match.start))) {
        continue;
      }

      final variable = match.group(1) ?? '';
      final expression = match.group(2) ?? '';
      final original = '${match.group(0)}';
      final position = match.start;

      // Only if looks like an equation (has operators or numbers on RHS)
      if (RegExp(r'[+\-×÷*/]|\d').hasMatch(expression)) {
        formulas.add(
          Formula(
            original: original,
            type: 'equation',
            variables: [variable],
            position: position,
          ),
        );
      }
    }

    // Sort by position
    formulas.sort((a, b) => a.position.compareTo(b.position));

    return formulas;
  }

  /// Classify formula type based on content
  static String _classifyFormula(String formula) {
    final normalized = formula.toLowerCase();

    if (normalized.contains('=')) {
      if (normalized.contains('²') ||
          normalized.contains('^2') ||
          normalized.contains('x^2')) {
        return 'quadratic';
      }
      return 'equation';
    }

    if (normalized.contains('>') || normalized.contains('<')) {
      return 'inequality';
    }

    if (normalized.contains('√') || normalized.contains('sqrt')) {
      return 'radical';
    }

    if (RegExp(r'\\frac|/').hasMatch(formula)) {
      return 'fraction';
    }

    return 'expression';
  }

  /// Extract variable names from formula
  static List<String> _extractVariables(String formula) {
    final variables = <String>{};

    // Match single letters (variables)
    final pattern = RegExp(r'\b([a-zA-Z])\b');
    for (final match in pattern.allMatches(formula)) {
      variables.add(match.group(1)!);
    }

    // Remove common non-variables
    variables.removeAll(['e', 'E', 'i', 'I']); // Mathematical constants

    return variables.toList()..sort();
  }

  /// Check if two ranges overlap
  static bool _overlaps(int pos1, int pos2, [int tolerance = 10]) {
    return (pos1 - pos2).abs() < tolerance;
  }

  /// Replace formulas with tagged versions in text
  static String tagFormulasInText(String text, List<Formula> formulas) {
    if (formulas.isEmpty) return text;

    // Sort by position descending to maintain indices during replacement
    final sorted = [...formulas]..sort((a, b) => b.position.compareTo(a.position));

    var result = text;
    for (final formula in sorted) {
      final tag =
          '<formula type="${formula.type}" vars="${formula.variables.join(',')}">${formula.original}</formula>';

      // Simple replacement - assumes formulas don't overlap
      if (formula.position >= 0 && formula.position <= result.length) {
        // Find the actual formula in text near the position
        final searchStart = (formula.position - 20).clamp(0, result.length);
        final searchEnd = (formula.position + 100).clamp(0, result.length);
        final substring = result.substring(searchStart, searchEnd);

        if (substring.contains(formula.original)) {
          final index = result.indexOf(formula.original, searchStart);
          if (index >= 0) {
            result = result.replaceFirst(formula.original, tag, index);
          }
        }
      }
    }

    return result;
  }

}
