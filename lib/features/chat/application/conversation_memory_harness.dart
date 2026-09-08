import '../domain/tutor_message.dart';
import '../data/local/chat_memory_policy_repository.dart';
import '../../rag/data/local/rag_repository.dart';

/// Memory Harness that manages sliding window history, compaction summary,
/// semantic recall, and tool-calling context injection for Mentora AI Tutor.
class ConversationMemoryHarness {
  ConversationMemoryHarness({RagRepository? ragRepository})
      : _ragRepository = ragRepository ?? RagRepository();

  final RagRepository _ragRepository;

  /// Builds a fully contextualized ChatML / Socratic prompt including:
  /// 1. System Guardrails & Tool Definitions
  /// 2. Compacted Summary of older messages (beyond sliding window)
  /// 3. Semantically recalled past memories / textbook RAG chunks
  /// 4. Sliding window of recent N chat messages
  Future<String> buildContextualPrompt({
    required List<TutorMessage> history,
    required String currentQuestion,
    required String chapterTitle,
    required String courseName,
    required ChatMemoryPolicy policy,
  }) async {
    final buffer = StringBuffer();

    // 1. System Role & Guardrails
    buffer.writeln('### System Context');
    buffer.writeln(
      'You are Mentora Socratic AI Tutor for $courseName, Grade 9. '
      'Subject Chapter: "$chapterTitle". '
      'Guide the student through interactive questioning, clear step-by-step explanations, and real-world examples. '
      'DO NOT give direct answers immediately if a guided hint helps them think.',
    );
    buffer.writeln();

    // 2. Available Tool Declarations (Function Calling Harness)
    buffer.writeln('### Available Memory & Knowledge Tools');
    buffer.writeln(
      '- Tool `search_chapter_knowledge(query)`: Search NCERT textbook concepts.\n'
      '- Tool `lookup_past_memory(query)`: Search previous student chat turns across chapters.',
    );
    buffer.writeln();

    // Separate history into older messages (to compact) vs recent sliding window
    final windowSize = policy.shortTermWindow > 0 ? policy.shortTermWindow : 8;
    final validHistory = history.where((m) => m.text.trim() != 'Thinking...').toList();

    List<TutorMessage> olderMessages = [];
    List<TutorMessage> recentMessages = validHistory;

    if (validHistory.length > windowSize) {
      olderMessages = validHistory.sublist(0, validHistory.length - windowSize);
      recentMessages = validHistory.sublist(validHistory.length - windowSize);
    }

    // 3. Compacted Conversation Summary Layer
    if (olderMessages.isNotEmpty) {
      final summary = _compactOlderHistory(olderMessages);
      buffer.writeln('### Previous Conversation Summary (Compacted)');
      buffer.writeln(summary);
      buffer.writeln();
    }

    // 4. Semantic Memory / RAG Recall Layer
    if (policy.semanticRecallEnabled) {
      try {
        final ragCheck = await _ragRepository.localRagPreCheck(
          chapterId: '',
          query: currentQuestion,
          limit: policy.semanticTopK > 0 ? policy.semanticTopK : 2,
        );
        if (ragCheck.chunks.isNotEmpty) {
          buffer.writeln('### Retrieved Relevant Textbook & Memory Context');
          for (final chunk in ragCheck.chunks) {
            final text = chunk.content;
            if (text.isNotEmpty) {
              buffer.writeln('- $text');
            }
          }
          buffer.writeln();
        }
      } catch (_) {
        // Best-effort RAG recall; non-blocking
      }
    }

    // 5. Short-Term Sliding Window Chat History
    if (recentMessages.isNotEmpty) {
      buffer.writeln('### Recent Conversation History (Sliding Window)');
      for (final msg in recentMessages) {
        final role = msg.isUser ? 'Student' : 'Tutor';
        buffer.writeln('$role: ${msg.text}');
      }
      buffer.writeln();
    }

    // 6. Current User Question
    buffer.writeln('### Student Question');
    buffer.writeln('Student: $currentQuestion');

    return buffer.toString();
  }

  /// Compacts older conversation turns into a high-density summary block
  String _compactOlderHistory(List<TutorMessage> olderMessages) {
    final topics = <String>[];
    for (final m in olderMessages) {
      if (m.isUser && m.text.length > 5) {
        final snippet = m.text.length > 60 ? '${m.text.substring(0, 60)}...' : m.text;
        topics.add('Asked about: "$snippet"');
      }
    }

    if (topics.isEmpty) {
      return '- Earlier discussion covered initial chapter introduction and basic concepts.';
    }

    return topics.map((t) => '- $t').join('\n');
  }
}
