import '../models/educational_models.dart';

class SearchResult {
  final String id;
  final String title;
  final String content;
  final String type; // 'concept', 'flashcard', 'chapter'
  final double score;

  SearchResult({
    required this.id,
    required this.title,
    required this.content,
    required this.type,
    this.score = 1.0,
  });
}

class ChapterContextData {
  final ChapterModel chapter;
  final List<ConceptModel> concepts;
  final int estimatedTokens;

  ChapterContextData({
    required this.chapter,
    required this.concepts,
    required this.estimatedTokens,
  });
}
