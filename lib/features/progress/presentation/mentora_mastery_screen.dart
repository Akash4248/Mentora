import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../course/data/local/course_repository.dart';
import '../data/local/progress_repository.dart';
import '../../home/presentation/mentora_home_screen.dart';

class MentoraMasteryScreen extends StatefulWidget {
  const MentoraMasteryScreen({Key? key}) : super(key: key);

  @override
  State<MentoraMasteryScreen> createState() => _MentoraMasteryScreenState();
}

class _MentoraMasteryScreenState extends State<MentoraMasteryScreen> {
  final ProgressRepository _progressRepo = ProgressRepository();
  final CourseRepository _courseRepo = CourseRepository();

  bool _isLoading = true;
  int _selectedGrade = 10;
  String _userName = 'Learner';
  int _streakDays = 0;
  int _dailyMinsLearned = 0;
  double _overallMasteryPercent = 0.0;
  List<Map<String, dynamic>> _subjectProgressList = [];

  @override
  void initState() {
    super.initState();
    _loadMasteryData();
  }

  Future<void> _loadMasteryData() async {
    setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final grade = prefs.getInt('selected_grade') ?? 9;
    final userName = prefs.getString('user_name') ?? 'Learner';
    final streak = prefs.getInt('study_streak_days') ?? 0;
    final totalMins = prefs.getInt('total_learning_minutes') ?? 0;

    await _courseRepo.ensureSeedData();
    final allProgress = await _progressRepo.getAllChapterProgress();
    final courseId = 'course_$grade';
    final subjects = await _courseRepo.getSubjects(courseId);

    final progressMap = <String, double>{};
    for (final p in allProgress) {
      progressMap[p.chapterId] = p.masteryScore;
    }

    final subjectList = <Map<String, dynamic>>[];
    double totalMasterySum = 0.0;
    int totalChaptersCount = 0;

    for (final sub in subjects) {
      final chapters = await _courseRepo.getChapters(sub.id);
      double subMasterySum = 0.0;
      for (final ch in chapters) {
        final score = progressMap[ch.id] ?? 0.0;
        subMasterySum += score;
        totalMasterySum += score;
        totalChaptersCount++;
      }
      final double avgSubMastery = chapters.isNotEmpty
          ? (subMasterySum / chapters.length).clamp(0, 100)
          : 0.0;

      subjectList.add({
        'name': sub.name,
        'chapterCount': chapters.length,
        'progress': avgSubMastery / 100,
        'percentage': avgSubMastery.round(),
      });
    }

    final overall = totalChaptersCount > 0
        ? (totalMasterySum / totalChaptersCount).clamp(0, 100).toDouble()
        : 0.0;

    if (mounted) {
      setState(() {
        _selectedGrade = grade;
        _userName = userName;
        _streakDays = streak;
        _dailyMinsLearned = totalMins;
        _overallMasteryPercent = overall;
        _subjectProgressList = subjectList;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const primaryIndigo = Color(0xFF4F46E5);
    const slateBg = Color(0xFFF8FAFC);
    const cardBg = Color(0xFFFFFFFF);
    const borderColor = Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: slateBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Concept Mastery & Analytics',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            Text(
              'NCERT Class $_selectedGrade Real Progress Analytics',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: primaryIndigo),
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
            icon: const Icon(Icons.settings_rounded, color: Color(0xFF64748B)),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MentoraHomeScreen(initialTabIndex: 4)),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: primaryIndigo),
            )
          : RefreshIndicator(
              onRefresh: _loadMasteryData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // OVERALL MASTERY STATS HERO CARD
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 72,
                                height: 72,
                                child: CircularProgressIndicator(
                                  value: (_overallMasteryPercent / 100).clamp(0.0, 1.0),
                                  strokeWidth: 8,
                                  backgroundColor: const Color(0xFF334155),
                                  valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF10B981),
                                  ),
                                ),
                              ),
                              Text(
                                '${_overallMasteryPercent.round()}%',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$_userName\'s Real Mastery',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '🔥 $_streakDays Day Streak • $_dailyMinsLearned mins total',
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _overallMasteryPercent >= 70
                                        ? 'Board Exam Readiness: High'
                                        : _overallMasteryPercent >= 40
                                            ? 'Board Exam Readiness: Moderate'
                                            : 'Board Exam Readiness: In Progress',
                                    style: const TextStyle(
                                      color: Color(0xFF34D399),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // SUBJECT BREAKDOWN HEADER
                    const Text(
                      '📊 Real Subject-wise Concept Breakdown',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // SUBJECT MASTERY LIST
                    ..._subjectProgressList.map((sub) {
                      final String name = (sub['name'] ?? 'Subject').toString();
                      final double progress = (sub['progress'] as num).toDouble();
                      final int percentage = sub['percentage'] as int;
                      final int chapterCount = sub['chapterCount'] as int;

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        color: cardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: borderColor),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: Color(0xFF0F172A),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '$chapterCount Real Chapters',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _getScoreColor(percentage).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '$percentage% Mastered',
                                      style: TextStyle(
                                        color: _getScoreColor(percentage),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress.clamp(0.0, 1.0),
                                  backgroundColor: const Color(0xFFF1F5F9),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    _getScoreColor(percentage),
                                  ),
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 70) return const Color(0xFF10B981);
    if (score >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFF6366F1);
  }
}
