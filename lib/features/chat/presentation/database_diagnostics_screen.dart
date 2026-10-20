import 'package:flutter/material.dart';
import '../../network/application/pi_hub_discovery_coordinator.dart';
import '../../network/application/connectivity_controller.dart';
import '../../course/data/local/app_database.dart';
import '../../educational/data/educational_database.dart';
import '../../../core/theme/idp_colors.dart';
import '../../../core/widgets/idp_core_widgets.dart';
import 'package:sqflite/sqflite.dart';

/// Hidden diagnostics page for rapid field debugging.
///
/// Access: Long-press the settings icon or navigate to /diagnostics.
/// Displays installed packs, chunk counts, FTS status, backend URL, etc.
class DatabaseDiagnosticsScreen extends StatefulWidget {
  const DatabaseDiagnosticsScreen({super.key});

  @override
  State<DatabaseDiagnosticsScreen> createState() => _DatabaseDiagnosticsScreenState();
}

class _DatabaseDiagnosticsScreenState extends State<DatabaseDiagnosticsScreen> {
  bool _loading = true;
  final Map<String, dynamic> _diagnostics = {};

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    setState(() => _loading = true);

    try {
      final appDb = await AppDatabase.instance.database;

      // Canonical v2 store (legacy rag_chunks is no longer written).
      final ragCount = Sqflite.firstIntValue(
        await appDb.rawQuery('SELECT COUNT(*) FROM rag_chunks_v2'),
      ) ?? 0;

      bool ftsAvailable = false;
      int ftsCount = 0;
      try {
        final ftsRows = await appDb.rawQuery('SELECT COUNT(*) FROM rag_chunks_v2_fts');
        ftsAvailable = true;
        ftsCount = Sqflite.firstIntValue(ftsRows) ?? 0;
      } catch (_) {
        ftsAvailable = false;
      }

      final eduDb = await EducationalDatabase.database;
      int conceptCount = 0, flashcardCount = 0, chapterCount = 0, quizCount = 0;
      try {
        conceptCount = Sqflite.firstIntValue(await eduDb.rawQuery('SELECT COUNT(*) FROM concepts')) ?? 0;
        flashcardCount = Sqflite.firstIntValue(await eduDb.rawQuery('SELECT COUNT(*) FROM flashcards')) ?? 0;
        chapterCount = Sqflite.firstIntValue(await eduDb.rawQuery('SELECT COUNT(*) FROM chapters')) ?? 0;
        quizCount = Sqflite.firstIntValue(await eduDb.rawQuery('SELECT COUNT(*) FROM quizzes')) ?? 0;
      } catch (_) {}

      bool eduFtsAvailable = EducationalDatabase.isFullTextSearchAvailable;

      final discovery = PiHubDiscoveryCoordinator();
      final connectivity = ConnectivityController();

      String sqliteVersion = 'unknown';
      try {
        final vRows = await appDb.rawQuery('SELECT sqlite_version()');
        sqliteVersion = vRows.first.values.first.toString();
      } catch (_) {}

      setState(() {
        _diagnostics['SQLite Version'] = sqliteVersion;
        _diagnostics['RAG Chunk Count'] = ragCount;
        _diagnostics['FTS Available'] = ftsAvailable ? 'YES ✓' : 'NO ✗';
        _diagnostics['FTS Row Count'] = ftsAvailable ? ftsCount : 'N/A';
        _diagnostics['Concepts'] = conceptCount;
        _diagnostics['Flashcards'] = flashcardCount;
        _diagnostics['Chapters'] = chapterCount;
        _diagnostics['Quizzes'] = quizCount;
        _diagnostics['Educational FTS'] = eduFtsAvailable ? 'YES ✓' : 'NO ✗';
        _diagnostics['Discovery Nodes'] = discovery.currentNodes.length;
        _diagnostics['Best Node'] = discovery.bestNode?.baseUrl ?? 'None';
        _diagnostics['Connectivity Mode'] = connectivity.mode.name;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _diagnostics['Error'] = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IDPColors.background,
      appBar: AppBar(
        title: const Text('System Diagnostics', style: IDPTypography.titleMedium),
        backgroundColor: IDPColors.surface,
        foregroundColor: IDPColors.onSurface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: IDPColors.primary),
            onPressed: _loadDiagnostics,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: IDPColors.primary))
          : ListView(
              padding: const EdgeInsets.all(IDPSpacing.md),
              children: [
                _buildSection('Database', [
                  'SQLite Version',
                  'RAG Chunk Count',
                  'FTS Available',
                  'FTS Row Count',
                ]),
                const SizedBox(height: IDPSpacing.md),
                _buildSection('Educational Content', [
                  'Concepts',
                  'Flashcards',
                  'Chapters',
                  'Quizzes',
                  'Educational FTS',
                ]),
                const SizedBox(height: IDPSpacing.md),
                _buildSection('Network', [
                  'Discovery Nodes',
                  'Best Node',
                  'Connectivity Mode',
                ]),
                if (_diagnostics.containsKey('Error')) ...[
                  const SizedBox(height: IDPSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(IDPSpacing.md),
                    decoration: BoxDecoration(
                      color: IDPColors.errorContainer,
                      borderRadius: BorderRadius.circular(IDPRadius.defaultRadius),
                      border: Border.all(color: IDPColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'Error: ${_diagnostics['Error']}',
                      style: IDPTypography.bodyMedium.copyWith(color: IDPColors.onErrorContainer),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildSection(String title, List<String> keys) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IDPSectionHeader(title: title),
        const SizedBox(height: IDPSpacing.xs),
        IDPCard(
          child: Column(
            children: keys
                .where((k) => _diagnostics.containsKey(k))
                .map((key) => _buildRow(key, _diagnostics[key]))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(String label, dynamic value) {
    final valueStr = value.toString();
    final isPositive = valueStr.contains('✓') || valueStr == 'online';
    final isNegative = valueStr.contains('✗') || valueStr == 'offline' || valueStr == 'None';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IDPSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: IDPTypography.bodyMedium.copyWith(color: IDPColors.textSecondary)),
          Text(
            valueStr,
            style: IDPTypography.bodyMedium.copyWith(
              color: isPositive
                  ? IDPColors.success
                  : isNegative
                      ? IDPColors.error
                      : IDPColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

