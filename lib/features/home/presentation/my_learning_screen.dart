import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../course/data/local/curriculum_repository.dart';
import '../../course/domain/curriculum_models.dart';
import '../../assessment/data/local/quiz_result_repository.dart';
import '../../analytics/application/learning_insights_service.dart';
import '../../analytics/domain/learning_profile_models.dart';
import '../../../core/widgets/idp_skeleton_loader.dart';
import '../../../core/theme/idp_colors.dart';
import '../../../core/theme/idp_theme.dart';
import '../../onboarding/presentation/grade_sync_screen.dart';
import 'subject_screen.dart';
import '../../course/domain/course_tree.dart';

class MyLearningScreen extends StatefulWidget {
  const MyLearningScreen({
    required this.languageCode,
    super.key,
  });

  final String languageCode;

  @override
  State<MyLearningScreen> createState() => _MyLearningScreenState();
}

class _MyLearningScreenState extends State<MyLearningScreen> {
  final CurriculumRepository _curriculumRepo = CurriculumRepository();
  final QuizResultRepository _quizRepo = QuizResultRepository();
  
  bool _loading = true;
  int _selectedGrade = 8;
  List<CurriculumSubject> _subjects = [];
  Map<String, int> _chapterQuizAttempts = {};
  LearningProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final grade = prefs.getInt('selected_grade') ?? 8;

    final results = await Future.wait([
      _quizRepo.getAllResults(),
      LearningInsightsService.create(),
      _curriculumRepo.getCurriculum(languageCode: widget.languageCode),
    ]);

    final allResults = results[0] as List<dynamic>;
    final insights = results[1] as LearningInsightsService;
    final curriculum = results[2] as List<CurriculumGrade>;

    final Map<String, int> attemptsMap = {};
    for (final res in allResults) {
      attemptsMap[res.chapterId] = (attemptsMap[res.chapterId] ?? 0) + 1;
    }

    final profile = await insights.generateProfile();

    final matchedGrade = curriculum.firstWhere(
      (g) => g.grade == grade,
      orElse: () => CurriculumGrade(grade: grade, subjects: []),
    );

