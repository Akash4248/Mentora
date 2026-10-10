import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/idp_colors.dart';
import '../../network/services/mentora_backend_client.dart';
import '../../home/presentation/mentora_home_screen.dart';
import '../../../config/app_environment.dart';

/// Grade-aware Practice hub: lists ALL chapters of the active grade,
/// grouped by subject. Tapping a chapter opens [ChapterLearningWorkspaceScreen]
/// at the Flashcards (2) or Quiz (5) tab.
///
/// Offline-first: chapters come from [MentoraBackendClient.getChaptersForSubject]
/// (local DB first, network only if empty). No RAG code is touched here.
class MentoraPracticeScreen extends StatefulWidget {
  const MentoraPracticeScreen({super.key});

  @override
  State<MentoraPracticeScreen> createState() => _MentoraPracticeScreenState();
}

class _MentoraPracticeScreenState extends State<MentoraPracticeScreen> {
  final MentoraBackendClient _client = MentoraBackendClient();

  int _activeGrade = 9;
  List<Map<String, dynamic>> _subjects = [];
  Map<String, List<Map<String, dynamic>>> _chaptersBySubject = {};
  String _subjectFilter = 'All';
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadGradeAndChapters();
  }

  Future<void> _loadGradeAndChapters() async {
    if (mounted && _chaptersBySubject.isEmpty) setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final grade = prefs.getInt('selected_grade') ?? 9;
      final subjects = await _client.getSubjectsForGrade(grade);

      // Parallel chapter fetch per subject (cached inside client).
      final entries = await Future.wait(
        subjects.map((s) async {
          final name = (s['name'] ?? '').toString();
          final chapters =
              await _client.getChaptersForSubject(name, grade: grade);
          return MapEntry(name, chapters);
        }),
      );

      if (!mounted) return;
      setState(() {
        _activeGrade = grade;
        _subjects = subjects;
        _chaptersBySubject = Map.fromEntries(entries);
        _error = null;
      });
    } catch (e) {
      AppEnvironment.log('PRACTICE', 'Failed loading grade chapters: $e');
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<String> get _subjectNames =>
      _chaptersBySubject.keys.toList()..sort();

  Map<String, List<Map<String, dynamic>>> get _visibleGroups {
    if (_subjectFilter == 'All') return _chaptersBySubject;
    final list = _chaptersBySubject[_subjectFilter];
    if (list == null) return const {};
    return {_subjectFilter: list};
  }

  int get _totalChapters => _chaptersBySubject.values
      .fold<int>(0, (sum, list) => sum + list.length);

  void _openChapter(
    String subject,
    String chapterTitle,
    int tabIndex,
  ) {
    Navigator.pushNamed(
      context,
      '/chapter_workspace',
      arguments: {
        'chapterTitle': chapterTitle,
        'subjectName': subject,
        'grade': _activeGrade,
        'initialTabIndex': tabIndex,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IDPColors.background,
      appBar: AppBar(
        backgroundColor: IDPColors.surface,
        elevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Practice & Assessment Studio',
                style: TextStyle(
                    color: IDPColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
            Text('Grade $_activeGrade • ${_subjects.length} subjects • $_totalChapters chapters',
                style: const TextStyle(
                    color: IDPColors.textSecondary, fontSize: 11)),
          ],
        ),
        iconTheme: const IconThemeData(color: IDPColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: IDPColors.primary),
            tooltip: 'Home Dashboard',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        const MentoraHomeScreen(initialTabIndex: 0)),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadGradeAndChapters,
              child: _error != null && _totalChapters == 0
                  ? ListView(
                      padding: const EdgeInsets.all(24),
                      children: [
                        const Icon(Icons.cloud_off_outlined,
                            size: 48, color: IDPColors.textHint),
                        const SizedBox(height: 12),
                        const Text(
                          'Could not load chapters.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _error ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: IDPColors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadGradeAndChapters,
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  : _totalChapters == 0
                      ? ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            const Icon(Icons.menu_book_outlined,
                                size: 48, color: IDPColors.textHint),
                            const SizedBox(height: 12),
                            Text(
                              'No chapters for Grade $_activeGrade yet.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Sync packs in Settings → Manage Content, then pull to refresh.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: IDPColors.textSecondary,
                                  fontSize: 12),
                            ),
                          ],
                        )
                      : CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    16, 16, 16, 8),
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: [
                                      _filterChip('All'),
                                      const SizedBox(width: 8),
                                      for (final name in _subjectNames) ...[
                                        _filterChip(name),
                                        const SizedBox(width: 8),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            for (final entry in _visibleGroups.entries)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 12, 16, 4),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          entry.key,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: IDPColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color:
                                              IDPColors.surfaceContainerLow,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: IDPColors.border),
                                        ),
                                        child: Text(
                                          '${entry.value.length} chapters',
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: IDPColors
                                                  .textSecondary),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            for (final entry in _visibleGroups.entries)
                              SliverList(
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final ch = entry.value[index];
                                    return _chapterCard(
                                        entry.key, index, ch);
                                  },
                                  childCount: entry.value.length,
                                ),
                              ),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 24)),
                          ],
                        ),
            ),
    );
  }

  Widget _filterChip(String label) {
    final selected = _subjectFilter == label;
    return ChoiceChip(
      label: Text(label,
          style: TextStyle(
              color: selected ? Colors.white : IDPColors.primary,
              fontWeight: FontWeight.bold,
              fontSize: 12)),
      selected: selected,
      selectedColor: IDPColors.primary,
      backgroundColor: IDPColors.primaryContainer,
      onSelected: (_) => setState(() => _subjectFilter = label),
    );
  }

  Widget _chapterCard(
      String subject, int index, Map<String, dynamic> ch) {
    final title = (ch['title'] ?? 'Chapter ${index + 1}').toString();
    final status = (ch['status'] ?? 'not_started').toString();
    final duration = (ch['duration'] ?? '').toString();
    final isCompleted = status == 'completed';
    final isInProgress = status == 'in_progress';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      color: IDPColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isInProgress ? IDPColors.primary : IDPColors.border,
          width: isInProgress ? 1.5 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openChapter(subject, title, 5), // Quiz tab
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: isCompleted
                          ? IDPColors.success
                          : (isInProgress
                              ? IDPColors.primary
                              : IDPColors.textHint),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  if (duration.isNotEmpty)
                    Text(duration,
                        style: const TextStyle(
                            fontSize: 11,
                            color: IDPColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pill(Icons.style_outlined, 'Flashcards',
                      () => _openChapter(subject, title, 2)),
                  _pill(Icons.quiz_outlined, 'Quiz',
                      () => _openChapter(subject, title, 5)),
                  _pill(Icons.menu_book_outlined, 'Textbook',
                      () => _openChapter(subject, title, 1)),
                  _pill(Icons.chat_bubble_outline, 'Ask AI',
                      () => _openChapter(subject, title, 0)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: IDPColors.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: IDPColors.primary),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: IDPColors.primary)),
          ],
        ),
      ),
    );
  }
}
