import 'dart:math' as math;

// ignore: deprecated_member_use
import 'package:math_expressions/math_expressions.dart';

/// Evaluates math expressions from blueprint JSON strings using the shared
/// `math_expressions` scientific library (same engine as the calculator).
///
/// Supported: + - * / ^ % () sqrt() abs() sin/cos/tan/ln/log, pi, e,
/// word-boundary variable substitution (no `temperature` → `t...` corruption).
///
/// Examples:
///   FormulaEvaluator.evaluate('sqrt(9.81 / var_length)', {'var_length': 2.0})
///   → sqrt(4.905) → 2.215
///
///   FormulaEvaluator.evaluate('2 * pi * sqrt(var_length / 9.81)', {'var_length': 1.0})
///   → 2.006
class FormulaEvaluator {
  static final Parser _parser = Parser();

  /// Evaluate [expression] with variable values substituted from [vars].
  /// Returns the computed double, or [defaultValue] if evaluation fails.
  static double evaluate(
    String expression,
    Map<String, double> vars, {
    double defaultValue = 0.0,
  }) {
    try {
      var expr = expression.trim();
      if (expr.isEmpty) return defaultValue;

      // 1. Substitute variables longest-first with word boundaries so
      // `var` never corrupts `var_length`, and `e` never corrupts `exp`.
      final sorted = vars.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final key in sorted) {
        if (key.isEmpty) continue;
        expr = expr.replaceAll(
          RegExp(r'\b' + RegExp.escape(key) + r'\b'),
          '(${vars[key].toString()})',
        );
      }

      // 2. Named constants with word boundaries.
      expr = expr.replaceAll(
          RegExp(r'\bpi\b'), '(${math.pi.toString()})');
      expr = expr.replaceAll(
          RegExp(r'\be\b'), '(${math.e.toString()})');
      expr = expr.replaceAll(RegExp(r'\bg\b'), '(9.81)');

      // 3. Evaluate via scientific library.
      // ignore: deprecated_member_use
      final parsed = _parser.parse(expr);
      final cm = ContextModel();
      // ignore: deprecated_member_use
      final value = parsed.evaluate(EvaluationType.REAL, cm);
      if (value is num) {
        final d = value.toDouble();
        if (d.isNaN || d.isInfinite) return defaultValue;
        return d;
      }
      return defaultValue;
    } catch (_) {
      return defaultValue;
    }
  }
}
