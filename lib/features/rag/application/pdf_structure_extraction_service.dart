import 'content_structure_heuristics.dart';

class PdfStructuredBlock {
  const PdfStructuredBlock({
    required this.type,
    required this.heading,
    required this.content,
  });

  final String type; // paragraph | table | figure_caption | formula_region | heading
  final String heading;
  final String content;
}

class PdfStructureExtractionService {
  /// Heuristic extraction of structural regions from plain extracted PDF text.
  /// This enables table/caption/formula-aware chunking without OCR.
  static List<PdfStructuredBlock> extractBlocks(String text) {
    final lines = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .split('\n')
        .map((e) => e.trimRight())
        .toList();

    final blocks = <PdfStructuredBlock>[];
    final current = StringBuffer();
    var currentType = 'paragraph';
    var currentHeading = 'Content';

    void flush() {
      final raw = current.toString().trim();
      if (raw.isEmpty) {
        current.clear();
        return;
      }
      blocks.add(
        PdfStructuredBlock(
          type: currentType,
          heading: currentHeading,
          content: raw,
        ),
      );
      current.clear();
    }

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        flush();
        continue;
      }

      final detected = _classifyLine(trimmed);

      if (detected == 'heading') {
        flush();
        currentType = 'paragraph';
        currentHeading = trimmed;
        continue;
      }

      if (detected != currentType && current.isNotEmpty) {
        flush();
      }

      currentType = detected;
      current.writeln(trimmed);
    }

    flush();

    if (blocks.isEmpty) {
      return <PdfStructuredBlock>[
        PdfStructuredBlock(type: 'paragraph', heading: 'Content', content: text.trim()),
      ];
    }

    return blocks;
  }

  static String _classifyLine(String line) {
    if (_looksLikeHeading(line)) {
      return 'heading';
    }

    if (ContentStructureHeuristics.isFigureCaption(line)) {
      return 'figure_caption';
    }

    if (ContentStructureHeuristics.isTableRow(line)) {
      return 'table';
    }

    if (ContentStructureHeuristics.isFormulaRegion(line)) {
      return 'formula_region';
    }

    return 'paragraph';
  }

  static bool _looksLikeHeading(String line) {
    final shortEnough = line.length <= 90;
    final noTerminalPunctuation = !line.endsWith('.') && !line.endsWith(';');
    final startsUpper = line.isNotEmpty && line[0] == line[0].toUpperCase();
    final words = line.split(RegExp(r'\s+'));
    return shortEnough && noTerminalPunctuation && startsUpper && words.length <= 12;
  }

  // Figure/table/formula detectors live in ContentStructureHeuristics
  // (shared with SemanticChunkingService). Heading stays local: block
  // classification needs stricter thresholds than section splitting.
}
