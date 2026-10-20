import 'package:shared_preferences/shared_preferences.dart';

import '../domain/learning_profile_models.dart';
import '../../assessment/data/local/quiz_result_repository.dart';
import 'achievement_service.dart';

class LearningInsightsService {
  final SharedPreferences prefs;
  final QuizResultRepository quizRepo;
  final AchievementService achievementService;

  LearningInsightsService({
    required this.prefs,
    required this.quizRepo,
    required this.achievementService,
  });

  static Future<LearningInsightsService> create() async {
    final futures = await Future.wait([
      SharedPreferences.getInstance(),
      AchievementService.create(),
    ]);

    return LearningInsightsService(
      prefs: futures[0] as SharedPreferences,
      quizRepo: QuizResultRepository(),
      achievementService: futures[1] as AchievementService,
    );
  }

  Future<LearningProfile> generateProfile() async {
    final results = await quizRepo.getAllResults();
    
    int totalQuestions = 0;
    int correctAnswers = 0;
    for (final r in results) {
      totalQuestions += r.totalQuestions;
      correctAnswers += (r.score / 100 * r.totalQuestions).round();
    }
    final avgAccuracy = totalQuestions > 0 ? (correctAnswers / totalQuestions) * 100 : 0.0;

    final completedChapters = prefs.getStringList('completed_chapters')?.length ?? 0;
    final totalTime = prefs.getInt('total_learning_minutes') ?? 0;
    final streak = prefs.getInt('study_streak_days') ?? 0;
    final exps = prefs.getInt('total_experiments_completed') ?? 0;

    // Dummy detection logic for strengths and weaknesses
    final strengths = <StudentStrength>[];
    final weaknesses = <StudentWeakness>[];
    
    if (avgAccuracy > 80) {
      strengths.add(StudentStrength('General Knowledge', 'Consistently scoring high on quizzes.'));
    } else if (avgAccuracy > 0 && avgAccuracy < 50) {
      weaknesses.add(StudentWeakness('General Knowledge', 'Low average quiz accuracy.', 'Review textbook before taking quizzes.'));
    }

    if (exps > 3) {
      strengths.add(StudentStrength('Practical Application', 'Highly engaged with experiments.'));
    }

    final recommendations = <LearningRecommendation>[];
    if (weaknesses.isNotEmpty) {
      recommendations.add(LearningRecommendation(
        title: 'Needs Revision',
        description: 'Review recent chapters to improve accuracy.',
        actionRoute: 'chapter',
        targetId: 'recent',
      ));
    } else {
      recommendations.add(LearningRecommendation(
        title: 'Keep Going',
        description: 'You are doing great! Try a new experiment.',
        actionRoute: 'experiment',
        targetId: 'random',
      ));
    }

    return LearningProfile(
      studyStreakDays: streak,
      completedChapters: completedChapters,
      totalLearningTimeMinutes: totalTime,
      experimentsCompleted: exps,
      averageQuizAccuracy: avgAccuracy,
      strengths: strengths,
      weaknesses: weaknesses,
      recommendations: recommendations,
      achievements: achievementService.getUnlockedAchievements(),
    );
  }

  Future<ChapterAnalytics> getChapterAnalytics(String chapterId) async {
    final results = await quizRepo.getChapterResults(chapterId);
    final hasRead = prefs.getBool('read_chapter_$chapterId') ?? false;
    final exps = prefs.getInt('exp_completed_count_$chapterId') ?? 0;

    double latestScore = 0.0;
    if (results.isNotEmpty) {
      latestScore = results.first.score.toDouble();
    }

    return ChapterAnalytics(
      chapterId: chapterId,
      hasRead: hasRead,
      quizAttempts: results.length,
      latestQuizScore: latestScore,
      experimentsCompleted: exps,
      tutorQuestionsAsked: prefs.getInt('tutor_questions_$chapterId') ?? 0,
    );
  }

  Future<void> markChapterRead(String chapterId) async {
    await prefs.setBool('read_chapter_$chapterId', true);
    
    final completedList = prefs.getStringList('completed_chapters') ?? [];
    if (!completedList.contains(chapterId)) {
      completedList.add(chapterId);
      await prefs.setStringList('completed_chapters', completedList);
      
      if (completedList.length == 1) {
        await achievementService.unlockAchievement('first_chapter');
      }
    }
  }

  Future<void> addLearningTime(int minutes) async {
    final current = prefs.getInt('total_learning_minutes') ?? 0;
    await prefs.setInt('total_learning_minutes', current + minutes);
  }
}
