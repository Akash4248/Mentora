import '../application/formula_extractor.dart';
import '../domain/chunk_v2.dart';
import 'content_structure_heuristics.dart';

/// Intelligently chunks text by logical sections (definitions, examples, proofs)
/// rather than fixed paragraph/character boundaries
class SemanticChunkingService {
  static const int minTokensPerChunk = 50;
  static const int maxTokensPerChunk = 500;
  static const int optimalTokenRange = 200; // Prefer this size

  /// Chunk types that can be detected
  static const List<String> chunkTypeMarkers = [
    'definition',
    'example',
    'exercise',
    'proof',
    'theorem',
    'concept',
    'note',
    'warning',
    'table',
    'figure_caption',
    'formula_region',
  ];

  /// Chunk text into logical sections
  static List<ChunkV2> chunkText({
    required String text,
    required String chapterId,
    required String sourceTitle,
    required String sourceLanguage,
    required String section,
    String? subsection,
  }) {
    final normalized = _normalizeText(text, sourceLanguage);
    if (normalized.isEmpty) return [];

    // Step 1: Extract formulas BEFORE chunking
    final formulas = FormulaExtractor.extractFormulas(normalized);

    // Step 2: Detect section structure
    final sections = _parseStructure(normalized);

    // Step 3: Group into chunks by semantic proximity
    final chunks = <ChunkV2>[];
    var chunkOrder = 0;

    for (final sec in sections) {
      final subChunks = _createChunksFromSection(
        section: sec,
        chapterId: chapterId,
        sourceTitle: sourceTitle,
        sourceLanguage: sourceLanguage,
        sectionName: section,
        subsection: subsection,
        baseOrder: chunkOrder,
        allFormulas: formulas,
      );

      chunks.addAll(subChunks);
      chunkOrder += subChunks.length;
    }

    return chunks.isEmpty ? _fallbackChunking(
      text,
      chapterId,
      sourceTitle,
      sourceLanguage,
      section,
      subsection,
      formulas,
    ) : chunks;
  }

  /// Normalize text: whitespace, encoding, language-specific rules
  static String _normalizeText(String raw, String language) {
    var text = raw.trim();

    // Remove extra whitespace
    text = text.replaceAll(RegExp(r'\s+'), ' ');

    // Normalize quotes
    text = text.replaceAll(RegExp(r'[""'']'), '"');

    // Normalize unicode symbols
    text = text.replaceAll('½', '1/2').replaceAll('¾', '3/4');
    text = text.replaceAll(RegExp(r'[ºᵒ]'), '°');

    // Language-specific normalization
    if (language == 'en') {
      text = text.toLowerCase();
    }
    // Kannada: preserve case

    return text;
  }

  /// Parse document structure to detect headers and sections
  static List<_Section> _parseStructure(String text) {
    final sections = <_Section>[];
    final lines = text.split('\n');

    var currentContent = StringBuffer();
    var currentTitle = '';

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      if (_looksLikeFigureCaption(trimmed)) {
        if (currentContent.isNotEmpty && currentTitle.isNotEmpty) {
          sections.add(_Section(
            title: currentTitle,
            content: currentContent.toString().trim(),
          ));
          currentContent = StringBuffer();
        }
        sections.add(_Section(title: 'Figure Caption', content: trimmed));
        continue;
      }

      if (_looksLikeTableRow(trimmed)) {
        if (currentContent.isNotEmpty && currentTitle.isNotEmpty) {
          sections.add(_Section(
            title: currentTitle,
            content: currentContent.toString().trim(),
          ));
          currentContent = StringBuffer();
        }
        currentTitle = 'Table';
        currentContent.writeln(trimmed);
        continue;
      }

      // Detect header levels (crude heuristic)
      // Real headers typically start with capital and short length
      final isHeader = _looksLikeHeader(trimmed);

      if (isHeader && currentContent.isNotEmpty) {
        // Save previous section
        if (currentTitle.isNotEmpty) {
          sections.add(_Section(
            title: currentTitle,
            content: currentContent.toString().trim(),
          ));
        }
        currentTitle = trimmed;
        currentContent = StringBuffer();
      } else {
        if (currentTitle.isEmpty && isHeader) {
          currentTitle = trimmed;
        } else {
          currentContent.writeln(trimmed);
        }
      }
    }

