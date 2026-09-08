import 'package:flutter/material.dart';
import '../../network/services/mentora_backend_client.dart';
import '../../home/presentation/mentora_home_screen.dart';

class MentoraPracticeScreen extends StatefulWidget {
  const MentoraPracticeScreen({Key? key}) : super(key: key);

  @override
  State<MentoraPracticeScreen> createState() => _MentoraPracticeScreenState();
}

class _MentoraPracticeScreenState extends State<MentoraPracticeScreen> {
  final MentoraBackendClient _client = MentoraBackendClient();
  String _selectedSubject = 'Physics';
  String _selectedDifficulty = 'Medium';
  Map<String, dynamic>? _quizData;
  bool _isLoading = true;
  int _currentQuestionIndex = 0;
  int? _selectedOption;
  bool _showExplanation = false;

  @override
  void initState() {
    super.initState();
    _loadPracticeQuestions();
  }

  Future<void> _loadPracticeQuestions() async {
    setState(() => _isLoading = true);
    final data = await _client.getQuizForChapter('Motion');
    setState(() {
      _quizData = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryIndigo = Color(0xFF4F46E5);
    const slateBg = Color(0xFFF8FAFC);
    const cardBg = Color(0xFFFFFFFF);
    const borderColor = Color(0xFFE2E8F0);

    final questions = List<Map<String, dynamic>>.from(_quizData?['questions'] ?? []);
    final currentQ = questions.isNotEmpty ? questions[_currentQuestionIndex] : null;

    return Scaffold(
      backgroundColor: slateBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0.5,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Practice & Assessment Studio', style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
            Text('NCERT Class 9-12 Adaptive Question Bank', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
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
          ? const Center(child: CircularProgressIndicator(color: primaryIndigo))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SUBJECT & DIFFICULTY FILTER CHIPS
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('Physics', _selectedSubject == 'Physics', () {
                          setState(() => _selectedSubject = 'Physics');
                          _loadPracticeQuestions();
                        }),
                        const SizedBox(width: 8),
                        _buildFilterChip('Chemistry', _selectedSubject == 'Chemistry', () {
                          setState(() => _selectedSubject = 'Chemistry');
                          _loadPracticeQuestions();
                        }),
                        const SizedBox(width: 8),
                        _buildFilterChip('Biology', _selectedSubject == 'Biology', () {
                          setState(() => _selectedSubject = 'Biology');
                          _loadPracticeQuestions();
                        }),
                        const SizedBox(width: 8),
                        _buildFilterChip('Mathematics', _selectedSubject == 'Mathematics', () {
                          setState(() => _selectedSubject = 'Mathematics');
                          _loadPracticeQuestions();
                        }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (currentQ != null) ...[
                    // PRACTICE QUESTION CARD
                    Card(
                      elevation: 0,
                      color: cardBg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: borderColor)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEF2FF),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Question ${_currentQuestionIndex + 1}/${questions.length}',
                                      style: const TextStyle(color: primaryIndigo, fontWeight: FontWeight.bold, fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                  decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                                  child: const Text('Difficulty: Medium', style: TextStyle(color: Color(0xFFD97706), fontWeight: FontWeight.bold, fontSize: 11)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              currentQ['question'] as String,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A), height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // OPTIONS LIST
                    ...List.generate((currentQ['options'] as List).length, (idx) {
                      final optionText = currentQ['options'][idx] as String;
                      final isSelected = _selectedOption == idx;
                      final isCorrect = currentQ['correctIndex'] == idx;

                      Color bg = cardBg;
                      Color border = borderColor;
                      if (_showExplanation) {
                        if (isCorrect) {
                          bg = const Color(0xFFECFDF5);
                          border = const Color(0xFF10B981);
                        } else if (isSelected) {
                          bg = const Color(0xFFFEF2F2);
                          border = const Color(0xFFEF4444);
                        }
                      } else if (isSelected) {
                        bg = const Color(0xFFEEF2FF);
                        border = primaryIndigo;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: border, width: isSelected ? 1.5 : 1.0),
                        ),
                        child: ListTile(
                          onTap: () {
                            if (!_showExplanation) {
                              setState(() => _selectedOption = idx);
                            }
                          },
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: isSelected ? primaryIndigo : const Color(0xFFF1F5F9),
                            child: Text(
                              String.fromCharCode(65 + idx),
                              style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(optionText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        ),
                      );
                    }),

                    const SizedBox(height: 12),

                    if (!_showExplanation && _selectedOption != null)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() => _showExplanation = true);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryIndigo,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Check Answer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),

                    if (_showExplanation) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('💡 Step-by-Step Solution:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text(currentQ['explanation'] as String, style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _currentQuestionIndex = (_currentQuestionIndex + 1) % questions.length;
                              _selectedOption = null;
                              _showExplanation = false;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primaryIndigo,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Next Question', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    const primaryIndigo = Color(0xFF4F46E5);
    return ChoiceChip(
      label: Text(label, style: TextStyle(color: isSelected ? Colors.white : primaryIndigo, fontWeight: FontWeight.bold, fontSize: 12)),
      selected: isSelected,
      selectedColor: primaryIndigo,
      backgroundColor: const Color(0xFFEEF2FF),
      onSelected: (_) => onTap(),
    );
  }
}
