import 'retrieval_router.dart';
import '../models/educational_models.dart';
import '../models/local_search_models.dart';
import '../../../config/app_environment.dart';

/// Tutorial response from the offline tutor
class TutorialResponse {
  final String id; // Unique response ID
  final String question;
  final String explanation; // Main explanation
  final List<String> keyPoints; // Key takeaways
  final String? relatedConcepts; // Comma-separated related concept names
  final List<String>? examples; // Example applications
  final String? nextRecommendation; // Suggested next topic to learn
  final int confidencePercent; // 0-100: confidence in response quality
  final DateTime timestamp;
  final bool isOfflineGenerated; // Whether this was generated offline

  TutorialResponse({
    required this.id,
    required this.question,
    required this.explanation,
    required this.keyPoints,
    this.relatedConcepts,
    this.examples,
    this.nextRecommendation,
    required this.confidencePercent,
    required this.timestamp,
    required this.isOfflineGenerated,
  });
}

/// Offline tutor service using local educational content
class OfflineTutorService {
  static final OfflineTutorService _instance = OfflineTutorService._internal();

  factory OfflineTutorService() {
    return _instance;
  }

  void rateResponse(String id, int rating) {
    AppEnvironment.log('SYNC', '[OfflineTutor] Rating response $id: $rating stars');
  }

  /// Answer a student question using local educational content
  /// 
  /// Process:
  /// 1. Route query to local retrieval engine
  /// 2. If local results: build explanation from local content
  /// 3. If no local results: provide guidance to seek backend tutor
  /// 4. Return TutorialResponse with confidence level
  Future<TutorialResponse?> answerQuestion(String question) async {
    try {
      AppEnvironment.log('SYNC', '[OfflineTutor] Answering question: "$question"');

      // Step 1: Route query
      final decision = await _router.routeQuery(question);

      // Step 2: Check if we have sufficient local content
      if (!decision.useLocal || decision.localResults.isEmpty) {
        AppEnvironment.log(
          'SYNC',
          '[OfflineTutor] Insufficient local results - recommending backend tutor',
        );

        // Return guidance response
        return _buildGuidanceResponse(question, decision.confidence);
      }

      // Step 3: Build explanation from local results
      final response = await _buildTutorialResponse(
        question,
        decision.localResults,
        decision.confidence,
      );

      AppEnvironment.log(
        'SYNC',
        '[OfflineTutor] Generated response (confidence: ${response.confidencePercent}%)',
      );

      return response;
    } catch (e) {
      AppEnvironment.log('SYNC', '[OfflineTutor] Error answering question: $e');
      return null;
    }
  }

  /// Build tutorial response from search results
  Future<TutorialResponse> _buildTutorialResponse(
    String question,
    List<SearchResult> results,
    double confidence,
  ) async {
    // Primary result (highest relevance)
    final primaryResult = results.first;

    // Get chapter context if available
    final concepts = _extractConceptsFromResults(results);
    ChapterContextData? context;

    if (primaryResult.type == 'concept' || primaryResult.type == 'chapter') {
      context = await _search.getChapterContext(primaryResult.id, concepts);
    }

    // Build explanation using primary result and context
    final explanation = _buildExplanation(
      question,
      primaryResult,
      context,
    );

    // Extract key points
    final keyPoints = _extractKeyPoints(primaryResult.content, concepts);

    // Find related concepts
    final relatedConcepts = _findRelatedConcepts(results);

    // Generate examples based on content
    final examples = _generateExamples(primaryResult, concepts);

    // Recommend next topic
    final nextRecommendation = _recommendNextTopic(primaryResult, concepts);

    return TutorialResponse(
      id: _generateResponseId(),
      question: question,
      explanation: explanation,
      keyPoints: keyPoints,
      relatedConcepts: relatedConcepts,
      examples: examples,
      nextRecommendation: nextRecommendation,
      confidencePercent: (confidence * 100).toInt(),
      timestamp: DateTime.now(),
      isOfflineGenerated: true,
    );
  }

