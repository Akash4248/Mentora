import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path/path.dart' as p;

import '../../../core/theme/idp_colors.dart';
import '../../../core/theme/idp_typography.dart';

class TextbookViewerScreen extends StatefulWidget {
  final String pdfPath;
  final String chapterTitle;
  final String subjectName;
  final int grade;
  final bool showAppBar;

  const TextbookViewerScreen({
    super.key,
    required this.pdfPath,
    required this.chapterTitle,
    required this.subjectName,
    required this.grade,
    this.showAppBar = true,
  });

  @override
  State<TextbookViewerScreen> createState() => _TextbookViewerScreenState();
}

class _TextbookViewerScreenState extends State<TextbookViewerScreen> {
  int _totalPages = 0;
  int _currentPage = 0;
  bool _isReady = false;
  String _errorMessage = '';
  PDFViewController? _pdfViewController;

  @override
  Widget build(BuildContext context) {
    final file = File(widget.pdfPath);
    final fileExists = file.existsSync();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: widget.showAppBar
          ? AppBar(
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.subjectName} • ${widget.chapterTitle}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
                  ),
                  Text(
                    'NCERT Class ${widget.grade} Official Textbook PDF',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF4F46E5),
              foregroundColor: Colors.white,
              elevation: 0,
              actions: [
                if (_isReady && _totalPages > 0)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Page ${_currentPage + 1} / $_totalPages',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : null,
      body: SafeArea(
        child: !fileExists
            ? _buildFileNotFoundView()
            : Stack(
                children: [
                  PDFView(
                    filePath: widget.pdfPath,
                    enableSwipe: true,
                    swipeHorizontal: false,
                    autoSpacing: true,
                    pageFling: true,
                    pageSnap: true,
                    fitPolicy: FitPolicy.BOTH,
                    onRender: (pages) {
                      setState(() {
                        _totalPages = pages ?? 0;
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
                        _errorMessage = 'Page $page: ${error.toString()}';
                      });
                    },
                    onViewCreated: (controller) {
                      _pdfViewController = controller;
                    },
                    onPageChanged: (page, total) {
                      setState(() {
                        _currentPage = page ?? 0;
                      });
                    },
                  ),

                  if (!_isReady && _errorMessage.isEmpty)
                    const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF4F46E5)),
                          SizedBox(height: 12),
                          Text(
                            'Loading NCERT Textbook PDF...',
                            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),

                  if (_errorMessage.isNotEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error_outline_rounded, color: Colors.orangeAccent, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              'PDF Rendering Error',
                              style: IDPTypography.titleSmall.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _errorMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
      bottomNavigationBar: _isReady && _totalPages > 0
          ? Container(
              height: 56,
              color: const Color(0xFF1E293B),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                    onPressed: _currentPage > 0
                        ? () {
                            _pdfViewController?.setPage(_currentPage - 1);
                          }
                        : null,
                  ),
                  Text(
                    'Page ${_currentPage + 1} of $_totalPages',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white),
                    onPressed: _currentPage < _totalPages - 1
                        ? () {
                            _pdfViewController?.setPage(_currentPage + 1);
                          }
                        : null,
                  ),
                ],
              ),
            )
          : null,
    );
  }

  Widget _buildFileNotFoundView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_rounded, size: 64, color: Color(0xFF818CF8)),
            const SizedBox(height: 16),
            Text(
              'Textbook PDF Pack Not Downloaded',
              style: IDPTypography.titleSmall.copyWith(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 10),
            Text(
              'The official NCERT textbook PDF for "${widget.chapterTitle}" will be available once the offline content pack for Grade ${widget.grade} is synced.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: const Text('Sync Offline Packs'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
