import '../../domain/chunk_v2.dart';
import '../../domain/rag_chunk.dart';
import 'rag_repository_v2.dart';

class RagCheckResult {
  final int chunkCount;
  final double topScore;
  final List<RagChunk> chunks;

  RagCheckResult({
    required this.chunkCount,
    required this.topScore,
    required this.chunks,
  });

  bool get hasRelevantLocalContent => chunkCount > 0 && topScore <= -0.1;
}

/// DEPRECATED single-store facade.
///
/// All reads/writes go to `rag_chunks_v2` via [RagRepositoryV2]. Kept so the
/// ~8 existing call sites (chat harness, P2P, quiz, sync, bootstrap,
/// diagnostics) keep compiling; new code must use [RagRepositoryV2] directly.
/// The legacy `rag_chunks` / `rag_chunks_fts` tables are no longer written.
@Deprecated('Use RagRepositoryV2 (single v2 store).')
class RagRepository {
  RagRepository({RagRepositoryV2? delegate}) : _v2 = delegate ?? RagRepositoryV2();

  final RagRepositoryV2 _v2;

  static RagChunk _toRagChunk(ChunkV2 c) => RagChunk(
        id: c.id,
        chapterId: c.chapterId,
        sourceTitle: c.sourceTitle,
        chunkOrder: c.chunkOrder,
        content: c.content,
      );

  Future<void> ensureSeedChunks() => _v2.ensureSeedChunks();

  Future<void> ingestChapterNotes({
    required String chapterId,
    required String sourceTitle,
    required String rawText,
  }) =>
      _v2.ingestNotes(
        chapterId: chapterId,
        sourceTitle: sourceTitle,
        rawText: rawText,
      );

  Future<void> ingestPrecomputedChunks({
    required String chapterId,
    required List<dynamic> chunks,
  }) =>
      _v2.insertBackendChunks(chapterId: chapterId, backendChunks: chunks);

  Future<List<RagChunk>> getChunksForChapter(String chapterId) async {
    final chunks = await _v2.getChunksForChapter(chapterId);
    return chunks.map(_toRagChunk).toList();
  }

  Future<List<String>> getChunkIdsForChapter(String chapterId) async {
    final chunks = await _v2.getChunksForChapter(chapterId);
    return chunks.map((c) => c.id).toList();
  }

  Future<int> getChunkCountForChapter(String chapterId) =>
      _v2.getChunkCount(chapterId);

  Future<RagCheckResult> localRagPreCheck({
    required String chapterId,
    required String query,
    int limit = 4,
  }) async {
    final List<ChunkV2> found = chapterId.trim().isEmpty
        ? await _v2.searchAll(query, limit: limit)
        : await _v2.searchChunks(query, chapterId, limit: limit);
    final chunks = found.map(_toRagChunk).toList();
    // FTS hits carry no BM25 score through this DTO; report the legacy
    // LIKE-hit sentinel (-1.0) so hasRelevantLocalContent keeps working.
    return RagCheckResult(
      chunkCount: chunks.length,
      topScore: chunks.isNotEmpty ? -1.0 : 0.0,
      chunks: chunks,
    );
  }

  Future<List<RagChunk>> searchChunksForChapter({
    required String chapterId,
    required String query,
    int limit = 10,
  }) async {
    final chunks = await _v2.searchChunks(query, chapterId, limit: limit);
    return chunks.map(_toRagChunk).toList();
  }
}
