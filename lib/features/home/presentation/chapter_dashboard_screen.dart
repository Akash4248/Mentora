import 'package:flutter/material.dart';

import '../../course/domain/curriculum_models.dart';
import '../../course/domain/course_tree.dart';
import '../../chat/presentation/chapter_chat_screen.dart';
import 'pdf_chapter_reader_screen.dart';
import 'quiz_player_screen.dart';
import 'chapter_summary_screen.dart';
import 'video_player_screen.dart';
import '../data/local/video_resource_repository.dart';
import 'widgets/chapter_experiments_section.dart';

import '../../analytics/domain/learning_profile_models.dart';
import '../../analytics/application/learning_insights_service.dart';
import '../../../core/widgets/idp_core_widgets.dart';
import '../../../core/widgets/idp_skeleton_loader.dart';
import '../../../core/theme/idp_colors.dart';
import '../../../core/theme/idp_theme.dart';
import '../../../core/theme/idp_typography.dart';

class ChapterDashboardScreen extends StatefulWidget {
  const ChapterDashboardScreen({
    required this.chapter,
    required this.subject,
    super.key,
  });

  final CurriculumChapter chapter;
  final CurriculumSubject subject;

  @override
  State<ChapterDashboardScreen> createState() => _ChapterDashboardScreenState();
}

