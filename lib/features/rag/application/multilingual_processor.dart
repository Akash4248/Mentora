/// Handles multilingual text processing for English and Kannada
class MultilingualProcessor {
  /// Detect language of text
  static String detectLanguage(String text) {
    // Check for Kannada Unicode range: U+0C80–U+0CFF
    if (RegExp(r'[\u0C80-\u0CF3]').hasMatch(text)) {
      return 'kn';
    }
    return 'en';
  }

  /// Normalize Kannada text (preserve Unicode, handle ligatures)
  static String normalizeKannada(String text) {
    var normalized = text;

    // Normalize Kannada virama (halant) usage
    // KANNADA SIGN VIRAMA U+0CCD
    normalized = normalized.replaceAll(RegExp(r'್+'), '್');

    // Normalize nuktas (combining marks)
    // Remove zero-width joiners that might cause issues
    normalized = normalized.replaceAll(RegExp(r'[\u200B\u200C\u200D]'), '');

    return normalized;
  }

  /// Clean up mixed-language text
  static String cleanMixedLanguage(String text) {
    // Remove control characters
    var cleaned = text.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');

    // Normalize spaces between scripts
    cleaned = cleaned.replaceAll(
      RegExp(r'([\u0C80-\u0CF3])\s+([\u0C80-\u0CF3])'),
      r'$1$2',
    );

    return cleaned;
  }
}
