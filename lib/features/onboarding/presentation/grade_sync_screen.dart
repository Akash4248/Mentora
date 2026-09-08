import 'dart:async';
import 'package:flutter/material.dart';
import '../../educational/application/sync_manager.dart';
import '../../educational/domain/pack_sync_entry.dart';
import '../../home/presentation/mentora_home_screen.dart';
import '../../course/data/local/course_repository.dart';
import '../application/background_prefetch_service.dart';

class GradeSyncScreen extends StatefulWidget {
  final int grade;
  final String languageCode;

  const GradeSyncScreen({
    super.key,
    required this.grade,
    required this.languageCode,
  });

  @override
  State<GradeSyncScreen> createState() => _GradeSyncScreenState();
}

class _GradeSyncScreenState extends State<GradeSyncScreen> {
  final SyncManager _syncManager = SyncManager();
  bool _loadingCatalog = true;
  bool _syncing = false;
  String? _error;
  StreamSubscription<String>? _progressSubscription;

  List<PackSyncEntry> _packs = [];
  int _totalPacks = 0;
  int _downloadedPacks = 0;
  double _estimatedSizeMb = 0;
  Set<String> _subjects = {};
  String _currentChapter = '';
  String _installStage = 'Installing Pack...';

  @override
  void initState() {
    super.initState();
    _progressSubscription = _syncManager.progressStream.listen((message) {
      if (!mounted) return;
      setState(() => _installStage = message);
    });
    _loadCatalog();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    setState(() {
      _loadingCatalog = true;
      _error = null;
    });

    try {
      // PHASE 2: CATALOG LOADING
      // Load the pack inventory from the older /packs endpoint and filter locally.
      final packs = await _syncManager.checkForPackUpdates(grade: widget.grade);

      double totalSizeMb = 0;
      Set<String> subjects = {};

      for (var pack in packs) {
        totalSizeMb += (pack.sizeBytes ?? 5000000) / (1024 * 1024);
        final subjectLabel = _displaySubject(pack.subject ?? '');
        if (subjectLabel.isNotEmpty) {
          subjects.add(subjectLabel);
        }
      }

      if (mounted) {
        setState(() {
          _packs = packs;
          _totalPacks = packs.length;
          _estimatedSizeMb = totalSizeMb;
          _subjects = subjects;
          _loadingCatalog = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load catalog: $e';
          _loadingCatalog = false;
        });
      }
    }
  }

  String _displaySubject(String rawSubject) {
    final cleaned = rawSubject.trim().replaceAll('_', ' ');
    if (cleaned.isEmpty) {
      return '';
    }

    final lower = cleaned.toLowerCase();
    if (lower == 'maths' || lower == 'mathematics') {
      return 'Mathematics';
    }
    if (lower == 'science') {
      return 'Science';
    }
    if (lower == 'social science' || lower == 'socialscience') {
      return 'Social Science';
    }
    if (lower == 'english') {
      return 'English';
    }
    if (lower == 'kannada') {
      return 'Kannada';
    }

    return cleaned
        .split(RegExp(r'\s+'))
        .map((part) {
          if (part.isEmpty) return '';
          return part[0].toUpperCase() + part.substring(1).toLowerCase();
        })
        .join(' ');
  }

  Future<void> _startSync() async {
    setState(() {
      _syncing = true;
    });

    // PHASE 4: DOWNLOAD QUEUE
    print('[SYNC] GRADE_SELECTED=${widget.grade}');
    print('[SYNC] FILTERED_PACK_COUNT=${_packs.length}');
    print('[SYNC] DOWNLOAD_QUEUE_SIZE=${_packs.length}');

    int successCount = 0;

    for (int i = 0; i < _packs.length; i++) {
      final pack = _packs[i];
      if (mounted) {
        setState(() {
          _currentChapter = pack.packId;
          _installStage = 'Installing Pack...';
        });
      }

      try {
        final queuedCount = await _syncManager.processPackUpdates([pack]);
        if (queuedCount == 0) {
          continue;
        }
        while (_syncManager.syncQueue.getStatus()['isProcessing'] == true) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
        successCount += queuedCount;
        if (mounted) {
          setState(() {
            _downloadedPacks = successCount;
          });
        }
      } catch (e) {
        print('[SYNC] Error syncing ${pack.packId}: $e');
      }
    }

    if (mounted) {
      // PHASE 6: BACKGROUND PREFETCH
      BackgroundPrefetchService.schedulePrefetch();

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const MentoraHomeScreen(),
        ),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Curriculum Setup'),
        backgroundColor: const Color(0xFF0B6E4F),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _loadingCatalog
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF0B6E4F)),
                )
              : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 48,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadCatalog,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _syncing
              ? _buildSyncingView()
              : _buildCatalogView(),
        ),
      ),
    );
  }

  Widget _buildCatalogView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.library_books_rounded,
          size: 64,
          color: Color(0xFF0B6E4F),
        ),
        const SizedBox(height: 24),
        Text(
          'Grade ${widget.grade} Curriculum',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 32),
        _buildStatRow(
          Icons.folder_zip_rounded,
          'Packs to Install',
          '$_totalPacks',
        ),
        const Divider(height: 32),
        _buildStatRow(
          Icons.data_usage_rounded,
          'Estimated Download Size',
          '${_estimatedSizeMb.toStringAsFixed(1)} MB',
        ),
        const Divider(height: 32),
        _buildStatRow(
          Icons.subject_rounded,
          'Subjects Included',
          _subjects.join(', '),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: _totalPacks > 0
              ? _startSync
              : () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const MentoraHomeScreen(),
                    ),
                    (route) => false,
                  );
                },
          icon: const Icon(Icons.download_rounded),
          label: Text(
            _totalPacks > 0
                ? 'Install Offline Content'
                : 'Continue to Dashboard',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0B6E4F),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSyncingView() {
    final progress = _totalPacks == 0 ? 1.0 : _downloadedPacks / _totalPacks;
    final remainingMb = _estimatedSizeMb * (1.0 - progress);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _installStage,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 32),
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              height: 120,
              width: 120,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 8,
                backgroundColor: Colors.grey.shade200,
                color: const Color(0xFF0B6E4F),
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0B6E4F),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          '$_downloadedPacks / $_totalPacks',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey.shade200,
          color: const Color(0xFF0B6E4F),
          minHeight: 12,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Text(
                'Current chapter: $_currentChapter',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 8),
              Text(
                'Estimated remaining size: ${remainingMb.toStringAsFixed(1)} MB',
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade600),
        const SizedBox(width: 16),
        Text(
          label,
          style: TextStyle(fontSize: 16, color: Colors.grey.shade700),
        ),
        const Spacer(),
        Expanded(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
