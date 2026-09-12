class MarkdownFormatNormalizer {
  MarkdownFormatNormalizer._();

  /// Normalizes unformatted or densely-packed GGUF LLM Markdown outputs into
  /// clean, beautifully structured Markdown with proper headers, paragraph breaks,
  /// bullet points, and sentence spacing.
  static String normalize(String text) {
    if (text.isEmpty) return text;

    var out = text;

    // 1. Separate headers attached to previous words without newlines (e.g., "Cube## Introduction")
    out = out.replaceAllMapped(
      RegExp(r'([^\n\s])\s*(#{1,4})\s*'),
      (m) => '${m.group(1)}\n\n${m.group(2)} ',
    );

    // 2. Ensure a space exists after hashes (e.g., "##Introduction" -> "## Introduction")
    out = out.replaceAllMapped(
      RegExp(r'^(#{1,4})([A-Za-z0-9])', multiLine: true),
      (m) => '${m.group(1)} ${m.group(2)}',
    );

    // 3. Separate header title glued directly to paragraph body text
    // (e.g., "## IntroductionIn this chapter" -> "## Introduction\n\nIn this chapter")
    // (e.g., "## Properties of a SquareA square has" -> "## Properties of a Square\n\nA square has")
    out = out.replaceAllMapped(
      RegExp(r'(#{1,4}\s+[A-Z][A-Za-z0-9\s]*?[a-z0-9])([A-Z](?:[a-z]+|\s+[a-z]+))'),
      (m) => '${m.group(1)}\n\n${m.group(2)}',
    );

    // 4. Separate bullet items stuck together without newlines (e.g., "equal.- All angles")
    out = out.replaceAllMapped(
      RegExp(r'([^\n])\s*([\-\*•])\s*([A-Z0-9])'),
      (m) => '${m.group(1)}\n${m.group(2)} ${m.group(3)}',
    );

    // 5. Fix missing space after period before a new sentence (e.g., "equal.A square" -> "equal. A square")
    out = out.replaceAllMapped(
      RegExp(r'([a-z0-9\)])\.([A-Z][a-z])'),
      (m) => '${m.group(1)}. ${m.group(2)}',
    );

    // 6. Fix space in chapter labels (e.g., "Chapter4:" -> "Chapter 4:")
    out = out.replaceAllMapped(
      RegExp(r'\b(Chapter|Section|Unit|Lesson|Part)(\d+)\b', caseSensitive: false),
      (m) => '${m.group(1)} ${m.group(2)}',
    );

    // 7. Clean up redundant blank lines (>2)
    out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    return out.trim();
  }
}
