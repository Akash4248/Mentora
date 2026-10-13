import 'package:flutter/material.dart';

import '../../course/domain/curriculum_models.dart';
import '../../assessment/data/local/quiz_result_repository.dart';
import '../../assessment/domain/quiz_result.dart';
import 'chapter_dashboard_screen.dart';
import 'pdf_chapter_reader_screen.dart';
import 'quiz_player_screen.dart';
import 'chapter_summary_screen.dart';
import '../../course/domain/course_tree.dart';
import '../../../core/theme/idp_colors.dart';
import '../../../core/theme/idp_typography.dart';
import '../../../core/theme/idp_theme.dart';

class SubjectScreen extends StatefulWidget {
  const SubjectScreen({
    required this.subject,
    super.key,
  });

  final CurriculumSubject subject;

  @override
  State<SubjectScreen> createState() => _SubjectScreenState();
}

class _SubjectScreenState extends State<SubjectScreen> {
  final QuizResultRepository _quizRepo = QuizResultRepository();
  Map<String, QuizResult?> _chapterResults = {};
  bool _loading = true;
  int? _expandedChapterIndex;

  @override
  void initState() {
    super.initState();
    _loadResults();
  }

  Future<void> _loadResults() async {
    setState(() {
      _loading = true;
    });

    final Map<String, QuizResult?> results = {};
    for (final chapter in widget.subject.chapters) {
      final res = await _quizRepo.getLatestChapterResult(chapter.packId);
      results[chapter.packId] = res;
    }

    if (mounted) {
      setState(() {
        _chapterResults = results;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IDPColors.background,
      appBar: AppBar(
        title: Text(widget.subject.name, style: IDPTypography.titleLarge.copyWith(color: IDPColors.onSurface)),
        backgroundColor: IDPColors.surface.withValues(alpha: 0.8),
        foregroundColor: IDPColors.onSurface,
        elevation: 0,
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: IDPColors.primary))
          : widget.subject.chapters.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: IDPSpacing.lg),
                  itemCount: widget.subject.chapters.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(left: IDPSpacing.lg, right: IDPSpacing.lg, bottom: IDPSpacing.xl),
                        child: Text(
                          'Course Curriculum',
                          style: IDPTypography.headlineLarge.copyWith(color: IDPColors.onSurface),
                        ),
                      );
                    }
                    final chapterIndex = index - 1;
                    final chapter = widget.subject.chapters[chapterIndex];
                    final result = _chapterResults[chapter.packId];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.lg),
                      child: _buildAccordionChapterCard(chapter, result, chapterIndex + 1),
                    );
                  },
                ),
    );
  }

  Widget _buildAccordionChapterCard(CurriculumChapter chapter, QuizResult? result, int number) {
    final isExpanded = _expandedChapterIndex == number;
    final isDone = result != null;
    
    return Container(
      margin: const EdgeInsets.only(bottom: IDPSpacing.md),
      decoration: BoxDecoration(
        color: IDPColors.surface,
        borderRadius: BorderRadius.circular(IDPRadius.md),
        border: Border.all(color: IDPColors.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _expandedChapterIndex = isExpanded ? null : number;
              });
            },
            borderRadius: BorderRadius.circular(IDPRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(IDPSpacing.lg),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDone ? IDPColors.secondaryContainer : IDPColors.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        isDone ? Icons.check_circle : Icons.auto_stories,
                        color: isDone ? IDPColors.onSecondaryContainer : IDPColors.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: IDPSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CHAPTER ${number.toString().padLeft(2, '0')}',
                          style: IDPTypography.labelMedium.copyWith(color: IDPColors.secondary),
                        ),
                        Text(
                          chapter.title,
                          style: IDPTypography.titleMedium,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: IDPColors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            Padding(
              padding: const EdgeInsets.only(left: IDPSpacing.lg, right: IDPSpacing.lg, bottom: IDPSpacing.lg),
              child: Column(
                children: [
                  Divider(color: IDPColors.outlineVariant.withValues(alpha: 0.2)),
                  const SizedBox(height: IDPSpacing.md),
                  _buildLessonRow(
                    '1.1 Read Textbook',
                    Icons.play_circle,
                    isDone ? 'Completed' : 'Resume',
                    isDone,
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PdfChapterReaderScreen(chapter: chapter),
                        ),
                      ).then((_) => _loadResults());
                    },
                  ),
                  _buildLessonRow(
                    '1.2 Summarize & Flashcards',
                    Icons.style_rounded,
                    'Available',
                    false,
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChapterSummaryScreen(chapter: chapter),
                        ),
                      ).then((_) => _loadResults());
                    },
                  ),
                  _buildLessonRow(
                    'Chapter Assessment',
                    Icons.quiz,
                    result != null ? 'Score: ${result.percentage}%' : 'Available',
                    result != null,
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => QuizPlayerScreen(chapter: chapter),
                        ),
                      ).then((_) => _loadResults());
                    },
                  ),
                  _buildLessonRow(
                    'Ask AI Tutor',
                    Icons.chat_bubble_rounded,
                    'Available',
                    false,
                    () {
                      // Canonical chat: chapter workspace, Chat tab (index 0).
                      Navigator.of(context).pushNamed(
                        '/chapter_workspace',
                        arguments: {
                          'chapterTitle': chapter.title,
                          'subjectName': widget.subject.name,
                          'grade': chapter.grade,
                          'initialTabIndex': 0,
                        },
                      ).then((_) => _loadResults());
                    },
                  ),
                  _buildLessonRow(
                    'Advanced Dashboard',
                    Icons.dashboard,
                    'Experiments & More',
                    false,
                    () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChapterDashboardScreen(
                            chapter: chapter,
                            subject: widget.subject,
                          ),
                        ),
                      ).then((_) => _loadResults());
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLessonRow(String title, IconData icon, String status, bool isDone, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(IDPRadius.sm),
      child: Container(
        padding: const EdgeInsets.all(IDPSpacing.md),
        margin: const EdgeInsets.only(bottom: IDPSpacing.sm),
        decoration: BoxDecoration(
          color: IDPColors.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(IDPRadius.sm),
          border: isDone ? Border.all(color: IDPColors.secondary.withValues(alpha: 0.2)) : null,
        ),
        child: Row(
          children: [
            Icon(icon, color: IDPColors.primary, size: 20),
            const SizedBox(width: IDPSpacing.md),
            Expanded(
              child: Text(
                title,
                style: IDPTypography.bodyMedium.copyWith(color: IDPColors.onSurface),
              ),
            ),
            if (status == 'Resume')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.md, vertical: IDPSpacing.xs),
                decoration: BoxDecoration(
                  color: IDPColors.primary,
                  borderRadius: BorderRadius.circular(IDPRadius.full),
                ),
                child: Text(
                  status,
                  style: IDPTypography.labelSmall.copyWith(color: IDPColors.onPrimary),
                ),
              )
            else
              Text(
                status,
                style: IDPTypography.labelMedium.copyWith(color: IDPColors.secondary),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(IDPSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.book_rounded,
              size: 64,
              color: IDPColors.outline,
            ),
            const SizedBox(height: IDPSpacing.md),
            Text(
              'No Chapters Installed',
              style: IDPTypography.titleLarge.copyWith(color: IDPColors.onSurface),
            ),
            const SizedBox(height: IDPSpacing.sm),
            Text(
              'No chapter packs were found for ${widget.subject.name}. Make sure they are installed successfully.',
              textAlign: TextAlign.center,
              style: IDPTypography.bodyMedium.copyWith(color: IDPColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
