import '../../educational/data/educational_repository.dart';
import 'intent_detector.dart';

/// Source metadata attached to every asset response.
class AssetSourceMetadata {
  final String sourceType; // 'Flashcard', 'Quiz', 'Glossary', 'Chapter Summary', etc.
  final String sourceTitle;
  final String intentUsed;

  const AssetSourceMetadata({
    required this.sourceType,
    required this.sourceTitle,
    required this.intentUsed,
  });

  @override
  String toString() => 'Source=$sourceType | Title=$sourceTitle | Intent=$intentUsed';
}

/// Result of asset resolution.
class AssetResolutionResult {
  final String formattedResponse;
  final AssetSourceMetadata metadata;

  const AssetResolutionResult({
    required this.formattedResponse,
    required this.metadata,
  });
}

/// Resolves structured educational assets from the local SQLite database.
///
/// Routes intent-specific queries to the correct repository:
///   flashcards → EducationalRepository.getFlashcardsByChapterId
///   glossary   → EducationalRepository.getConceptsByChapterId
///   keyPoints  → EducationalRepository.getChapterById (summary)
///   quiz       → EducationalRepository.getQuizzesByChapterId
///
/// Bypasses the LLM entirely for asset intents.
class AssetResolver {
  const AssetResolver();

  /// Attempt to resolve an asset for the given intent and topic.
  ///
  /// Returns null if no matching asset is found, signaling the caller
  /// to fall through to RAG + LLM.
  Future<AssetResolutionResult?> resolve({
    required TutorIntent intent,
    required String topic,
    String? chapterId,
  }) async {
    switch (intent) {
      case TutorIntent.flashcards:
        return _resolveFlashcard(topic, chapterId);
      case TutorIntent.glossary:
        return _resolveGlossary(topic, chapterId);
      case TutorIntent.keyPoints:
      case TutorIntent.revisionPlan:
        return _resolveChapterSummary(topic, chapterId);
      case TutorIntent.startQuiz:
      case TutorIntent.continueQuiz:
        return _resolveQuiz(topic, chapterId);
      case TutorIntent.generateWorksheet:
        return _resolveWorksheet(topic, chapterId);
      default:
        return null;
    }
  }

  Future<AssetResolutionResult?> _resolveFlashcard(String topic, String? chapterId) async {
    // Strategy 1: If chapter context is available, query directly by chapter ID
    if (chapterId != null) {
      final chapterIdInt = int.tryParse(chapterId.replaceAll(RegExp(r'[^0-9]'), ''));
      if (chapterIdInt != null) {
        final flashcards = await EducationalRepository.getFlashcardsByChapterId(chapterIdInt);
        if (flashcards.isNotEmpty) {
          // Find the best match by topic, or return the first one
          final match = _findBestFlashcard(flashcards, topic);
          return AssetResolutionResult(
            formattedResponse: _formatFlashcard(match),
            metadata: AssetSourceMetadata(
              sourceType: 'Flashcard',
              sourceTitle: match.term,
              intentUsed: 'flashcards',
            ),
          );
        }
      }
    }

    return null;
  }

  Future<AssetResolutionResult?> _resolveGlossary(String topic, String? chapterId) async {
    if (chapterId != null) {
      final chapterIdInt = int.tryParse(chapterId.replaceAll(RegExp(r'[^0-9]'), ''));
      if (chapterIdInt != null) {
        final concepts = await EducationalRepository.getConceptsByChapterId(chapterIdInt);
        if (concepts.isNotEmpty) {
          final match = _findBestConcept(concepts, topic);
          if (match != null) {
            return AssetResolutionResult(
              formattedResponse: _formatGlossaryEntry(match),
              metadata: AssetSourceMetadata(
                sourceType: 'Glossary',
                sourceTitle: match.name,
                intentUsed: 'glossary',
              ),
            );
          }
          // If no topic match, return the full glossary
          return AssetResolutionResult(
            formattedResponse: _formatFullGlossary(concepts),
            metadata: AssetSourceMetadata(
              sourceType: 'Glossary',
              sourceTitle: 'Chapter Glossary (${concepts.length} terms)',
              intentUsed: 'glossary',
            ),
          );
        }
      }
    }

    return null;
  }

  Future<AssetResolutionResult?> _resolveChapterSummary(String topic, String? chapterId) async {
    if (chapterId != null) {
      final chapterIdInt = int.tryParse(chapterId.replaceAll(RegExp(r'[^0-9]'), ''));
      if (chapterIdInt != null) {
        final chapter = await EducationalRepository.getChapterById(chapterIdInt);
        if (chapter != null && (chapter.summary?.isNotEmpty == true || chapter.content?.isNotEmpty == true)) {
          final summaryText = chapter.summary ?? chapter.content ?? '';
          return AssetResolutionResult(
            formattedResponse: '**📋 Source: Chapter Summary**\n\n'
                '**Chapter:** ${chapter.name}\n\n'
                '$summaryText',
            metadata: AssetSourceMetadata(
              sourceType: 'Chapter Summary',
              sourceTitle: chapter.name,
              intentUsed: 'keyPoints',
            ),
          );
        }
      }
    }

    return null;
  }

