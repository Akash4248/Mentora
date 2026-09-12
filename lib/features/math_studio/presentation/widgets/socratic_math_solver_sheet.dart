import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';

import '../../../../core/theme/idp_colors.dart';
import '../../../../core/theme/idp_typography.dart';
import '../../../chat/data/platform_tutor_inference_gateway.dart';

class SocraticMathSolverSheet extends StatefulWidget {
  final String? initialQuery;

  const SocraticMathSolverSheet({
    super.key,
    this.initialQuery,
  });

  @override
  State<SocraticMathSolverSheet> createState() =>
      _SocraticMathSolverSheetState();
}

class _SocraticMathSolverSheetState extends State<SocraticMathSolverSheet> {
  final TextEditingController _queryController = TextEditingController();
  bool _isSolving = false;
  List<_SolutionStep>? _steps;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null) {
      _queryController.text = widget.initialQuery!;
      _solveEquation();
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _solveEquation() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSolving = true;
      _steps = null;
    });

    try {
      // 1. Attempt symbolic math_expressions parsing first
      final symbolicSteps = _solveSymbolically(query);
      if (symbolicSteps != null && symbolicSteps.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _isSolving = false;
          _steps = symbolicSteps;
        });
        return;
      }
    } catch (_) {
      // Ignore symbolic parse errors and proceed to LLM gateway fallback
    }

    // 2. Fallback to PlatformTutorInferenceGateway for complex equations or word problems
    try {
      final gateway = PlatformTutorInferenceGateway();
      final prompt = 'Solve the following math equation or word problem step-by-step using Socratic tutoring format:\nQuestion: $query\nFormat your answer with clear step numbers (Step 1:, Step 2:, Step 3:) and brief explanations.';
      final buffer = StringBuffer();

      await for (final chunk in gateway.streamResponse(prompt: prompt)) {
        buffer.write(chunk);
      }

      final text = buffer.toString().trim();
      final parsedLlmSteps = _parseLlmResponseToSteps(text, query);

      if (!mounted) return;
      setState(() {
        _isSolving = false;
        _steps = parsedLlmSteps;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSolving = false;
        _steps = [
          _SolutionStep(
            stepNumber: 1,
            title: 'Problem Parsing',
            latexExpression: query,
            explanation: 'Unable to evaluate query online/offline. Please check syntax.',
          ),
        ];
      });
    }
  }

  List<_SolutionStep>? _solveSymbolically(String query) {
    final clean = query.replaceAll(' ', '');

    // Check simple quadratic equation e.g. x^2 - 4 = 0 or x^2 = 9
    final quadMatch = RegExp(r'^x\^2\-?(\d+)=0$|^x\^2=(\d+)$').firstMatch(clean);
    if (quadMatch != null) {
      final valStr = quadMatch.group(1) ?? quadMatch.group(2)!;
      final val = double.tryParse(valStr) ?? 0.0;
      final root = math.sqrt(val);
      final isInt = root == root.roundToDouble();
      final rootDisplay = isInt ? root.toInt().toString() : root.toStringAsFixed(2);

      return [
        _SolutionStep(
          stepNumber: 1,
          title: 'Identify Quadratic Equation',
          latexExpression: query,
          explanation: 'Standard form x² - k = 0 where k = $valStr.',
        ),
        _SolutionStep(
          stepNumber: 2,
          title: 'Isolate Square Term',
          latexExpression: 'x² = $valStr',
          explanation: 'Add constant $valStr to both sides of the equation.',
        ),
        _SolutionStep(
          stepNumber: 3,
          title: 'Extract Square Roots',
          latexExpression: 'x = ±$rootDisplay',
          explanation: 'Taking the principal and negative square root gives x = $rootDisplay or x = -$rootDisplay.',
        ),
      ];
    }

    // Check simple linear equation ax + b = c e.g. 2x + 5 = 15
    final linMatch = RegExp(r'^(\d*)x\+?(\d+)=(\d+)$').firstMatch(clean);
    if (linMatch != null) {
      final a = double.tryParse(linMatch.group(1)!.isEmpty ? '1' : linMatch.group(1)!) ?? 1.0;
      final b = double.tryParse(linMatch.group(2)!) ?? 0.0;
      final c = double.tryParse(linMatch.group(3)!) ?? 0.0;
      final rhs = c - b;
      final ans = rhs / a;
      final ansDisplay = ans == ans.roundToDouble() ? ans.toInt().toString() : ans.toStringAsFixed(2);

      return [
        _SolutionStep(
          stepNumber: 1,
          title: 'State Equation',
          latexExpression: '$a x + $b = $c',
          explanation: 'Isolate the linear term containing x.',
        ),
        _SolutionStep(
          stepNumber: 2,
          title: 'Subtract Constant from Both Sides',
          latexExpression: '$a x = $c - $b = ${rhs == rhs.roundToDouble() ? rhs.toInt() : rhs}',
          explanation: 'Perform inverse operations on left and right sides.',
        ),
        _SolutionStep(
          stepNumber: 3,
          title: 'Divide by Coefficient',
          latexExpression: 'x = $ansDisplay',
          explanation: 'Divide by $a to determine exact solution for x.',
        ),
      ];
    }

    // Attempt math_expressions evaluation for arithmetic expressions e.g. sin(30) + cos(60) or (12 * 4) / 3
    final parser = Parser();
    final exp = parser.parse(query.replaceAll('×', '*').replaceAll('÷', '/'));
    final cm = ContextModel();
    final eval = exp.evaluate(EvaluationType.REAL, cm);
    final evalDisplay = (eval as double) == (eval).roundToDouble() ? eval.toInt().toString() : eval.toStringAsFixed(4);

    return [
      _SolutionStep(
        stepNumber: 1,
        title: 'Parse Expression',
        latexExpression: query,
        explanation: 'Construct symbolic expression syntax tree.',
      ),
      _SolutionStep(
        stepNumber: 2,
        title: 'Evaluate Numerical Result',
        latexExpression: '= $evalDisplay',
        explanation: 'Simplified evaluated result.',
      ),
    ];
  }

  List<_SolutionStep> _parseLlmResponseToSteps(String llmText, String query) {
    final lines = llmText.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final steps = <_SolutionStep>[];
    int stepNum = 1;

    for (final line in lines) {
      if (line.toLowerCase().startsWith('step') || line.contains(':')) {
        final colonIdx = line.indexOf(':');
        final title = colonIdx >= 0 ? line.substring(0, colonIdx) : 'Step $stepNum';
        final explanation = colonIdx >= 0 ? line.substring(colonIdx + 1).trim() : line;
        steps.add(
          _SolutionStep(
            stepNumber: stepNum++,
            title: title,
            latexExpression: query,
            explanation: explanation,
          ),
        );
      }
    }

    if (steps.isEmpty) {
      steps.add(
        _SolutionStep(
          stepNumber: 1,
          title: 'Socratic Tutor Explanation',
          latexExpression: query,
          explanation: llmText,
        ),
      );
    }
    return steps;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // SHEET HEADER BAR
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFF4F46E5)),
                const SizedBox(width: 8),
                Text(
                  'Socratic Step-by-Step Problem Solver',
                  style: IDPTypography.titleSmall.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // INPUT SEARCH BAR
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _queryController,
                    decoration: InputDecoration(
                      hintText: 'Enter equation e.g. 2x + 3 = 7 or sin(x)',
                      prefixIcon: const Icon(Icons.functions_rounded, color: Color(0xFF4F46E5)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _solveEquation(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.psychology_rounded),
                  label: const Text('Solve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _solveEquation,
                ),
              ],
            ),
          ),

          // SOLUTION STEPS LIST
          Expanded(
            child: _isSolving
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Color(0xFF4F46E5)),
                        SizedBox(height: 12),
                        Text('Analyzing mathematical steps...'),
                      ],
                    ),
                  )
                : _steps == null
                    ? Center(
                        child: Text(
                          'Enter an equation above to generate a step-by-step Socratic solution.',
                          style: IDPTypography.bodyMd.copyWith(color: IDPColors.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _steps!.length,
                        itemBuilder: (context, index) {
                          final step = _steps![index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 14,
                                        backgroundColor: const Color(0xFF4F46E5),
                                        child: Text(
                                          '${step.stepNumber}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          step.title,
                                          style: IDPTypography.titleSmall.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFF4F46E5).withValues(alpha: 0.2)),
                                    ),
                                    child: Text(
                                      step.latexExpression,
                                      style: IDPTypography.bodyMd.copyWith(
                                        color: const Color(0xFF4F46E5),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    step.explanation,
                                    style: IDPTypography.caption.copyWith(
                                      color: IDPColors.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SolutionStep {
  final int stepNumber;
  final String title;
  final String latexExpression;
  final String explanation;

  _SolutionStep({
    required this.stepNumber,
    required this.title,
    required this.latexExpression,
    required this.explanation,
  });
}