    // Add final section
    if (currentContent.isNotEmpty) {
      sections.add(_Section(
        title: currentTitle,
        content: currentContent.toString().trim(),
      ));
    }

    return sections.isEmpty
        ? [_Section(title: 'Content', content: text)]
        : sections;
  }

  // Figure/table detectors live in ContentStructureHeuristics (shared with
  // PdfStructureExtractionService). Header stays local: section splitting
  // needs looser thresholds than block classification.
  static bool _looksLikeFigureCaption(String line) =>
      ContentStructureHeuristics.isFigureCaption(line);

  static bool _looksLikeTableRow(String line) =>
      ContentStructureHeuristics.isTableRow(line);

  /// Detect if line looks like a section header
  static bool _looksLikeHeader(String line) {
    // Rules: starts with capital, < 80 chars, no period unless abbrev
    if (line.length > 80) return false;
    if (!line[0].toUpperCase().contains(line[0])) return false;

    // Avoid common false positives (examples, long sentences)
    if (line.contains('example') &&
        line.contains(':') &&
        line.split(':')[1].length > 30) {
      return false;
    }

    return true;
  }

  /// Create chunks from a section, respecting token limits
  static List<ChunkV2> _createChunksFromSection({
    required _Section section,
    required String chapterId,
    required String sourceTitle,
    required String sourceLanguage,
    required String sectionName,
    String? subsection,
    required int baseOrder,
    required List<Formula> allFormulas,
  }) {
    final chunks = <ChunkV2>[];

    // Detect chunk type from section title
    final contentType = _detectChunkType(section.title);

    // Split content by sentences for fine-grained chunking
    final sentences = _splitIntoSentences(section.content);
    final buffer = StringBuffer();
    var totalTokens = 0;

    for (final sentence in sentences) {
      final tokens = _tokenCount(sentence);

      // If adding this sentence would exceed max, save chunk
      if (totalTokens + tokens > maxTokensPerChunk && buffer.isNotEmpty) {
        final content = buffer.toString().trim();
        final sectionFormulas =
            _formulasInText(content, allFormulas);

        chunks.add(_createChunk(
          content: content,
          contentType: contentType,
          chapterId: chapterId,
          sourceTitle: sourceTitle,
          sourceLanguage: sourceLanguage,
          section: sectionName,
          subsection: subsection,
          chunkOrder: baseOrder + chunks.length,
          formulas: sectionFormulas,
        ));

        buffer.clear();
        totalTokens = 0;
      }

      buffer.writeln(sentence);
      totalTokens += tokens;
    }

    // Add final chunk
    if (buffer.isNotEmpty) {
      final content = buffer.toString().trim();
      if (_tokenCount(content) >= minTokensPerChunk) {
        final sectionFormulas =
            _formulasInText(content, allFormulas);

        chunks.add(_createChunk(
          content: content,
          contentType: contentType,
          chapterId: chapterId,
          sourceTitle: sourceTitle,
          sourceLanguage: sourceLanguage,
          section: sectionName,
          subsection: subsection,
          chunkOrder: baseOrder + chunks.length,
          formulas: sectionFormulas,
        ));
      }
    }

    return chunks;
  }

  /// Detect chunk type from content patterns
  static String _detectChunkType(String text) {
    final lower = text.toLowerCase();

    if (_looksLikeFigureCaption(text)) {
      return 'figure_caption';
    }

    if (_looksLikeTableRow(text)) {
      return 'table';
    }

    final formulaDensity =
      RegExp(r'[=+\-*/^<>()]').allMatches(text).length / (text.isEmpty ? 1 : text.length);
    if (formulaDensity > 0.045) {
      return 'formula_region';
    }

    if (lower.startsWith('definition') ||
        lower.contains('is defined as') ||
        lower.contains('means')) {
      return 'definition';
    }
    if (lower.startsWith('example') || lower.contains('for instance')) {
      return 'example';
    }
    if (lower.startsWith('exercise') || lower.contains('problem')) {
      return 'exercise';
    }
    if (lower.startsWith('proof') || lower.contains('prove that')) {
      return 'proof';
    }
    if (lower.startsWith('theorem')) {
      return 'theorem';
    }

    return 'concept';
  }

  /// Fallback chunking if structure parsing fails
  static List<ChunkV2> _fallbackChunking(
    String text,
    String chapterId,
    String sourceTitle,
    String sourceLanguage,
    String section,
    String? subsection,
    List<Formula> allFormulas,
  ) {
    final chunks = <ChunkV2>[];
    final paragraphs = text.split(RegExp(r'\n\s*\n'));

    for (var i = 0; i < paragraphs.length; i++) {
      final para = paragraphs[i].trim();
      if (para.isEmpty) continue;

      final sectionFormulas =
          _formulasInText(para, allFormulas);

      chunks.add(_createChunk(
        content: para,
        contentType: 'concept',
        chapterId: chapterId,
        sourceTitle: sourceTitle,
        sourceLanguage: sourceLanguage,
        section: section,
        subsection: subsection,
        chunkOrder: i,
        formulas: sectionFormulas,
      ));
    }

    return chunks;
  }

  /// Create ChunkV2 object
  static ChunkV2 _createChunk({
    required String content,
    required String contentType,
    required String chapterId,
    required String sourceTitle,
    required String sourceLanguage,
    required String section,
    String? subsection,
    required int chunkOrder,
    required List<Formula> formulas,
  }) {
    // Tag formulas in content
    var taggedContent =
        FormulaExtractor.tagFormulasInText(content, formulas);

    return ChunkV2(
      id: '${chapterId}_${DateTime.now().millisecondsSinceEpoch}_$chunkOrder',
      chapterId: chapterId,
      sourceTitle: sourceTitle,
      sourceLanguage: sourceLanguage,
      content: taggedContent,
      contentType: contentType,
      chunkOrder: chunkOrder,
      createdAt: DateTime.now(),
      formulas: formulas,
      originalMarkdown: content, // Preserve original
      tokenCount: _tokenCount(content),
      metadata: {
        'section': section,
        'subsection': subsection,
        'difficulty': _estimateDifficulty(content),
        'has_formulas': formulas.isNotEmpty,
        'formula_count': formulas.length,
      },
    );
  }

  /// Estimate difficulty from text complexity
  static String _estimateDifficulty(String text) {
    final tokenCount = _tokenCount(text);
    final formulaCount = RegExp(r'[+\-×÷*/=()]').allMatches(text).length;
    final complexity = formulaCount / (tokenCount > 0 ? tokenCount : 1);

    if (complexity > 0.3) return 'advanced';
    if (complexity > 0.15) return 'intermediate';
    return 'beginner';
  }

  /// Split text into sentences
  static List<String> _splitIntoSentences(String text) {
    // Simple sentence splitter (handles ., !, ?)
    final sents = text.split(RegExp(r'(?<=[.!?])\s+'));
    return sents.where((s) => s.trim().isNotEmpty).toList();
  }

  /// Count tokens (rough estimate: words + punctuation chunks)
  static int _tokenCount(String text) {
    if (text.isEmpty) return 0;
    final words = text.split(RegExp(r'\W+'));
    return words.where((w) => w.isNotEmpty).length;
  }

  /// Find formulas within a text chunk
  static List<Formula> _formulasInText(
    String text,
    List<Formula> allFormulas,
  ) {
    return allFormulas
        .where((f) => text.contains(f.original))
        .toList();
  }
}

class _Section {
  _Section({required this.title, required this.content});
  final String title;
  final String content;
}
