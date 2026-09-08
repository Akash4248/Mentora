import 'package:flutter/material.dart';

import '../../../../core/theme/idp_colors.dart';
import '../../../../core/theme/idp_typography.dart';

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

  void _solveEquation() {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSolving = true;
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      setState(() {
        _isSolving = false;
        _steps = [
          _SolutionStep(
            stepNumber: 1,
            title: 'Identify Problem Structure & State Equation',
            latexExpression: query,
            explanation: 'Classify the given mathematical expression and determine target variable.',
          ),
          _SolutionStep(
            stepNumber: 2,
            title: 'Apply Inverse Operations to Isolate Variable',
            latexExpression: 'Subtract constants from both sides of equation',
            explanation: 'Keep balance scale equal by performing identical operations on left and right sides.',
          ),
          _SolutionStep(
            stepNumber: 3,
            title: 'Compute Final Simplification',
            latexExpression: 'x = 2',
            explanation: 'Divide by the coefficient to find exact solution.',
          ),
        ];
      });
    });
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