class _ChapterDashboardScreenState extends State<ChapterDashboardScreen> {
  ChapterAnalytics? _analytics;
  List<ChapterVideoResource> _videos = [];
  final VideoResourceRepository _videoRepo = VideoResourceRepository();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    final insights = await LearningInsightsService.create();
    final analytics = await insights.getChapterAnalytics(widget.chapter.packId);
    final videos = await _videoRepo.getVideosForChapter(widget.chapter.packId, grade: widget.chapter.grade);
    if (mounted) {
      setState(() {
        _analytics = analytics;
        _videos = videos;
        _loading = false;
      });
    }
  }

  Color _getSubjectColor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('math')) {
      return const Color(0xFF6366F1);
    } else if (lower.contains('science')) {
      return const Color(0xFF0D9488);
    } else if (lower.contains('english')) {
      return const Color(0xFFD97706);
    } else if (lower.contains('kannada')) {
      return const Color(0xFFDC2626);
    } else if (lower.contains('social')) {
      return const Color(0xFF8B5CF6);
    }
    return const Color(0xFF4B5563);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _getSubjectColor(widget.subject.name);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.subject.name), backgroundColor: themeColor, foregroundColor: Colors.white),
        body: ListView.separated(
          padding: const EdgeInsets.all(IDPSpacing.lg),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: IDPSpacing.md),
          itemBuilder: (_, index) => IDPSkeletonLoader(
            width: double.infinity,
            height: index == 0 ? 120 : 80,
            borderRadius: IDPRadius.lg,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(widget.subject.name),
        backgroundColor: themeColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Chapter Title Header
            Text(
              widget.chapter.title,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Grade ${widget.chapter.grade} • ${widget.chapter.language.toUpperCase()}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),

            if (_analytics != null) ...[
              _buildChapterAnalyticsPanel(_analytics!, themeColor),
              const SizedBox(height: 24),
            ],

            // Summary Card
            _buildSummaryCard(context, themeColor),
            const SizedBox(height: 24),

            // Action Grid
            const Text(
              'Learning Activities',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),
            _buildActionCard(
              context: context,
              title: 'Read Textbook',
              subtitle: 'Study textbook content & examples offline',
              icon: Icons.menu_book_rounded,
              colors: [const Color(0xFF3B82F6), const Color(0xFF1D4ED8)],
              onTap: () async {
                final insights = await LearningInsightsService.create();
                await insights.markChapterRead(widget.chapter.packId);
                
                if (mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => PdfChapterReaderScreen(chapter: widget.chapter),
                    ),
                  ).then((_) => _loadAnalytics());
                }
              },
            ),
            const SizedBox(height: 12),
            _buildActionCard(
              context: context,
              title: 'Practice Quiz',
              subtitle: 'Test your understanding with practice questions',
              icon: Icons.assignment_turned_in_rounded,
              colors: [const Color(0xFF10B981), const Color(0xFF047857)],
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => QuizPlayerScreen(chapter: widget.chapter),
                  ),
                ).then((_) => _loadAnalytics());
              },
            ),
            const SizedBox(height: 12),
            _buildActionCard(
              context: context,
              title: 'Summarize & Flashcards',
              subtitle: 'Review key terms and swipe study cards',
              icon: Icons.style_rounded,
              colors: [const Color(0xFFF59E0B), const Color(0xFFB45309)],
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChapterSummaryScreen(chapter: widget.chapter),
                  ),
                ).then((_) => _loadAnalytics());
              },
            ),
            const SizedBox(height: 12),
            _buildActionCard(
              context: context,
              title: 'Ask AI Tutor',
              subtitle: 'Ask helper questions using offline local RAG',
              icon: Icons.chat_bubble_rounded,
              colors: [const Color(0xFF8B5CF6), const Color(0xFF6D28D9)],
              onTap: () {
                // Map to legacy models to pass to ChapterChatScreen
                final legacyCourse = Course(
                  id: 'grade_${widget.chapter.grade}',
                  name: 'Grade ${widget.chapter.grade}',
                );
                final legacySubject = Subject(
                  id: 'sub_${widget.subject.name.toLowerCase()}',
                  courseId: legacyCourse.id,
                  name: widget.subject.name,
                );
                final legacyChapter = Chapter(
                  id: widget.chapter.packId,
                  subjectId: legacySubject.id,
                  title: widget.chapter.title,
                  summary: widget.chapter.summary,
                );

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChapterChatScreen(
                      course: legacyCourse,
                      subject: legacySubject,
                      chapter: legacyChapter,
                    ),
                  ),
                ).then((_) => _loadAnalytics());
              },
            ),

            // Inject the new Experiments Section here
            ChapterExperimentsSection(
              chapter: widget.chapter,
              subject: widget.subject,
            ),
            const SizedBox(height: 24),
            _buildVideoSectionCard(context),
          ],
        ),
      ),
    );
  }

  Widget _buildChapterAnalyticsPanel(ChapterAnalytics analytics, Color themeColor) {
    return IDPCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_rounded, color: themeColor, size: 20),
              const SizedBox(width: IDPSpacing.sm),
              Text('Chapter Progress', style: IDPTypography.heading3.copyWith(fontSize: 16)),
            ],
          ),
          const SizedBox(height: IDPSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMiniStat('Status', analytics.hasRead ? 'Read' : 'Unread', analytics.hasRead ? IDPColors.success : IDPColors.textHint),
              _buildMiniStat('Quiz Score', analytics.quizAttempts > 0 ? '${analytics.latestQuizScore}%' : '-', IDPColors.warning),
              _buildMiniStat('Experiments', '${analytics.experimentsCompleted}', IDPColors.secondary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        Text(label, style: IDPTypography.caption),
      ],
    );
  }

  Widget _buildSummaryCard(BuildContext context, Color themeColor) {
    final hasSummary = widget.chapter.summary.isNotEmpty;
    
    return IDPCard(
      backgroundColor: themeColor.withValues(alpha: 0.05),
      padding: const EdgeInsets.all(IDPSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline_rounded,
                color: themeColor,
                size: 24,
              ),
              const SizedBox(width: IDPSpacing.sm),
              Text(
                'Chapter Overview',
                style: IDPTypography.heading3.copyWith(color: themeColor),
              ),
            ],
          ),
          const SizedBox(height: IDPSpacing.sm),
          Text(
            hasSummary 
                ? widget.chapter.summary 
                : 'Study this chapter to master core concepts, definition rules, and practice application questions.',
            style: IDPTypography.body.copyWith(color: IDPColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors[0].withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVideoSectionCard(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Top Ranked Video Lectures',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_videos.length} Channels',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF6366F1),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_videos.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.video_library_outlined, color: Color(0xFF94A3B8)),
                SizedBox(width: 12),
                Text(
                  'No video links available for this chapter.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          )
        else
          ..._videos.map(
            (video) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    print('[VIDEO_DEBUG] ChapterDashboardScreen: Opening VideoPlayerScreen for "${video.videoTitle}", URL: "${video.videoUrl}"');
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => VideoPlayerScreen(
                          videoUrl: video.videoUrl,
                          title: video.videoTitle,
                          subtitle: video.channelName,
                          description: video.description,
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              const Icon(
                                Icons.play_circle_fill_rounded,
                                color: Color(0xFF6366F1),
                                size: 36,
                              ),
                              Positioned(
                                bottom: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF4F46E5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#${video.rank}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE0E7FF),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      video.channelName,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF4338CA),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                video.videoTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E293B),
                                  height: 1.3,
                                ),
                              ),
                              if (video.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  video.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Color(0xFF6366F1),
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

