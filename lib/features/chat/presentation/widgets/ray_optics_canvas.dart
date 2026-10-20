import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../application/optics_engine.dart';
import '../../application/visual_resolver.dart';

/// Interactive, mathematically grounded canvas rendering an optical ray diagram
/// (mirrors and lenses) with analytical ground-truth from [OpticsEngine].
class RayOpticsCanvas extends StatefulWidget {
  const RayOpticsCanvas({
    required this.payload,
    super.key,
  });

  final OpticsVisualPayload payload;

  @override
  State<RayOpticsCanvas> createState() => _RayOpticsCanvasState();
}

class _RayOpticsCanvasState extends State<RayOpticsCanvas> {
  late double _currentU;
  late OpticsEngine _engine;

  @override
  void initState() {
    super.initState();
    _engine = const OpticsEngine();
    _currentU = widget.payload.result.objectDistanceCm.abs();
  }

  String _formatScenarioTitle(OpticsScenario scenario) {
    switch (scenario) {
      case OpticsScenario.concaveMirror:
        return 'Concave Mirror Ray Diagram';
      case OpticsScenario.convexMirror:
        return 'Convex Mirror Ray Diagram';
      case OpticsScenario.convexLens:
        return 'Convex Lens Ray Diagram';
      case OpticsScenario.concaveLens:
        return 'Concave Lens Ray Diagram';
      case OpticsScenario.planeMirror:
        return 'Plane Mirror Ray Diagram';
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.payload.result.focalLengthCm.abs();
    final ho = widget.payload.result.objectHeightCm;
    final scenario = widget.payload.result.scenario;

    // Recalculate state dynamically as user scrubs _currentU
    final currentResult = _engine.solve(
      scenario: scenario,
      focalLengthCm: f,
      objectDistanceCm: _currentU,
      objectHeightCm: ho,
    );

    final minU = math.max(1.0, f * 0.2);
    final maxU = math.max(30.0, f * 3.5);

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
                const Icon(Icons.flare_rounded, color: Color(0xFF38BDF8), size: 18),
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
                    color: (currentResult.isReal ? const Color(0xFF0284C7) : const Color(0xFFF59E0B))
                        .withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: currentResult.isReal ? const Color(0xFF38BDF8) : const Color(0xFFFBBF24),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    currentResult.natureDescription,
                    style: TextStyle(
                      color: currentResult.isReal ? const Color(0xFF38BDF8) : const Color(0xFFFBBF24),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // CustomPainter Optics Viewport
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  painter: _OpticsRayPainter(
                    result: currentResult,
                  ),
                ),
              ),
            ),
          ),

          // Real-time Telemetry readouts
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTelemetry('Object (u)', '-${_currentU.toStringAsFixed(1)} cm'),
                _buildTelemetry(
                  'Image (v)',
                  currentResult.isAtInfinity ? '∞' : '${currentResult.imageDistanceCm.toStringAsFixed(1)} cm',
                ),
                _buildTelemetry('Focal (f)', '${f.toStringAsFixed(1)} cm'),
                _buildTelemetry(
                  'Mag (m)',
                  currentResult.isAtInfinity ? '∞' : '${currentResult.magnification.toStringAsFixed(2)}×',
                ),
              ],
            ),
          ),

          // Interactive Object Distance Scrubber
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, color: Color(0xFF94A3B8), size: 16),
                const SizedBox(width: 4),
                const Text(
                  'Object Distance (u):',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: const Color(0xFF38BDF8),
                      inactiveTrackColor: const Color(0xFF334155),
                      thumbColor: Colors.white,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      trackHeight: 3,
                    ),
                    child: Slider(
                      value: _currentU.clamp(minU, maxU),
                      min: minU,
                      max: maxU,
                      onChanged: (val) {
                        setState(() {
                          _currentU = val;
                        });
                      },
                    ),
                  ),
                ),
                Text(
                  '${_currentU.toStringAsFixed(1)} cm',
                  style: const TextStyle(
                    color: Color(0xFF38BDF8),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
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
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _OpticsRayPainter extends CustomPainter {
  _OpticsRayPainter({
    required this.result,
  });

  final OpticsRayResult result;

  @override
  void paint(Canvas canvas, Size size) {
    // Coordinate mapping: origin (optical center / pole) at center (size.width / 2, size.height / 2)
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Viewport bounds: optical plane extends [-40, 40] cm horizontally
    const domainSpan = 70.0;
    final scaleX = size.width / domainSpan;
    final scaleY = size.height / 20.0;

    double toScreenX(double optX) => cx + optX * scaleX;
    double toScreenY(double optY) => cy - optY * scaleY; // Invert y for canvas

    // 1. Draw Principal Axis
    final axisPaint = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, cy), Offset(size.width, cy), axisPaint);

    // 2. Mark Focus (F) and Center (2F) on Principal Axis
    final f = result.focalLengthCm.abs();
    final isLens = result.scenario == OpticsScenario.convexLens || result.scenario == OpticsScenario.concaveLens;

    final dotPaint = Paint()..color = const Color(0xFF38BDF8);
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    void drawTick(double optX, String label) {
      final sx = toScreenX(optX);
      if (sx < 0 || sx > size.width) return;
      canvas.drawCircle(Offset(sx, cy), 3, dotPaint);

      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(sx - textPainter.width / 2, cy + 6));
    }

    if (isLens) {
      drawTick(-f, 'F₁');
      drawTick(-2 * f, '2F₁');
      drawTick(f, 'F₂');
      drawTick(2 * f, '2F₂');
    } else {
      drawTick(result.focalLengthCm, 'F');
      drawTick(result.focalLengthCm * 2, 'C');
    }

    // 3. Draw Optical Element at Center (x = 0)
    final elementPaint = Paint()
      ..color = const Color(0xFF67E8F9).withValues(alpha: 0.8)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final mirrorShadePaint = Paint()
      ..color = const Color(0xFF64748B)
      ..strokeWidth = 1.0;

    if (isLens) {
      // Draw double convex or double concave lens
      final lensPath = Path();
      if (result.scenario == OpticsScenario.convexLens) {
        lensPath.moveTo(cx, cy - 70);
        lensPath.quadraticBezierTo(cx + 10, cy, cx, cy + 70);
        lensPath.quadraticBezierTo(cx - 10, cy, cx, cy - 70);
      } else {
        lensPath.moveTo(cx - 8, cy - 70);
        lensPath.lineTo(cx + 8, cy - 70);
        lensPath.quadraticBezierTo(cx + 2, cy, cx + 8, cy + 70);
        lensPath.lineTo(cx - 8, cy + 70);
        lensPath.quadraticBezierTo(cx - 2, cy, cx - 8, cy - 70);
      }
      canvas.drawPath(lensPath, elementPaint);
    } else {
      // Mirror curve
      final mirrorPath = Path();
      final isConcave = result.scenario == OpticsScenario.concaveMirror;
      final bulge = isConcave ? -12.0 : 12.0;
      mirrorPath.moveTo(cx, cy - 75);
      mirrorPath.quadraticBezierTo(cx + bulge, cy, cx, cy + 75);
      canvas.drawPath(mirrorPath, elementPaint);

      // Silvered hatch marks on back
      final hatchDir = isConcave ? 1 : -1;
      for (double y = cy - 65; y <= cy + 65; y += 12) {
        canvas.drawLine(Offset(cx, y), Offset(cx + 6 * hatchDir, y - 4), mirrorShadePaint);
      }
    }

    // 4. Draw Object Arrow (at u, ho)
    final objPaint = Paint()
      ..color = const Color(0xFF34D399) // Emerald
      ..strokeWidth = 3.0;

    final objBaseX = toScreenX(result.objectDistanceCm);
    final objTipY = toScreenY(result.objectHeightCm);

    canvas.drawLine(Offset(objBaseX, cy), Offset(objBaseX, objTipY), objPaint);
    // Arrow head
    canvas.drawLine(Offset(objBaseX - 4, objTipY + 6), Offset(objBaseX, objTipY), objPaint);
    canvas.drawLine(Offset(objBaseX + 4, objTipY + 6), Offset(objBaseX, objTipY), objPaint);

    // Label Object
    textPainter.text = const TextSpan(
      text: 'Object',
      style: TextStyle(color: Color(0xFF34D399), fontSize: 9.5, fontWeight: FontWeight.bold),
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(objBaseX - textPainter.width / 2, objTipY - 14));

    // 5. Draw Image Arrow (at v, hi)
    if (!result.isAtInfinity) {
      final imgPaint = Paint()
        ..color = result.isReal ? const Color(0xFFFB923C) : const Color(0xFFFBBF24)
        ..strokeWidth = 3.0;

      final imgBaseX = toScreenX(result.imageDistanceCm);
      final imgTipY = toScreenY(result.imageHeightCm);

      if (imgBaseX >= 0 && imgBaseX <= size.width) {
        canvas.drawLine(Offset(imgBaseX, cy), Offset(imgBaseX, imgTipY), imgPaint);

        // Arrow head pointing in correct direction
        final headDir = result.isErect ? 1 : -1;
        canvas.drawLine(
          Offset(imgBaseX - 4, imgTipY + 6 * headDir),
          Offset(imgBaseX, imgTipY),
          imgPaint,
        );
        canvas.drawLine(
          Offset(imgBaseX + 4, imgTipY + 6 * headDir),
          Offset(imgBaseX, imgTipY),
          imgPaint,
        );

        textPainter.text = TextSpan(
          text: result.isReal ? 'Image (Real)' : 'Image (Virt)',
          style: TextStyle(
            color: result.isReal ? const Color(0xFFFB923C) : const Color(0xFFFBBF24),
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
          ),
        );
        textPainter.layout();
        final textY = result.isErect ? (imgTipY - 14) : (imgTipY + 4);
        textPainter.paint(canvas, Offset(imgBaseX - textPainter.width / 2, textY));
      }
    }

    // 6. Draw Ray Paths
    final rayColors = [const Color(0xFF38BDF8), const Color(0xFFFCD34D), const Color(0xFFA78BFA)];

    for (int i = 0; i < result.rays.length; i++) {
      final ray = result.rays[i];
      final color = rayColors[i % rayColors.length];

      final rayPaint = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = 1.5;

      for (int j = 0; j < ray.points.length - 1; j++) {
        final pA = ray.points[j];
        final pB = ray.points[j + 1];
        canvas.drawLine(
          Offset(toScreenX(pA.x), toScreenY(pA.y)),
          Offset(toScreenX(pB.x), toScreenY(pB.y)),
          rayPaint,
        );
      }

      // Draw virtual dashed back-projection
      if (ray.virtualPoints.length >= 2) {
        final dashedPaint = Paint()
          ..color = color.withValues(alpha: 0.45)
          ..strokeWidth = 1.2;

        for (int j = 0; j < ray.virtualPoints.length - 1; j++) {
          final pA = ray.virtualPoints[j];
          final pB = ray.virtualPoints[j + 1];
          _drawDashedLine(
            canvas,
            Offset(toScreenX(pA.x), toScreenY(pA.y)),
            Offset(toScreenX(pB.x), toScreenY(pB.y)),
            dashedPaint,
          );
        }
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashLength = 4.0;
    const dashSpace = 3.0;
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    if (distance <= 0) return;

    final unitX = dx / distance;
    final unitY = dy / distance;

    double currentDist = 0.0;
    while (currentDist < distance) {
      final startX = p1.dx + unitX * currentDist;
      final startY = p1.dy + unitY * currentDist;
      final endDist = math.min(currentDist + dashLength, distance);
      final endX = p1.dx + unitX * endDist;
      final endY = p1.dy + unitY * endDist;

      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
      currentDist += dashLength + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _OpticsRayPainter oldDelegate) {
    return oldDelegate.result.objectDistanceCm != result.objectDistanceCm ||
        oldDelegate.result.imageDistanceCm != result.imageDistanceCm;
  }
}
