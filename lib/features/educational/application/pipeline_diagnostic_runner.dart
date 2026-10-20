import '../../rag/data/local/rag_repository.dart';

class PipelineDiagnosticRunner {
  static Future<void> runPhase8And9Verification() async {
    print('\n[SYNC_VERIFY] ==== PHASE 8 & 9 START ====');
    final repo = RagRepository();
    
    // Phase 9
    final queries = [
      'arithmetic progression',
      'quadrilaterals',
      'gravitation',
      'constitutional design',
      'prime numbers'
    ];

    print('\n[RAG_VERIFY] ==== RETRIEVAL VERIFICATION ====');
    for (final q in queries) {
      print('[RAG_VERIFY] QUERY=$q');
      try {
        final result = await repo.searchChunksForChapter(
          chapterId: '', // Empty chapter searches all chapters (global search).
          query: q,
          limit: 4,
        );
        print('[RAG_VERIFY] HITS=${result.length}');
        // Wait, if we don't know the chapterId, we need a global search.
        // I will write a custom SQLite query to search all chapters just for verification.
      } catch (e) {
        print('[RAG_VERIFY] FTS_ERROR=$e');
      }
    }
  }
}