  Future<AssetResolutionResult?> _resolveQuiz(String topic, String? chapterId) async {
    if (chapterId != null) {
      final chapterIdInt = int.tryParse(chapterId.replaceAll(RegExp(r'[^0-9]'), ''));
      if (chapterIdInt != null) {
        final quizzes = await EducationalRepository.getQuizzesByChapterId(chapterIdInt);
        if (quizzes.isNotEmpty) {
          final quiz = quizzes.first;
          final questions = await EducationalRepository.getQuizQuestions(quiz.id!);
          return AssetResolutionResult(
            formattedResponse: _formatQuiz(quiz, questions),
            metadata: AssetSourceMetadata(
              sourceType: 'Quiz',
              sourceTitle: quiz.title,
              intentUsed: 'startQuiz',
            ),
          );
        }
      }
    }

    return null;
  }

  Future<AssetResolutionResult?> _resolveWorksheet(String topic, String? chapterId) async {
    if (chapterId != null) {
      final chapterIdInt = int.tryParse(chapterId.replaceAll(RegExp(r'[^0-9]'), ''));
      if (chapterIdInt != null) {
        final quizzes = await EducationalRepository.getQuizzesByChapterId(chapterIdInt);
        if (quizzes.isNotEmpty) {
          final quiz = quizzes.first;
          final questions = await EducationalRepository.getQuizQuestions(quiz.id!);
          
          if (questions.isNotEmpty) {
            final worksheetQuestions = questions.take(5).toList();
            return AssetResolutionResult(
              formattedResponse: _formatWorksheet(worksheetQuestions, topic),
              metadata: AssetSourceMetadata(
                sourceType: 'Worksheet',
                sourceTitle: 'Practice Set: $topic',
                intentUsed: 'generateWorksheet',
              ),
            );
          }
        }
      }
    }
    
    return null;
  }

  // ── Formatting helpers ──

  String _formatFlashcard(dynamic flashcard) {
    final term = flashcard.term as String;
    final definition = flashcard.definition as String;
    final example = flashcard.example as String?;
    final buf = StringBuffer('**📇 Source: Flashcard**\n\n');
    buf.writeln('**Term:** $term\n');
    buf.writeln('**Definition:** $definition');
    if (example != null && example.isNotEmpty) {
      buf.writeln('\n**Example:** $example');
    }
    return buf.toString();
  }

  String _formatGlossaryEntry(dynamic concept) {
    final name = concept.name as String;
    final definition = concept.definition as String? ?? '';
    final examples = concept.examples as String?;
    final buf = StringBuffer('**📖 Source: Glossary**\n\n');
    buf.writeln('**Concept:** $name\n');
    buf.writeln('**Definition:** $definition');
    if (examples != null && examples.isNotEmpty) {
      buf.writeln('\n**Examples:** $examples');
    }
    return buf.toString();
  }

  String _formatFullGlossary(List<dynamic> concepts) {
    final buf = StringBuffer('**📖 Source: Glossary**\n\n');
    for (final c in concepts) {
      buf.writeln('• **${c.name}**: ${c.definition ?? ""}');
    }
    return buf.toString();
  }

  String _formatQuiz(dynamic quiz, List<dynamic> questions) {
    final buf = StringBuffer('**📝 Source: Quiz**\n\n');
    buf.writeln('**Quiz:** ${quiz.title}');
    if (quiz.description != null && (quiz.description as String).isNotEmpty) {
      buf.writeln('${quiz.description}\n');
    }
    buf.writeln('**Questions: ${questions.length}** | **Passing Score: ${quiz.passingScorePercent}%**\n');
    buf.writeln('*(Navigate to the Quizzes tab to start this quiz interactively!)*');
    return buf.toString();
  }

  String _formatWorksheet(List<dynamic> questions, String topic) {
    final buf = StringBuffer('**📝 Source: Worksheet**\n\n');
    buf.writeln('**Topic:** ${topic.isNotEmpty ? topic : "Practice Questions"}\n');
    
    for (int i = 0; i < questions.length; i++) {
      final q = questions[i];
      buf.writeln('**Q${i+1}:** ${q.question}\n');
    }
    
    return buf.toString();
  }

  // ── Matching helpers ──

  dynamic _findBestFlashcard(List<dynamic> flashcards, String topic) {
    if (topic.isEmpty) return flashcards.first;
    final topicLower = topic.toLowerCase();
    for (final fc in flashcards) {
      if ((fc.term as String).toLowerCase().contains(topicLower)) return fc;
    }
    for (final fc in flashcards) {
      if ((fc.definition as String).toLowerCase().contains(topicLower)) return fc;
    }
    return flashcards.first;
  }

  dynamic _findBestConcept(List<dynamic> concepts, String topic) {
    if (topic.isEmpty) return null;
    final topicLower = topic.toLowerCase();
    for (final c in concepts) {
      if ((c.name as String).toLowerCase().contains(topicLower)) return c;
    }
    for (final c in concepts) {
      final def = c.definition as String? ?? '';
      if (def.toLowerCase().contains(topicLower)) return c;
    }
    return null;
  }
}
