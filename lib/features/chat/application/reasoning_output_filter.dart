class ReasoningOutputFilter {
  final StringBuffer _buffer = StringBuffer();

  String _emitted = '';

  String push(String chunk) {
    if (chunk.isEmpty) {
      return '';
    }

    _buffer.write(chunk);
    var text = _buffer.toString();
    var cleaned = stripComplete(text);

    if (_hasOpenReasoningTag(cleaned)) {
      final openIndex = _firstOpenReasoningTag(cleaned);
      cleaned = cleaned.substring(0, openIndex);
    }

    // Withhold emission if it ends with a potential partial stop token
    // For example, if it ends with "<", "<|", etc.
    final partialStop = _endsWithPartialStopToken(cleaned);
    if (partialStop > 0) {
      cleaned = cleaned.substring(0, cleaned.length - partialStop);
    }

    if (cleaned.startsWith(_emitted)) {
      final delta = cleaned.substring(_emitted.length);
      _emitted = cleaned;
      return delta;
    } else {
      // If stripComplete retroactively modified something we already emitted
      // we just emit the new characters that are beyond the emitted length, or fallback.
      // Because we can't un-emit, we'll try to find the longest common prefix.
      int common = 0;
      while (common < _emitted.length && common < cleaned.length && _emitted[common] == cleaned[common]) {
        common++;
      }
      final delta = cleaned.substring(common);
      _emitted = cleaned;
      return delta;
    }
  }

  String flush() {
    var cleaned = stripComplete(_buffer.toString());
    if (_hasOpenReasoningTag(cleaned)) {
      final openIndex = _firstOpenReasoningTag(cleaned);
      cleaned = cleaned.substring(0, openIndex);
    }
    
    if (cleaned.startsWith(_emitted)) {
      final delta = cleaned.substring(_emitted.length);
      _emitted = cleaned;
      return delta;
    } else {
      int common = 0;
      while (common < _emitted.length && common < cleaned.length && _emitted[common] == cleaned[common]) {
        common++;
      }
      final delta = cleaned.substring(common);
      _emitted = cleaned;
      return delta;
    }
  }

  int _endsWithPartialStopToken(String text) {
    final stopTokens = const <String>[
      '<|im_start|>', '<|im_end|>', '<_im_end_>', '<|endoftext|>', '<end_of_turn>', '</s>', '[END]', '<think>', '<reasoning>', '<analysis>'
    ];
    for (int i = 1; i <= text.length; i++) {
      final suffix = text.substring(text.length - i);
      if (!suffix.startsWith('<') && !suffix.startsWith('[')) {
        continue;
      }
      for (final st in stopTokens) {
        if (st == suffix || st.startsWith(suffix)) return i;
      }
    }
    return 0;
  }

  static String stripComplete(String text) {
    var output = text.replaceAll('\r', '');

    // Strip ChatML stop tokens and everything after them
    for (final stopToken in const <String>[
      '<|im_start|>',
      '<|im_end|>',
      '<_im_end_>',
      '<|endoftext|>',
      '<end_of_turn>',
      '</s>',
      '[END]',
      '<|im_end',
      '<|im_start',
    ]) {
      final idx = output.indexOf(stopToken);
      if (idx >= 0) {
        output = output.substring(0, idx);
      }
    }

    // Strip any lingering stop tag literal occurrences
    output = output.replaceAll(RegExp(r'<\|im_(start|end)\|>'), '');

    // Strip <think>/<reasoning>/<analysis> blocks
    for (final tag in const <String>['think', 'reasoning', 'analysis']) {
      output = output.replaceAll(
        RegExp('<$tag[^>]*>[\\s\\S]*?</$tag>', caseSensitive: false),
        '',
      );
    }
    output = _stripPromptEcho(output);
    return output.trim();
  }

  static String _stripPromptEcho(String text) {
    final lines = text.split('\n');
    final kept = <String>[];
    var startedAnswer = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        if (startedAnswer && kept.isNotEmpty && kept.last.isNotEmpty) {
          kept.add('');
        }
        continue;
      }

      final lower = trimmed.toLowerCase();
      if (!startedAnswer && _isPromptScaffoldLine(lower)) {
        continue;
      }

      if (lower.startsWith('answer:') || lower.startsWith('tutor answer:')) {
        final colonIndex = trimmed.indexOf(':');
        final remainder = colonIndex >= 0
            ? trimmed.substring(colonIndex + 1).trim()
            : '';
        if (remainder.isNotEmpty) {
          kept.add(remainder);
          startedAnswer = true;
        }
        continue;
      }

      if (!startedAnswer) {
        if (lower.startsWith('student question:') ||
            lower.startsWith('question:') ||
            lower.startsWith('user query:') ||
            lower.startsWith('recent conversation:') ||
            lower.startsWith('session summary:') ||
            lower.startsWith('priority context:') ||
            lower.startsWith('relevant notes:') ||
            lower.startsWith('context:') ||
            lower.startsWith('educational context:')) {
          continue;
        }

        if (trimmed.startsWith('[') && lower.contains('source')) {
          continue;
        }
      }

      startedAnswer = true;
      kept.add(line);
    }

    return kept.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static bool _isPromptScaffoldLine(String lower) {
    return lower.startsWith('system:') ||
        lower.startsWith('system ') ||
        lower.startsWith('instruction:') ||
        lower.startsWith('instructions:') ||
        lower.startsWith('educational context:') ||
        lower.startsWith('priority context:') ||
        lower.startsWith('session summary:') ||
        lower.startsWith('recent conversation:') ||
        lower.startsWith('relevant notes:') ||
        lower.startsWith('context:') ||
        lower.startsWith('student question:') ||
        lower.startsWith('question:') ||
        lower.startsWith('student:') ||
        lower.startsWith('tutor:') ||
        lower.startsWith('answer:') ||
        lower.startsWith('tutor answer:') ||
        lower.startsWith('user query:') ||
        lower.startsWith('[source') ||
        lower.startsWith('you are an expert') ||
        lower.startsWith('you are a helpful') ||
        lower.startsWith('you are an educational') ||
        lower.startsWith('provide clear') ||
        lower.startsWith('provide structured') ||
        lower.startsWith('prioritize learning') ||
        lower.startsWith('subject:') ||
        lower.startsWith('chapter:') ||
        lower.startsWith('topic:') ||
        lower.startsWith('language:') ||
        lower.startsWith('teaching style:') ||
        lower.startsWith('grade') ||
        RegExp(r'^[\-\s=]{3,}$').hasMatch(lower) ||
        lower.contains('do not reveal internal reasoning') ||
        lower.contains('do not output chain of thought') ||
        lower.contains('provide only the final answer') ||
        lower.contains('answer only') ||
        lower.contains('return one short answer only') ||
        lower.contains('use provided context only');
  }

  bool _hasOpenReasoningTag(String text) {
    final open = _firstOpenReasoningTag(text);
    if (open < 0) {
      return false;
    }
    final tail = text.substring(open).toLowerCase();
    return !tail.contains('</think>') &&
        !tail.contains('</reasoning>') &&
        !tail.contains('</analysis>');
  }

  int _firstOpenReasoningTag(String text) {
    final match = RegExp(
      r'<(think|reasoning|analysis)\b[^>]*>',
      caseSensitive: false,
    ).firstMatch(text);
    return match?.start ?? -1;
  }
}
