import 'package:flutter/material.dart';

import '../../../core/theme/idp_colors.dart';
import '../application/exploration_repository.dart';
import '../domain/saved_exploration.dart';
import 'algebra_workspace_screen.dart';
import 'geometry_workspace_screen.dart';
import 'functions_workspace_screen.dart';
import 'statistics_workspace_screen.dart';
import 'formula_playground_screen.dart';
import 'widgets/math_studio_workspace_shell.dart';

class SavedExplorationsScreen extends StatefulWidget {
  const SavedExplorationsScreen({super.key});

  @override
  State<SavedExplorationsScreen> createState() =>
      _SavedExplorationsScreenState();
}

class _SavedExplorationsScreenState extends State<SavedExplorationsScreen> {
  ExplorationRepository? _repository;
  List<SavedExploration> _explorations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initRepo();
  }

  Future<void> _initRepo() async {
    _repository = await ExplorationRepository.create();
    var exps = await _repository!.getAllExplorations();
    if (exps.isEmpty) {
      final defaultSeed = [
        SavedExploration(
          id: 'exp_algebra_1',
          title: 'Quadratic Balance Equilibrium',
          type: ExplorationType.algebra,
          data: {'equation': '2x + 3 = 7'},
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        SavedExploration(
          id: 'exp_functions_1',
          title: 'Sine Wave Harmonic Oscillator',
          type: ExplorationType.functions,
          data: {'formula': 'sin(x)'},
          createdAt: DateTime.now().subtract(const Duration(days: 2)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 5)),
        ),
        SavedExploration(
          id: 'exp_geometry_1',
          title: 'Pythagorean Triangle Theorem',
          type: ExplorationType.geometry,
          data: {'shape': 'triangle'},
          createdAt: DateTime.now().subtract(const Duration(days: 3)),
          updatedAt: DateTime.now().subtract(const Duration(hours: 12)),
        ),
      ];
      for (final s in defaultSeed) {
        await _repository!.saveExploration(s);
      }
      exps = await _repository!.getAllExplorations();
    }
    if (!mounted) return;
    setState(() {
      _explorations = exps;
      _isLoading = false;
    });
  }

  Future<void> _loadExplorations() async {
    if (_repository == null) return;
    final exps = await _repository!.getAllExplorations();
    if (!mounted) return;
    setState(() {
      _explorations = exps;
      _isLoading = false;
    });
  }

  Future<void> _delete(String id) async {
    if (_repository == null) return;
    await _repository!.deleteExploration(id);
    await _loadExplorations();
  }

  Future<void> _rename(SavedExploration exp) async {
    if (_repository == null) return;

    final controller = TextEditingController(text: exp.title);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rename Exploration'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Enter new name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newTitle != null && newTitle.trim().isNotEmpty) {
      await _repository!.renameExploration(exp.id, newTitle.trim());
      await _loadExplorations();
    }
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MathStudioWorkspaceShell(
      title: 'Saved Explorations',
      accentColor: const Color(0xFF4B5563),
      children: [
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_explorations.isEmpty)
          _buildEmptyState(context)
        else
          _buildList(),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IDPColors.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.folder_open_rounded, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          const Text(
            'No saved explorations yet.',
            style: TextStyle(fontSize: 18, color: IDPColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create one from Algebra, Geometry, Functions, Statistics, or the Formula Playground.',
            textAlign: TextAlign.center,
            style: TextStyle(color: IDPColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to Math Studio'),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _explorations.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final exp = _explorations[index];
        return Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: _getIconForType(exp.type),
            title: Text(
              exp.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('Saved: ${exp.updatedAt.toString().split('.')[0]}'),
            trailing: PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'rename') _rename(exp);
                if (val == 'delete') _delete(exp.id);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'rename', child: Text('Rename')),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
            onTap: () {
              Widget target;
              switch (exp.type) {
                case ExplorationType.algebra:
                  target = const AlgebraWorkspaceScreen();
                  break;
                case ExplorationType.geometry:
                  final shapeStr = exp.data['shape'] as String?;
                  final shape = GeometryShape.values.firstWhere(
                    (e) => e.name == shapeStr,
                    orElse: () => GeometryShape.triangle,
                  );
                  target = GeometryWorkspaceScreen(initialShape: shape);
                  break;
                case ExplorationType.functions:
                  target = FunctionLabScreen(
                    initialFormula: exp.data['formula'] as String?,
                  );
                  break;
                case ExplorationType.statistics:
                  target = const StatisticsLabScreen();
                  break;
                case ExplorationType.formulaPlayground:
                  target = const FormulaPlaygroundScreen();
                  break;
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => target),
              );
            },
          ),
        );
      },
    );
  }

  Widget _getIconForType(ExplorationType type) {
    switch (type) {
      case ExplorationType.algebra:
        return const CircleAvatar(
          backgroundColor: Color(0xFF6366F1),
          child: Icon(Icons.calculate_rounded, color: Colors.white),
        );
      case ExplorationType.geometry:
        return const CircleAvatar(
          backgroundColor: Color(0xFF0D9488),
          child: Icon(Icons.architecture_rounded, color: Colors.white),
        );
      case ExplorationType.functions:
        return const CircleAvatar(
          backgroundColor: Color(0xFFD97706),
          child: Icon(Icons.show_chart_rounded, color: Colors.white),
        );
      case ExplorationType.statistics:
        return const CircleAvatar(
          backgroundColor: Color(0xFFDC2626),
          child: Icon(Icons.bar_chart_rounded, color: Colors.white),
        );
      case ExplorationType.formulaPlayground:
        return const CircleAvatar(
          backgroundColor: Color(0xFF8B5CF6),
          child: Icon(Icons.science_rounded, color: Colors.white),
        );
    }
  }
}
