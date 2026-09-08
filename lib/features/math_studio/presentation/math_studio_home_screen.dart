import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/theme/idp_colors.dart';

import 'algebra_workspace_screen.dart';
import 'geometry_workspace_screen.dart';
import 'geometry_playground_screen.dart';
import 'functions_workspace_screen.dart';
import 'statistics_workspace_screen.dart';
import 'formula_playground_screen.dart';
import 'saved_explorations_screen.dart';
import 'exploration_catalog_screen.dart';

class MathStudioHomeScreen extends StatefulWidget {
  const MathStudioHomeScreen({super.key});

  @override
  State<MathStudioHomeScreen> createState() => _MathStudioHomeScreenState();
}

class _MathStudioHomeScreenState extends State<MathStudioHomeScreen> {
  double _amplitude = 1.5;
  double _frequency = 1.0;
  double _phaseShift = 0.0;

  @override
  Widget build(BuildContext context) {
    const primaryIndigo = Color(0xFF4F46E5);
    const darkBg = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.functions_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text('Math Studio', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: primaryIndigo,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth >= 700;
            final crossAxisExtent = isWide ? 260.0 : 180.0;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // HERO GRAPH PLOTTER PREVIEW CARD
                  Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [darkBg, Color(0xFF1E1B4B)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: primaryIndigo.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.show_chart_rounded, color: Color(0xFF818CF8), size: 22),
                                SizedBox(width: 8),
                                Text(
                                  'Live Function Grapher Engine',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF312E81),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFF6366F1)),
                              ),
                              child: const Text(
                                'Native 60FPS Canvas',
                                style: TextStyle(
                                  color: Color(0xFFA5B4FC),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Formula Display Tag
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'y = ${_amplitude.toStringAsFixed(1)} · sin(${_frequency.toStringAsFixed(1)}x + ${_phaseShift.toStringAsFixed(1)})',
                            style: const TextStyle(
                              color: Color(0xFF38BDF8),
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Interactive Graph Canvas
                        Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFF020617),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF334155)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: CustomPaint(
                              painter: _HeroGraphPainter(
                                amplitude: _amplitude,
                                frequency: _frequency,
                                phaseShift: _phaseShift,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        // Live Interactive Sliders
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Amplitude (a): ${_amplitude.toStringAsFixed(1)}',
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  ),
                                  SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    ),
                                    child: Slider(
                                      value: _amplitude,
                                      min: 0.5,
                                      max: 3.0,
                                      activeColor: const Color(0xFF38BDF8),
                                      onChanged: (val) => setState(() => _amplitude = val),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Frequency (b): ${_frequency.toStringAsFixed(1)}',
                                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                                  ),
                                  SliderTheme(
                                    data: SliderThemeData(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                    ),
                                    child: Slider(
                                      value: _frequency,
                                      min: 0.5,
                                      max: 3.0,
                                      activeColor: const Color(0xFF818CF8),
                                      onChanged: (val) => setState(() => _frequency = val),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    'Interactive Workspaces',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: IDPColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Select a visual studio to experiment with math equations, graphs & shapes.',
                    style: TextStyle(
                      color: IDPColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // WORKSPACE CARDS GRID
                  GridView.count(
                    crossAxisCount: (constraints.maxWidth / crossAxisExtent)
                        .floor()
                        .clamp(1, 4),
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: isWide ? 1.2 : 0.95,
                    children: [
                      _buildModernCard(
                        title: 'Functions Lab',
                        subtitle: 'Interactive 2D graph plotter & curves',
                        icon: Icons.show_chart_rounded,
                        gradient: const [Color(0xFF4F46E5), Color(0xFF6366F1)],
                        badge: 'Plots & Sliders',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FunctionLabScreen(),
                            ),
                          );
                        },
                      ),
                      _buildModernCard(
                        title: 'Algebra & Step Solver',
                        subtitle: 'Visual balance scale & step solver',
                        icon: Icons.calculate_rounded,
                        gradient: const [Color(0xFF0284C7), Color(0xFF38BDF8)],
                        badge: 'Step Visualizer',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AlgebraWorkspaceScreen(),
                            ),
                          );
                        },
                      ),
                      _buildModernCard(
                        title: 'Geometry Studio',
                        subtitle: 'Shapes, area, perimeter & angles',
                        icon: Icons.architecture_rounded,
                        gradient: const [Color(0xFF0D9488), Color(0xFF14B8A6)],
                        badge: 'Interactive Canvas',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GeometryWorkspaceScreen(),
                            ),
                          );
                        },
                      ),
                      _buildModernCard(
                        title: 'Statistics & Data',
                        subtitle: 'Histograms, boxplots & distributions',
                        icon: Icons.bar_chart_rounded,
                        gradient: const [Color(0xFFDC2626), Color(0xFFF87171)],
                        badge: 'Data Visualizer',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const StatisticsLabScreen(),
                            ),
                          );
                        },
                      ),
                      _buildModernCard(
                        title: 'Guided Explorations',
                        subtitle: 'Step-by-step math investigations',
                        icon: Icons.explore_rounded,
                        gradient: const [Color(0xFF1E3A8A), Color(0xFF3B82F6)],
                        badge: 'Lessons',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ExplorationCatalogScreen(),
                            ),
                          );
                        },
                      ),
                      _buildModernCard(
                        title: 'Formula Playground',
                        subtitle: 'Interactive variable expression solver',
                        icon: Icons.science_rounded,
                        gradient: const [Color(0xFF7C3AED), Color(0xFFA78BFA)],
                        badge: 'Variables',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FormulaPlaygroundScreen(),
                            ),
                          );
                        },
                      ),
                      _buildModernCard(
                        title: 'Multi-Shape Canvas',
                        subtitle: 'Drag, scale & rotate 2D geometries',
                        icon: Icons.dashboard_customize_rounded,
                        gradient: const [Color(0xFF059669), Color(0xFF34D399)],
                        badge: 'Freeform',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GeometryPlaygroundScreen(),
                            ),
                          );
                        },
                      ),
                      _buildModernCard(
                        title: 'Saved Workspaces',
                        subtitle: 'Open stored math investigations',
                        icon: Icons.folder_special_rounded,
                        gradient: const [Color(0xFF475569), Color(0xFF64748B)],
                        badge: 'Storage',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SavedExplorationsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildModernCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required String badge,
    required VoidCallback onTap,
  }) {
    final primaryColor = gradient.first;

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      shadowColor: primaryColor.withValues(alpha: 0.15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: primaryColor.withValues(alpha: 0.15)),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: gradient),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 22),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: primaryColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroGraphPainter extends CustomPainter {
  const _HeroGraphPainter({
    required this.amplitude,
    required this.frequency,
    required this.phaseShift,
  });

  final double amplitude;
  final double frequency;
  final double phaseShift;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B)
      ..strokeWidth = 1.0;

    final axisPaint = Paint()
      ..color = const Color(0xFF475569)
      ..strokeWidth = 1.5;

    final curvePaint = Paint()
      ..color = const Color(0xFF38BDF8)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          const Color(0xFF38BDF8).withValues(alpha: 0.35),
          const Color(0xFF38BDF8).withValues(alpha: 0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final centerY = size.height / 2;

    // Draw Gridlines
    for (double x = 0; x < size.width; x += 30) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += 25) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Draw Axis
    canvas.drawLine(Offset(0, centerY), Offset(size.width, centerY), axisPaint);

    // Draw Sine Curve
    final path = Path();
    final fillPath = Path();
    fillPath.moveTo(0, centerY);

    bool firstPoint = true;
    const scaleY = 22.0;

    for (double x = 0; x <= size.width; x += 2) {
      final normX = (x / size.width) * 4 * math.pi;
      final y = centerY - (amplitude * scaleY * math.sin(frequency * normX + phaseShift));

      if (firstPoint) {
        path.moveTo(x, y);
        fillPath.lineTo(x, y);
        firstPoint = false;
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, centerY);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, curvePaint);
  }

  @override
  bool shouldRepaint(covariant _HeroGraphPainter oldDelegate) {
    return oldDelegate.amplitude != amplitude ||
        oldDelegate.frequency != frequency ||
        oldDelegate.phaseShift != phaseShift;
  }
}
