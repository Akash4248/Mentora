import 'dart:math';
import 'package:math_expressions/math_expressions.dart';

class ToolCallResult {
  final String toolName;
  final String rawArguments;
  final String outputText;
  final bool isSuccess;

  ToolCallResult({
    required this.toolName,
    required this.rawArguments,
    required this.outputText,
    required this.isSuccess,
  });
}

class EducationalToolCallingEngine {
  EducationalToolCallingEngine._();

  static final EducationalToolCallingEngine instance = EducationalToolCallingEngine._();

  final Parser _parser = Parser();

  /// Evaluates arithmetic/algebraic mathematical expressions safely using math_expressions.
  ToolCallResult evaluateMath(String expression) {
    final cleaned = expression.trim();
    if (cleaned.isEmpty) {
      return ToolCallResult(
        toolName: 'calculate',
        rawArguments: expression,
        outputText: 'Error: Empty expression',
        isSuccess: false,
      );
    }

    try {
      // Normalize common math symbols
      var exprText = cleaned
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll('π', 'pi')
          .replaceAll('√', 'sqrt');

      // Replace pi and e constants
      exprText = exprText.replaceAll('pi', '${pi}');
      exprText = exprText.replaceAll('e', '${e}');

      final Expression exp = _parser.parse(exprText);
      final ContextModel cm = ContextModel();
      final double eval = exp.evaluate(EvaluationType.REAL, cm);

      final resultString = (eval % 1 == 0) ? eval.toInt().toString() : eval.toStringAsFixed(4);
      return ToolCallResult(
        toolName: 'calculate',
        rawArguments: expression,
        outputText: resultString,
        isSuccess: true,
      );
    } catch (e) {
      return ToolCallResult(
        toolName: 'calculate',
        rawArguments: expression,
        outputText: 'Calculation error: $e',
        isSuccess: false,
      );
    }
  }

  /// Evaluates and replaces all structured tool call tags in text (e.g. `[TOOL: calculate("10 + 5 * 2")]`)
  String processAndExecuteToolCalls(String text) {
    var processed = text;

    // Pattern 1: [TOOL: calculate("...")] or [TOOL: calculate('...')] or calculate("...")
    final calcRegExp = RegExp(r'\[TOOL:\s*calculate\((?:"|\')([^"\']+)(?:"|\')\)\s*\]|calculate\((?:"|\')([^"\']+)(?:"|\')\)', caseSensitive: false);
    
    processed = processed.replaceAllMapped(calcRegExp, (match) {
      final expr = match.group(1) ?? match.group(2) ?? '';
      final result = evaluateMath(expr);
      if (result.isSuccess) {
        return '`${expr} = ${result.outputText}`';
      }
      return match.group(0) ?? '';
    });

    return processed;
  }
}
