/// Single home for line-level content-structure detectors.
///
/// Previously copy-pasted between [SemanticChunkingService] and
/// [PdfStructureExtractionService]. Heading/header thresholds stay local to
/// each caller (section-splitting vs block-classification need different
/// strictness) — everything else lives here.
class ContentStructureHeuristics {
  static bool isFigureCaption(String line) {
    final lower = line.toLowerCase();
    return lower.startsWith('figure ') ||
        lower.startsWith('fig. ') ||
        lower.startsWith('diagram ') ||
        lower.startsWith('image ');
  }

  static bool isTableRow(String line) {
    final hasPipe = line.contains('|');
    final hasTab = line.contains('\t');
    final hasMultiSpacing = RegExp(r'\s{2,}').hasMatch(line);
    final tokenCount =
        line.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).length;
    return tokenCount >= 3 && (hasPipe || hasTab || hasMultiSpacing);
  }

  static bool isFormulaRegion(String line) {
    final formulaSymbols = RegExp(r'[=+\-*/^<>()]').allMatches(line).length;
    final digits = RegExp(r'\d').allMatches(line).length;
    return formulaSymbols >= 2 && digits >= 1;
  }
}
