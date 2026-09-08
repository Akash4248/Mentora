import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:math_expressions/math_expressions.dart';

import '../../../core/theme/idp_colors.dart';
import '../../../core/theme/idp_theme.dart';
import '../../../core/theme/idp_typography.dart';
import '../../home/presentation/mentora_home_screen.dart';

class ScientificCalculatorScreen extends StatefulWidget {
  const ScientificCalculatorScreen({super.key});

  @override
  State<ScientificCalculatorScreen> createState() =>
      _ScientificCalculatorScreenState();
}

class _ScientificCalculatorScreenState
    extends State<ScientificCalculatorScreen> {
  String _expression = '';
  String _result = '0';
  bool _isRadian = true;
  bool _isSecondFunction = false;
  double _memory = 0.0;
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _onKeyPress(String value) {
    HapticFeedback.lightImpact();
    setState(() {
      if (value == 'AC') {
        _expression = '';
        _result = '0';
      } else if (value == '⌫') {
        if (_expression.isNotEmpty) {
          _expression = _expression.substring(0, _expression.length - 1);
        }
      } else if (value == '=') {
        _evaluateExpression();
      } else if (value == 'RAD' || value == 'DEG') {
        _isRadian = !_isRadian;
      } else if (value == '2nd') {
        _isSecondFunction = !_isSecondFunction;
      } else if (value == 'MC') {
        _memory = 0.0;
      } else if (value == 'MR') {
        _expression += _memory.toString();
      } else if (value == 'M+') {
        final val = double.tryParse(_result) ?? 0.0;
        _memory += val;
      } else if (value == 'M-') {
        final val = double.tryParse(_result) ?? 0.0;
        _memory -= val;
      } else {
        _expression += value;
      }
    });
  }

  void _evaluateExpression() {
    if (_expression.trim().isEmpty) return;

    try {
      String sanitized = _expression
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll('π', '${math.pi}')
          .replaceAll('e', '${math.e}');

      if (!_isRadian) {
        // Convert sin(x) to sin(x*pi/180) for degree mode
        sanitized = sanitized.replaceAllMapped(
          RegExp(r'(sin|cos|tan)\(([^)]+)\)'),
          (match) {
            final func = match.group(1);
            final arg = match.group(2);
            return '$func(($arg) * ${math.pi} / 180)';
          },
        );
      }

      final parser = Parser();
      final exp = parser.parse(sanitized);
      final cm = ContextModel();
      final eval = exp.evaluate(EvaluationType.REAL, cm) as double;

      setState(() {
        if (eval.isNaN || eval.isInfinite) {
          _result = 'Error';
        } else {
          // Format output: round floating point precision artifacts
          if (eval == eval.roundToDouble()) {
            _result = eval.toInt().toString();
          } else {
            _result = eval.toStringAsFixed(6).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
          }
          _history.insert(0, '$_expression = $_result');
          if (_history.length > 20) _history.removeLast();
        }
      });
    } catch (e) {
      setState(() {
        _result = 'Syntax Error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : IDPColors.background,
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.calculate_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'NCERT Scientific Calculator',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Colors.white),
            tooltip: 'Calculation History',
            onPressed: _showHistoryDialog,
          ),
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Colors.white),
            tooltip: 'Home Dashboard',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => const MentoraHomeScreen(initialTabIndex: 0),
                ),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // DISPLAY AREA
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Chip(
                          label: Text(
                            _isRadian ? 'RAD' : 'DEG',
                            style: IDPTypography.caption.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          backgroundColor: const Color(0xFF4F46E5),
                          visualDensity: VisualDensity.compact,
                        ),
                        if (_memory != 0.0)
                          Chip(
                            label: Text(
                              'M = $_memory',
                              style: IDPTypography.caption.copyWith(
                                color: const Color(0xFF10B981),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.1),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Text(
                        _expression.isEmpty ? '0' : _expression,
                        style: IDPTypography.headlineLg.copyWith(
                          color: isDark ? Colors.white70 : IDPColors.onSurfaceVariant,
                          fontSize: 24,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      reverse: true,
                      child: Text(
                        _result,
                        style: IDPTypography.headlineLg.copyWith(
                          color: const Color(0xFF4F46E5),
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // KEYPAD AREA
            Expanded(
              flex: 5,
              child: Container(
                padding: const EdgeInsets.all(12),
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cols = constraints.maxWidth > 500 ? 7 : 5;
                    final buttons = _buildKeypadButtons();
                    final rows = (buttons.length / cols).ceil();
                    final itemWidth = (constraints.maxWidth - (cols - 1) * 6) / cols;
                    final itemHeight = ((constraints.maxHeight - (rows - 1) * 6) / rows).clamp(24.0, 70.0);
                    final ratio = (itemWidth / itemHeight).clamp(0.8, 3.5);

                    return GridView.builder(
                      physics: const BouncingScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: cols,
                        childAspectRatio: ratio,
                        crossAxisSpacing: 6,
                        mainAxisSpacing: 6,
                      ),
                      itemCount: buttons.length,
                      itemBuilder: (context, index) {
                        final btn = buttons[index];
                        return _buildButtonTile(btn, isDark);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_CalcBtn> _buildKeypadButtons() {
    return [
      _CalcBtn('2nd', isFunction: true),
      _CalcBtn(_isRadian ? 'DEG' : 'RAD', isFunction: true),
      _CalcBtn('MC', isFunction: true),
      _CalcBtn('MR', isFunction: true),
      _CalcBtn('AC', isAction: true, color: Colors.redAccent),

      _CalcBtn(_isSecondFunction ? 'asin(' : 'sin(', isFunction: true),
      _CalcBtn(_isSecondFunction ? 'acos(' : 'cos(', isFunction: true),
      _CalcBtn(_isSecondFunction ? 'atan(' : 'tan(', isFunction: true),
      _CalcBtn('ln(', isFunction: true),
      _CalcBtn('⌫', isAction: true, color: Colors.orangeAccent),

      _CalcBtn('x²', textOverride: 'x²', isFunction: true, actionValue: '^2'),
      _CalcBtn('^', textOverride: 'xʸ', isFunction: true),
      _CalcBtn('sqrt(', textOverride: '√x', isFunction: true),
      _CalcBtn('log(', isFunction: true),
      _CalcBtn('÷', isOperator: true),

      _CalcBtn('(', isFunction: true),
      _CalcBtn('7'),
      _CalcBtn('8'),
      _CalcBtn('9'),
      _CalcBtn('×', isOperator: true),

      _CalcBtn(')', isFunction: true),
      _CalcBtn('4'),
      _CalcBtn('5'),
      _CalcBtn('6'),
      _CalcBtn('-', isOperator: true),

      _CalcBtn('π', isFunction: true),
      _CalcBtn('1'),
      _CalcBtn('2'),
      _CalcBtn('3'),
      _CalcBtn('+', isOperator: true),

      _CalcBtn('e', isFunction: true),
      _CalcBtn('0'),
      _CalcBtn('.'),
      _CalcBtn('=', isAction: true, color: const Color(0xFF4F46E5)),
    ];
  }

  Widget _buildButtonTile(_CalcBtn btn, bool isDark) {
    Color bg = isDark ? const Color(0xFF1E293B) : Colors.white;
    Color fg = isDark ? Colors.white : Colors.black87;

    if (btn.isOperator) {
      bg = const Color(0xFF4F46E5).withValues(alpha: 0.15);
      fg = const Color(0xFF4F46E5);
    } else if (btn.isFunction) {
      bg = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
      fg = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
    } else if (btn.isAction) {
      bg = btn.color ?? const Color(0xFF4F46E5);
      fg = Colors.white;
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      elevation: btn.isAction ? 3 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _onKeyPress(btn.actionValue ?? btn.label),
        child: Center(
          child: Text(
            btn.textOverride ?? btn.label,
            style: IDPTypography.titleSmall.copyWith(
              color: fg,
              fontWeight: btn.isAction || btn.isOperator ? FontWeight.bold : FontWeight.w600,
              fontSize: 18,
            ),
          ),
        ),
      ),
    );
  }

  void _showHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history_rounded, color: Color(0xFF4F46E5)),
            SizedBox(width: 8),
            Text('Calculation History'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: _history.isEmpty
              ? const Center(child: Text('No calculation history yet.'))
              : ListView.separated(
                  itemCount: _history.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = _history[index];
                    return ListTile(
                      dense: true,
                      title: Text(item, style: const TextStyle(fontWeight: FontWeight.w600)),
                      onTap: () {
                        final parts = item.split(' = ');
                        if (parts.isNotEmpty) {
                          setState(() => _expression += parts.first);
                          Navigator.pop(context);
                        }
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _history.clear());
              Navigator.pop(context);
            },
            child: const Text('Clear History', style: TextStyle(color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _CalcBtn {
  final String label;
  final String? textOverride;
  final String? actionValue;
  final bool isOperator;
  final bool isFunction;
  final bool isAction;
  final Color? color;

  _CalcBtn(
    this.label, {
    this.textOverride,
    this.actionValue,
    this.isOperator = false,
    this.isFunction = false,
    this.isAction = false,
    this.color,
  });
}
