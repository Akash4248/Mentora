import 'dart:math' as math;

import 'markdown_format_normalizer.dart';
import 'reasoning_output_filter.dart';

class StreamingOutputNormalizer {
  StreamingOutputNormalizer._();

  static final RegExp _ansiEscape = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

  static String clean(String text) {
    var output = ReasoningOutputFilter.stripComplete(
      text,
    ).replaceAll(_ansiEscape, '').replaceAll('\r', '');

    output = output.replaceAll(RegExp(r'<\|[^>]*\|>'), '');
    output = output.replaceAll(RegExp(r'<\|[^\n]*'), '');
    output = output.replaceAll(RegExp(r'<[^\s>]*\|>'), '');

    final lower = output.toLowerCase();
    final answerTagIndex = lower.indexOf('<|answer|>');
    if (answerTagIndex >= 0) {
      output = output.substring(answerTagIndex + '<|answer|>'.length);
    }

    final roleplayTagIndex = lower.indexOf('<|roleplay|>');
    if (roleplayTagIndex >= 0) {
      output = output.substring(0, roleplayTagIndex);
    }

    output = output
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|im_start|>assistant', '')
        .replaceAll('<|question|>', '')
        .replaceAll('<|answer|>', '')
        .replaceAll('<|roleplay|>', '')
        .replaceAll('<im_start>assistant', '')
        .replaceAll('<im_end>', '')
        .replaceAll('</s>', '')
        .replaceAll('<s>', '');

    output = MarkdownFormatNormalizer.normalize(output);
    return output.trim();
  }

  static String merge(String previous, String incoming) {
    if (incoming.isEmpty) return previous;
    if (previous.isEmpty) return incoming;

    final cleanedPrevious = clean(previous);
    final cleanedIncoming = clean(incoming);

    if (cleanedIncoming.isEmpty) {
      return previous;
    }
    if (cleanedPrevious.isEmpty) {
      return incoming;
    }
    if (cleanedIncoming == cleanedPrevious) {
      return previous;
    }
    if (cleanedIncoming.startsWith(cleanedPrevious)) {
      return incoming;
    }
    if (previous.startsWith(cleanedIncoming)) {
      return previous;
    }

    final overlap = _longestOverlap(cleanedPrevious, cleanedIncoming);
    if (overlap > 0) {
      return cleanedPrevious + cleanedIncoming.substring(overlap);
    }

    // Preserve original whitespace and spaces by concatenating the raw strings directly
    return previous + incoming;
  }

  static String delta(String previous, String incoming) {
    final merged = merge(previous, incoming);
    final cleanedPrevious = clean(previous);
    if (merged.length <= cleanedPrevious.length) {
      return '';
    }
    return merged.substring(cleanedPrevious.length);
  }

  static int _longestOverlap(String left, String right) {
    final maxOverlap = math.min(left.length, right.length);
    for (var overlap = maxOverlap; overlap > 0; overlap -= 1) {
      if (left.substring(left.length - overlap) ==
          right.substring(0, overlap)) {
        return overlap;
      }
    }
    return 0;
  }
}
