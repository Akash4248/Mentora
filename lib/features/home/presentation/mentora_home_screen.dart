import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../network/services/mentora_backend_client.dart';

import '../../assessment/presentation/mentora_practice_screen.dart';
import '../../progress/presentation/mentora_mastery_screen.dart';
import '../../math_studio/presentation/math_studio_home_screen.dart';
import '../../settings/presentation/mentora_settings_screen.dart';

class MentoraHomeScreen extends StatefulWidget {
  final int initialTabIndex;

  const MentoraHomeScreen({
    Key? key,
    this.initialTabIndex = 0,
  }) : super(key: key);

  @override
  State<MentoraHomeScreen> createState() => _MentoraHomeScreenState();
}

class _MentoraHomeScreenState extends State<MentoraHomeScreen> {
  int _selectedGrade = 9;
  late int _selectedNavIndex;
  String _userName = 'Learner';
  final MentoraBackendClient _client = MentoraBackendClient();
  List<Map<String, dynamic>> _subjects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedNavIndex = widget.initialTabIndex;
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('user_name') ?? 'Learner';
    final savedGrade = prefs.getInt('selected_grade') ?? 9;
    if (mounted) {
      setState(() {
        _userName = name;
        _selectedGrade = savedGrade;
      });
      _fetchBackendSubjects();
    }
  }

  Future<void> _fetchBackendSubjects() async {
    if (_subjects.isEmpty) {
      setState(() => _isLoading = true);
    }
    final data = await _client.getSubjectsForGrade(_selectedGrade);
    if (mounted) {
      setState(() {
        _subjects = data;
        _isLoading = false;
      });
    }
  }

  Color _parseColor(dynamic colorVal) {
    if (colorVal is Color) return colorVal;
    if (colorVal is String) {
      String hex = colorVal.replaceAll('#', '').replaceAll('0x', '');
      if (hex.length == 6) hex = 'FF$hex';
      final intColor = int.tryParse(hex, radix: 16);
      if (intColor != null) return Color(intColor);
    }
    return const Color(0xFF4F46E5);
  }

  IconData _parseIcon(dynamic iconVal) {
    if (iconVal is IconData) return iconVal;
    if (iconVal is String) {
      switch (iconVal.toLowerCase()) {
        case 'science_outlined':
        case 'science':
          return Icons.science_outlined;
        case 'biotech_outlined':
        case 'biotech':
          return Icons.biotech_outlined;
        case 'nature_outlined':
        case 'nature':
          return Icons.nature_outlined;
        case 'calculate_outlined':
        case 'calculate':
        case 'math':
          return Icons.calculate_outlined;
        default:
          return Icons.menu_book_outlined;
      }
    }
    return Icons.school_outlined;
  }

  double _parseProgress(dynamic progressVal) {
    if (progressVal is num) return progressVal.toDouble();
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    const primaryIndigo = Color(0xFF4F46E5);

    return Scaffold(
      body: IndexedStack(
        index: _selectedNavIndex,
        children: [
          _buildHomeTab(context),
          const MentoraPracticeScreen(),
          const MentoraMasteryScreen(),
          const MathStudioHomeScreen(),
          const MentoraSettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedNavIndex,
          selectedItemColor: primaryIndigo,
          unselectedItemColor: const Color(0xFF94A3B8),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 8,
          selectedFontSize: 12,
          unselectedFontSize: 11,
          onTap: (index) {
            setState(() {
              _selectedNavIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home_rounded),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined),
              activeIcon: Icon(Icons.assignment_rounded),
              label: 'Practice',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.leaderboard_outlined),
              activeIcon: Icon(Icons.leaderboard_rounded),
              label: 'Mastery',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.functions_outlined),
              activeIcon: Icon(Icons.functions_rounded),
              label: 'Studio',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab(BuildContext context) {
    const primaryIndigo = Color(0xFF4F46E5);
    const slateBg = Color(0xFFF8FAFC);
    const cardBg = Color(0xFFFFFFFF);
    const borderColor = Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: slateBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0.5,
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFEEF2FF),
              child: Icon(Icons.school, color: primaryIndigo, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hello $_userName! 👋',
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Text(
                  'What will you learn today?',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFC7D2FE)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bookmark_outline, size: 14, color: primaryIndigo),
                const SizedBox(width: 4),
                Text(
                  'Grade $_selectedGrade',
                  style: const TextStyle(
                    color: primaryIndigo,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HERO MOTIVATIONAL CARD
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF6366F1)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: primaryIndigo.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Daily Goal: 30 Mins',
                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Grade $_selectedGrade NCERT Curriculum',
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Start learning Grade $_selectedGrade subjects from 0% progress',
                          style: const TextStyle(color: Color(0xFFE0E7FF), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      if (_subjects.isNotEmpty) {
                        Navigator.pushNamed(
                          context,
                          '/subject_chapters',
                          arguments: {'subject': _subjects.first['name'], 'grade': _selectedGrade},
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: primaryIndigo,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                    child: const Text('Start', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // SUBJECTS GRID HEADER
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Grade $_selectedGrade NCERT Subjects',
                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('View All', style: TextStyle(color: primaryIndigo, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // SUBJECTS GRID
            _isLoading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32.0),
                    child: Center(child: CircularProgressIndicator(color: primaryIndigo)),
                  )
                : GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: _subjects.length,
                    itemBuilder: (context, index) {
                      final sub = _subjects[index];
                      final Color subColor = _parseColor(sub['color']);
                      final IconData subIcon = _parseIcon(sub['icon']);
                      final double subProgress = _parseProgress(sub['progress']);

                      return InkWell(
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            '/subject_chapters',
                            arguments: {'subject': sub['name'], 'grade': _selectedGrade},
                          );
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: subColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(subIcon, color: subColor, size: 22),
                                  ),
                                  Text(
                                    '${(subProgress * 100).toInt()}%',
                                    style: TextStyle(color: subColor, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    (sub['name'] ?? 'Subject').toString(),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${sub['chaptersCompleted'] ?? 0}/${sub['totalChapters'] ?? 10} Chapters',
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                  ),
                                  const SizedBox(height: 6),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: subProgress,
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      valueColor: AlwaysStoppedAnimation<Color>(subColor),
                                      minHeight: 5,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}
