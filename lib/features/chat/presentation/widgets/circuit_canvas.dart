import 'package:flutter/material.dart';

import '../../application/circuit_engine.dart';
import '../../application/visual_resolver.dart';

/// Interactive, mathematically grounded canvas rendering DC circuit schematics
/// (Ohm's law, series, parallel networks) with live switch toggles and analytical calculations.
class CircuitCanvas extends StatefulWidget {
  const CircuitCanvas({
    required this.payload,
    super.key,
  });

  final CircuitVisualPayload payload;

  @override
  State<CircuitCanvas> createState() => _CircuitCanvasState();
}

class _CircuitCanvasState extends State<CircuitCanvas> with SingleTickerProviderStateMixin {
  late CircuitEngine _engine;
  late double _voltage;
  late bool _isSwitchClosed;
  late double _primaryResistance;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _engine = const CircuitEngine();
    _voltage = widget.payload.result.voltageVolts;
    _isSwitchClosed = widget.payload.result.isSwitchClosed;
    _primaryResistance = widget.payload.result.resistances.isNotEmpty
        ? widget.payload.result.resistances.first
        : 10.0;

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String _formatScenarioTitle(CircuitScenario scenario) {
    switch (scenario) {
      case CircuitScenario.simple:
        return 'Simple DC Circuit';
      case CircuitScenario.series:
        return 'Series Resistor Network';
      case CircuitScenario.parallel:
        return 'Parallel Resistor Network';
      case CircuitScenario.ohmsLaw:
        return "Ohm's Law (V = IR) Circuit";
    }
  }

  @override
  Widget build(BuildContext context) {
    final scenario = widget.payload.result.scenario;
    final rList = widget.payload.result.resistances.length > 1
        ? [_primaryResistance, widget.payload.result.resistances[1]]
        : [_primaryResistance];

    final currentResult = _engine.solve(
      scenario: scenario,
      voltageVolts: _voltage,
      isSwitchClosed: _isSwitchClosed,
      resistances: rList,
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF334155)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.electric_bolt_rounded, color: Color(0xFFFBBF24), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.payload.intent.title ?? _formatScenarioTitle(scenario),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (_isSwitchClosed ? const Color(0xFF10B981) : const Color(0xFFEF4444))
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isSwitchClosed ? const Color(0xFF34D399) : const Color(0xFFF87171),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    _isSwitchClosed ? 'SWITCH CLOSED (ON)' : 'SWITCH OPEN (OFF)',
                    style: TextStyle(
                      color: _isSwitchClosed ? const Color(0xFF34D399) : const Color(0xFFF87171),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // CustomPainter Circuit Viewport
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AnimatedBuilder(
                  animation: _animController,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _CircuitPainter(
                        result: currentResult,
                        flowAnimationValue: _animController.value,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Theorem badge note
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155), width: 0.8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.bolt_rounded, color: Color(0xFFFBBF24), size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      currentResult.theoremNote,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Telemetry readouts
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTelemetry('Voltage (V)', '${_voltage.toStringAsFixed(1)} V'),
                _buildTelemetry('Current (I)', '${currentResult.totalCurrentAmps.toStringAsFixed(2)} A'),
                _buildTelemetry('Total R', '${currentResult.equivalentResistanceOhms.toStringAsFixed(1)} Ω'),
                _buildTelemetry('Power (P)', '${currentResult.totalPowerWatts.toStringAsFixed(1)} W'),
              ],
            ),
          ),

