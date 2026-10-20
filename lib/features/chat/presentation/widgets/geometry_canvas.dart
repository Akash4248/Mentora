import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../application/geometry_engine.dart';
import '../../application/visual_resolver.dart';

/// Interactive, mathematically grounded canvas rendering geometric constructions
/// (triangles, circle tangents, transversals) with analytical ground-truth from [GeometryEngine].
class GeometryCanvas extends StatefulWidget {
  const GeometryCanvas({
    required this.payload,
    super.key,
  });

  final GeometryVisualPayload payload;

  @override
  State<GeometryCanvas> createState() => _GeometryCanvasState();
}

class _GeometryCanvasState extends State<GeometryCanvas> {
  late GeometryEngine _engine;
  late double _param;

  @override
  void initState() {
    super.initState();
    _engine = const GeometryEngine();
    final scenario = widget.payload.result.scenario;
    final inputs = widget.payload.intent.inputs;

    switch (scenario) {
      case GeometryScenario.rightTriangle:
      case GeometryScenario.triangleAngles:
        _param = (inputs['base'] ?? inputs['a'] ?? 4.0 as num).toDouble();
        break;
      case GeometryScenario.circleTangents:
        _param = (inputs['distance'] ?? inputs['d'] ?? 6.0 as num).toDouble();
        break;
      case GeometryScenario.parallelTransversal:
        _param = (inputs['angle'] ?? inputs['theta'] ?? 45.0 as num).toDouble();
        break;
    }
  }

  String _formatScenarioTitle(GeometryScenario scenario) {
    switch (scenario) {
      case GeometryScenario.rightTriangle:
        return 'Right Triangle & Pythagoras';
      case GeometryScenario.triangleAngles:
        return 'Triangle Geometry';
      case GeometryScenario.circleTangents:
        return 'Circle Tangents (External Point)';
      case GeometryScenario.parallelTransversal:
        return 'Parallel Lines & Transversal';
    }
  }

  String _paramLabel(GeometryScenario scenario) {
    switch (scenario) {
      case GeometryScenario.rightTriangle:
      case GeometryScenario.triangleAngles:
        return 'Base Length (a):';
      case GeometryScenario.circleTangents:
        return 'Distance to Point (d):';
      case GeometryScenario.parallelTransversal:
        return 'Transversal Angle (θ):';
    }
  }

