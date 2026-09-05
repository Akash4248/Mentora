import 'package:flutter/material.dart';
import '../../network/services/mentora_backend_client.dart';

class ChapterLearningWorkspaceScreen extends StatefulWidget {
  final String chapterTitle;

  const ChapterLearningWorkspaceScreen({
    Key? key,
    this.chapterTitle = 'Motion',
  }) : super(key: key);

  @override
  State<ChapterLearningWorkspaceScreen> createState() => _ChapterLearningWorkspaceScreenState();
}

class _ChapterLearningWorkspaceScreenState extends State<ChapterLearningWorkspaceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _chatController = TextEditingController();
  final MentoraBackendClient _client = MentoraBackendClient();

  // Tab 1 state
  bool _isSending = false;
  final List<Map<String, dynamic>> _messages = [
    {
      'isUser': false,
      'text': 'Hello Rahul! 👋 Welcome to Chapter 8: Motion.\n\nIn NCERT Class 9 Physics, motion is defined as a change in position of an object with time. Key equations of motion:\n\n• First Equation: v = u + at\n• Second Equation: s = ut + ½at²\n• Third Equation: v² = u² + 2as',
      'formulas': ['v = u + at', 's = ut + ½at²', 'v² = u² + 2as'],
      'hasAudio': true,
    },
    {
      'isUser': true,
      'text': 'What is the difference between speed and velocity?',
    },
    {
      'isUser': false,
      'text': 'Great question! Here is the simple distinction:\n\n• Speed is a scalar quantity (has magnitude only, e.g., 50 km/h).\n• Velocity is a vector quantity (has both magnitude and direction, e.g., 50 km/h North).\n\nFormula: Velocity = Displacement / Time',
      'formulas': ['Velocity = Displacement / Time'],
      'hasAudio': true,
    },
  ];

  // Tab 2 Simulation state
  Map<String, dynamic>? _simData;
  double _simLength = 2.0;
  double _simGravity = 9.8;
  bool _simIsPlaying = true;

  // Tab 3 Video state
  Map<String, dynamic>? _videoData;
  bool _islEnabled = false;

  // Tab 4 Quiz state
  Map<String, dynamic>? _quizData;
  int _currentQuestionIndex = 0;
  int? _selectedOptionIndex;
  bool _showExplanation = false;
  int _score = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadTabResources();
  }

  Future<void> _loadTabResources() async {
    final sim = await _client.getSimulationForChapter(widget.chapterTitle);
    final video = await _client.getVideoLecturesForChapter(widget.chapterTitle);
    final quiz = await _client.getQuizForChapter(widget.chapterTitle);

    if (mounted) {
      setState(() {
        _simData = sim;
        _videoData = video;
        _quizData = quiz;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({'isUser': true, 'text': text});
      _chatController.clear();
      _isSending = true;
    });

    final reply = await _client.queryAiTutor(
      question: text,
      topic: widget.chapterTitle,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        _messages.add({
          'isUser': false,
          'text': reply['answer'] ?? reply['response'] ?? 'I have analyzed your query from the NCERT curriculum.',
          'formulas': List<String>.from(reply['formulas'] ?? ['v = u + at']),
          'hasAudio': true,
        });
      });
    }
  }

  void _showExplainDifferentlySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('💡 How would you like me to explain this?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              _buildExplainOption(Icons.directions_car, 'Use a Real-World Analogy', 'Car on a highway example'),
              _buildExplainOption(Icons.child_care, 'Simplify the Language', 'Easier words for younger readers'),
              _buildExplainOption(Icons.format_list_numbered, 'Show Step-by-Step Math', 'Detailed formula breakdown'),
              _buildExplainOption(Icons.science, 'Suggest a Visual Simulation', 'Opens interactive pendulum lab'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExplainOption(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: const CircleAvatar(backgroundColor: Color(0xFFEEF2FF), child: Icon(Icons.lightbulb, color: Color(0xFF4F46E5), size: 20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      onTap: () {
        Navigator.pop(context);
        _sendMessageWithTopic('Explain "$title" for ${widget.chapterTitle}');
      },
    );
  }

  Future<void> _sendMessageWithTopic(String text) async {
    setState(() {
      _messages.add({'isUser': true, 'text': text});
      _isSending = true;
    });

    final reply = await _client.queryAiTutor(
      question: text,
      topic: widget.chapterTitle,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        _messages.add({
          'isUser': false,
          'text': reply['answer'] ?? reply['response'] ?? 'Here is a simplified explanation with step-by-step breakdown.',
          'formulas': List<String>.from(reply['formulas'] ?? ['v = u + at']),
          'hasAudio': true,
        });
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
            Text('Grade 9 Physics > ${widget.chapterTitle}', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
            const Text('NCERT Class 9 Chapter 8', style: TextStyle(color: Color(0xFF64748B), fontSize: 11)),
          ],
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: primaryIndigo,
          unselectedLabelColor: const Color(0xFF64748B),
          indicatorColor: primaryIndigo,
          tabs: const [
            Tab(text: '💬 Chat'),
            Tab(text: '🔬 Simulation'),
            Tab(text: '🎥 Watch'),
            Tab(text: '📝 Quiz'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // TAB 1: CHAT WORKSPACE
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    final bool isUser = msg['isUser'] as bool;

                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                        decoration: BoxDecoration(
                          color: isUser ? primaryIndigo : cardBg,
                          borderRadius: BorderRadius.circular(14),
                          border: isUser ? null : Border.all(color: borderColor),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg['text'] as String,
                              style: TextStyle(color: isUser ? Colors.white : const Color(0xFF0F172A), fontSize: 14, height: 1.4),
                            ),
                            if (!isUser && msg['formulas'] != null) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                children: (msg['formulas'] as List<String>).map((formula) {
                                  return Chip(
                                    label: Text(formula, style: const TextStyle(color: primaryIndigo, fontWeight: FontWeight.bold, fontSize: 11)),
                                    backgroundColor: const Color(0xFFEEF2FF),
                                  );
                                }).toList(),
                              ),
                            ],
                            if (!isUser) ...[
                              const Divider(height: 16, color: borderColor),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: () {},
                                    icon: const Icon(Icons.volume_up_outlined, size: 14, color: primaryIndigo),
                                    label: const Text('Read Aloud', style: TextStyle(color: primaryIndigo, fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 4),
                                  TextButton.icon(
                                    onPressed: _showExplainDifferentlySheet,
                                    icon: const Icon(Icons.lightbulb_outline, size: 14, color: Color(0xFFF59E0B)),
                                    label: const Text('Explain Differently', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_isSending)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: primaryIndigo)),
                      SizedBox(width: 8),
                      Text('Mentora Socratic AI is thinking...', style: TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                    ],
                  ),
                ),
              // INPUT BAR
              Container(
                padding: const EdgeInsets.all(12),
                color: cardBg,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.mic, color: primaryIndigo),
                      onPressed: () {
                        Navigator.pushNamed(context, '/voice_overlay');
                      },
                    ),
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Ask anything about ${widget.chapterTitle}...',
                          filled: true,
                          fillColor: slateBg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    CircleAvatar(
                      backgroundColor: primaryIndigo,
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 18),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // TAB 2: INTERACTIVE SIMULATION PLAYER (STITCH DESIGN)
          _buildSimulationTab(),

          // TAB 3: YOUTUBE VIDEO LECTURE WATCH SCREEN (STITCH DESIGN)
          _buildWatchTab(),

          // TAB 4: DIAGNOSTIC ASSESSMENT QUIZ (STITCH DESIGN)
          _buildQuizTab(),
        ],
      ),
    );
  }

  // STITCH TAB 2: INTERACTIVE HTML5 SIMULATION PLAYER
  Widget _buildSimulationTab() {
    const primaryIndigo = Color(0xFF4F46E5);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SIMULATION CANVAS VIEWPORT
          Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(_simIsPlaying ? Icons.science : Icons.pause_circle_filled, size: 48, color: const Color(0xFF8B5CF6)),
                      const SizedBox(height: 8),
                      Text(
                        _simData?['title'] ?? 'Interactive Pendulum Lab',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Period T = ${(2 * 3.14159 * ( _simLength / _simGravity ).clamp(0.1, 10.0)).toStringAsFixed(2)}s',
                        style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    icon: Icon(_simIsPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white),
                    onPressed: () => setState(() => _simIsPlaying = !_simIsPlaying),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // PARAMETER SLIDERS CARD
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8F0))),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('⚙️ Simulation Controls', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 16),

                  // Slider 1: Length
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Length (L): ${_simLength.toStringAsFixed(1)} m', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Chip(
                        label: Text('${_simLength.toStringAsFixed(1)} m', style: const TextStyle(color: primaryIndigo, fontWeight: FontWeight.bold, fontSize: 11)),
                        backgroundColor: const Color(0xFFEEF2FF),
                      ),
                    ],
                  ),
                  Slider(
                    value: _simLength,
                    min: 0.5,
                    max: 5.0,
                    divisions: 45,
                    activeColor: primaryIndigo,
                    onChanged: (val) => setState(() => _simLength = val),
                  ),
                  const SizedBox(height: 10),

                  // Slider 2: Gravity
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Gravity (g): ${_simGravity.toStringAsFixed(1)} m/s²', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Chip(
                        label: Text('${_simGravity.toStringAsFixed(1)} m/s²', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                        backgroundColor: const Color(0xFFECFDF5),
                      ),
                    ],
                  ),
                  Slider(
                    value: _simGravity,
                    min: 1.6,
                    max: 24.8,
                    divisions: 232,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (val) => setState(() => _simGravity = val),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // STITCH TAB 3: YOUTUBE VIDEO LECTURE WATCH SCREEN
  Widget _buildWatchTab() {
    const primaryIndigo = Color(0xFF4F46E5);
    final playlist = List<Map<String, dynamic>>.from(_videoData?['playlist'] ?? []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // EMBEDDED YOUTUBE VIDEO CARD
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 200,
              width: double.infinity,
              color: const Color(0xFF0F172A),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.network(
                      'https://img.youtube.com/vi/tBmavvMwu68/hqdefault.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.video_library_outlined, size: 48, color: Color(0xFF8B5CF6)),
                          ),
                        );
                      },
                    ),
                  ),
                  Center(
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: primaryIndigo,
                      child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // TITLE & ISL TOGGLE ROW
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'NCERT Class 9 Physics: Motion & Velocity',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                ),
              ),
              FilterChip(
                label: Text('ISL Track', style: TextStyle(color: _islEnabled ? Colors.white : primaryIndigo, fontWeight: FontWeight.bold, fontSize: 11)),
                selected: _islEnabled,
                selectedColor: primaryIndigo,
                backgroundColor: const Color(0xFFEEF2FF),
                onSelected: (val) => setState(() => _islEnabled = val),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // PLAYLIST SECTION
          const Text('📚 Playlist Chapters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          ...playlist.map((item) {
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFE2E8F0))),
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: Color(0xFFEEF2FF), child: Icon(Icons.play_circle_fill, color: primaryIndigo, size: 20)),
                title: Text(item['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                trailing: Text(item['duration'] as String, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  // STITCH TAB 4: DIAGNOSTIC ASSESSMENT QUIZ
  Widget _buildQuizTab() {
    const primaryIndigo = Color(0xFF4F46E5);
    final questions = List<Map<String, dynamic>>.from(_quizData?['questions'] ?? []);
    if (questions.isEmpty) return const Center(child: CircularProgressIndicator());

    final currentQ = questions[_currentQuestionIndex];
    final options = List<String>.from(currentQ['options']);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PROGRESS HEADER BAR
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Question ${_currentQuestionIndex + 1} of ${questions.length}', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 13)),
              Chip(
                label: Text('${_quizData?['userMastery'] ?? 85}% Mastered', style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 11)),
                backgroundColor: const Color(0xFFECFDF5),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // QUESTION CARD
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFFE2E8F0))),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                currentQ['question'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A), height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // MCQ OPTIONS
          ...List.generate(options.length, (idx) {
            final isSelected = _selectedOptionIndex == idx;
            final isCorrect = currentQ['correctIndex'] == idx;

            Color optionBg = Colors.white;
            Color optionBorder = const Color(0xFFE2E8F0);
            if (_showExplanation) {
              if (isCorrect) {
                optionBg = const Color(0xFFECFDF5);
                optionBorder = const Color(0xFF10B981);
              } else if (isSelected) {
                optionBg = const Color(0xFFFEF2F2);
                optionBorder = const Color(0xFFEF4444);
              }
            } else if (isSelected) {
              optionBg = const Color(0xFFEEF2FF);
              optionBorder = primaryIndigo;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: optionBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: optionBorder, width: isSelected ? 1.5 : 1.0),
              ),
              child: ListTile(
                onTap: () {
                  if (!_showExplanation) {
                    setState(() => _selectedOptionIndex = idx);
                  }
                },
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: isSelected ? primaryIndigo : const Color(0xFFF1F5F9),
                  child: Text(String.fromCharCode(65 + idx), style: TextStyle(color: isSelected ? Colors.white : const Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold)),
                ),
                title: Text(options[idx], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ),
            );
          }),

          const SizedBox(height: 16),
          if (!_showExplanation && _selectedOptionIndex != null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _showExplanation = true;
                    if (_selectedOptionIndex == currentQ['correctIndex']) {
                      _score++;
                    }
                  });
                },
                style: ElevatedButton.styleFrom(backgroundColor: primaryIndigo, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Submit Answer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),

          if (_showExplanation) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFCBD5E1))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💡 Explanation:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(currentQ['explanation'] as String, style: const TextStyle(fontSize: 13, color: Color(0xFF334155))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  setState(() {
                    _currentQuestionIndex = (_currentQuestionIndex + 1) % questions.length;
                    _selectedOptionIndex = null;
                    _showExplanation = false;
                  });
                },
                style: ElevatedButton.styleFrom(backgroundColor: primaryIndigo, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('Next Question', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
