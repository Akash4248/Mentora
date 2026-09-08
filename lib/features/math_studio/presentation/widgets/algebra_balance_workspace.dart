import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../../core/theme/idp_colors.dart';
import '../../../../core/theme/idp_typography.dart';

class AlgebraBalanceWorkspace extends StatefulWidget {
  const AlgebraBalanceWorkspace({super.key});

  @override
  State<AlgebraBalanceWorkspace> createState() =>
      _AlgebraBalanceWorkspaceState();
}

class _AlgebraBalanceWorkspaceState extends State<AlgebraBalanceWorkspace> {
  int _leftXCount = 2;
  int _leftUnits = 3;
  int _rightXCount = 0;
  int _rightUnits = 7;
  final double _xValue = 2.0;

  double get _leftTotalWeight => (_leftXCount * _xValue) + _leftUnits;
  double get _rightTotalWeight => (_rightXCount * _xValue) + _rightUnits;

  double get _tiltAngle {
    final diff = _rightTotalWeight - _leftTotalWeight;
    return (diff * 0.05).clamp(-0.3, 0.3);
  }

  bool get _isBalanced => (_leftTotalWeight - _rightTotalWeight).abs() < 0.001;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          // EQUATION READOUT BANNER
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Algebraic Equation:',
                      style: IDPTypography.caption.copyWith(color: IDPColors.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_leftXCount}x + $_leftUnits  =  ${_rightXCount > 0 ? '${_rightXCount}x + ' : ''}$_rightUnits',
                      style: IDPTypography.titleSmall.copyWith(
                        color: const Color(0xFF4F46E5),
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                Chip(
                  avatar: Icon(
                    _isBalanced ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                    color: _isBalanced ? Colors.white : Colors.amber,
                    size: 18,
                  ),
                  label: Text(
                    _isBalanced ? 'Balanced (x = $_xValue)' : 'Unbalanced',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  backgroundColor: _isBalanced ? const Color(0xFF10B981) : Colors.orangeAccent,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // VISUAL BALANCE SCALE CANVAS
          Expanded(
            child: CustomPaint(
              painter: _BalanceScalePainter(
                tiltAngle: _tiltAngle,
                isDark: isDark,
              ),
              child: Stack(
                children: [
                  // LEFT PAN WEIGHT BLOCKS
                  Align(
                    alignment: Alignment(-0.55 + _tiltAngle * 0.5, 0.2 - _tiltAngle * 0.8),
                    child: _buildPanContents(
                      xCount: _leftXCount,
                      unitCount: _leftUnits,
                      onAddX: () => setState(() => _leftXCount++),
                      onRemoveX: () => setState(() => _leftXCount = math.max(0, _leftXCount - 1)),
                      onAddUnit: () => setState(() => _leftUnits++),
                      onRemoveUnit: () => setState(() => _leftUnits = math.max(0, _leftUnits - 1)),
                    ),
                  ),

                  // RIGHT PAN WEIGHT BLOCKS
                  Align(
                    alignment: Alignment(0.55 + _tiltAngle * 0.5, 0.2 + _tiltAngle * 0.8),
                    child: _buildPanContents(
                      xCount: _rightXCount,
                      unitCount: _rightUnits,
                      onAddX: () => setState(() => _rightXCount++),
                      onRemoveX: () => setState(() => _rightXCount = math.max(0, _rightXCount - 1)),
                      onAddUnit: () => setState(() => _rightUnits++),
                      onRemoveUnit: () => setState(() => _rightUnits = math.max(0, _rightUnits - 1)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanContents({
    required int xCount,
    required int unitCount,
    required VoidCallback onAddX,
    required VoidCallback onRemoveX,
    required VoidCallback onAddUnit,
    required VoidCallback onRemoveUnit,
  }) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              ...List.generate(
                xCount,
                (_) => Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F46E5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Text('x', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              ...List.generate(
                unitCount,
                (_) => Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Text('1', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.add_box_rounded, size: 20, color: Color(0xFF38BDF8)),
                onPressed: onAddX,
                tooltip: 'Add x Block',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              IconButton(
                icon: const Icon(Icons.indeterminate_check_box_rounded, size: 20, color: Colors.orangeAccent),
                onPressed: onRemoveX,
                tooltip: 'Remove x Block',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_rounded, size: 20, color: Color(0xFF10B981)),
                onPressed: onAddUnit,
                tooltip: 'Add Unit 1',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceScalePainter extends CustomPainter {
  final double tiltAngle;
  final bool isDark;

  _BalanceScalePainter({required this.tiltAngle, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.7);
    final beamLength = size.width * 0.7;

    final paint = Paint()
      ..color = isDark ? Colors.white70 : const Color(0xFF334155)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    // Base Stand (Triangle)
    final base = Path()
      ..moveTo(center.dx, center.dy - 60)
      ..lineTo(center.dx - 40, center.dy + 40)
      ..lineTo(center.dx + 40, center.dy + 40)
      ..close();

    final fillPaint = Paint()..color = const Color(0xFF4F46E5).withValues(alpha: 0.3);
    canvas.drawPath(base, fillPaint);
    canvas.drawPath(base, paint);

    // Tilted Fulcrum Beam
    canvas.save();
    canvas.translate(center.dx, center.dy - 60);
    canvas.rotate(tiltAngle);

    final leftEnd = Offset(-beamLength / 2, 0);
    final rightEnd = Offset(beamLength / 2, 0);

    canvas.drawLine(leftEnd, rightEnd, paint..strokeWidth = 6);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BalanceScalePainter oldDelegate) {
    return oldDelegate.tiltAngle != tiltAngle || oldDelegate.isDark != isDark;
  }
}
