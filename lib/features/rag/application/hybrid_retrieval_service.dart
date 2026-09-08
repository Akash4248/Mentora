import 'dart:convert';

import '../../../features/course/data/local/app_database.dart';
import '../domain/chunk_v2.dart';
import 'vector_embedding_service.dart';

/// Hybrid retrieval combining BM25 full-text search + semantic vector search
/// Returns ranked results blending both signals for better relevance
class HybridRetrievalService {
  HybridRetrievalService({
    AppDatabase? database,
    VectorEmbeddingService? vectorService,
  })  : _database = database ?? AppDatabase.instance,
        _vectorService = vectorService ?? VectorEmbeddingService();

  final AppDatabase _database;
  final VectorEmbeddingService _vectorService;

  /// Hybrid search: BM25 + semantic similarity
  /// Returns chunks ranked by combined score
  Future<List<RetrievalResult>> hybridSearch({
    required String query,
    required String chapterId,
    int limit = 10,
    double semanticWeight = 0.4,
  }) async {
    // Run both searches in parallel
    final bm25Results = _bm25Search(
      query: query,
      chapterId: chapterId,
      limit: limit * 2, // Get more for blending
    );

    final semanticResults = _semanticSearch(
      query: query,
      chapterId: chapterId,
      limit: limit * 2,
    );

    final [bm25, semantic] = await Future.wait([bm25Results, semanticResults]);

    // Blend scores: semantic gives us semantic relevance, BM25 gives exact match
    final blendedScores = <String, double>{};
    final chunkDetails = <String, (ChunkV2, String)>{}; // id -> (chunk, source)

    // Normalize BM25 scores
    final maxBm25 = bm25.isEmpty ? 1.0 : bm25.first.score;
    for (final result in bm25) {
      final normalized = result.score / maxBm25;
      blendedScores[result.chunk.id] = (normalized * (1 - semanticWeight));
      chunkDetails[result.chunk.id] = (result.chunk, 'bm25');
    }

    // Normalize semantic scores and blend
    final maxSemantic = semantic.isEmpty ? 1.0 : semantic.first.score;
    for (final result in semantic) {
      final normalized = result.score / maxSemantic;
      final weightedScore = normalized * semanticWeight;
      blendedScores[result.chunk.id] =
          (blendedScores[result.chunk.id] ?? 0) + weightedScore;

      if (!chunkDetails.containsKey(result.chunk.id)) {
        chunkDetails[result.chunk.id] = (result.chunk, 'semantic');
      } else {
        final (chunk, _) = chunkDetails[result.chunk.id]!;
        chunkDetails[result.chunk.id] = (chunk, 'both');
      }
    }

    // Sort by blended score and return top results
    return blendedScores.entries
        .map((e) {
          final (chunk, source) = chunkDetails[e.key]!;
          return RetrievalResult(
            chunk: chunk,
            score: e.value,
            source: source,
            bm25Score: bm25
                .firstWhere(
                  (r) => r.chunk.id == e.key,
                  orElse: () => RetrievalResult(
                    chunk: chunk,
                    score: 0,
                    source: '',
                  ),
                )
                .score,
            semanticScore: semantic
                .firstWhere(
                  (r) => r.chunk.id == e.key,
                  orElse: () => RetrievalResult(
                    chunk: chunk,
                    score: 0,
                    source: '',
                  ),
                )
                .score,
          );
        })
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score))
      ..take(limit)
        ..toList();
  }

  /// BM25 keyword search using FTS5 BM25 ranking or term-frequency weighted fallback
  Future<List<RetrievalResult>> _bm25Search({
    required String query,
    required String chapterId,
    required int limit,
  }) async {
    final db = await _database.database;

    final stopWords = {
      'what', 'is', 'the', 'meaning', 'of', 'explain', 'describe', 'tell', 'me',
      'about', 'how', 'does', 'work', 'can', 'you', 'give', 'an', 'example', 'a',
      'to', 'in', 'for', 'on', 'with', 'by', 'as', 'at', 'solution'
    };
    final rawTerms = query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty && !stopWords.contains(t))
        .toList();

    if (rawTerms.isEmpty) {
      return [];
    }

    // 1. Attempt FTS5 / FTS4 search with BM25 ranking via rag_chunks_fts
    try {
      final ftsMatch = rawTerms.map((t) => '$t*').join(' OR ');
      final ftsResults = await db.rawQuery('''
        SELECT c.*, -bm25(fts) AS fts_score
        FROM rag_chunks_v2 c
        INNER JOIN rag_chunks_fts fts ON fts.id = c.id
        WHERE c.chapter_id = ? AND fts MATCH ?
        ORDER BY fts_score DESC
        LIMIT ?
      ''', [chapterId, ftsMatch, limit]);

      if (ftsResults.isNotEmpty) {
        return ftsResults.map((row) {
          final chunk = _rowToChunk(row);
          final rawScore = (row['fts_score'] as num?)?.toDouble() ?? 1.0;
          return RetrievalResult(
            chunk: chunk,
            score: rawScore.clamp(0.1, 10.0),
            source: 'bm25',
          );
        }).toList();
      }
    } catch (_) {
      // FTS module missing or query error — continue to term-weighted fallback
    }

    // 2. Term-frequency weighted fallback search
    final likeTerms = rawTerms.map((t) => '%$t%').toList();
    final whereClauses = likeTerms.map((_) => 'content LIKE ?').join(' OR ');

    final results = await db.query(
      'rag_chunks_v2',
      where: 'chapter_id = ? AND ($whereClauses)',
      whereArgs: [chapterId, ...likeTerms],
      limit: limit,
    );

    return results.map((row) {
      final chunk = _rowToChunk(row);
      final contentLower = chunk.content.toLowerCase();
      int matches = 0;
      for (final term in rawTerms) {
        if (contentLower.contains(term)) matches++;
      }
      final score = matches / rawTerms.length;
      return RetrievalResult(
        chunk: chunk,
        score: score,
        source: 'bm25',
      );
    }).toList();
  }

  /// Semantic search using TF-IDF embeddings
  Future<List<RetrievalResult>> _semanticSearch({
    required String query,
    required String chapterId,
    required int limit,
  }) async {
    // Get all chunks in chapter
    final db = await _database.database;
    final rows = await db.query(
      'rag_chunks_v2',
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
    );

    if (rows.isEmpty) {
      return [];
    }

    final chunks = rows.map(_rowToChunk).toList();

    // Generate embeddings for all chunks
    final embeddings = <String, List<double>>{};
    try {
      for (final chunk in chunks) {
        embeddings[chunk.id] = _vectorService.generateEmbedding(chunk);
      }
    } catch (_) {
      // If vocabulary not initialized, return empty
      return [];
    }

    // Search using embeddings
    final results = _vectorService.searchSimilar(
      query,
      embeddings,
      threshold: 0.05,
    );

    return results
        .take(limit)
        .map((record) {
          final (id, similarity) = record;
          final chunk = chunks.firstWhere((c) => c.id == id);
          return RetrievalResult(
            chunk: chunk,
            score: (similarity + 1) / 2, // Normalize to 0-1 range
            source: 'semantic',
          );
        })
        .toList();
  }

  /// Configure semantic weight (0-1): how much to weight semantic relevance
  /// 0 = pure BM25, 1 = pure semantic, 0.5 = equal weight
  Future<List<RetrievalResult>> customWeightSearch({
    required String query,
    required String chapterId,
    required double semanticWeight,
    int limit = 10,
  }) async {
    if (semanticWeight < 0 || semanticWeight > 1) {
      throw ArgumentError('semanticWeight must be between 0 and 1');
    }
    return hybridSearch(
      query: query,
      chapterId: chapterId,
      limit: limit,
      semanticWeight: semanticWeight,
    );
  }

  /// Initialize vocabulary for semantic search from chapter's chunks
  Future<void> initializeChapterEmbeddings(String chapterId) async {
    final db = await _database.database;
    final rows = await db.query(
      'rag_chunks_v2',
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
    );

    if (rows.isNotEmpty) {
      final chunks = rows.map(_rowToChunk).toList();
      await _vectorService.initializeVocabulary(chunks);
    }
  }

  // ─────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────

  ChunkV2 _rowToChunk(Map<String, dynamic> row) {
    // Parse JSON fields if they exist
    List<Formula> formulas = [];
    if (row['formulas_json'] != null && (row['formulas_json'] as String).isNotEmpty) {
      try {
        final jsonList = jsonDecode(row['formulas_json']) as List;
        formulas = jsonList
            .map((item) => Formula.fromJson(item as Map<String, dynamic>))
            .toList();
      } catch (_) {
        // Silently ignore invalid JSON
      }
    }

    Map<String, dynamic> metadata = {};
    if (row['metadata_json'] != null && (row['metadata_json'] as String).isNotEmpty) {
      try {
        metadata = jsonDecode(row['metadata_json']) as Map<String, dynamic>;
      } catch (_) {
        // Silently ignore invalid JSON
      }
    }

    return ChunkV2(
      id: row['id'] as String,
      chapterId: row['chapter_id'] as String,
      content: row['content'] as String,
      contentType: row['content_type'] as String,
      sourceTitle: row['source_title'] as String,
      sourceLanguage: row['source_language'] as String? ?? 'en',
      chunkOrder: row['chunk_order'] as int,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      tokenCount: row['token_count'] as int? ?? 0,
      originalMarkdown: row['original_markdown'] as String?,
      formulas: formulas,
      metadata: metadata,
    );
  }
}

/// Result from hybrid retrieval with blend of both signals
class RetrievalResult {
  final ChunkV2 chunk;
  final double score; // Combined blended score (0-1)
  final String source; // 'bm25', 'semantic', or 'both'
  final double bm25Score;
  final double semanticScore;

  RetrievalResult({
    required this.chunk,
    required this.score,
    required this.source,
    this.bm25Score = 0,
    this.semanticScore = 0,
  });

  @override
  String toString() =>
      'RetrievalResult(${chunk.id}, score: ${score.toStringAsFixed(3)}, source: $source)';
}
