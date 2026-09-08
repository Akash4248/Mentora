import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

import '../../../../core/theme/idp_colors.dart';
import 'math_lab_toolbar.dart';

class MathStudio3DCanvas extends StatefulWidget {
  final MathLabTool activeTool;
  final double amplitude;
  final double frequencyX;
  final double frequencyY;
  final String functionType;
  final String geometryShape;
  final double geometryRadius;
  final double geometryHeight;
  final List<vector.Vector3> points;
  final List<vector.Vector3> vectors;
  final int? selectedIndex;
  final ValueChanged<vector.Vector3>? onTapCanvas;

  const MathStudio3DCanvas({
    super.key,
    this.activeTool = MathLabTool.surface3D,
    this.amplitude = 1.5,
    this.frequencyX = 1.0,
    this.frequencyY = 1.0,
    this.functionType = 'sine_wave',
    this.geometryShape = 'sphere',
    this.geometryRadius = 1.5,
    this.geometryHeight = 2.0,
    this.points = const [],
    this.vectors = const [],
    this.selectedIndex,
    this.onTapCanvas,
  });

  @override
  State<MathStudio3DCanvas> createState() => _MathStudio3DCanvasState();
}

class _MathStudio3DCanvasState extends State<MathStudio3DCanvas>
    with SingleTickerProviderStateMixin {
  double _azimuth = 0.8;
  double _elevation = 0.5;
  double _zoom = 1.0;
  bool _isAutoRotating = false;
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..addListener(() {
        if (_isAutoRotating) {
          setState(() {
            _azimuth += 0.015;
          });
        }
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleAutoRotate() {
    setState(() {
      _isAutoRotating = !_isAutoRotating;
      if (_isAutoRotating) {
        _animController.repeat();
      } else {
        _animController.stop();
      }
    });
  }

  void _handleTap(TapUpDetails details, Size size) {
    if (widget.onTapCanvas == null) return;

    final center = Offset(size.width / 2, size.height / 2);
    final scale = math.min(size.width, size.height) * 0.18 * _zoom;
    final dx = (details.localPosition.dx - center.dx) / scale;
    final dy = (center.dy - details.localPosition.dy) / scale;

    // Convert 2D tap coordinate to 3D world coordinate using inverse rotation
    final cosA = math.cos(-_azimuth);
    final sinA = math.sin(-_azimuth);
    final sinE = math.sin(_elevation);
    final cosE = math.cos(_elevation);

    final x3d = (dx * cosA - dy * sinA * sinE).clamp(-3.0, 3.0);
    final y3d = (-dx * sinA - dy * cosA * sinE).clamp(-3.0, 3.0);
    final z3d = (dy * cosE).clamp(-2.5, 2.5);

    widget.onTapCanvas!(vector.Vector3(x3d, y3d, z3d));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);

            return Stack(
              children: [
                // 3D INTERACTIVE CANVAS VIEWPORT WITH GESTURE & TAP DETECTOR
                GestureDetector(
                  onTapUp: (details) => _handleTap(details, size),
                  onScaleUpdate: (details) {
                    setState(() {
                      if (details.scale != 1.0) {
                        _zoom = (_zoom * details.scale).clamp(0.5, 2.5);
                      } else {
                        _azimuth += details.focalPointDelta.dx * 0.008;
                        _elevation = (_elevation - details.focalPointDelta.dy * 0.008)
                            .clamp(-math.pi / 2 + 0.1, math.pi / 2 - 0.1);
                      }
                    });
                  },
                  child: CustomPaint(
                    painter: _Math3DPainter(
                      activeTool: widget.activeTool,
                      azimuth: _azimuth,
                      elevation: _elevation,
                      zoom: _zoom,
                      amplitude: widget.amplitude,
                      frequencyX: widget.frequencyX,
                      frequencyY: widget.frequencyY,
                      functionType: widget.functionType,
                      geometryShape: widget.geometryShape,
                      geometryRadius: widget.geometryRadius,
                      geometryHeight: widget.geometryHeight,
                      points: widget.points,
                      vectors: widget.vectors,
                      selectedIndex: widget.selectedIndex,
                    ),
                    size: Size.infinite,
                  ),
                ),

                // CANVAS OVERLAY BADGE
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          widget.activeTool == MathLabTool.addPoint
                              ? Icons.adjust_rounded
                              : widget.activeTool == MathLabTool.addLine
                                  ? Icons.timeline_rounded
                                  : widget.activeTool == MathLabTool.geometry
                                      ? Icons.category_rounded
                                      : Icons.view_in_ar_rounded,
                          color: const Color(0xFF38BDF8),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.activeTool == MathLabTool.addPoint
                              ? 'Tap to Place 3D Point'
                              : widget.activeTool == MathLabTool.addLine
                                  ? 'Tap to Draw 3D Vector'
                                  : widget.activeTool == MathLabTool.geometry
                                      ? '3D ${widget.geometryShape.toUpperCase()} Solid'
                                      : '3D Orbit (Drag/Pinch)',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.95),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // CAMERA CONTROLS
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Row(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'auto_rotate_btn',
                        backgroundColor: _isAutoRotating
                            ? const Color(0xFF10B981)
                            : Colors.white.withValues(alpha: 0.15),
                        foregroundColor: Colors.white,
                        onPressed: _toggleAutoRotate,
                        tooltip: 'Auto Rotate 360°',
                        child: const Icon(Icons.sync_rounded),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton.small(
                        heroTag: 'reset_view_btn',
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        foregroundColor: Colors.white,
                        onPressed: () {
                          setState(() {
                            _azimuth = 0.8;
                            _elevation = 0.5;
                            _zoom = 1.0;
                          });
                        },
                        tooltip: 'Reset Camera',
                        child: const Icon(Icons.center_focus_strong_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Math3DPainter extends CustomPainter {
  final MathLabTool activeTool;
  final double azimuth;
  final double elevation;
  final double zoom;
  final double amplitude;
  final double frequencyX;
  final double frequencyY;
  final String functionType;
  final String geometryShape;
  final double geometryRadius;
  final double geometryHeight;
  final List<vector.Vector3> points;
  final List<vector.Vector3> vectors;
  final int? selectedIndex;

  _Math3DPainter({
    required this.activeTool,
    required this.azimuth,
    required this.elevation,
    required this.zoom,
    required this.amplitude,
    required this.frequencyX,
    required this.frequencyY,
    required this.functionType,
    required this.geometryShape,
    required this.geometryRadius,
    required this.geometryHeight,
    required this.points,
    required this.vectors,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final scale = math.min(size.width, size.height) * 0.18 * zoom;

    // Build 3D Transformation Matrix
    final transform = vector.Matrix4.identity()
      ..rotateY(azimuth)
      ..rotateX(elevation);

    Offset project(double x, double y, double z) {
      final p = transform.transform3(vector.Vector3(x, y, z));
      return Offset(center.dx + p.x * scale, center.dy - p.z * scale);
    }

    // Draw Grid & Axis Lines
    final origin = project(0, 0, 0);
    final xAxis = project(3, 0, 0);
    final yAxis = project(0, 3, 0);
    final zAxis = project(0, 0, 3);

    final axisPaint = Paint()
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    // X-Axis (Red), Y-Axis (Green), Z-Axis (Blue)
    axisPaint.color = Colors.redAccent.withValues(alpha: 0.85);
    canvas.drawLine(origin, xAxis, axisPaint);
    axisPaint.color = Colors.greenAccent.withValues(alpha: 0.85);
    canvas.drawLine(origin, yAxis, axisPaint);
    axisPaint.color = const Color(0xFF38BDF8).withValues(alpha: 0.85);
    canvas.drawLine(origin, zAxis, axisPaint);

    // DRAW 3D SURFACE OR 3D GEOMETRY SOLID
    if (activeTool == MathLabTool.geometry) {
      _drawGeometrySolid(canvas, project);
    } else {
      _drawSurfaceMesh(canvas, project);
    }

    // DRAW USER CREATED 3D VECTORS
    for (int i = 0; i < vectors.length; i++) {
      final vec = vectors[i];
      final target = project(vec.x, vec.y, vec.z);
      final isSel = selectedIndex == i;

      final vecPaint = Paint()
        ..color = isSel ? const Color(0xFFF59E0B) : const Color(0xFF10B981)
        ..strokeWidth = isSel ? 3.5 : 2.5
        ..style = PaintingStyle.stroke;

      canvas.drawLine(origin, target, vecPaint);

      // Draw Arrow Head Pin
      canvas.drawCircle(
        target,
        isSel ? 7.0 : 5.0,
        Paint()..color = isSel ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
      );

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: 'v${i + 1} (${vec.x.toStringAsFixed(1)}, ${vec.y.toStringAsFixed(1)}, ${vec.z.toStringAsFixed(1)})',
          style: TextStyle(
            color: isSel ? const Color(0xFFF59E0B) : const Color(0xFF34D399),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black.withValues(alpha: 0.7),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, target + const Offset(8, -12));
    }

    // DRAW USER CREATED 3D POINTS
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      final pPos = project(pt.x, pt.y, pt.z);
      final isSel = selectedIndex == i;

      // Glow Ring
      canvas.drawCircle(
        pPos,
        isSel ? 10.0 : 7.0,
        Paint()..color = isSel ? const Color(0xFFEC4899) : const Color(0xFF8B5CF6).withValues(alpha: 0.6),
      );
      canvas.drawCircle(
        pPos,
        isSel ? 5.0 : 4.0,
        Paint()..color = Colors.white,
      );

      // Label
      final tp = TextPainter(
        text: TextSpan(
          text: 'P${i + 1} (${pt.x.toStringAsFixed(1)}, ${pt.y.toStringAsFixed(1)}, ${pt.z.toStringAsFixed(1)})',
          style: TextStyle(
            color: isSel ? const Color(0xFFEC4899) : const Color(0xFFC4B5FD),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            backgroundColor: Colors.black.withValues(alpha: 0.7),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pPos + const Offset(8, -12));
    }
  }

  void _drawSurfaceMesh(Canvas canvas, Offset Function(double x, double y, double z) project) {
    const steps = 16;
    const stepSize = 5.0 / steps;

    double evalSurface(double x, double y) {
      if (functionType == 'saddle') {
        return amplitude * (x * x - y * y) * 0.2;
      } else if (functionType == 'paraboloid') {
        return amplitude * (x * x + y * y) * 0.15;
      } else {
        return amplitude * math.sin(frequencyX * x) * math.cos(frequencyY * y);
      }
    }

    final meshPaint = Paint()
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < steps; i++) {
      final x1 = -2.5 + i * stepSize;
      final x2 = x1 + stepSize;

      for (int j = 0; j < steps; j++) {
        final y1 = -2.5 + j * stepSize;
        final y2 = y1 + stepSize;

        final z11 = evalSurface(x1, y1);
        final z12 = evalSurface(x1, y2);
        final z21 = evalSurface(x2, y1);
        final z22 = evalSurface(x2, y2);

        final p11 = project(x1, y1, z11);
        final p12 = project(x1, y2, z12);
        final p21 = project(x2, y1, z21);
        final p22 = project(x2, y2, z22);

        final path = Path()
          ..moveTo(p11.dx, p11.dy)
          ..lineTo(p12.dx, p12.dy)
          ..lineTo(p22.dx, p22.dy)
          ..lineTo(p21.dx, p21.dy)
          ..close();

        final avgZ = (z11 + z12 + z21 + z22) / 4.0;
        final norm = ((avgZ + amplitude) / (2 * amplitude + 0.1)).clamp(0.0, 1.0);

        fillPaint.color = Color.lerp(
          const Color(0xFF4F46E5).withValues(alpha: 0.3),
          const Color(0xFF06B6D4).withValues(alpha: 0.5),
          norm,
        )!;

        canvas.drawPath(path, fillPaint);
        meshPaint.color = Colors.white.withValues(alpha: 0.12 + norm * 0.18);
        canvas.drawPath(path, meshPaint);
      }
    }
  }

  void _drawGeometrySolid(Canvas canvas, Offset Function(double x, double y, double z) project) {
    final r = geometryRadius;
    final h = geometryHeight;
    final wirePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = const Color(0xFF4F46E5).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    if (geometryShape == 'cube') {
      final half = r;
      final corners = [
        project(-half, -half, -half),
        project(half, -half, -half),
        project(half, half, -half),
        project(-half, half, -half),
        project(-half, -half, half),
        project(half, -half, half),
        project(half, half, half),
        project(-half, half, half),
      ];

      final edges = [
        [0, 1], [1, 2], [2, 3], [3, 0],
        [4, 5], [5, 6], [6, 7], [7, 4],
        [0, 4], [1, 5], [2, 6], [3, 7]
      ];

      for (final e in edges) {
        canvas.drawLine(corners[e[0]], corners[e[1]], wirePaint);
      }
    } else if (geometryShape == 'cylinder') {
      const segs = 16;
      final bottom = <Offset>[];
      final top = <Offset>[];

      for (int i = 0; i < segs; i++) {
        final angle = (i / segs) * math.pi * 2;
        final x = math.cos(angle) * r;
        final y = math.sin(angle) * r;
        bottom.add(project(x, y, -h / 2));
        top.add(project(x, y, h / 2));
      }

      for (int i = 0; i < segs; i++) {
        final next = (i + 1) % segs;
        canvas.drawLine(bottom[i], bottom[next], wirePaint);
        canvas.drawLine(top[i], top[next], wirePaint);
        if (i % 4 == 0) {
          canvas.drawLine(bottom[i], top[i], wirePaint);
        }
      }
    } else if (geometryShape == 'cone' || geometryShape == 'pyramid') {
      const segs = 12;
      final base = <Offset>[];
      final apex = project(0, 0, h / 2);

      for (int i = 0; i < segs; i++) {
        final angle = (i / segs) * math.pi * 2;
        final x = math.cos(angle) * r;
        final y = math.sin(angle) * r;
        base.add(project(x, y, -h / 2));
      }

      for (int i = 0; i < segs; i++) {
        final next = (i + 1) % segs;
        canvas.drawLine(base[i], base[next], wirePaint);
        if (i % 3 == 0) {
          canvas.drawLine(base[i], apex, wirePaint);
        }
      }
    } else {
      // Sphere or Torus wireframe circles
      const rings = 10;
      const ptsPerRing = 16;

      for (int i = 0; i < rings; i++) {
        final phi = (i / rings) * math.pi;
        final ringPts = <Offset>[];
        for (int j = 0; j < ptsPerRing; j++) {
          final theta = (j / ptsPerRing) * math.pi * 2;
          final x = r * math.sin(phi) * math.cos(theta);
          final y = r * math.sin(phi) * math.sin(theta);
          final z = r * math.cos(phi);
          ringPts.add(project(x, y, z));
        }
        for (int k = 0; k < ptsPerRing; k++) {
          final next = (k + 1) % ptsPerRing;
          canvas.drawLine(ringPts[k], ringPts[next], wirePaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Math3DPainter oldDelegate) {
    return oldDelegate.azimuth != azimuth ||
        oldDelegate.elevation != elevation ||
        oldDelegate.zoom != zoom ||
        oldDelegate.amplitude != amplitude ||
        oldDelegate.frequencyX != frequencyX ||
        oldDelegate.frequencyY != frequencyY ||
        oldDelegate.functionType != functionType ||
        oldDelegate.geometryShape != geometryShape ||
        oldDelegate.geometryRadius != geometryRadius ||
        oldDelegate.geometryHeight != geometryHeight ||
        oldDelegate.points != points ||
        oldDelegate.vectors != vectors ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.activeTool != activeTool;
  }
}
