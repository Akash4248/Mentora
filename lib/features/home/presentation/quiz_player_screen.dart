import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../course/domain/curriculum_models.dart';
import '../../assessment/data/local/quiz_result_repository.dart';
import '../../assessment/domain/quiz_result.dart';


import '../../../core/theme/idp_theme.dart';
import '../../network/services/mentora_backend_client.dart';


class QuizQuestion {
  QuizQuestion({
    required this.question,
    required this.correctAnswer,
    required this.options,
    required this.correctIndex,
  });

  final String question;
  final String correctAnswer;
  final List<String> options;
  final int correctIndex;
}

class QuizPlayerScreen extends StatefulWidget {
  const QuizPlayerScreen({
    required this.chapter,
    super.key,
  });

  final CurriculumChapter chapter;

  @override
  State<QuizPlayerScreen> createState() => _QuizPlayerScreenState();
}

class _QuizPlayerScreenState extends State<QuizPlayerScreen> {
  final QuizResultRepository _quizRepo = QuizResultRepository();
  bool _loading = true;
  String? _error;
  
  List<QuizQuestion> _questions = [];
  int _currentIndex = 0;
  int? _selectedOptionIndex;
  bool _checked = false;
  int _score = 0;
  Map<int, int> _answers = {}; // questionIndex -> selectedIndex
  
  final Set<int> _reviewLaterIndices = {};
  int? _confidenceLevel; // 1: Low, 2: Medium, 3: High
  
  bool _quizFinished = false;

  @override
  void initState() {
    super.initState();
    _loadQuiz();
  }

  Future<void> _loadQuiz() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final List<QuizQuestion> parsedQuestions = [];

      // 1. Try local content pack quizzes.json
      if (widget.chapter.rootPath.isNotEmpty) {
        final quizPath = p.join(widget.chapter.rootPath, 'quizzes.json');
        final file = File(quizPath);
        if (await file.exists()) {
          final content = await file.readAsString();
          final List<dynamic> decoded = jsonDecode(content);
          final random = Random();

          for (final item in decoded) {
            if (item is Map) {
              final mapItem = Map<String, dynamic>.from(item);
              final question = mapItem['question'] as String? ?? '';
              final correct = (mapItem['correct_answer'] ?? mapItem['answer'] ?? '') as String;
              if (question.isNotEmpty && correct.isNotEmpty) {
                final List<String> options = List<String>.from(mapItem['options'] ?? [correct]);
                if (options.length < 4) {
                  options.addAll(['None of the above', 'All of the above', 'Not applicable'].where((o) => !options.contains(o)));
                }
                options.shuffle(random);
                final correctIndex = options.indexOf(correct);

                parsedQuestions.add(QuizQuestion(
                  question: question,
                  correctAnswer: mapItem['explanation'] as String? ?? correct,
                  options: options,
                  correctIndex: correctIndex >= 0 ? correctIndex : 0,
                ));
              }
            }
          }
        }
      }

      // 2. Fetch directly from backend API /quizzes/{chapter}
      if (parsedQuestions.isEmpty) {
        final backendQuiz = await MentoraBackendClient().getQuizForChapter(widget.chapter.title);
        final qList = backendQuiz['questions'] as List? ?? [];
        for (final item in qList) {
          if (item is Map) {
            final mapItem = Map<String, dynamic>.from(item);
            final opts = List<String>.from(mapItem['options'] ?? []);
            final cIdx = (mapItem['correctIndex'] as num?)?.toInt() ?? 0;
            final correctStr = cIdx < opts.length ? opts[cIdx] : '';
            parsedQuestions.add(QuizQuestion(
              question: mapItem['question'] as String? ?? 'Question',
              correctAnswer: mapItem['explanation'] as String? ?? correctStr,
              options: opts,
              correctIndex: cIdx,
            ));
          }
        }
      }

