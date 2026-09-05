import 'package:flutter/material.dart';
import '../../network/services/mentora_backend_client.dart';

class SubjectChaptersScreen extends StatefulWidget {
  final String subjectName;

  const SubjectChaptersScreen({
    Key? key,
    this.subjectName = 'Physics',
  }) : super(key: key);

  @override
  State<SubjectChaptersScreen> createState() => _SubjectChaptersScreenState();
}

class _SubjectChaptersScreenState extends State<SubjectChaptersScreen> {
  final MentoraBackendClient _client = MentoraBackendClient();
  List<Map<String, dynamic>> _chapters = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChapters();
  }

  Future<void> _loadChapters() async {
    setState(() => _isLoading = true);
    final data = await _client.getChaptersForSubject(widget.subjectName);
    setState(() {
      _chapters = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    const primaryIndigo = Color(0xFF4F46E5);
    const slateBg = Color(0xFFF8FAFC);
    const cardBg = Color(0xFFFFFFFF);
    const borderColor = Color(0xFFE2E8F0);

    final int overallMastery = _chapters.isEmpty
        ? 0
        : (_chapters.fold<int>(0, (sum, ch) => sum + ((ch['mastery'] as num?)?.toInt() ?? 0)) / _chapters.length).round();

    return Scaffold(
      backgroundColor: slateBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0.5,
        title: Text(
          'Grade 9 ${widget.subjectName}',
          style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFA7F3D0)),
            ),
            child: Center(
              child: Text(
                '$overallMastery% Mastered',
                style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryIndigo))
          : RefreshIndicator(
              onRefresh: _loadChapters,
              child: ListView.builder(
                padding: const EdgeInsets.all(16.0),
                itemCount: _chapters.length,
                itemBuilder: (context, index) {
                  final ch = _chapters[index];
                  final bool isCompleted = ch['status'] == 'completed';
                  final bool isInProgress = ch['status'] == 'in_progress';

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 12),
                    color: cardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isInProgress ? primaryIndigo : borderColor,
                        width: isInProgress ? 1.5 : 1.0,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.pushNamed(context, '/chapter_workspace', arguments: ch['title']);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isCompleted
                                        ? const Color(0xFF10B981)
                                        : (isInProgress ? primaryIndigo : const Color(0xFF94A3B8)),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: isCompleted
                                        ? const Icon(Icons.check, color: Colors.white, size: 18)
                                        : Text(
                                            '${ch['number']}',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Chapter ${ch['number']}',
                                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11, fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        ch['title'] as String,
                                        style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 15),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isInProgress ? Icons.play_circle_fill : Icons.chevron_right,
                                  color: isInProgress ? primaryIndigo : const Color(0xFF94A3B8),
                                  size: 24,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.schedule, size: 14, color: Color(0xFF64748B)),
                                    const SizedBox(width: 4),
                                    Text((ch['duration'] ?? '20 mins').toString(), style: const TextStyle(color: Color(0xFF64748B), fontSize: 12)),
                                  ],
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    reverse: true,
                                    child: Row(
                                      children: [
                                        _buildActionPill('Chat', Icons.chat_bubble_outline, primaryIndigo),
                                        const SizedBox(width: 4),
                                        _buildActionPill('Sims', Icons.science_outlined, const Color(0xFF10B981)),
                                        const SizedBox(width: 4),
                                        _buildActionPill('Watch', Icons.play_arrow_outlined, const Color(0xFFF59E0B)),
                                        const SizedBox(width: 4),
                                        _buildActionPill('Quiz', Icons.quiz_outlined, const Color(0xFF8B5CF6)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }

  Widget _buildActionPill(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
