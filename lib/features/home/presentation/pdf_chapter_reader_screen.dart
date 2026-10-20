import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/idp_colors.dart';
import '../../../core/theme/idp_typography.dart';
import '../../../core/theme/idp_theme.dart';
import '';
import '../../course/domain/curriculum_models.dart';
import '../../course/data/local/pdf_chapter_locator.dart';
import '../../course/data/local/textbook_repository.dart';
import '../../course/domain/textbook_models.dart';
import '../../course/domain/course_tree.dart';
import 'chapter_summary_screen.dart';
import 'quiz_player_screen.dart';

class PdfChapterReaderScreen extends StatefulWidget {
  final CurriculumChapter chapter;

  const PdfChapterReaderScreen({
    Key? key,
    required this.chapter,
  }) : super(key: key);

  @override
  State<PdfChapterReaderScreen> createState() => _PdfChapterReaderScreenState();
}

class _PdfChapterReaderScreenState extends State<PdfChapterReaderScreen> {
  final Completer<PDFViewController> _pdfViewController = Completer<PDFViewController>();
  final PdfChapterLocator _locator = PdfChapterLocator();
  
  ChapterPdfReference? _pdfRef;
  bool _isLoading = true;
  String? _errorMessage;
  
  int _currentPage = 0;
  int _totalPages = 0;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _initPdf();
  }

  Future<void> _initPdf() async {
    try {
      final ref = await _locator.locateChapterPdf(widget.chapter);
      if (ref == null) {
        setState(() {
          _errorMessage = "PDF not found for this chapter.";
          _isLoading = false;
        });
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final savedPage = prefs.getInt('reader_progress_${widget.chapter.packId}');
      
      setState(() {
        _pdfRef = ref;
        _currentPage = savedPage ?? ref.startPage;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Failed to load PDF: $e";
        _isLoading = false;
      });
    }
  }

  void _saveProgress(int page) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reader_progress_${widget.chapter.packId}', page);
  }

  void _onPageChanged(int? page, int? total) {
    if (page == null || total == null) return;
    
    setState(() {
      _currentPage = page;
      _totalPages = total;
    });
    
    _saveProgress(page);

    if (_pdfRef != null) {
      if (page < _pdfRef!.startPage) {
        _showOutOfBoundsWarning(true);
      } else if (_pdfRef!.endPage != null && page > _pdfRef!.endPage!) {
        _showOutOfBoundsWarning(false);
      }
    }
  }

  void _showOutOfBoundsWarning(bool isBeforeStart) {
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isBeforeStart ? "You've scrolled before the chapter starts." : "You have reached the end of the chapter."),
        backgroundColor: IDPColors.surfaceContainerHigh,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: "Return",
          textColor: IDPColors.primary,
          onPressed: () async {
            final controller = await _pdfViewController.future;
            final targetPage = isBeforeStart ? _pdfRef!.startPage : _pdfRef!.endPage!;
            await controller.setPage(targetPage);
          },
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _openTutor() {
    // Canonical chat: chapter workspace, Chat tab (index 0).
    Navigator.of(context).pushNamed(
      '/chapter_workspace',
      arguments: {
        'chapterTitle': widget.chapter.title,
        'subjectName': widget.chapter.subject,
        'grade': widget.chapter.grade,
        'initialTabIndex': 0,
      },
    );
  }

  void _openFlashcards() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChapterSummaryScreen(chapter: widget.chapter),
      ),
    );
  }

  void _openQuiz() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuizPlayerScreen(chapter: widget.chapter),
      ),
    );
  }

  Future<void> _showSummaryPanel() async {
    final repo = TextbookRepository();
    final chapterData = await repo.loadChapter(widget.chapter.rootPath);
    
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          builder: (_, controller) {
            return Container(
              decoration: const BoxDecoration(
                color: IDPColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(IDPRadius.xl)),
              ),
              padding: const EdgeInsets.all(IDPSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: IDPColors.outlineVariant,
                        borderRadius: BorderRadius.circular(IDPRadius.full),
                      ),
                    ),
                  ),
                  const SizedBox(height: IDPSpacing.lg),
                  Text(
                    "Chapter Summary & Concepts",
                    style: IDPTypography.titleLarge.copyWith(color: IDPColors.onSurface),
                  ),
                  const SizedBox(height: IDPSpacing.md),
                  Expanded(
                    child: ListView(
                      controller: controller,
                      children: [
                        if (chapterData == null)
                          Text("No summary available for this chapter.", style: IDPTypography.bodyMedium.copyWith(color: IDPColors.onSurfaceVariant))
                        else ...[
                          Text(
                            widget.chapter.summary.isNotEmpty ? widget.chapter.summary : "No summary provided.",
                            style: IDPTypography.bodyLarge.copyWith(color: IDPColors.onSurface),
                          ),
                          const SizedBox(height: IDPSpacing.xl),
                          Text("Sections", style: IDPTypography.titleMedium.copyWith(color: IDPColors.onSurface)),
                          const SizedBox(height: IDPSpacing.sm),
                          ...chapterData.sections.map((sec) => Padding(
                            padding: const EdgeInsets.only(bottom: IDPSpacing.xs),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("• ", style: TextStyle(color: IDPColors.primary, fontSize: 16)),
                                Expanded(child: Text(sec.title, style: IDPTypography.bodyMedium.copyWith(color: IDPColors.onSurfaceVariant))),
                              ],
                            ),
                          )).toList(),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IDPColors.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(widget.chapter.title, style: IDPTypography.titleMedium.copyWith(color: IDPColors.onSurface)),
            if (_totalPages > 0)
              Text(
                'Page ${_currentPage + 1} of $_totalPages',
                style: IDPTypography.labelSmall.copyWith(color: IDPColors.onSurfaceVariant),
              ),
          ],
        ),
        backgroundColor: IDPColors.surface.withValues(alpha: 0.9),
        foregroundColor: IDPColors.onSurface,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined, color: IDPColors.primary),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Bookmarked page ${_currentPage + 1}'),
                  backgroundColor: IDPColors.surfaceContainerHigh,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openTutor,
        backgroundColor: IDPColors.primary,
        foregroundColor: IDPColors.onPrimary,
        icon: const Icon(Icons.psychology),
        label: const Text('Ask AI Tutor'),
      ),
      bottomNavigationBar: _buildToolbar(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: IDPColors.primary));
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(IDPSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: IDPColors.error),
              const SizedBox(height: IDPSpacing.md),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: IDPTypography.bodyLarge.copyWith(color: IDPColors.onErrorContainer),
              ),
            ],
          ),
        ),
      );
    }

    if (_pdfRef == null) return const SizedBox.shrink();

    return Stack(
      children: [
        PDFView(
          filePath: _pdfRef!.pdfPath,
          enableSwipe: true,
          swipeHorizontal: false, 
          autoSpacing: false,
          pageFling: false,
          defaultPage: _currentPage,
          fitPolicy: FitPolicy.BOTH,
          onRender: (_pages) {
            setState(() {
              _totalPages = _pages!;
              _isReady = true;
            });
          },
          onError: (error) {
            setState(() {
              _errorMessage = error.toString();
            });
          },
          onPageError: (page, error) {
            setState(() {
              _errorMessage = '$page: ${error.toString()}';
            });
          },
          onViewCreated: (PDFViewController pdfViewController) {
            _pdfViewController.complete(pdfViewController);
          },
          onPageChanged: _onPageChanged,
        ),
        if (!_isReady)
          const Center(child: CircularProgressIndicator(color: IDPColors.primary)),
      ],
    );
  }

  Widget _buildToolbar() {
    return Container(
      decoration: BoxDecoration(
        color: IDPColors.surface.withValues(alpha: 0.9),
        border: Border(top: BorderSide(color: IDPColors.outlineVariant.withValues(alpha: 0.5))),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.md, vertical: IDPSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildToolbarAction(
                icon: Icons.article_outlined,
                label: "Summary",
                onTap: _showSummaryPanel,
              ),
              _buildToolbarAction(
                icon: Icons.style_outlined,
                label: "Flashcards",
                onTap: _openFlashcards,
              ),
              _buildToolbarAction(
                icon: Icons.quiz_outlined,
                label: "Quiz",
                onTap: _openQuiz,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(IDPRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.md, vertical: IDPSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: IDPColors.onSurfaceVariant, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: IDPTypography.labelSmall.copyWith(color: IDPColors.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
