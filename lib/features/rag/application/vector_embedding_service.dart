import 'dart:convert';
import 'dart:math' as math;

import '../domain/chunk_v2.dart';

/// Lightweight TF-IDF based embedding service for offline semantic search
/// Generates normalized TF-IDF vectors for chunks without external ML dependencies
class VectorEmbeddingService {
  final Map<String, double> _globalIdf = {}; // Cached IDF values
  final List<String> _vocabulary = []; // Ordered vocabulary
  final int _minTermFreq = 2; // Minimum documents containing term for inclusion

  bool get isVocabularyEmpty => _vocabulary.isEmpty;

  /// Initialize vocabulary and IDF from corpus of chunks
  Future<void> initializeVocabulary(List<ChunkV2> trainingChunks) async {
    if (trainingChunks.isEmpty) return;

    // Build document-term matrix
    final docTerms = <String, Set<String>>{};
    final termDocCount = <String, int>{};

    for (final chunk in trainingChunks) {
      final terms = _tokenize(chunk.content);
      docTerms[chunk.id] = terms;

      for (final term in terms) {
        termDocCount[term] = (termDocCount[term] ?? 0) + 1;
      }
    }

    // Filter terms by minimum document frequency
    final frozenTerms = termDocCount.entries
        .where((e) => e.value >= _minTermFreq)
        .map((e) => e.key)
        .toList()
      ..sort();

    _vocabulary.clear();
    _vocabulary.addAll(frozenTerms);

    // Compute IDF for each term
    final n = trainingChunks.length.toDouble();
    _globalIdf.clear();

    for (final term in _vocabulary) {
      final df = termDocCount[term]?.toDouble() ?? 1.0;
      _globalIdf[term] = math.log(n / df);
    }
  }

  /// Generate TF-IDF embedding vector for a chunk
  List<double> generateEmbedding(ChunkV2 chunk) {
    if (_vocabulary.isEmpty) {
      throw StateError('Vocabulary not initialized. Call initializeVocabulary first.');
    }

    // Tokenize and compute term frequencies
    final terms = _tokenize(chunk.content);
    final termFreq = <String, int>{};
    for (final term in terms) {
      termFreq[term] = (termFreq[term] ?? 0) + 1;
    }

    // Build TF-IDF vector
    final vector = List<double>.filled(_vocabulary.length, 0.0);
    final totalTerms = terms.length.toDouble();

    for (var i = 0; i < _vocabulary.length; i++) {
      final term = _vocabulary[i];
      final tf = (termFreq[term] ?? 0) / totalTerms;
      final idf = _globalIdf[term] ?? 0.0;
      vector[i] = tf * idf;
    }

    // L2 normalize
    return _normalize(vector);
  }

  /// Compute cosine similarity between two embedding vectors
  double cosineSimilarity(List<double> vec1, List<double> vec2) {
    if (vec1.length != vec2.length) {
      throw ArgumentError('Vectors must have same dimension');
    }

    var dotProduct = 0.0;
    for (var i = 0; i < vec1.length; i++) {
      dotProduct += vec1[i] * vec2[i];
    }

    return dotProduct; // Already normalized, so dot product = cosine similarity
  }

  /// Batch generate embeddings for multiple chunks
  Future<Map<String, List<double>>> generateBatchEmbeddings(
    List<ChunkV2> chunks,
  ) async {
    final embeddings = <String, List<double>>{};
    for (final chunk in chunks) {
      embeddings[chunk.id] = generateEmbedding(chunk);
    }
    return embeddings;
  }

  /// Search for similar chunks using embedding similarity
  /// Returns list of (chunkId, similarity) sorted by relevance
  List<(String id, double similarity)> searchSimilar(
    String queryText,
    Map<String, List<double>> chunkEmbeddings, {
    double threshold = 0.1,
  }) {
    // Create temporary chunk for query
    final queryChunk = ChunkV2(
      id: 'query',
      chapterId: '',
      content: queryText,
      contentType: 'query',
      sourceTitle: '',
      sourceLanguage: 'en',
      chunkOrder: 0,
      createdAt: DateTime.now(),
    );

    final queryVector = generateEmbedding(queryChunk);

    final results = <(String id, double similarity)>[];
    chunkEmbeddings.forEach((chunkId, embedding) {
      final similarity = cosineSimilarity(queryVector, embedding);
      if (similarity >= threshold) {
        results.add((chunkId, similarity));
      }
    });

    results.sort((a, b) => b.$2.compareTo(a.$2));
    return results;
  }

  /// Get vocabulary size (vector dimension)
  int get vocabularySize => _vocabulary.length;

  /// Get cached vocabulary for serialization
  List<String> get vocabulary => List.unmodifiable(_vocabulary);

  /// Get cached IDF values for serialization
  Map<String, double> get globalIdf => Map.unmodifiable(_globalIdf);

  // ─────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────

  /// Tokenize text: lowercase, split, remove stop words
  Set<String> _tokenize(String text) {
    // Lowercase and split on non-alphanumeric
    final tokens = text.toLowerCase().split(RegExp(r'[^a-z0-9ಕ-ೃ]+'));

    // Filter: remove empty, stop words, and too-short terms
    final stopWords = {
      'the', 'a', 'an', 'and', 'or', 'is', 'are', 'was', 'were', 'be', 'been',
      'being', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
      'could', 'should', 'may', 'might', 'must', 'can', 'in', 'on', 'at', 'to',
      'for', 'of', 'with', 'by', 'from', 'as', 'it', 'its', 'this', 'that',
      'these', 'those', 'i', 'you', 'he', 'she', 'we', 'they', 'what', 'which',
      'who', 'whom', 'why', 'how', 'when', 'where', 'ಮತ್ತು', 'ಈ', 'ಆ',
    };

    return tokens
        .where((t) => t.isNotEmpty && t.length > 2 && !stopWords.contains(t))
        .toSet();
  }

  /// L2 normalize a vector to unit length
  List<double> _normalize(List<double> vector) {
    var magnitude = 0.0;
    for (final v in vector) {
      magnitude += v * v;
    }
    magnitude = math.sqrt(magnitude);

    if (magnitude == 0) {
      return vector;
    }

    return vector.map((v) => v / magnitude).toList();
  }

  /// Convert embedding to JSON-compatible format
  static String embedToJsonStr(List<double> embedding) {
    return jsonEncode(embedding);
  }

  /// Deserialize embedding from JSON string
  static List<double> embedFromJsonStr(String jsonStr) {
    final list = jsonDecode(jsonStr) as List;
    return list.map((v) => (v as num).toDouble()).toList();
  }
}