  /// Build guidance response when local content insufficient
  TutorialResponse _buildGuidanceResponse(String question, double confidence) {
    return TutorialResponse(
      id: _generateResponseId(),
      question: question,
      explanation: '''
I have limited information about "$question" in my offline knowledge base.

To get a comprehensive answer, I recommend:
1. **Download Educational Packs** - Get offline access to more subjects
2. **Connect to Backend Tutor** - Use the AI tutor when internet is available
3. **Explore Related Topics** - Browse similar topics that might help

In the meantime, here are some suggestions for nearby learning:
- Review concepts from earlier chapters
- Try flashcards to reinforce fundamentals
- Attempt practice quizzes to identify knowledge gaps
      ''',
      keyPoints: [
        'Limited local knowledge available',
        'Download packs for more content',
        'Use backend tutor when available',
      ],
      confidencePercent: (confidence * 100).toInt(),
      timestamp: DateTime.now(),
      isOfflineGenerated: true,
    );
  }

  /// Build explanation from primary result and context
  String _buildExplanation(
    String question,
    SearchResult result,
    ChapterContextData? context,
  ) {
    final buffer = StringBuffer();

    buffer.writeln('**Based on: ${result.title}**\n');

    if (result.type == 'concept') {
      buffer.writeln('## Definition');
      buffer.writeln(result.content);
      buffer.writeln();

      if (context != null) {
        buffer.writeln('## Detailed Explanation');
        buffer.writeln(context.chapter.summary ?? 'See course content for more details.');
        buffer.writeln();
      }
    } else if (result.type == 'chapter') {
      buffer.writeln('## Chapter Content');
      buffer.writeln(result.content);
      buffer.writeln();

      if (context != null && context.chapter.content != null) {
        buffer.writeln('## Full Details');
        buffer.writeln(context.chapter.content);
        buffer.writeln();
      }
    } else if (result.type == 'flashcard') {
      buffer.writeln('## Term Definition');
      buffer.writeln(result.content);
      buffer.writeln();
    } else {
      buffer.writeln(result.content);
      buffer.writeln();
    }

    // Add learning tip
    buffer.writeln('**💡 Learning Tip:** Review related concepts to build deeper understanding.');

    return buffer.toString();
  }

  /// Extract key points from content
  List<String> _extractKeyPoints(String content, List<ConceptModel> concepts) {
    final keyPoints = <String>[];

    // Add concept definitions as key points
    for (final concept in concepts.take(3)) {
      if (concept.definition != null) {
        keyPoints.add(concept.definition!.length > 100
            ? '${concept.definition!.substring(0, 100)}...'
            : concept.definition!);
      }
    }

    // Extract sentences starting with important keywords
    final importantPatterns = [
      'important',
      'note',
      'remember',
      'key',
      'essential',
      'significant',
    ];

    final sentences = content.split('.');
    for (final sentence in sentences) {
      final lower = sentence.toLowerCase();
      for (final pattern in importantPatterns) {
        if (lower.contains(pattern)) {
          final cleaned = sentence.trim();
          if (cleaned.isNotEmpty && keyPoints.length < 5) {
            keyPoints.add(cleaned);
          }
          break;
        }
      }
    }

    return keyPoints.isNotEmpty
        ? keyPoints.take(5).toList()
        : ['Review the explanation above for key insights'];
  }

  /// Find related concepts from search results
  String? _findRelatedConcepts(List<SearchResult> results) {
    final related = <String>[];

    for (final result in results) {
      if (result.type == 'concept') {
        related.add(result.title);
      }
    }

    return related.isNotEmpty ? related.take(5).join(', ') : null;
  }

