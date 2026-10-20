/// Attributable grounding lesson chunk retrieved from the local textbook/curriculum.
final class GroundingChunk {
  const GroundingChunk({
    required this.id,
    required this.chapterId,
    required this.sourceTitle,
    required this.content,
    this.tokenCount = 0,
  });

  /// Unique identifier of the curriculum chunk.
  final String id;

  /// Chapter identifier (e.g. 'chap_linear_eq', 'chap_motion').
  final String chapterId;

  /// Clear, un-fabricated human-readable source title (e.g. 'NCERT Class 9 Physics: Motion').
  final String sourceTitle;

  /// Clean textual curriculum content.
  final String content;

  /// Approximate or calculated token count.
  final int tokenCount;

  /// Formatted citation string.
  String get citation => 'Source: $sourceTitle (Chapter: $chapterId)';

  @override
  String toString() => 'GroundingChunk($id, $sourceTitle)';
}
