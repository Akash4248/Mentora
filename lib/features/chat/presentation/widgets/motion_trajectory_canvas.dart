import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../application/kinematics_engine.dart';
import '../../application/visual_resolver.dart';

/// Interactive, mathematically grounded canvas rendering a validated physical trajectory.
///
/// Driven entirely by analytical solutions from [KinematicsEngine]. Never relies on
/// model-generated coordinates. Includes an interactive time scrubber.
class MotionTrajectoryCanvas extends StatefulWidget {
  const MotionTrajectoryCanvas({
    required this.payload,
    super.key,
  });

  final TrajectoryVisualPayload payload;

  @override
  State<MotionTrajectoryCanvas> createState() => _MotionTrajectoryCanvasState();
}

class _MotionTrajectoryCanvasState extends State<MotionTrajectoryCanvas> {
  late double _currentTime;

  @override
  void initState() {
    super.initState();
    // Default scrubber position to apex if requested, else t = 0
    final focusKind = widget.payload.intent.focus?['kind'];
    if (focusKind == 'apex') {
      _currentTime = widget.payload.trajectory.timeToApexSeconds;
    } else {
      _currentTime = 0.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trajectory = widget.payload.trajectory;
    final maxTime = math.max(0.01, trajectory.totalFlightTimeSeconds);
    final currentPoint = trajectory.sampleAtTime(_currentTime) ?? trajectory.samples.first;

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
                const Icon(Icons.show_chart_rounded, color: Color(0xFF38BDF8), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.payload.intent.title ?? 'Physical Motion Trajectory',
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
                    border: Border.all(color: const Color(0xFF38BDF8), width: 0.8),
                  ),
                  child: Text(
                    'Apex: ${trajectory.peakHeightMeters}m @ ${trajectory.timeToApexSeconds}s',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // CustomPainter trajectory viewport
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CustomPaint(
                  painter: _TrajectoryPainter(
                    trajectory: trajectory,
                    currentTime: _currentTime,
                    currentPoint: currentPoint,
                  ),
                ),
              ),
            ),
          ),

          // Real-time telemetry readouts
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildTelemetry('Time (t)', '${_currentTime.toStringAsFixed(2)} s'),
                _buildTelemetry('Height (y)', '${currentPoint.yPositionMeters.toStringAsFixed(2)} m'),
                _buildTelemetry('Speed (v)', '${currentPoint.speedMps.toStringAsFixed(2)} m/s'),
                if (trajectory.netForceAtPeakNewtons != null)
                  _buildTelemetry('Net Force', '${trajectory.netForceAtPeakNewtons} N'),
              ],
            ),
          ),

          // Interactive time scrubber slider
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.timer_outlined, color: Color(0xFF94A3B8), size: 16),
                const SizedBox(width: 4),
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
                      value: _currentTime.clamp(0.0, maxTime),
                      min: 0.0,
                      max: maxTime,
                      onChanged: (val) {
                        setState(() {
                          _currentTime = val;
                        });
                      },
                    ),
                  ),
                ),
                Text(
                  '${maxTime.toStringAsFixed(1)}s',
                  style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
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
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w500),
        ),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

class _TrajectoryPainter extends CustomPainter {
  _TrajectoryPainter({
    required this.trajectory,
    required this.currentTime,
    required this.currentPoint,
  });

  final KinematicsTrajectoryResult trajectory;
  final double currentTime;
  final KinematicsSamplePoint currentPoint;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Background & ground
    final groundY = h - 20;
    final groundPaint = Paint()
      ..color = const Color(0xFF334155)
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, groundY), Offset(w, groundY), groundPaint);

    final samples = trajectory.samples;
    if (samples.length < 2) return;

    final maxH = math.max(1.0, trajectory.peakHeightMeters * 1.25);
    final is2D = trajectory.rangeMeters > 0;
    final maxDist = is2D ? math.max(1.0, trajectory.rangeMeters * 1.1) : w;

    // Draw trajectory curve
    final path = Path();
    for (var i = 0; i < samples.length; i++) {
      final s = samples[i];
      final px = is2D ? (20 + (s.xPositionMeters / maxDist) * (w - 40)) : (w / 2);
      final py = groundY - ((s.yPositionMeters / maxH) * (groundY - 20));

      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
    }

    final curvePaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, curvePaint);

    // Apex highlight
    final apexY = groundY - ((trajectory.peakHeightMeters / maxH) * (groundY - 20));
    final apexX = is2D ? (20 + ((trajectory.rangeMeters / 2) / maxDist) * (w - 40)) : (w / 2);
    final apexPaint = Paint()..color = const Color(0xFFF59E0B);
    canvas.drawCircle(Offset(apexX, apexY), 4, apexPaint);

    // Current ball position
    final ballX = is2D ? (20 + (currentPoint.xPositionMeters / maxDist) * (w - 40)) : (w / 2);
    final ballY = groundY - ((currentPoint.yPositionMeters / maxH) * (groundY - 20));

    final ballPaint = Paint()..color = const Color(0xFFEC4899);
    canvas.drawCircle(Offset(ballX, ballY), 6, ballPaint);

    // Velocity arrow
    if (currentPoint.speedMps > 0.1) {
      final vyNorm = (currentPoint.yVelocityMps / math.max(0.1, currentPoint.speedMps)) * 20;
      final arrowEnd = Offset(ballX, ballY - vyNorm);
      final arrowPaint = Paint()
        ..color = const Color(0xFFA855F7)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(ballX, ballY), arrowEnd, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrajectoryPainter oldDelegate) =>
      oldDelegate.currentTime != currentTime || oldDelegate.trajectory != trajectory;
}