      if (mounted) {
        setState(() {
          _questions = parsedQuestions;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load quizzes: $e';
          _loading = false;
        });
      }
    }
  }

  void _selectOption(int index) {
    if (_checked) return;
    setState(() {
      _selectedOptionIndex = index;
    });
  }

  void _checkAnswer() {
    if (_selectedOptionIndex == null || _checked || _confidenceLevel == null) return;

    final q = _questions[_currentIndex];
    final isCorrect = _selectedOptionIndex == q.correctIndex;
    
    setState(() {
      _checked = true;
      _answers[_currentIndex] = _selectedOptionIndex!;
      if (isCorrect) {
        _score++;
      }
    });
  }

  void _nextQuestion() {
    if (_currentIndex < _questions.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOptionIndex = null;
        _checked = false;
        _confidenceLevel = null;
      });
    } else {
      _finishQuiz();
    }
  }

  void _toggleReviewLater() {
    setState(() {
      if (_reviewLaterIndices.contains(_currentIndex)) {
        _reviewLaterIndices.remove(_currentIndex);
      } else {
        _reviewLaterIndices.add(_currentIndex);
      }
    });
  }

  Future<void> _finishQuiz() async {
    // Save result to DB
    final result = QuizResult(
      chapterId: widget.chapter.packId,
      score: _score,
      totalQuestions: _questions.length,
      answers: _answers,
      attemptedAt: DateTime.now(),
    );
    await _quizRepo.saveResult(result);

    if (mounted) {
      setState(() {
        _quizFinished = true;
      });
    }
  }

  void _restartQuiz() {
    setState(() {
      _currentIndex = 0;
      _selectedOptionIndex = null;
      _checked = false;
      _score = 0;
      _answers = {};
      _quizFinished = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IDPColors.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: IDPColors.primary))
          : _error != null
              ? _buildErrorView()
              : _questions.isEmpty
                  ? _buildEmptyState()
                  : _quizFinished
                      ? _buildResultsView()
                      : _buildQuizPlayView(),
    );
  }

  Widget _buildQuizPlayView() {
    final q = _questions[_currentIndex];
    final progress = (_currentIndex + 1) / _questions.length;

    return Stack(
      children: [
        // Background Atmospheric Effect
        Positioned(
          top: -100,
          right: -100,
          child: Container(
            width: 500,
            height: 500,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: IDPColors.primary.withValues(alpha: 0.05),
            ),
          ),
        ),
        Positioned(
          bottom: -100,
          left: -100,
          child: Container(
            width: 400,
            height: 400,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: IDPColors.secondary.withValues(alpha: 0.05),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                color: IDPColors.surface.withValues(alpha: 0.8),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: IDPColors.surfaceContainerLow,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, color: IDPColors.textSecondary),
                          ),
                        ),
                        Column(
                          children: [
                            Text(
                              'Question ${_currentIndex + 1} of ${_questions.length}',
                              style: IDPTypography.labelMd.copyWith(color: IDPColors.textSecondary),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.star, size: 18, color: IDPColors.primary),
                                const SizedBox(width: 4),
                                Text(
                                  'Score: $_score',
                                  style: IDPTypography.titleMd.copyWith(color: IDPColors.primary),
                                ),
                              ],
                            ),
                          ],
                        ),
                        InkWell(
                          onTap: _toggleReviewLater,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: IDPColors.surfaceContainerLow,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _reviewLaterIndices.contains(_currentIndex) ? Icons.bookmark : Icons.bookmark_outline,
                              color: _reviewLaterIndices.contains(_currentIndex) ? IDPColors.primary : IDPColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Progress Bar
                    Container(
                      width: double.infinity,
                      height: 8,
                      decoration: BoxDecoration(
                        color: IDPColors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progress,
                        child: Container(
                          decoration: BoxDecoration(
                            color: IDPColors.secondary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Main Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Question Card
                      Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: IDPColors.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(color: IDPColors.outlineVariant.withValues(alpha: 0.3)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 20,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: IDPColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.bolt, size: 16, color: IDPColors.primary),
                                  const SizedBox(width: 8),
                                  Text(
                                    widget.chapter.title,
                                    style: IDPTypography.labelMd.copyWith(color: IDPColors.primary),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              q.question,
                              style: IDPTypography.headlineLgMobile,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      
                      // Options
                      ...List.generate(q.options.length, (index) {
                        final optionText = q.options[index];
                        final isSelected = _selectedOptionIndex == index;
                        final isCorrect = index == q.correctIndex;
                        
                        bool showAsSelected = isSelected;
                        Color bgColor = IDPColors.surfaceContainerLowest;
                        Color borderColor = IDPColors.outlineVariant;
                        Color indicatorBg = IDPColors.surfaceContainerHigh;
                        Color indicatorText = IDPColors.textSecondary;
                        
                        if (_checked) {
                          if (isCorrect) {
                            showAsSelected = true;
                            bgColor = IDPColors.secondaryContainer.withValues(alpha: 0.1);
                            borderColor = IDPColors.secondary;
                            indicatorBg = IDPColors.secondary;
                            indicatorText = IDPColors.onSecondary;
                          } else if (isSelected && !isCorrect) {
                            showAsSelected = true;
                            bgColor = IDPColors.errorLight.withValues(alpha: 0.1);
                            borderColor = IDPColors.error;
                            indicatorBg = IDPColors.error;
                            indicatorText = IDPColors.onError;
                          }
                        } else if (isSelected) {
                          bgColor = IDPColors.secondaryContainer.withValues(alpha: 0.1);
                          borderColor = IDPColors.secondary;
                          indicatorBg = IDPColors.secondary;
                          indicatorText = IDPColors.onSecondary;
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: InkWell(
                            onTap: () => _selectOption(index),
                            borderRadius: BorderRadius.circular(32),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(32),
                                border: Border.all(
                                  color: borderColor,
                                  width: showAsSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: indicatorBg,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        String.fromCharCode(65 + index),
                                        style: IDPTypography.bodyLg.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: indicatorText,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      optionText,
                                      style: IDPTypography.bodyLg.copyWith(
                                        fontWeight: showAsSelected ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  if (showAsSelected && _checked)
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: indicatorBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        isCorrect ? Icons.check : Icons.close,
                                        size: 16,
                                        color: indicatorText,
                                      ),
                                    )
                                  else if (showAsSelected)
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        color: indicatorBg,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.check,
                                        size: 16,
                                        color: indicatorText,
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 24,
                                      height: 24,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(color: IDPColors.outlineVariant, width: 2),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                      
                      const SizedBox(height: 16),
                      if (!_checked) ...[
                        if (_selectedOptionIndex != null) ...[
                          Text(
                            'How confident are you?',
                            style: IDPTypography.labelMd,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              _buildConfidenceButton(1, 'Low', Icons.sentiment_dissatisfied_rounded, Colors.orange),
                              const SizedBox(width: 8),
                              _buildConfidenceButton(2, 'Medium', Icons.sentiment_neutral_rounded, Colors.blue),
                              const SizedBox(width: 8),
                              _buildConfidenceButton(3, 'High', Icons.sentiment_very_satisfied_rounded, Colors.green),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: IDPColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: IDPColors.outlineVariant.withValues(alpha: 0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.lightbulb_outline, color: IDPColors.primary, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Explanation',
                                    style: IDPTypography.labelMd.copyWith(color: IDPColors.primary),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                q.correctAnswer,
                                style: IDPTypography.bodyMd,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
              ),
              
              // Footer Controls
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      IDPColors.surface,
                      IDPColors.surface.withValues(alpha: 0.95),
                      IDPColors.surface.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    if (!_checked)
                      InkWell(
                        onTap: (_selectedOptionIndex == null || _confidenceLevel == null) ? null : _checkAnswer,
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: (_selectedOptionIndex == null || _confidenceLevel == null)
                                ? null
                                : const LinearGradient(
                                    colors: [IDPColors.primary, IDPColors.primaryContainer],
                                  ),
                            color: (_selectedOptionIndex == null || _confidenceLevel == null)
                                ? IDPColors.surfaceContainerHigh
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Check Answer',
                                style: IDPTypography.titleMd.copyWith(
                                  color: (_selectedOptionIndex == null || _confidenceLevel == null)
                                      ? IDPColors.textHint
                                      : IDPColors.onPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      InkWell(
                        onTap: _nextQuestion,
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            gradient: const LinearGradient(
                              colors: [IDPColors.primary, IDPColors.primaryContainer],
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _currentIndex < _questions.length - 1 ? 'Next Question' : 'Finish Quiz',
                                style: IDPTypography.titleMd.copyWith(color: IDPColors.onPrimary),
                              ),
                              const SizedBox(width: 12),
                              const Icon(Icons.arrow_forward, color: IDPColors.onPrimary),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConfidenceButton(int level, String label, IconData icon, MaterialColor baseColor) {
    final isSelected = _confidenceLevel == level;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _confidenceLevel = level;
          });
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? baseColor.shade50 : IDPColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isSelected ? baseColor : IDPColors.outlineVariant.withValues(alpha: 0.5),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? baseColor : IDPColors.textSecondary, size: 24),
              const SizedBox(height: 8),
              Text(
                label,
                style: IDPTypography.caption.copyWith(
                  color: isSelected ? baseColor : IDPColors.textSecondary,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsView() {
    final pct = (_score * 100 / _questions.length).round();
    final isPass = pct >= 60;
    
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 40),
            Icon(
              isPass ? Icons.emoji_events_rounded : Icons.sentiment_dissatisfied_rounded,
              size: 100,
              color: isPass ? IDPColors.secondary : IDPColors.textSecondary,
            ),
            const SizedBox(height: 24),
            Text(
              isPass ? 'Congratulations!' : 'Keep Learning!',
              textAlign: TextAlign.center,
              style: IDPTypography.displayLg,
            ),
            const SizedBox(height: 16),
            Text(
              isPass ? 'You did a great job on this chapter quiz.' : 'Try reading the textbook content again and retry.',
              textAlign: TextAlign.center,
              style: IDPTypography.bodyLg.copyWith(color: IDPColors.textSecondary),
            ),
            const SizedBox(height: 48),

            // Score Indicator Circle
            Center(
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  color: IDPColors.surfaceContainerLowest,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isPass ? IDPColors.secondary : IDPColors.outlineVariant, 
                    width: 8,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    )
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$_score / ${_questions.length}',
                        style: IDPTypography.headlineLg,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$pct%',
                        style: IDPTypography.titleMd.copyWith(
                          color: isPass ? IDPColors.secondary : IDPColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 48),

            if (_reviewLaterIndices.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.bookmark, color: Colors.amber),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'You marked ${_reviewLaterIndices.length} question(s) for review. Check the breakdown below.',
                        style: IDPTypography.bodyMd.copyWith(color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],

            // Breakdown section
            Text(
              'Question Breakdown',
              style: IDPTypography.titleMd,
            ),
            const SizedBox(height: 16),
            ...List.generate(_questions.length, (idx) {
              final q = _questions[idx];
              final userSel = _answers[idx];
              final correct = q.correctIndex;
              final isCorrect = userSel == correct;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: IDPColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: IDPColors.outlineVariant.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    )
                  ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      children: [
                        Icon(
                          isCorrect ? Icons.check_circle : Icons.cancel,
                          color: isCorrect ? IDPColors.secondary : IDPColors.error,
                          size: 24,
                        ),
                        if (_reviewLaterIndices.contains(idx))
                          const Padding(
                            padding: EdgeInsets.only(top: 8.0),
                            child: Icon(Icons.bookmark, color: Colors.amber, size: 20),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Question ${idx + 1}',
                            style: IDPTypography.labelMd.copyWith(color: IDPColors.textSecondary),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            q.question,
                            style: IDPTypography.bodyLg,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Your Answer: ${userSel != null ? q.options[userSel] : "None"}',
                            style: IDPTypography.bodyMd.copyWith(
                              color: isCorrect ? IDPColors.secondary : IDPColors.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (!isCorrect)
                            Padding(
                              padding: const EdgeInsets.only(top: 8.0),
                              child: Text(
                                'Correct Answer: ${q.options[correct]}',
                                style: IDPTypography.bodyMd.copyWith(color: IDPColors.textSecondary),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),

            const SizedBox(height: 32),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _restartQuiz,
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: IDPColors.primary, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          'Retry Quiz',
                          style: IDPTypography.titleMd.copyWith(color: IDPColors.primary),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: IDPColors.primary,
                      ),
                      child: Center(
                        child: Text(
                          'Back to Home',
                          style: IDPTypography.titleMd.copyWith(color: IDPColors.onPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: IDPColors.errorLight.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline, size: 40, color: IDPColors.error),
              ),
              const SizedBox(height: 24),
              Text(
                'Failed to Load Quiz',
                style: IDPTypography.titleMd,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: IDPTypography.bodyMd.copyWith(color: IDPColors.textSecondary),
              ),
              const SizedBox(height: 32),
              InkWell(
                onTap: _loadQuiz,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: IDPColors.primary,
                  ),
                  child: Text(
                    'Retry',
                    style: IDPTypography.titleMd.copyWith(color: IDPColors.onPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: IDPColors.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.quiz_outlined, size: 40, color: IDPColors.textSecondary),
              ),
              const SizedBox(height: 24),
              Text(
                'No Practice Quizzes Found',
                style: IDPTypography.titleMd,
              ),
              const SizedBox(height: 12),
              Text(
                'There are no precomputed quiz questions available in this content pack yet.',
                textAlign: TextAlign.center,
                style: IDPTypography.bodyMd.copyWith(color: IDPColors.textSecondary),
              ),
              const SizedBox(height: 32),
              InkWell(
                onTap: () => Navigator.of(context).pop(),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: IDPColors.primary,
                  ),
                  child: Text(
                    'Go Back',
                    style: IDPTypography.titleMd.copyWith(color: IDPColors.onPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
