import '../domain/visual_intent.dart';

/// The result of parsing a tutor message containing streaming or completed text
/// and zero or more embedded `mentora-visual` blocks.
final class ParsedVisualTurn {
  const ParsedVisualTurn({
    required this.proseText,
    required this.visualIntents,
    required this.hasIncompleteBlock,
  });

  /// The cleaned text with visual fence blocks extracted.
  final String proseText;

  /// Validated or parsed visual intents extracted from the message.
  final List<VisualIntent> visualIntents;

  /// True if a `mentora-visual` block has opened but not yet received its closing fence.
  final bool hasIncompleteBlock;

  @override
  String toString() =>
      'ParsedVisualTurn(proseLength: ${proseText.length}, visuals: ${visualIntents.length}, incomplete: $hasIncompleteBlock)';
}

/// State-machine stream parser for extracting `mentora-visual` fenced artifact blocks.
///
/// Designed to parse efficiently without $O(n^2)$ overhead while text streams token-by-token.
/// Strips out raw JSON blocks so the student never sees raw technical JSON in prose chat bubbles.
final class VisualStreamParser {
  const VisualStreamParser();

  static const _openFence1 = '```mentora-visual';
  static const _openFence2 = '```json:mentora-visual';
  static const _closeFence = '```';

  /// Parses text into cleaned prose and extracted [VisualIntent] objects.
  ParsedVisualTurn parse(String rawText) {
    if (rawText.isEmpty) {
      return const ParsedVisualTurn(
        proseText: '',
        visualIntents: [],
        hasIncompleteBlock: false,
      );
    }

    // Strip completed tool call blocks so raw JSON/function calls never leak into proseText
    var sanitizedText = rawText.replaceAll(
      RegExp(r'```(?:json:)?mentora-tool-call[\s\S]*?```'),
      '',
    );
    // Strip trailing incomplete tool-call fence if currently streaming mid-block
    final toolIdx1 = sanitizedText.indexOf('```mentora-tool-call');
    final toolIdx2 = sanitizedText.indexOf('```json:mentora-tool-call');
    final earliestToolIdx = (toolIdx1 != -1 && toolIdx2 != -1)
        ? (toolIdx1 < toolIdx2 ? toolIdx1 : toolIdx2)
        : (toolIdx1 != -1 ? toolIdx1 : toolIdx2);
    if (earliestToolIdx != -1) {
      sanitizedText = sanitizedText.substring(0, earliestToolIdx).trimRight();
    }

    final proseBuffer = StringBuffer();
    final intents = <VisualIntent>[];
    var hasIncomplete = false;

    var currentIndex = 0;
    final length = sanitizedText.length;

    while (currentIndex < length) {
      // Look for the next open fence
      final idx1 = sanitizedText.indexOf(_openFence1, currentIndex);
      final idx2 = sanitizedText.indexOf(_openFence2, currentIndex);

      int openIdx = -1;
      int fenceLen = 0;

      if (idx1 != -1 && idx2 != -1) {
        if (idx1 < idx2) {
          openIdx = idx1;
          fenceLen = _openFence1.length;
        } else {
          openIdx = idx2;
          fenceLen = _openFence2.length;
        }
      } else if (idx1 != -1) {
        openIdx = idx1;
        fenceLen = _openFence1.length;
      } else if (idx2 != -1) {
        openIdx = idx2;
        fenceLen = _openFence2.length;
      }

      if (openIdx == -1) {
        // No more visual blocks, append the rest to prose
        proseBuffer.write(sanitizedText.substring(currentIndex));
        break;
      }

      // Append preceding text to prose
      proseBuffer.write(sanitizedText.substring(currentIndex, openIdx));

      // Locate closing fence after open fence
      final contentStart = openIdx + fenceLen;
      final closeIdx = sanitizedText.indexOf(_closeFence, contentStart);

      if (closeIdx == -1) {
        // Fenced block is currently being streamed, wait for completion
        hasIncomplete = true;
        break;
      }

      // Extract JSON content between fences
      final jsonBlock = sanitizedText.substring(contentStart, closeIdx).trim();
      final parsed = VisualIntent.tryParse(jsonBlock);
      if (parsed != null) {
        intents.add(parsed);
      }

      currentIndex = closeIdx + _closeFence.length;
    }

    final cleanProse = proseBuffer.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    return ParsedVisualTurn(
      proseText: cleanProse,
      visualIntents: intents,
      hasIncompleteBlock: hasIncomplete,
    );
  }
}
