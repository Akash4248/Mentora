import 'package:flutter/material.dart';
import '../../network/services/mentora_backend_client.dart';

class MentoraMasteryScreen extends StatefulWidget {
  const MentoraMasteryScreen({Key? key}) : super(key: key);

  @override
  State<MentoraMasteryScreen> createState() => _MentoraMasteryScreenState();
}

class _MentoraMasteryScreenState extends State<MentoraMasteryScreen> {
  final MentoraBackendClient _client = MentoraBackendClient();
  Map<String, dynamic>? _userProfile;
  List<Map<String, dynamic>> _subjects = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMasteryData();
  }

  Future<void> _loadMasteryData() async {
    setState(() => _isLoading = true);
    final profile = await _client.getUserProfile();
    final subjects = await _client.getSubjectsForGrade(profile['grade'] ?? 9);
    setState(() {
      _userProfile = profile;
      _subjects = subjects;
      _isLoading = false;
    });
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
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Concept Mastery & Analytics', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
            Text('NCERT Grade 9 Learning Intelligence', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
          ],
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryIndigo))
          : SingleChildScrollView(
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
                        BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 72,
                              height: 72,
                              child: CircularProgressIndicator(
                                value: 0.76,
                                strokeWidth: 8,
                                backgroundColor: Color(0xFF334155),
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
                              ),
                            ),
                            Text('76%', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_userProfile?['name'] ?? "Rahul"}\'s Overall Mastery',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '🔥 ${_userProfile?['streakDays'] ?? 5} Day Streak • ${_userProfile?['dailyMinsLearned'] ?? 24} mins today',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(color: const Color(0xFF10B981).withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                                child: const Text('Target Board Exam Readiness: High', style: TextStyle(color: Color(0xFF34D399), fontWeight: FontWeight.bold, fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // SUBJECT BREAKDOWN HEADER
                  const Text('📊 Subject-wise Concept Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A))),
                  const SizedBox(height: 12),

                  // SUBJECT MASTERY LIST
                  ..._subjects.map((sub) {
                    final String name = (sub['name'] ?? 'Subject').toString();
                    final double progress = (sub['progress'] is num) ? (sub['progress'] as num).toDouble() : 0.5;
                    final int percentage = (progress * 100).toInt();

                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      color: cardBg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: borderColor)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0F172A)),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _getScoreColor(percentage).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '$percentage% Mastered',
                                    style: TextStyle(color: _getScoreColor(percentage), fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: const Color(0xFFF1F5F9),
                                valueColor: AlwaysStoppedAnimation<Color>(_getScoreColor(percentage)),
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
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 70) return const Color(0xFF10B981);
    if (score >= 50) return const Color(0xFFF59E0B);
    return const Color(0xFFEF4444);
  }
}
