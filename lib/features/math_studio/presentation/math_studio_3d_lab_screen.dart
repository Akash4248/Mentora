import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vector;

import '../../../core/theme/idp_colors.dart';
import '../../../core/theme/idp_typography.dart';
import 'widgets/math_studio_3d_canvas.dart';
import 'widgets/math_lab_toolbar.dart';
import 'widgets/geogebra_embedded_view.dart';
import 'widgets/algebra_balance_workspace.dart';
import 'widgets/socratic_math_solver_sheet.dart';
import 'scientific_calculator_screen.dart';

class MathStudio3DLabScreen extends StatefulWidget {
  const MathStudio3DLabScreen({super.key});

  @override
  State<MathStudio3DLabScreen> createState() => _MathStudio3DLabScreenState();
}

class _MathStudio3DLabScreenState extends State<MathStudio3DLabScreen> {
  MathLabTool _activeTool = MathLabTool.surface3D;
  double _amplitude = 1.5;
  double _frequencyX = 1.0;
  double _frequencyY = 1.0;
  String _functionType = 'sine_wave';
  bool _useGeoGebra = false;

  // Geometry State
  String _geometryShape = 'sphere';
  double _geometryRadius = 1.5;
  double _geometryHeight = 2.0;

  // Points & Vectors State
  final List<vector.Vector3> _points = [
    vector.Vector3(1.0, 1.0, 1.5),
    vector.Vector3(-1.2, 0.8, -0.5),
  ];
  final List<vector.Vector3> _vectors = [
    vector.Vector3(1.5, 2.0, 1.0),
    vector.Vector3(-1.0, 1.5, 2.0),
  ];
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    // Enforce default landscape orientation for mobile screens in 3D Math Lab
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // Restore all device orientations on screen exit
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  void _openSocraticSolver() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SocraticMathSolverSheet(),
    );
  }

  void _openScientificCalculator() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScientificCalculatorScreen()),
    );
  }

  void _handleCanvasTap(vector.Vector3 tapPt) {
    setState(() {
      if (_activeTool == MathLabTool.addPoint) {
        _points.add(tapPt);
        _selectedIndex = _points.length - 1;
      } else if (_activeTool == MathLabTool.addLine) {
        _vectors.add(tapPt);
        _selectedIndex = _vectors.length - 1;
      } else if (_activeTool == MathLabTool.select) {
        // Find nearest point or vector
        double minDist = 999.0;
        int? closestIndex;

        for (int i = 0; i < _points.length; i++) {
          final d = (points_dist(_points[i], tapPt));
          if (d < minDist && d < 1.2) {
            minDist = d;
            closestIndex = i;
          }
        }
        _selectedIndex = closestIndex;
      }
    });
  }

  double points_dist(vector.Vector3 a, vector.Vector3 b) {
    return (a - b).length;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.view_in_ar_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Advanced 3D Math Lab Studio',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate_rounded, color: Colors.white),
            tooltip: 'Scientific Calculator',
            onPressed: _openScientificCalculator,
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
            tooltip: 'Socratic Step Solver',
            onPressed: _openSocraticSolver,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // FLOATING TOOLBAR WITH HORIZONTAL SCROLLING
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: MathLabToolbar(
                activeTool: _activeTool,
                onToolSelected: (tool) {
                  setState(() {
                    _activeTool = tool;
                    _selectedIndex = null;
                    if (tool == MathLabTool.socraticSolver) {
                      _openSocraticSolver();
                    }
                  });
                },
              ),
            ),

            // MAIN WORKSPACE CONTENT
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 550;

                    if (_activeTool == MathLabTool.balanceScale) {
                      return const AlgebraBalanceWorkspace();
                    }

                    if (_useGeoGebra) {
                      return const GeogebraEmbeddedView(initialApp: '3d');
                    }

                    final canvasWidget = MathStudio3DCanvas(
                      activeTool: _activeTool,
                      amplitude: _amplitude,
                      frequencyX: _frequencyX,
                      frequencyY: _frequencyY,
                      functionType: _functionType,
                      geometryShape: _geometryShape,
                      geometryRadius: _geometryRadius,
                      geometryHeight: _geometryHeight,
                      points: _points,
                      vectors: _vectors,
                      selectedIndex: _selectedIndex,
                      onTapCanvas: _handleCanvasTap,
                    );

                    if (isWide) {
                      // LANDSCAPE / TABLET SIDE-BY-SIDE DUAL-PANE LAYOUT
                      return Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: canvasWidget,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 4,
                            child: _buildControlPanel(isDark),
                          ),
                        ],
                      );
                    } else {
                      // PORTRAIT SINGLE-COLUMN LAYOUT
                      return Column(
                        children: [
                          Expanded(
                            flex: 5,
                            child: canvasWidget,
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            flex: 4,
                            child: _buildControlPanel(isDark),
                          ),
                        ],
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _activeTool == MathLabTool.geometry
                      ? '3D Geometry Solid Controls'
                      : _activeTool == MathLabTool.addPoint
                          ? '3D Points Inspector'
                          : _activeTool == MathLabTool.addLine
                              ? '3D Vectors Inspector'
                              : _activeTool == MathLabTool.select
                                  ? 'Selected 3D Object Inspector'
                                  : '3D Surface Controls',
                  style: IDPTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
                ),
                Switch(
                  value: _useGeoGebra,
                  activeColor: const Color(0xFF4F46E5),
                  onChanged: (val) => setState(() => _useGeoGebra = val),
                ),
              ],
            ),
            Text(
              _useGeoGebra ? 'GeoGebra 3D Engine Active' : 'Mentora 60FPS Interactive Engine',
              style: IDPTypography.caption.copyWith(color: IDPColors.onSurfaceVariant),
            ),
            const Divider(height: 16),

            // TOOL SPECIFIC CONTROL PANELS
            if (_activeTool == MathLabTool.geometry) ...[
              const Text('Select 3D Solid:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('Sphere'),
                    selected: _geometryShape == 'sphere',
                    onSelected: (_) => setState(() => _geometryShape = 'sphere'),
                  ),
                  ChoiceChip(
                    label: const Text('Cube'),
                    selected: _geometryShape == 'cube',
                    onSelected: (_) => setState(() => _geometryShape = 'cube'),
                  ),
                  ChoiceChip(
                    label: const Text('Cylinder'),
                    selected: _geometryShape == 'cylinder',
                    onSelected: (_) => setState(() => _geometryShape = 'cylinder'),
                  ),
                  ChoiceChip(
                    label: const Text('Cone'),
                    selected: _geometryShape == 'cone',
                    onSelected: (_) => setState(() => _geometryShape = 'cone'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Radius / Scale (r): ${_geometryRadius.toStringAsFixed(2)}'),
              Slider(
                value: _geometryRadius,
                min: 0.5,
                max: 2.5,
                activeColor: const Color(0xFF38BDF8),
                onChanged: (val) => setState(() => _geometryRadius = val),
              ),
              if (_geometryShape == 'cylinder' || _geometryShape == 'cone') ...[
                Text('Height (h): ${_geometryHeight.toStringAsFixed(2)}'),
                Slider(
                  value: _geometryHeight,
                  min: 0.5,
                  max: 3.0,
                  activeColor: const Color(0xFF10B981),
                  onChanged: (val) => setState(() => _geometryHeight = val),
                ),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _geometryShape == 'sphere'
                      ? 'Volume V = 4/3 π r³ = ${(4 / 3 * math.pi * math.pow(_geometryRadius, 3)).toStringAsFixed(2)}\nSurface Area A = 4 π r² = ${(4 * math.pi * math.pow(_geometryRadius, 2)).toStringAsFixed(2)}'
                      : _geometryShape == 'cube'
                          ? 'Volume V = a³ = ${math.pow(_geometryRadius * 2, 3).toStringAsFixed(2)}\nSurface Area A = 6 a² = ${(6 * math.pow(_geometryRadius * 2, 2)).toStringAsFixed(2)}'
                          : 'Volume V = π r² h = ${(math.pi * math.pow(_geometryRadius, 2) * _geometryHeight).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF4F46E5)),
                ),
              ),
            ] else if (_activeTool == MathLabTool.addPoint) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Points Added (${_points.length}):', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _points.clear();
                      _selectedIndex = null;
                    }),
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                    label: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                ],
              ),
              const Text('Tap on 3D canvas viewport to place coordinates.', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              const SizedBox(height: 8),
              Column(
                children: List.generate(_points.length, (i) {
                  final pt = _points[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(0xFF8B5CF6),
                      child: Text('P${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    title: Text('(${pt.x.toStringAsFixed(2)}, ${pt.y.toStringAsFixed(2)}, ${pt.z.toStringAsFixed(2)})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text('Distance to origin: ${pt.length.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                      onPressed: () => setState(() => _points.removeAt(i)),
                    ),
                  );
                }),
              ),
            ] else if (_activeTool == MathLabTool.addLine) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('3D Vectors (${_vectors.length}):', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _vectors.clear();
                      _selectedIndex = null;
                    }),
                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                    label: const Text('Clear All', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                ],
              ),
              const Text('Tap on 3D canvas to draw vector arrow from origin.', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              const SizedBox(height: 8),
              Column(
                children: List.generate(_vectors.length, (i) {
                  final vec = _vectors[i];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(0xFF10B981),
                      child: Text('v${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    title: Text('v${i + 1} = ${vec.x.toStringAsFixed(1)}î + ${vec.y.toStringAsFixed(1)}ĵ + ${vec.z.toStringAsFixed(1)}k̂', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    subtitle: Text('Magnitude ||v|| = ${vec.length.toStringAsFixed(2)}', style: const TextStyle(fontSize: 11)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                      onPressed: () => setState(() => _vectors.removeAt(i)),
                    ),
                  );
                }),
              ),
              if (_vectors.length >= 2) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Dot Product v1 · v2 = ${(_vectors[0].dot(_vectors[1])).toStringAsFixed(2)}\nCross Product v1 × v2 = (${(_vectors[0].cross(_vectors[1])).x.toStringAsFixed(1)}, ${(_vectors[0].cross(_vectors[1])).y.toStringAsFixed(1)}, ${(_vectors[0].cross(_vectors[1])).z.toStringAsFixed(1)})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF047857)),
                  ),
                ),
              ],
            ] else ...[
              // DEFAULT SURFACE CONTROLS
              const Text('Surface Function z = f(x,y):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ChoiceChip(
                    label: const Text('Sine Wave'),
                    selected: _functionType == 'sine_wave',
                    onSelected: (sel) => setState(() => _functionType = 'sine_wave'),
                  ),
                  ChoiceChip(
                    label: const Text('Saddle Surface'),
                    selected: _functionType == 'saddle',
                    onSelected: (sel) => setState(() => _functionType = 'saddle'),
                  ),
                  ChoiceChip(
                    label: const Text('Paraboloid'),
                    selected: _functionType == 'paraboloid',
                    onSelected: (sel) => setState(() => _functionType = 'paraboloid'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text('Amplitude (A): ${_amplitude.toStringAsFixed(2)}'),
              Slider(
                value: _amplitude,
                min: 0.5,
                max: 3.0,
                activeColor: const Color(0xFF4F46E5),
                onChanged: (val) => setState(() => _amplitude = val),
              ),
              Text('Frequency X (ωx): ${_frequencyX.toStringAsFixed(2)}'),
              Slider(
                value: _frequencyX,
                min: 0.5,
                max: 3.0,
                activeColor: const Color(0xFF38BDF8),
                onChanged: (val) => setState(() => _frequencyX = val),
              ),
              Text('Frequency Y (ωy): ${_frequencyY.toStringAsFixed(2)}'),
              Slider(
                value: _frequencyY,
                min: 0.5,
                max: 3.0,
                activeColor: const Color(0xFF10B981),
                onChanged: (val) => setState(() => _frequencyY = val),
              ),
            ],

            const SizedBox(height: 10),
            ElevatedButton.icon(
              icon: const Icon(Icons.calculate_rounded),
              label: const Text('Launch Scientific Calculator'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 42),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _openScientificCalculator,
            ),
          ],
        ),
      ),
    );
  }
}
