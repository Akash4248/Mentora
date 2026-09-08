import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../domain/rag_chunk.dart';
import '../data/local/embedding_index_repository.dart';
import '../data/local/rag_repository.dart';
import 'on_device_embedding_engine.dart';

class VectorSearchHit {
  final RagChunk chunk;
  final double cosineSimilarity;
  final double lexicalScore;
  final double hybridScore;

  VectorSearchHit({
    required this.chunk,
    required this.cosineSimilarity,
    required this.lexicalScore,
    required this.hybridScore,
  });
}

class VectorSearchService {
  VectorSearchService({
    EmbeddingIndexRepository? embeddingRepository,
    RagRepository? ragRepository,
  })  : _embeddingRepository = embeddingRepository ?? EmbeddingIndexRepository(),
        _ragRepository = ragRepository ?? RagRepository();

  final EmbeddingIndexRepository _embeddingRepository;
  final RagRepository _ragRepository;

  /// Performs hybrid semantic vector search + lexical keyword scoring across local chunks.
  Future<List<VectorSearchHit>> searchChapter({
    required String chapterId,
    required String query,
    int topK = 5,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return [];
    }

    final queryVector = OnDeviceEmbeddingEngine.instance.generateEmbedding(trimmed);
    final indexedVectors = await _embeddingRepository.getVectorEmbeddingsForChapter(chapterId: chapterId);
    
    if (indexedVectors.isEmpty) {
      // Fallback to lexical check if vector index has not been populated yet
      final ragCheck = await _ragRepository.checkChapterLocalContent(
        chapterId: chapterId,
        question: query,
        maxChunks: topK,
      );
      return ragCheck.chunks
          .map((chunk) => VectorSearchHit(
                chunk: chunk,
                cosineSimilarity: 0.0,
                lexicalScore: 0.5,
                hybridScore: 0.5,
              ))
          .toList();
    }

    final hits = <VectorSearchHit>[];
    final queryTokens = _tokenize(trimmed);

    for (final item in indexedVectors) {
      final chunk = item.chunk;
      final vectorBlob = item.vectorBlob;
      double sim = 0.0;

      if (vectorBlob != null && vectorBlob.isNotEmpty) {
        final chunkVector = OnDeviceEmbeddingEngine.unpackVector(vectorBlob);
        sim = OnDeviceEmbeddingEngine.computeCosineSimilarity(queryVector, chunkVector);
      }

      final chunkTokens = _tokenize(chunk.content);
      double lex = 0.0;
      if (queryTokens.isNotEmpty && chunkTokens.isNotEmpty) {
        final matches = queryTokens.intersection(chunkTokens).length;
        lex = matches / queryTokens.length;
      }

      // Hybrid rank score (60% semantic vector similarity + 40% lexical keyword overlap)
      final hybrid = (0.6 * sim) + (0.4 * lex);

      hits.add(VectorSearchHit(
        chunk: chunk,
        cosineSimilarity: sim,
        lexicalScore: lex,
        hybridScore: hybrid,
      ));
    }

    hits.sort((a, b) => b.hybridScore.compareTo(a.hybridScore));
    return hits.take(topK).toList();
  }

  Set<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s\u0900-\u097F\u0C80-\u0CFF']"), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toSet();
  }
}