          // Interactive Controls: Switch Toggle & Voltage Slider
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
            child: Row(
              children: [
                // Switch Toggle Button
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isSwitchClosed = !_isSwitchClosed;
                    });
                  },
                  icon: Icon(
                    _isSwitchClosed ? Icons.power_rounded : Icons.power_off_rounded,
                    size: 16,
                  ),
                  label: Text(_isSwitchClosed ? 'Toggle OFF' : 'Toggle ON'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSwitchClosed ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),

                // Voltage Slider
                Expanded(
                  child: Row(
                    children: [
                      const Text(
                        'V:',
                        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: const Color(0xFFFBBF24),
                            inactiveTrackColor: const Color(0xFF334155),
                            thumbColor: Colors.white,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            trackHeight: 3,
                          ),
                          child: Slider(
                            value: _voltage.clamp(1.0, 24.0),
                            min: 1.0,
                            max: 24.0,
                            onChanged: (val) {
                              setState(() {
                                _voltage = val;
                              });
                            },
                          ),
                        ),
                      ),
                      Text(
                        '${_voltage.toStringAsFixed(1)} V',
                        style: const TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetry(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFFF8FAFC),
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// CustomPainter rendering clean DC schematic diagrams with battery, switch, bulb, and current flow.
class _CircuitPainter extends CustomPainter {
  const _CircuitPainter({
    required this.result,
    required this.flowAnimationValue,
  });

  final CircuitCalculationResult result;
  final double flowAnimationValue;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final w = size.width;
    final h = size.height;

    // Schematic loop coordinates
    final left = w * 0.14;
    final right = w * 0.86;
    final top = h * 0.22;
    final bottom = h * 0.78;

    final wirePaint = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    // 1. Draw Bottom Wire with Battery
    // Left bottom corner to battery negative terminal
    final battCenterX = (left + right) / 2;
    canvas.drawLine(Offset(left, bottom), Offset(battCenterX - 22, bottom), wirePaint);
    canvas.drawLine(Offset(battCenterX + 22, bottom), Offset(right, bottom), wirePaint);

    // Draw Battery Symbol (Long line +, Short thick line -)
    final posPlatePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 2.6;
    final negPlatePaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..strokeWidth = 4.5;

    // Negative plate (left)
    canvas.drawLine(Offset(battCenterX - 8, bottom - 10), Offset(battCenterX - 8, bottom + 10), negPlatePaint);
    // Positive plate (right)
    canvas.drawLine(Offset(battCenterX + 8, bottom - 18), Offset(battCenterX + 8, bottom + 18), posPlatePaint);

    _drawText(
      canvas,
      '+',
      Offset(battCenterX + 16, bottom - 22),
      const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
    );
    _drawText(
      canvas,
      '${result.voltageVolts.toStringAsFixed(1)}V Battery',
      Offset(battCenterX, bottom + 16),
      const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
    );

    // 2. Draw Left Wire
    canvas.drawLine(Offset(left, bottom), Offset(left, top), wirePaint);

    // 3. Draw Right Wire with Switch
    final switchY = (top + bottom) / 2;
    canvas.drawLine(Offset(right, bottom), Offset(right, switchY + 18), wirePaint);
    canvas.drawLine(Offset(right, switchY - 18), Offset(right, top), wirePaint);

    // Draw Switch contacts
    final switchDotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(right, switchY + 16), 3.0, switchDotPaint);
    canvas.drawCircle(Offset(right, switchY - 16), 3.0, switchDotPaint);

    // Switch Blade
    final bladePaint = Paint()
      ..color = result.isSwitchClosed ? const Color(0xFF34D399) : const Color(0xFFF87171)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;

    if (result.isSwitchClosed) {
      canvas.drawLine(Offset(right, switchY + 16), Offset(right, switchY - 16), bladePaint);
    } else {
      // Tilted open blade
      canvas.drawLine(Offset(right, switchY + 16), Offset(right - 18, switchY - 10), bladePaint);
    }

    _drawText(
      canvas,
      result.isSwitchClosed ? 'Switch [ON]' : 'Switch [OFF]',
      Offset(right + 26, switchY),
      TextStyle(
        color: result.isSwitchClosed ? const Color(0xFF34D399) : const Color(0xFFF87171),
        fontSize: 9.5,
        fontWeight: FontWeight.bold,
      ),
    );

    // 4. Draw Top Rail with Resistors and Bulb
    if (result.scenario == CircuitScenario.parallel) {
      // Parallel branches
      _drawParallelTopRail(canvas, left, right, top);
    } else {
      // Series or Simple top rail
      _drawSeriesTopRail(canvas, left, right, top);
    }

    // 5. Draw Animated Current Flow Arrows if Closed and Current > 0
    if (result.hasCurrent) {
      _drawCurrentFlow(canvas, left, right, top, bottom);
    }
  }

  void _drawSeriesTopRail(Canvas canvas, double left, double right, double top) {
    final wirePaint = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    final bulbX = left + (right - left) * 0.35;
    final resistorX = left + (right - left) * 0.70;

    // Wires
    canvas.drawLine(Offset(left, top), Offset(bulbX - 16, top), wirePaint);
    canvas.drawLine(Offset(bulbX + 16, top), Offset(resistorX - 22, top), wirePaint);
    canvas.drawLine(Offset(resistorX + 22, top), Offset(right, top), wirePaint);

    // Draw Bulb
    _drawBulb(canvas, Offset(bulbX, top));

    // Draw Resistor
    final rVal = result.resistances.isNotEmpty ? result.resistances.first : 10.0;
    _drawResistor(canvas, Offset(resistorX, top), 'R = ${rVal.toStringAsFixed(1)} Ω');
  }

  void _drawParallelTopRail(Canvas canvas, double left, double right, double top) {
    final wirePaint = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    final branchLeft = left + (right - left) * 0.3;
    final branchRight = left + (right - left) * 0.7;
    const branchGap = 24.0;

    canvas.drawLine(Offset(left, top), Offset(branchLeft, top), wirePaint);
    canvas.drawLine(Offset(branchRight, top), Offset(right, top), wirePaint);

    // Branch 1 (Upper)
    canvas.drawLine(Offset(branchLeft, top), Offset(branchLeft, top - branchGap), wirePaint);
    canvas.drawLine(Offset(branchLeft, top - branchGap), Offset(branchRight, top - branchGap), wirePaint);
    canvas.drawLine(Offset(branchRight, top - branchGap), Offset(branchRight, top), wirePaint);

    // Branch 2 (Lower)
    canvas.drawLine(Offset(branchLeft, top), Offset(branchLeft, top + branchGap), wirePaint);
    canvas.drawLine(Offset(branchLeft, top + branchGap), Offset(branchRight, top + branchGap), wirePaint);
    canvas.drawLine(Offset(branchRight, top + branchGap), Offset(branchRight, top), wirePaint);

    final r1 = result.resistances.isNotEmpty ? result.resistances[0] : 10.0;
    final r2 = result.resistances.length > 1 ? result.resistances[1] : 10.0;

    final midX = (branchLeft + branchRight) / 2;
    _drawResistor(canvas, Offset(midX, top - branchGap), 'R₁ = ${r1.toStringAsFixed(1)} Ω');
    _drawResistor(canvas, Offset(midX, top + branchGap), 'R₂ = ${r2.toStringAsFixed(1)} Ω');
  }

  void _drawBulb(Canvas canvas, Offset center) {
    // Glow aura if brightness > 0
    if (result.bulbBrightnessFactor > 0) {
      final glowPaint = Paint()
        ..color = const Color(0xFFFBBF24).withValues(alpha: result.bulbBrightnessFactor * 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(center, 22.0, glowPaint);
    }

    final bulbPaint = Paint()
      ..color = result.bulbBrightnessFactor > 0 ? const Color(0xFFFBBF24) : const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, 14.0, bulbPaint);

    // Filament cross
    final filamentPaint = Paint()
      ..color = result.bulbBrightnessFactor > 0 ? Colors.white : const Color(0xFF475569)
      ..strokeWidth = 1.4;
    canvas.drawLine(center + const Offset(-7, -7), center + const Offset(7, 7), filamentPaint);
    canvas.drawLine(center + const Offset(-7, 7), center + const Offset(7, -7), filamentPaint);

    _drawText(
      canvas,
      'Bulb',
      center + const Offset(0, -22),
      const TextStyle(color: Color(0xFFCBD5E1), fontSize: 9, fontWeight: FontWeight.bold),
    );
  }

  void _drawResistor(Canvas canvas, Offset center, String label) {
    final boxPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final rRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: 34, height: 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(rRect, boxPaint);
    canvas.drawRRect(rRect, borderPaint);

    _drawText(
      canvas,
      label,
      center + const Offset(0, -14),
      const TextStyle(color: Color(0xFF38BDF8), fontSize: 9.5, fontWeight: FontWeight.bold),
    );
  }

  void _drawCurrentFlow(Canvas canvas, double left, double right, double top, double bottom) {
    final dotPaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..style = PaintingStyle.fill;

    // Calculate looped positions for charge carrier dots
    final totalPerimeter = (right - left) * 2 + (bottom - top) * 2;
    const numDots = 8;

    for (int i = 0; i < numDots; i++) {
      final progress = (flowAnimationValue + i / numDots) % 1.0;
      final dist = progress * totalPerimeter;

      Offset pos;
      final w = right - left;
      final h = bottom - top;

      if (dist < w) {
        // Bottom rail moving right (from + to -)
        pos = Offset(left + dist, bottom);
      } else if (dist < w + h) {
        // Right rail moving up
        pos = Offset(right, bottom - (dist - w));
      } else if (dist < 2 * w + h) {
        // Top rail moving left
        pos = Offset(right - (dist - (w + h)), top);
      } else {
        // Left rail moving down
        pos = Offset(left, top + (dist - (2 * w + h)));
      }

      canvas.drawCircle(pos, 2.5, dotPaint);
    }
  }

  void _drawText(Canvas canvas, String text, Offset position, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      position - Offset(painter.width / 2, painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _CircuitPainter oldDelegate) {
    return oldDelegate.result != result || oldDelegate.flowAnimationValue != flowAnimationValue;
  }
}
