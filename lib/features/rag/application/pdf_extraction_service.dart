import 'dart:io';
import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Service for extracting text content from PDF files
class PdfExtractionService {
  /// Extract all text from a PDF file using in-app parser.
  static Future<String> extractTextFromPdf(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw PdfExtractionException('File not found: $filePath');
      }

      final bytes = await file.readAsBytes();
      return _extractTextFromBytes(bytes, filePath);
    } catch (e) {
      throw PdfExtractionException(
        'Failed to extract text from PDF: $e',
      );
    }
  }

  static String _extractTextFromBytes(Uint8List bytes, String filePath) {
    try {
      final document = PdfDocument(inputBytes: bytes);
      final pageCount = document.pages.count;
      if (pageCount <= 0) {
        document.dispose();
        throw PdfExtractionException('PDF has no pages: $filePath');
      }

      final extractor = PdfTextExtractor(document);
      final extracted = extractor.extractText(
        startPageIndex: 0,
        endPageIndex: pageCount - 1,
      );
      document.dispose();

      final normalized = extracted
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .trim();

      if (normalized.isEmpty) {
        throw PdfExtractionException('No extractable text found in PDF: $filePath');
      }

      return normalized;
    } catch (e) {
      throw PdfExtractionException('In-app PDF parser failed: $e');
    }
  }
}

/// Exception during PDF extraction
class PdfExtractionException implements Exception {
  final String message;

  PdfExtractionException(this.message);

  @override
  String toString() => 'PdfExtractionException: $message';
}