  (double, double) _paramRange(GeometryScenario scenario, Map<String, dynamic> inputs) {
    switch (scenario) {
      case GeometryScenario.rightTriangle:
      case GeometryScenario.triangleAngles:
        return (1.0, 10.0);
      case GeometryScenario.circleTangents:
        final r = (inputs['radius'] ?? inputs['r'] ?? 3.0 as num).toDouble();
        return (r + 0.5, r * 3.5);
      case GeometryScenario.parallelTransversal:
        return (20.0, 80.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scenario = widget.payload.result.scenario;
    final inputs = widget.payload.intent.inputs;
    final (minP, maxP) = _paramRange(scenario, inputs);

    // Recalculate dynamic geometry with current _param
    final currentInputs = Map<String, dynamic>.from(inputs);
    switch (scenario) {
      case GeometryScenario.rightTriangle:
      case GeometryScenario.triangleAngles:
        currentInputs['base'] = _param;
        break;
      case GeometryScenario.circleTangents:
        currentInputs['distance'] = _param;
        break;
      case GeometryScenario.parallelTransversal:
        currentInputs['angle'] = _param;
        break;
    }

    final currentResult = _engine.solve(
      scenario: scenario,
      inputs: currentInputs,
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
                const Icon(Icons.straighten_rounded, color: Color(0xFF38BDF8), size: 18),
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
                    color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF38BDF8),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    _formatScenarioTitle(scenario),
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // CustomPainter Geometry Viewport
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SizedBox(
              height: 210,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  painter: _GeometryPainter(result: currentResult),
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
                  const Icon(Icons.verified_rounded, color: Color(0xFF34D399), size: 14),
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
              children: currentResult.measurements.entries.take(4).map((entry) {
                return _buildTelemetry(entry.key, entry.value);
              }).toList(),
            ),
          ),

          // Interactive Parameter Scrubber
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.tune_rounded, color: Color(0xFF94A3B8), size: 16),
                const SizedBox(width: 4),
                Text(
                  _paramLabel(scenario),
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
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
                      value: _param.clamp(minP, maxP),
                      min: minP,
                      max: maxP,
                      onChanged: (val) {
                        setState(() {
                          _param = val;
                        });
                      },
                    ),
                  ),
                ),
                Text(
                  scenario == GeometryScenario.parallelTransversal
                      ? '${_param.toStringAsFixed(0)}°'
                      : _param.toStringAsFixed(1),
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

/// CustomPainter rendering 2D geometry with procedural arcs, right-angle markers, and segments.
class _GeometryPainter extends CustomPainter {
  const _GeometryPainter({required this.result});

  final GeometryConstructionResult result;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFF0F172A);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final spanX = (result.maxX - result.minX).abs();
    final spanY = (result.maxY - result.minY).abs();
    if (spanX <= 0 || spanY <= 0) return;

    // Viewport padding
    const pad = 36.0;
    final availW = size.width - pad * 2;
    final availH = size.height - pad * 2;

    final scale = math.min(availW / spanX, availH / spanY);

    // Map math coords (x, y) with y-up to canvas coords (sx, sy) with y-down
    Offset toCanvas(double x, double y) {
      final sx = pad + (x - result.minX) * scale + (availW - spanX * scale) / 2;
      final sy = size.height - (pad + (y - result.minY) * scale + (availH - spanY * scale) / 2);
      return Offset(sx, sy);
    }

    // 1. Draw Circles
    for (final circle in result.circles) {
      final centerOffset = toCanvas(circle.center.x, circle.center.y);
      final rCanvas = circle.radius * scale;

      final circlePaint = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(centerOffset, rCanvas, circlePaint);
    }

    // 2. Draw Segments
    final segmentPaint = Paint()
      ..color = const Color(0xFF94A3B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final dashedPaint = Paint()
      ..color = const Color(0xFF64748B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    for (final seg in result.segments) {
      final p1 = toCanvas(seg.p1.x, seg.p1.y);
      final p2 = toCanvas(seg.p2.x, seg.p2.y);

      if (seg.highlightColorValue != null) {
        final hlPaint = Paint()
          ..color = Color(seg.highlightColorValue!)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(p1, p2, hlPaint);
      } else if (seg.isDashed) {
        _drawDashedLine(canvas, p1, p2, dashedPaint);
      } else {
        canvas.drawLine(p1, p2, segmentPaint);
      }

      // Draw segment label if present
      if (seg.label != null) {
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        _drawText(
          canvas,
          seg.label!,
          mid + const Offset(0, -12),
          const TextStyle(
            color: Color(0xFF38BDF8),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        );
      }
    }

    // 3. Draw Angles & Right-angle Glyphs
    for (final angle in result.angles) {
      final vertexOffset = toCanvas(angle.vertex.x, angle.vertex.y);

      if (angle.isRightAngle) {
        // Draw 90-degree square marker (8x8 px)
        final markerPaint = Paint()
          ..color = const Color(0xFFF59E0B)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6;

        const s = 10.0;
        final rightSquare = Path()
          ..moveTo(vertexOffset.dx + s, vertexOffset.dy)
          ..lineTo(vertexOffset.dx + s, vertexOffset.dy - s)
          ..lineTo(vertexOffset.dx, vertexOffset.dy - s);
        canvas.drawPath(rightSquare, markerPaint);
      } else {
        final arcPaint = Paint()
          ..color = const Color(0xFFF59E0B).withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

        final rect = Rect.fromCircle(center: vertexOffset, radius: 18.0);
        // Canvas angles increase clockwise, math angles increase counter-clockwise
        canvas.drawArc(rect, -angle.startAngleRad, -angle.sweepAngleRad, false, arcPaint);

        if (angle.label != null) {
          final midAngle = angle.startAngleRad + angle.sweepAngleRad / 2;
          final labelOffset = vertexOffset +
              Offset(28 * math.cos(midAngle), -28 * math.sin(midAngle));
          _drawText(
            canvas,
            angle.label!,
            labelOffset,
            const TextStyle(
              color: Color(0xFFF59E0B),
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
            ),
          );
        }
      }
    }

    // 4. Draw Vertex Points & Labels
    final vertexPaint = Paint()..color = const Color(0xFF38BDF8);
    for (final entry in result.points.entries) {
      final pt = entry.value;
      final offset = toCanvas(pt.x, pt.y);

      canvas.drawCircle(offset, 4.0, vertexPaint);
      if (pt.label != null) {
        _drawText(
          canvas,
          pt.label!,
          offset + const Offset(6, 6),
          const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        );
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashLength = 5.0;
    const dashSpace = 4.0;
    final distance = (p2 - p1).distance;
    final unit = (p2 - p1) / distance;

    double current = 0.0;
    while (current < distance) {
      final start = p1 + unit * current;
      final end = p1 + unit * math.min(current + dashLength, distance);
      canvas.drawLine(start, end, paint);
      current += dashLength + dashSpace;
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
  bool shouldRepaint(covariant _GeometryPainter oldDelegate) {
    return oldDelegate.result != result;
  }
}
