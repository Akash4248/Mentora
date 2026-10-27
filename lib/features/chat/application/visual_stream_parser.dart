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

  static final _openFenceRegex = RegExp(
    r'```(?:json:)?(?:mentora|merora|mentor|m)?[_\-]?visual\b\s*|```mermaid\b\s*',
    caseSensitive: false,
  );
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
      RegExp(r'```(?:json:)?(?:mentora|merora|mentor|m)?[_\-]?tool-call[\s\S]*?```', caseSensitive: false),
      '',
    );
    // Strip trailing incomplete tool-call fence if currently streaming mid-block
    final toolCallFenceRegex = RegExp(r'```(?:json:)?(?:mentora|merora|mentor|m)?[_\-]?tool-call', caseSensitive: false);
    final toolMatch = toolCallFenceRegex.firstMatch(sanitizedText);
    if (toolMatch != null) {
      sanitizedText = sanitizedText.substring(0, toolMatch.start).trimRight();
    }

    final proseBuffer = StringBuffer();
    final intents = <VisualIntent>[];
    var hasIncomplete = false;

    var currentIndex = 0;
    final length = sanitizedText.length;

    while (currentIndex < length) {
      // Look for the next open fence matching any visual variant or mermaid
      final match = _openFenceRegex.firstMatch(sanitizedText.substring(currentIndex));
      if (match == null) {
        // No more visual blocks, append the rest to prose
        proseBuffer.write(sanitizedText.substring(currentIndex));
        break;
      }

      final openIdx = currentIndex + match.start;
      final fenceLen = match.end - match.start;
      final matchedFenceStr = match[0]!.toLowerCase();
      final isMermaidFence = matchedFenceStr.contains('mermaid');

      // Append preceding text to prose
      proseBuffer.write(sanitizedText.substring(currentIndex, openIdx));

      // Locate closing fence after open fence
      final contentStart = openIdx + fenceLen;
      final closeIdx = sanitizedText.indexOf(_closeFence, contentStart);

      if (closeIdx == -1) {
        if (isMermaidFence) {
          // If unclosed mermaid block, let it stream into prose normally
          proseBuffer.write(sanitizedText.substring(openIdx));
          break;
        } else {
          // Fenced visual block is currently being streamed, wait for completion
          hasIncomplete = true;
          break;
        }
      }

      // Extract JSON content between fences
      final blockContent = sanitizedText.substring(contentStart, closeIdx).trim();
      final parsed = VisualIntent.tryParse(blockContent);

      if (parsed != null) {
        // Successfully parsed a visual intent (either from ```mentora-visual or intercepted from ```mermaid)
        intents.add(parsed);
      } else if (isMermaidFence) {
        // Legitimate Mermaid diagram syntax (not a JSON tool-call) — preserve in prose!
        proseBuffer.write(sanitizedText.substring(openIdx, closeIdx + _closeFence.length));
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
