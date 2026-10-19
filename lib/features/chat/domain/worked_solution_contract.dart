import 'solution_step.dart';

/// Contract representing a fully structured, pedagogically validated worked solution.
final class WorkedSolution {
  const WorkedSolution({
    required this.problemStatement,
    this.givenParameters = const {},
    required this.targetVariable,
    required this.steps,
    required this.finalAnswer,
    required this.finalUnits,
  });

  /// The original problem or numerical question.
  final String problemStatement;

  /// Parsed given values with physical units (e.g. {'u': '0 m/s', 'a': '2 m/s²'}).
  final Map<String, String> givenParameters;

  /// The variable to solve for (e.g. 'v' or 'Final velocity').
  final String targetVariable;

  /// Ordered solution steps.
  final List<SolutionStep> steps;

  /// The numeric or algebraic final computed value (e.g. '10').
  final String finalAnswer;

  /// The SI unit of the final value (e.g. 'm/s').
  final String finalUnits;

  /// Validates that the steps are sequential, non-empty, and terminate with an answer.
  bool isValid() {
    if (steps.isEmpty || finalAnswer.trim().isEmpty || finalUnits.trim().isEmpty) {
      return false;
    }
    for (var i = 0; i < steps.length; i++) {
      if (steps[i].stepNumber != i + 1) return false;
      if (steps[i].title.trim().isEmpty) return false;
    }
    return true;
  }

  /// Formats the worked solution into clean, readable Markdown.
  String toMarkdown() {
    final buffer = StringBuffer();
    buffer.writeln('### Step-by-Step Solution\n');

    if (givenParameters.isNotEmpty) {
      buffer.writeln('**Given Values:**');
      for (final entry in givenParameters.entries) {
        buffer.writeln('- ${entry.key} = `${entry.value}`');
      }
      buffer.writeln('- **Find:** `$targetVariable`\n');
    }

    for (final step in steps) {
      buffer.writeln('#### Step ${step.stepNumber}: ${step.title}');
      buffer.writeln(step.explanation);
      if (step.formula != null) {
        buffer.writeln('\$\$\\text{Formula: } ${step.formula}\$\$');
      }
      if (step.substitution != null) {
        buffer.writeln('\$\$\\text{Substitution: } ${step.substitution}\$\$');
      }
      if (step.calculation != null) {
        buffer.writeln('\$\$\\text{Calculation: } ${step.calculation}\$\$');
      }
      buffer.writeln();
    }

    buffer.writeln('**Final Answer:**');
    buffer.writeln('\$\$\\mathbf{$targetVariable = $finalAnswer\\text{ $finalUnits}}\$\$');
    return buffer.toString().trim();
  }

  /// Parses markdown text containing step headers (e.g. `Step 1: ...` or `#### Step 1: ...`).
  static WorkedSolution? tryParseFromText({
    required String text,
    required String question,
  }) {
    final stepRegex = RegExp(r'(?:###*|\*\*)\s*Step\s*(\d+)[:.]?\s*([^\n*]+)(?:\*\*|\n)([\s\S]*?)(?=(?:###*|\*\*)\s*Step\s*\d+|$)', caseSensitive: false);
    final matches = stepRegex.allMatches(text).toList();
    if (matches.isEmpty) return null;

    final steps = <SolutionStep>[];
    for (final match in matches) {
      final stepNum = int.tryParse(match.group(1) ?? '1') ?? (steps.length + 1);
      final title = (match.group(2) ?? 'Step $stepNum').trim();
      final body = (match.group(3) ?? '').trim();

      steps.add(
        SolutionStep(
          stepNumber: stepNum,
          title: title,
          explanation: body,
        ),
      );
    }

    if (steps.isEmpty) return null;

    return WorkedSolution(
      problemStatement: question,
      targetVariable: 'Result',
      steps: steps,
      finalAnswer: 'Computed',
      finalUnits: '',
    );
  }
}