    if (mounted) {
      setState(() {
        _selectedGrade = grade;
        _subjects = matchedGrade.subjects;
        _chapterQuizAttempts = attemptsMap;
        _profile = profile;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return ListView.separated(
        padding: const EdgeInsets.all(IDPSpacing.lg),
        itemCount: 5,
        separatorBuilder: (_, _) => const SizedBox(height: IDPSpacing.md),
        itemBuilder: (_, index) => IDPSkeletonLoader(
          width: double.infinity,
          height: index == 0 ? 150 : 80,
          borderRadius: IDPRadius.lg,
        ),
      );
    }

    if (_subjects.isEmpty) {
      return _buildEmptyState();
    }

    return Scaffold(
      backgroundColor: Colors.transparent, // Background handled by parent scaffold
      appBar: _buildTopAppBar(),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: IDPColors.primary,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.containerMargin, vertical: IDPSpacing.xl),
          children: [
            _buildStreakAndFocus(),
            const SizedBox(height: IDPSpacing.xl),
            _buildContinueLearning(),
            const SizedBox(height: IDPSpacing.xl),
            _buildRecommendedSection(),
            const SizedBox(height: IDPSpacing.xl),
            _buildAITutorShortcut(),
            const SizedBox(height: IDPSpacing.xxl),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildTopAppBar() {
    return AppBar(
      backgroundColor: IDPColors.surface.withValues(alpha: 0.8),
      elevation: 0,
      scrolledUnderElevation: 2,
      shadowColor: IDPColors.primary.withValues(alpha: 0.2),
      flexibleSpace: ClipRRect(
        child: BackdropFilter(
          filter: ColorFilter.mode(Colors.white.withValues(alpha: 0.1), BlendMode.dstATop),
          child: Container(color: Colors.transparent),
        ),
      ),
      title: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: IDPColors.primaryContainer, width: 2),
              color: IDPColors.surfaceVariant,
            ),
            child: const Center(
              child: Icon(Icons.person, color: IDPColors.primary, size: 26),
            ),
          ),
          const SizedBox(width: IDPSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("OfflineTutor", style: IDPTypography.headlineLgMobile.copyWith(color: IDPColors.primary, fontSize: 20)),
              Text("Good morning, Alex", style: IDPTypography.labelMd.copyWith(color: IDPColors.textSecondary, fontWeight: FontWeight.normal)),
            ],
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: IDPSpacing.containerMargin),
          padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.md, vertical: IDPSpacing.xs),
          decoration: BoxDecoration(
            color: IDPColors.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(IDPRadius.full),
            border: Border.all(color: IDPColors.outlineVariant.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.signal_cellular_connected_no_internet_4_bar, size: 18, color: IDPColors.textSecondary),
              const SizedBox(width: IDPSpacing.xs),
              Text("Offline", style: IDPTypography.labelMd.copyWith(color: IDPColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStreakAndFocus() {
    final streakDays = _profile?.studyStreakDays ?? 0;
    final accuracy = _profile?.averageQuizAccuracy ?? 0;

    return Row(
      children: [
        // Streak Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(IDPSpacing.lg),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(IDPRadius.lg),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("DAILY GOAL", style: IDPTypography.labelMd.copyWith(color: IDPColors.textSecondary, fontSize: 10)),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text("$streakDays Day Streak", style: IDPTypography.headlineLgMobile.copyWith(color: IDPColors.primary, fontSize: 18)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: IDPSpacing.sm),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: IDPColors.primaryContainer,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: IDPColors.primaryContainer.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: const Icon(Icons.local_fire_department, color: IDPColors.onPrimaryContainer, size: 24),
                    ),
                  ],
                ),
                const SizedBox(height: IDPSpacing.md),
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: IDPColors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(IDPRadius.full),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: (streakDays / 7).clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [IDPColors.primary, IDPColors.secondary]),
                        borderRadius: BorderRadius.circular(IDPRadius.full),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: IDPSpacing.md),
        // Focus Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(IDPSpacing.lg),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(IDPRadius.lg),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 20, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("FOCUS SCORE", style: IDPTypography.labelMd.copyWith(color: IDPColors.textSecondary, fontSize: 10)),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text("Deep Work", style: IDPTypography.headlineLgMobile.copyWith(color: IDPColors.secondary, fontSize: 18)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: IDPSpacing.sm),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: IDPColors.secondaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.psychology, color: IDPColors.onSecondaryContainer, size: 24),
                    ),
                  ],
                ),
                const SizedBox(height: IDPSpacing.md),
                Text("${accuracy.toStringAsFixed(0)}% concentration during last session", style: IDPTypography.labelMd.copyWith(color: IDPColors.textSecondary, fontSize: 11, fontWeight: FontWeight.normal)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContinueLearning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Continue Learning", style: IDPTypography.titleMd.copyWith(fontWeight: FontWeight.bold)),
            TextButton(
              onPressed: () {},
              child: Text("View All", style: IDPTypography.labelMd.copyWith(color: IDPColors.primary)),
            ),
          ],
        ),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 240),
          decoration: BoxDecoration(
            color: IDPColors.primaryContainer,
            borderRadius: BorderRadius.circular(IDPRadius.xl),
            image: DecorationImage(
              image: NetworkImage("https://lh3.googleusercontent.com/aida-public/AB6AXuBE_Q0dj3YtSwLpLMzpM6Y3Tgt09K72tnyQMLrf9sTIrHFS6CXXmbrubPl9k-WvrmKIJOGExvDyblrfNq_oNsV1aCXiNCGc574MvSIly4pyyP0uXHWzHyr1VY0ZRmDMxWlGTV9QzfTYNd0fF9lKDlvzufBkRVmMejnTyoD7uNbJWO-Wk6_zAi7xj6sMc1mDuxsbjJyw1_nqYpLWebslGIqMC-DbbU_EMaObdw3KFevAMuj5jjvPTXMwTbwwLkwF11WpRHLppa5ZChb3"),
              fit: BoxFit.cover,
              onError: (_, __) {},
            ),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, 5)),
            ],
          ),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(IDPRadius.xl),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [IDPColors.primary.withValues(alpha: 0.9), Colors.transparent],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(IDPSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.sm, vertical: IDPSpacing.xs),
                      decoration: BoxDecoration(
                        color: IDPColors.secondaryContainer,
                        borderRadius: BorderRadius.circular(IDPRadius.full),
                      ),
                      child: Text("CHAPTER 3", style: IDPTypography.caption.copyWith(color: IDPColors.onSecondaryContainer, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: IDPSpacing.sm),
                    Text("Quantum Physics: The Observer Effect", style: IDPTypography.headlineLg.copyWith(color: Colors.white, fontSize: 24)),
                    const SizedBox(height: IDPSpacing.sm),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("65% Completed", style: IDPTypography.labelMd.copyWith(color: IDPColors.onPrimaryContainer.withValues(alpha: 0.8))),
                        Text("12m remaining", style: IDPTypography.caption.copyWith(color: Colors.white70)),
                      ],
                    ),
                    const SizedBox(height: IDPSpacing.xs),
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: IDPColors.onPrimaryContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(IDPRadius.full),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: 0.65,
                        child: Container(
                          decoration: BoxDecoration(
                            color: IDPColors.secondaryContainer,
                            borderRadius: BorderRadius.circular(IDPRadius.full),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: IDPSpacing.md),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.play_arrow),
                      label: const Text("Resume Lesson"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: IDPColors.surface,
                        foregroundColor: IDPColors.primary,
                        elevation: 4,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IDPRadius.full)),
                        padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.xl, vertical: IDPSpacing.md),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Recommended for You", style: IDPTypography.titleMd.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: IDPSpacing.md),
        SizedBox(
          height: 240,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _subjects.length,
            separatorBuilder: (_, __) => const SizedBox(width: IDPSpacing.md),
            itemBuilder: (context, index) {
              final subject = _subjects[index];
              final progress = _getSubjectProgress(subject);

              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SubjectScreen(subject: subject),
                    ),
                  ).then((_) => _loadData());
                },
                child: Container(
                  width: 280,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(IDPRadius.lg),
                    border: Border.all(color: IDPColors.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 128,
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(IDPRadius.lg), topRight: Radius.circular(IDPRadius.lg)),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [IDPColors.primary.withValues(alpha: 0.85), IDPColors.secondary.withValues(alpha: 0.85)],
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            _subjectIcon(subject.name),
                            size: 44,
                            color: IDPColors.onPrimary,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(IDPSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(subject.name.toUpperCase(), style: IDPTypography.caption.copyWith(color: IDPColors.secondary, fontWeight: FontWeight.bold)),
                            const SizedBox(height: IDPSpacing.xs),
                            Text(
                              subject.chapters.isNotEmpty ? subject.chapters.first.title : "Advanced Subject",
                              style: IDPTypography.bodyLg.copyWith(color: IDPColors.textPrimary, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: IDPSpacing.xs),
                            Text("${(progress * 100).toInt()}% • Available Offline", style: IDPTypography.caption.copyWith(color: IDPColors.textSecondary)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAITutorShortcut() {
    return Container(
      padding: const EdgeInsets.all(IDPSpacing.xl),
      decoration: BoxDecoration(
        color: IDPColors.surface,
        borderRadius: BorderRadius.circular(IDPRadius.xl),
        border: Border.all(color: IDPColors.primary.withValues(alpha: 0.12), width: 1.5),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [IDPColors.surface, IDPColors.primaryFixed.withValues(alpha: 0.18)],
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -24,
            right: -24,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: IDPColors.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 520;
              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: IDPColors.primary,
                            borderRadius: BorderRadius.circular(IDPRadius.md),
                            boxShadow: [
                              BoxShadow(
                                color: IDPColors.primary.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(Icons.smart_toy, color: Colors.white, size: 28),
                          ),
                        ),
                        const SizedBox(width: IDPSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Offline AI Tutor",
                                style: IDPTypography.titleMd.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "Works 100% on-device without internet",
                                style: IDPTypography.caption.copyWith(color: IDPColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: IDPSpacing.md),
                    Text(
                      "Stuck on a problem? Ask the AI, it works even without internet using on-device processing.",
                      style: IDPTypography.bodyMd.copyWith(color: IDPColors.textSecondary),
                    ),
                    const SizedBox(height: IDPSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _openOfflineTutor(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: IDPColors.primary,
                          foregroundColor: IDPColors.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: IDPSpacing.xl,
                            vertical: IDPSpacing.md,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(IDPRadius.full),
                          ),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [

                            Icon(Icons.psychology, size: 20),
                            SizedBox(width: 8),
                            Text(
                              "Ask AI",
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              softWrap: false,
                            ),
                            SizedBox(width: 6),
                            Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: IDPColors.primary,
                      borderRadius: BorderRadius.circular(IDPRadius.lg),
                      boxShadow: [
                        BoxShadow(
                          color: IDPColors.primary.withValues(alpha: 0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.smart_toy, color: Colors.white, size: 34),
                    ),
                  ),
                  const SizedBox(width: IDPSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Offline AI Tutor",
                          style: IDPTypography.titleMd.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: IDPSpacing.xs),
                        Text(
                          "Stuck on a problem? Ask the AI, it works even without internet using on-device processing.",
                          style: IDPTypography.bodyMd.copyWith(color: IDPColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: IDPSpacing.lg),
                  ElevatedButton(
                    onPressed: () => _openOfflineTutor(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: IDPColors.primary,
                      foregroundColor: IDPColors.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: IDPSpacing.xl,
                        vertical: IDPSpacing.md,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(IDPRadius.full),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.psychology, size: 18),
                        SizedBox(width: 6),
                        Text(
                          "Ask AI",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          softWrap: false,
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward, size: 16),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(IDPSpacing.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.school_outlined,
            size: 80,
            color: IDPColors.textSecondary,
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)!.noContentForGrade(_selectedGrade.toString()),
            style: IDPTypography.titleMd.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.noContentForGradeDescription(_selectedGrade.toString()),
            textAlign: TextAlign.center,
            style: IDPTypography.bodyMd.copyWith(color: IDPColors.textSecondary),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => GradeSyncScreen(
                    grade: _selectedGrade,
                    languageCode: widget.languageCode,
                  ),
                ),
              ).then((_) => _loadData());
            },
            icon: const Icon(Icons.download_rounded),
            label: Text(AppLocalizations.of(context)!.installGradeContent(_selectedGrade.toString())),
            style: FilledButton.styleFrom(
              backgroundColor: IDPColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(IDPRadius.md),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _getSubjectProgress(CurriculumSubject subject) {
    if (subject.chapters.isEmpty) return 0.0;
    int attemptedChapters = 0;
    for (final chapter in subject.chapters) {
      if ((_chapterQuizAttempts[chapter.packId] ?? 0) > 0) {
        attemptedChapters++;
      }
    }
    return attemptedChapters / subject.chapters.length;
  }

  IconData _subjectIcon(String name) {
    final n = name.toLowerCase();
    if (n.contains('math')) return Icons.calculate;
    if (n.contains('science') || n.contains('physics') || n.contains('chem')) return Icons.science;
    if (n.contains('bio')) return Icons.biotech;
    if (n.contains('history') || n.contains('civics') || n.contains('geo')) return Icons.public;
    if (n.contains('english') || n.contains('language')) return Icons.menu_book;
    return Icons.school;
  }

  void _openOfflineTutor(BuildContext context) {
    // Prefer opening the tutor for the first installed chapter so RAG context is available.
    CurriculumSubject? subject;
    CurriculumChapter? chapter;
    for (final s in _subjects) {
      if (s.chapters.isNotEmpty) {
        subject = s;
        chapter = s.chapters.first;
        break;
      }
    }

    if (subject == null || chapter == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No content installed yet. Install a grade to chat with the AI Tutor.')),
      );
      return;
    }

    // Canonical chat: chapter workspace, Chat tab (index 0).
    Navigator.of(context).pushNamed(
      '/chapter_workspace',
      arguments: {
        'chapterTitle': chapter.title,
        'subjectName': subject.name,
        'grade': chapter.grade,
        'initialTabIndex': 0,
      },
    );
  }
}
