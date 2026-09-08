import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../core/theme/idp_colors.dart';
import '../../../core/theme/idp_typography.dart';
import '../../educational/data/educational_repository.dart';
import '../../educational/models/educational_models.dart';

class ChapterFlashcardsScreen extends StatefulWidget {
  final int chapterId;
  final String chapterTitle;
  final String subjectName;
  final int grade;

  const ChapterFlashcardsScreen({
    super.key,
    required this.chapterId,
    required this.chapterTitle,
    required this.subjectName,
    required this.grade,
  });

  @override
  State<ChapterFlashcardsScreen> createState() => _ChapterFlashcardsScreenState();
}

class _ChapterFlashcardsScreenState extends State<ChapterFlashcardsScreen> {
  List<FlashcardModel> _cards = [];
  bool _isLoading = true;
  int _currentIndex = 0;
  bool _isFlipped = false;

  @override
  void initState() {
    super.initState();
    _loadFlashcardsFromDb();
  }

  Future<void> _loadFlashcardsFromDb() async {
    setState(() => _isLoading = true);
    var list = await EducationalRepository.getFlashcardsByChapterId(widget.chapterId);
    if (list.isEmpty) {
      list = await EducationalRepository.getFlashcardsByChapterTitle(widget.chapterTitle);
    }
    if (mounted) {
      setState(() {
        _cards = list;
        _isLoading = false;
      });
    }
  }

  void _flipCard() {
    setState(() {
      _isFlipped = !_isFlipped;
    });
  }

  void _nextCard() {
    if (_currentIndex < _cards.length - 1) {
      setState(() {
        _currentIndex++;
        _isFlipped = false;
      });
    }
  }

  void _previousCard() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _isFlipped = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.subjectName} • ${widget.chapterTitle}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
            ),
            Text(
              'Class ${widget.grade} NCERT Flashcards Deck',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF4F46E5),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF4F46E5)))
            : _cards.isEmpty
                ? _buildEmptyState()
                : Column(
                    children: [
                      // PROGRESS COUNTER BANNER
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Card ${_currentIndex + 1} of ${_cards.length}',
                              style: IDPTypography.titleSmall.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF4F46E5),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                'Backend Synced Data',
                                style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // FLIP CARD VIEWPORT
                      Expanded(
                        child: Center(
                          child: GestureDetector(
                            onTap: _flipCard,
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 300),
                              transitionBuilder: (child, anim) {
                                final rotate = Tween(begin: math.pi, end: 0.0).animate(anim);
                                return AnimatedBuilder(
                                  animation: rotate,
                                  child: child,
                                  builder: (context, child) {
                                    final isBack = child!.key == const ValueKey(true);
                                    final value = isBack ? math.min(rotate.value, math.pi / 2) : rotate.value;
                                    return Transform(
                                      transform: Matrix4.rotationY(value),
                                      alignment: Alignment.center,
                                      child: child,
                                    );
                                  },
                                );
                              },
                              child: _isFlipped
                                  ? _buildCardSide(
                                      key: const ValueKey(true),
                                      title: 'DEFINITION / CONCEPT',
                                      body: _cards[_currentIndex].definition,
                                      color: const Color(0xFF1E1B4B),
                                      accentColor: const Color(0xFF38BDF8),
                                      isDark: isDark,
                                    )
                                  : _buildCardSide(
                                      key: const ValueKey(false),
                                      title: 'TERM / KEYWORD',
                                      body: _cards[_currentIndex].term,
                                      color: const Color(0xFF4F46E5),
                                      accentColor: Colors.white,
                                      isDark: isDark,
                                    ),
                            ),
                          ),
                        ),
                      ),

                      // NAVIGATION CONTROLS
                      Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text('Previous'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                foregroundColor: isDark ? Colors.white : Colors.black87,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _currentIndex > 0 ? _previousCard : null,
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.swap_horiz_rounded),
                              label: const Text('Flip Card'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4F46E5),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _flipCard,
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.arrow_forward_rounded),
                              label: const Text('Next'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                                foregroundColor: isDark ? Colors.white : Colors.black87,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: _currentIndex < _cards.length - 1 ? _nextCard : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _buildCardSide({
    required Key key,
    required String title,
    required String body,
    required Color color,
    required Color accentColor,
    required bool isDark,
  }) {
    return Container(
      key: key,
      width: 320,
      height: 380,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: accentColor.withValues(alpha: 0.8),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 1.2,
                ),
              ),
              Icon(Icons.touch_app_rounded, color: accentColor.withValues(alpha: 0.8), size: 20),
            ],
          ),
          Center(
            child: Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22,
                height: 1.4,
              ),
            ),
          ),
          Center(
            child: Text(
              'Tap card to flip',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.style_rounded, size: 64, color: Color(0xFF818CF8)),
            const SizedBox(height: 16),
            Text(
              'No Backend Flashcards Synced Yet',
              style: IDPTypography.titleSmall.copyWith(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              'Flashcard terms for "${widget.chapterTitle}" will automatically populate once the official Grade ${widget.grade} content pack is downloaded from the backend server.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: IDPColors.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.sync_rounded),
              label: const Text('Check Content Pack Sync'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _loadFlashcardsFromDb,
            ),
          ],
        ),
      ),
    );
  }
}
