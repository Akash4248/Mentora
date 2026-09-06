import 'package:flutter/material.dart';
import '../../network/services/mentora_backend_client.dart';
import '../../chat/presentation/formatted_text_widget.dart';
import '../../home/presentation/video_player_screen.dart';
import '../../home/data/local/video_resource_repository.dart';

class ChapterLearningWorkspaceScreen extends StatefulWidget {
  final String chapterTitle;
  final String subjectName;
  final int grade;

  const ChapterLearningWorkspaceScreen({
    Key? key,
    this.chapterTitle = 'Motion',
    this.subjectName = 'Science',
    this.grade = 9,
  }) : super(key: key);

  @override
  State<ChapterLearningWorkspaceScreen> createState() => _ChapterLearningWorkspaceScreenState();
}

class _ChapterLearningWorkspaceScreenState extends State<ChapterLearningWorkspaceScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _chatController = TextEditingController();
  final MentoraBackendClient _client = MentoraBackendClient();

  String _activeChapterTitle = 'Motion';
  String _activeSubjectName = 'Science';
  int _activeGrade = 9;
  bool _argsResolved = false;

  // Tab 1 state
  bool _isSending = false;
  final List<Map<String, dynamic>> _messages = [];

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_argsResolved) {
      _argsResolved = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _activeChapterTitle = args['chapterTitle']?.toString() ?? widget.chapterTitle;
        _activeSubjectName = args['subjectName']?.toString() ?? args['subject']?.toString() ?? widget.subjectName;
        _activeGrade = (args['grade'] as num?)?.toInt() ?? widget.grade;
      } else if (args is String) {
        _activeChapterTitle = args;
        _activeSubjectName = widget.subjectName;
        _activeGrade = widget.grade;
      } else {
        _activeChapterTitle = widget.chapterTitle;
        _activeSubjectName = widget.subjectName;
        _activeGrade = widget.grade;
      }

      _messages.clear();
      _messages.add({
        'isUser': false,
        'text': 'Welcome to Grade $_activeGrade $_activeSubjectName: *$_activeChapterTitle*! 👋\n\nI am your Mentora Socratic AI Tutor. Ask me any question or concept related to *$_activeChapterTitle* to begin learning.',
        'formulas': <String>[],
        'hasAudio': false,
      });

      _loadTabResources();
    }
  }

  Future<void> _loadTabResources() async {
    print('[VIDEO_DEBUG] Workspace: Loading resources for chapter: "$_activeChapterTitle" (Grade $_activeGrade $_activeSubjectName)');
    final sim = await _client.getSimulationForChapter(_activeChapterTitle);
    final video = await _client.getVideoLecturesForChapter(_activeChapterTitle);
    final quiz = await _client.getQuizForChapter(_activeChapterTitle);

    List<Map<String, dynamic>> playlistItems = [];
    try {
      final localRepo = VideoResourceRepository();
      final localVideos = await localRepo.getVideosForChapter(_activeChapterTitle);
      print('[VIDEO_DEBUG] Workspace: Found ${localVideos.length} local SQLite videos for "$_activeChapterTitle"');
      if (localVideos.isNotEmpty) {
        playlistItems = localVideos.map((v) => {
          'id': v.videoId,
          'youtubeId': v.videoId,
          'videoUrl': v.videoUrl,
          'title': v.videoTitle,
          'channel': v.channelName,
          'duration': '${(v.durationSeconds / 60).round()}:00',
          'description': v.description,
        }).toList();
      }
    } catch (e) {
      print('[VIDEO_DEBUG] Workspace: Error querying VideoResourceRepository: $e');
    }

    if (mounted) {
      setState(() {
        _simData = sim;
        _quizData = quiz;
        if (playlistItems.isNotEmpty) {
          _videoData = {
            'chapter': _activeChapterTitle,
            'currentVideo': playlistItems.first,
            'playlist': playlistItems,
            'islAvailable': true,
          };
        } else {
          _videoData = video;
        }
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
      topic: _activeChapterTitle,
      grade: _activeGrade,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        _messages.add({
          'isUser': false,
          'text': reply['answer'] ?? reply['response'] ?? 'I have analyzed your query from the NCERT curriculum.',
          'formulas': List<String>.from(reply['formulas'] ?? <String>[]),
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
              _buildExplainOption(Icons.directions_car, 'Use a Real-World Analogy', 'Practical daily life example'),
              _buildExplainOption(Icons.child_care, 'Simplify the Language', 'Easier words for younger readers'),
              _buildExplainOption(Icons.format_list_numbered, 'Show Step-by-Step Math', 'Detailed breakdown'),
              _buildExplainOption(Icons.science, 'Suggest a Visual Simulation', 'Opens interactive lab'),
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
        String prompt = 'Please explain $_activeChapterTitle in clear detail.';
        if (title.contains('Analogy')) {
          prompt = 'Please explain $_activeChapterTitle using a practical real-world daily life example or analogy.';
        } else if (title.contains('Simplify')) {
          prompt = 'Please simplify the core concepts and equations of $_activeChapterTitle for a school student.';
        } else if (title.contains('Step-by-Step')) {
          prompt = 'Please show a clear, step-by-step mathematical breakdown and key formulas for $_activeChapterTitle.';
        } else if (title.contains('Visual')) {
          prompt = 'Please describe an interactive visual experiment or simulation to understand $_activeChapterTitle.';
        }
        _sendMessageWithTopic(prompt);
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
      topic: _activeChapterTitle,
      grade: _activeGrade,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        _messages.add({
          'isUser': false,
          'text': reply['answer'] ?? reply['response'] ?? 'Here is a simplified explanation with step-by-step breakdown.',
          'formulas': List<String>.from(reply['formulas'] ?? <String>[]),
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
            Text('Grade $_activeGrade $_activeSubjectName > $_activeChapterTitle', style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 16)),
            Text('NCERT Class $_activeGrade $_activeSubjectName', style: const TextStyle(color: Color(0xFF64748B), fontSize: 11)),
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
                            isUser
                                ? Text(
                                    msg['text'] as String,
                                    style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.4),
                                  )
                                : FormattedTextWidget(
                                    text: msg['text'] as String,
                                    style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14, height: 1.4),
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
                          hintText: 'Ask anything about $_activeChapterTitle...',
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
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(_simIsPlaying ? Icons.science : Icons.pause_circle_filled, size: 48, color: const Color(0xFF8B5CF6)),
                        const SizedBox(height: 8),
                        Text(
                          _simData?['title'] ?? 'Interactive $_activeChapterTitle Lab',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _simData?['description'] ?? 'Adjust key parameters to observe principles of $_activeChapterTitle',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.w500, fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
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

                  // Slider 1: Intensity / Parameter 1
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Intensity (I): ${_simLength.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Chip(
                        label: Text('${_simLength.toStringAsFixed(1)} units', style: const TextStyle(color: primaryIndigo, fontWeight: FontWeight.bold, fontSize: 11)),
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

                  // Slider 2: Factor / Parameter 2
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Environmental Factor (k): ${_simGravity.toStringAsFixed(1)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      Chip(
                        label: Text('${_simGravity.toStringAsFixed(1)} const', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                        backgroundColor: const Color(0xFFECFDF5),
                      ),
                    ],
                  ),
                  Slider(
                    value: _simGravity.clamp(1.0, 10.0),
                    min: 1.0,
                    max: 10.0,
                    divisions: 90,
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
    final currentVideo = _videoData?['currentVideo'] as Map<String, dynamic>?;

    final heroTitle = currentVideo?['title']?.toString() ?? 'NCERT Class $_activeGrade $_activeSubjectName: $_activeChapterTitle';
    final heroUrl = currentVideo?['videoUrl']?.toString() ?? currentVideo?['youtubeId']?.toString() ?? 'https://www.youtube.com/watch?v=tBmavvMwu68';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // EMBEDDED YOUTUBE VIDEO CARD (CLICKABLE)
          InkWell(
            onTap: () {
              print('[VIDEO_DEBUG] Tapped Workspace Hero Video Card. Launching VideoPlayerScreen with title "$heroTitle", URL "$heroUrl"');
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => VideoPlayerScreen(
                    videoUrl: heroUrl,
                    title: heroTitle,
                    subtitle: 'NCERT Class $_activeGrade $_activeSubjectName • $_activeChapterTitle',
                    description: currentVideo?['description']?.toString(),
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircleAvatar(
                            radius: 28,
                            backgroundColor: primaryIndigo,
                            child: Icon(Icons.play_arrow, color: Colors.white, size: 36),
                          ),
                          const SizedBox(height: 10),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Text(
                              heroTitle,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '▶ Tap to launch full screen player',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // TITLE & ISL TOGGLE ROW
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'NCERT Class $_activeGrade $_activeSubjectName: $_activeChapterTitle',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
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
            final itemTitle = item['title']?.toString() ?? 'Video Chapter';
            final itemUrl = item['videoUrl']?.toString() ?? item['youtubeId']?.toString() ?? 'https://www.youtube.com/watch?v=tBmavvMwu68';
            final itemDuration = item['duration']?.toString() ?? '10:00';
            final itemChannel = item['channel']?.toString() ?? 'NCERT';

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Color(0xFFE2E8F0))),
              child: ListTile(
                onTap: () {
                  print('[VIDEO_DEBUG] Tapped Workspace Playlist Item "$itemTitle". Launching VideoPlayerScreen with URL "$itemUrl"');
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => VideoPlayerScreen(
                        videoUrl: itemUrl,
                        title: itemTitle,
                        subtitle: '$itemChannel • Grade $_activeGrade $_activeChapterTitle',
                        description: item['description']?.toString(),
                      ),
                    ),
                  );
                },
                leading: const CircleAvatar(backgroundColor: Color(0xFFEEF2FF), child: Icon(Icons.play_circle_fill, color: primaryIndigo, size: 20)),
                title: Text(itemTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(itemChannel, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                trailing: Text(itemDuration, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
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
              Text('Question ${_currentQuestionIndex + 1} of ${questions.length} • Score: $_score', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF64748B), fontSize: 13)),
              Chip(
                label: Text('${_quizData?['userMastery'] ?? 0}% Mastered', style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 11)),
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
