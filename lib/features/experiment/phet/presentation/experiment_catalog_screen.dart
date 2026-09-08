import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/phet_catalog_service.dart';
import '../data/phet_pack_install_service.dart';
import '../models/experiment_descriptor.dart';
import 'experiment_player_screen.dart';
import '../../../home/presentation/mentora_home_screen.dart';

class ExperimentCatalogScreen extends ConsumerStatefulWidget {
  const ExperimentCatalogScreen({super.key});

  @override
  ConsumerState<ExperimentCatalogScreen> createState() =>
      _ExperimentCatalogScreenState();
}

class _ExperimentCatalogScreenState
    extends ConsumerState<ExperimentCatalogScreen> {
  final TextEditingController _searchController = TextEditingController();
  final PhetPackInstallService _packInstaller = PhetPackInstallService();

  PhetCatalogSnapshot? _snapshot;
  bool _isLoading = true;
  bool _isInstalling = false;
  String _installMessage = '';
  double? _installProgress;
  String _query = '';
  String _selectedSubject = 'All';
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final snapshot = await ref.read(phetCatalogServiceProvider).loadCatalog();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load PhET simulations: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _installPack() async {
    setState(() {
      _isInstalling = true;
      _installMessage = 'Preparing download...';
      _installProgress = null;
      _error = null;
    });
    try {
      await _packInstaller.install(
        onProgress: (message, progress) {
          if (!mounted) return;
          setState(() {
            _installMessage = message;
            _installProgress = progress;
          });
        },
      );
      await _loadCatalog();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'PhET pack installation failed: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isInstalling = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryIndigo = Color(0xFF4F46E5);
    final snapshot = _snapshot;

    final allExperiments = snapshot?.experiments ?? const <ExperimentDescriptor>[];
    final availableSubjects = <String>['All', 'Physics', 'Chemistry', 'Mathematics', 'Biology'];

    final filteredExperiments = allExperiments.where((experiment) {
      final matchesQuery = _query.trim().isEmpty ||
          experiment.title.toLowerCase().contains(_query.trim().toLowerCase()) ||
          experiment.subject.toLowerCase().contains(_query.trim().toLowerCase());

      final matchesSubject = _selectedSubject == 'All' ||
          experiment.subject.toLowerCase() == _selectedSubject.toLowerCase();

      return matchesQuery && matchesSubject;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.science_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text('PhET Simulations', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        backgroundColor: primaryIndigo,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: Colors.white),
            tooltip: 'Home Dashboard',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MentoraHomeScreen(initialTabIndex: 0)),
                (route) => false,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded, color: Colors.white),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MentoraHomeScreen(initialTabIndex: 4)),
                (route) => false,
              );
            },
          ),
          IconButton(
            onPressed: _isLoading ? null : _loadCatalog,
            tooltip: 'Refresh catalog',
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryIndigo))
          : Column(
              children: [
                _buildHeroBanner(context, snapshot),
                if (_error != null)
                  Container(
                    width: double.infinity,
                    color: const Color(0xFFFEE2E2),
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFF991B1B)),
                    ),
                  ),

                // Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search 80+ PhET simulations...',
                      prefixIcon: const Icon(Icons.search_rounded, color: primaryIndigo),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ),

                // Subject Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: availableSubjects.map((subj) {
                      final isSelected = _selectedSubject == subj;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(subj, style: TextStyle(
                            color: isSelected ? Colors.white : const Color(0xFF475569),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          )),
                          selected: isSelected,
                          selectedColor: primaryIndigo,
                          backgroundColor: Colors.white,
                          side: BorderSide(
                            color: isSelected ? primaryIndigo : const Color(0xFFCBD5E1),
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedSubject = subj);
                            }
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 8),

                // Simulation Grid/List
                Expanded(
                  child: filteredExperiments.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: filteredExperiments.length,
                          itemBuilder: (context, index) {
                            final experiment = filteredExperiments[index];
                            return _buildExperimentCard(experiment);
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeroBanner(
    BuildContext context,
    PhetCatalogSnapshot? snapshot,
  ) {
    final installed = snapshot?.packInstalled ?? false;
    final count = snapshot?.experiments.length ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.science_outlined, color: Color(0xFF818CF8), size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Interactive PhET Labs ($count)',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              if (installed)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF065F46),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF10B981)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.offline_pin_rounded, size: 14, color: Color(0xFF6EE7B7)),
                      SizedBox(width: 4),
                      Text('Offline Bundle Ready', style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )
              else
                ElevatedButton.icon(
                  onPressed: _isInstalling ? null : _installPack,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Install Offline Pack', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
            ],
          ),
          if (_isInstalling) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: _installProgress, backgroundColor: const Color(0xFF334155), color: const Color(0xFF38BDF8)),
            const SizedBox(height: 6),
            Text(_installMessage, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
          ],
        ],
      ),
    );
  }

  Widget _buildExperimentCard(ExperimentDescriptor experiment) {
    const primaryIndigo = Color(0xFF4F46E5);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.play_circle_fill_rounded, color: primaryIndigo, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        experiment.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              experiment.subject,
                              style: const TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            experiment.isInstalled ? 'PhET · Offline HTML5' : 'Bundled Interactive',
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openExperiment(experiment),
                icon: const Icon(Icons.screen_rotation_rounded, color: Colors.white, size: 18),
                label: const Text(
                  'Play Fullscreen (Landscape)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryIndigo,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.science_outlined, size: 48, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            const Text(
              'No simulations found for this filter.',
              style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _query = '';
                  _selectedSubject = 'All';
                });
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reset Filters'),
            ),
          ],
        ),
      ),
    );
  }

  void _openExperiment(ExperimentDescriptor experiment) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ExperimentPlayerScreen(experiment: experiment),
      ),
    );
  }
}
