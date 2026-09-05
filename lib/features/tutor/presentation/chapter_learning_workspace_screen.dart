import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
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
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('Regenerate Explanation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExplainOption(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: const Color(0xFFEEF2FF), child: Icon(icon, color: const Color(0xFF4F46E5), size: 20)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
      onTap: () => Navigator.pop(context),
    );
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
                        decoration: InputDecoration(
                          hintText: 'Ask anything about Motion...',
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
                        onPressed: () {
                          if (_chatController.text.trim().isNotEmpty) {
                            setState(() {
                              _messages.add({'isUser': true, 'text': _chatController.text.trim()});
                              _chatController.clear();
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // TAB 2: SIMULATION PLACEHOLDER
          const Center(child: Text('Interactive HTML5 Simulation View (Phase 3)')),
          // TAB 3: WATCH PLACEHOLDER
          const Center(child: Text('YouTube NCERT Video Player View (Phase 4)')),
          // TAB 4: QUIZ PLACEHOLDER
          const Center(child: Text('NCERT Diagnostic Quiz View (Phase 6)')),
        ],
      ),
    );
  }
}