  /// Generate examples from content and concepts
  List<String>? _generateExamples(
    SearchResult result,
    List<ConceptModel> concepts,
  ) {
    final examples = <String>[];

    // Use concept examples if available
    for (final concept in concepts) {
      if (concept.examples != null && concept.examples!.isNotEmpty) {
        examples.add(concept.examples!);
      }
    }

    // Try to extract examples from content
    if (result.content.contains('example')) {
      final parts = result.content.split('example');
      if (parts.length > 1) {
        final example = parts[1].split('.').first.trim();
        if (example.isNotEmpty) {
          examples.add('Example: $example');
        }
      }
    }

    return examples.isNotEmpty ? examples.take(3).toList() : null;
  }

  /// Recommend next topic to learn
  String? _recommendNextTopic(
    SearchResult result,
    List<ConceptModel> concepts,
  ) {
    if (concepts.length > 1) {
      final nextConcept = concepts[1];
      return 'Next, explore "${nextConcept.name}" to build on this foundation.';
    }

    return null;
  }

  /// Extract concept models from search results
  List<ConceptModel> _extractConceptsFromResults(List<SearchResult> results) {
    final concepts = <ConceptModel>[];

    for (final result in results) {
      if (result.type == 'concept') {
        concepts.add(
          ConceptModel(
            id: int.tryParse(result.id),
            chapterId: 0, // TODO: Get from database if needed
            name: result.title,
            sequenceNumber: 0,
            definition: result.content,
            examples: null,
            relatedConcepts: null,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }
    }

    return concepts;
  }

  /// Generate unique response ID
  String _generateResponseId() {
    return 'tutor_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Rate helpfulness of response (for learning)
  void rateResponse(String responseId, int rating) {
    // Rating: 1-5 stars
    if (rating < 1 || rating > 5) return;

    AppEnvironment.log(
      'SYNC',
      '[OfflineTutor] User rated response: $rating/5 (responseId: $responseId)',
    );

    // TODO: Store rating for analytics and model improvement
  }

  /// Get follow-up suggestions
  Future<List<String>> getFollowUpSuggestions(String question) async {
    try {
      // Get initial response
      final response = await answerQuestion(question);
      if (response == null) return [];

      // Generate follow-up questions
      final suggestions = <String>[];

      if (response.relatedConcepts != null) {
        suggestions.add('Learn more about: ${response.relatedConcepts}');
      }

      if (response.nextRecommendation != null) {
        suggestions.add(response.nextRecommendation!);
      }

      suggestions.add('Try a quiz to test your understanding');
      suggestions.add('Use flashcards for this chapter');

      return suggestions;
    } catch (e) {
      AppEnvironment.log('SYNC', '[OfflineTutor] Error getting follow-ups: $e');
      return [];
    }
  }
}

/// Extension for formatting tutor responses
extension TutorialResponseFormatting on TutorialResponse {
  /// Get formatted response for display in UI
  String getFormattedResponse() {
    final buffer = StringBuffer();

    buffer.writeln(explanation);
    buffer.writeln();

    if (keyPoints.isNotEmpty) {
      buffer.writeln('### Key Points');
      for (final point in keyPoints) {
        buffer.writeln('• $point');
      }
      buffer.writeln();
    }

    if (examples != null && examples!.isNotEmpty) {
      buffer.writeln('### Examples');
      for (final example in examples!) {
        buffer.writeln('• $example');
      }
      buffer.writeln();
    }

    if (relatedConcepts != null) {
      buffer.writeln('### Related Topics');
      buffer.writeln(relatedConcepts);
      buffer.writeln();
    }

    if (nextRecommendation != null) {
      buffer.writeln('### Next Step');
      buffer.writeln(nextRecommendation);
      buffer.writeln();
    }

    buffer.writeln('*Generated offline • Confidence: $confidencePercent%*');

    return buffer.toString();
  }

  /// Get concise summary for quick reference
  String getSummary() {
    return '$explanation\n\n${keyPoints.map((p) => '• $p').join('\n')}';
  }
}
