import 'package:flutter/material.dart';

import '../../domain/sensor_sample.dart';

/// Real-time multi-axis sensor waveform graph drawn using Flutter CustomPainter.
class LiveSensorGraph extends StatelessWidget {
  const LiveSensorGraph({
    super.key,
    required this.samples,
    this.height = 140,
    this.maxWindowSamples = 100,
    this.yRange = 20.0,
  });

  final List<SensorSample> samples;
  final double height;
  final int maxWindowSamples;
  final double yRange;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Dark slate
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Live Waveform (m/s²)',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Row(
                children: const [
                  _AxisLegend(label: 'X', color: Color(0xFFEF4444)), // Red
                  SizedBox(width: 8),
                  _AxisLegend(label: 'Y', color: Color(0xFF10B981)), // Green
                  SizedBox(width: 8),
                  _AxisLegend(label: 'Z', color: Color(0xFF3B82F6)), // Blue
                  SizedBox(width: 8),
                  _AxisLegend(label: '|a|', color: Color(0xFFF59E0B)), // Amber
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ClipRect(
              child: CustomPaint(
                painter: _SensorWaveformPainter(
                  samples: samples,
                  maxWindowSamples: maxWindowSamples,
                  yRange: yRange,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AxisLegend extends StatelessWidget {
  const _AxisLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _SensorWaveformPainter extends CustomPainter {
  _SensorWaveformPainter({
    required this.samples,
    required this.maxWindowSamples,
    required this.yRange,
  });

  final List<SensorSample> samples;
  final int maxWindowSamples;
  final double yRange;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw center zero line
    final zeroY = size.height / 2;
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1.0;

    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), gridPaint);
    canvas.drawLine(Offset(0, zeroY - size.height * 0.25),
        Offset(size.width, zeroY - size.height * 0.25), gridPaint);
    canvas.drawLine(Offset(0, zeroY + size.height * 0.25),
        Offset(size.width, zeroY + size.height * 0.25), gridPaint);

    if (samples.length < 2) return;

    final window = samples.length > maxWindowSamples
        ? samples.sublist(samples.length - maxWindowSamples)
        : samples;

    final dx = size.width / (maxWindowSamples - 1);
    final startOffset = (maxWindowSamples - window.length) * dx;

    final pathX = Path();
    final pathY = Path();
    final pathZ = Path();
    final pathMag = Path();

    double mapY(double val) {
      final normalized = val / yRange; // [-1.0, 1.0]
      return zeroY - (normalized * (size.height / 2));
    }

    for (var i = 0; i < window.length; i++) {
      final s = window[i];
      final xPos = startOffset + i * dx;

      final yX = mapY(s.x).clamp(0.0, size.height);
      final yY = mapY(s.y).clamp(0.0, size.height);
      final yZ = mapY(s.z).clamp(0.0, size.height);
      final yMag = mapY(s.magnitude).clamp(0.0, size.height);

      if (i == 0) {
        pathX.moveTo(xPos, yX);
        pathY.moveTo(xPos, yY);
        pathZ.moveTo(xPos, yZ);
        pathMag.moveTo(xPos, yMag);
      } else {
        pathX.lineTo(xPos, yX);
        pathY.lineTo(xPos, yY);
        pathZ.lineTo(xPos, yZ);
        pathMag.lineTo(xPos, yMag);
      }
    }

    void drawPath(Path path, Color color) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, paint);
    }

    drawPath(pathX, const Color(0xFFEF4444));
    drawPath(pathY, const Color(0xFF10B981));
    drawPath(pathZ, const Color(0xFF3B82F6));
    drawPath(pathMag, const Color(0xFFF59E0B));
  }

  @override
  bool shouldRepaint(covariant _SensorWaveformPainter oldDelegate) {
    return oldDelegate.samples.length != samples.length ||
        (samples.isNotEmpty && oldDelegate.samples.lastOrNull != samples.lastOrNull);
  }
}
