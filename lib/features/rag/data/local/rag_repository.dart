import 'package:sqflite/sqflite.dart';

import '../../../course/data/local/app_database.dart';
import '../../domain/rag_chunk.dart';

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

class RagRepository {
  RagRepository({AppDatabase? database}) : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<void> ensureSeedChunks() async {
    final db = await _database.database;
    final existing = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM rag_chunks'),
    );

    if ((existing ?? 0) > 0) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();

    final ftsTableExists = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='rag_chunks_fts'")) ?? 0;

    batch.insert('rag_chunks', {
      'id': 'chunk_linear_1',
      'chapter_id': 'chap_linear_eq',
      'source_title': 'Linear Equations Notes',
      'chunk_order': 1,
      'content': 'A linear equation in one variable has the form ax + b = 0 where a is not zero. Solve by isolating x using inverse operations on both sides.',
      'created_at': now,
    });

    if (ftsTableExists > 0) {
      batch.insert('rag_chunks_fts', {
        'id': 'chunk_linear_1',
        'chapter_id': 'chap_linear_eq',
        'content': 'A linear equation in one variable has the form ax + b = 0 where a is not zero. Solve by isolating x using inverse operations on both sides.',
      });
    }

    batch.insert('rag_chunks', {
      'id': 'chunk_linear_2',
      'chapter_id': 'chap_linear_eq',
      'source_title': 'Linear Equations Notes',
      'chunk_order': 2,
      'content': 'For word problems, define the unknown as x, write an equation from the statement, simplify, solve, and verify the solution in context.',
      'created_at': now,
    });
    if (ftsTableExists > 0) {
      batch.insert('rag_chunks_fts', {
        'id': 'chunk_linear_2',
        'chapter_id': 'chap_linear_eq',
        'content': 'For word problems, define the unknown as x, write an equation from the statement, simplify, solve, and verify the solution in context.',
      });
    }

    batch.insert('rag_chunks', {
      'id': 'chunk_rxn_1',
      'chapter_id': 'chap_chemical_rxn',
      'source_title': 'Chemical Reactions Notes',
      'chunk_order': 1,
      'content': 'A chemical reaction changes reactants into products. Common signs are color change, gas release, precipitate formation, and temperature change.',
      'created_at': now,
    });
    if (ftsTableExists > 0) {
      batch.insert('rag_chunks_fts', {
        'id': 'chunk_rxn_1',
        'chapter_id': 'chap_chemical_rxn',
        'content': 'A chemical reaction changes reactants into products. Common signs are color change, gas release, precipitate formation, and temperature change.',
      });
    }

    batch.insert('rag_chunks', {
      'id': 'chunk_rxn_2',
      'chapter_id': 'chap_chemical_rxn',
      'source_title': 'Chemical Reactions Notes',
      'chunk_order': 2,
      'content': 'Balanced equations follow conservation of mass. Adjust coefficients, not subscripts, until atom counts are equal on both sides.',
      'created_at': now,
    });
    if (ftsTableExists > 0) {
      batch.insert('rag_chunks_fts', {
        'id': 'chunk_rxn_2',
        'chapter_id': 'chap_chemical_rxn',
        'content': 'Balanced equations follow conservation of mass. Adjust coefficients, not subscripts, until atom counts are equal on both sides.',
      });
    }

    await batch.commit(noResult: true);
  }

  Future<void> ingestChapterNotes({
    required String chapterId,
    required String sourceTitle,
    required String rawText,
  }) async {
    print('[RAG_VERIFY] INGEST_START');
    print('[RAG_VERIFY] CHAPTER=$chapterId');
    print('[RAG_VERIFY] TEXT_LENGTH=${rawText.length}');
    
    final db = await _database.database;
    final normalized = rawText.trim();
    if (normalized.isEmpty) {
      return;
    }

    final chunks = _chunkText(normalized);
    
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    int sqliteInserts = 0;
    int ftsInserts = 0;

    final ftsTableExists = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='rag_chunks_fts'")) ?? 0;

    for (var i = 0; i < chunks.length; i++) {
      final id = '${chapterId}_${now}_$i';
      batch.insert('rag_chunks', {
        'id': id,
        'chapter_id': chapterId,
        'source_title': sourceTitle,
        'chunk_order': i,
        'content': chunks[i],
        'created_at': now,
      });
      sqliteInserts++;
      
      if (ftsTableExists > 0) {
        batch.insert('rag_chunks_fts', {
          'id': id,
          'chapter_id': chapterId,
          'content': chunks[i],
        });
        ftsInserts++;
      }
    }

    print('[RAG] CHUNKS_CREATED=$sqliteInserts');
    print('[RAG] FTS_ROWS_CREATED=$ftsInserts');

    await batch.commit(noResult: true);
  }

  Future<void> ingestPrecomputedChunks({
    required String chapterId,
    required List<dynamic> chunks,
  }) async {
    print('[RAG_VERIFY] INGEST_PRECOMPUTED_START');
    print('[RAG_VERIFY] CHAPTER=$chapterId');
    print('[RAG_VERIFY] CHUNK_COUNT=${chunks.length}');
    
    final db = await _database.database;
    final batch = db.batch();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    int sqliteInserts = 0;
    int ftsInserts = 0;

    final ftsTableExists = Sqflite.firstIntValue(await db.rawQuery(
        "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='rag_chunks_fts'")) ?? 0;

    for (var i = 0; i < chunks.length; i++) {
      final chunkData = chunks[i] as Map<String, dynamic>;
      final chunkId = chunkData['chunk_id'] as String? ?? '${chapterId}_${now}_$i';
      final content = chunkData['text'] as String? ?? '';
      
      if (content.trim().isEmpty) continue;

      final metadata = chunkData['metadata'] as Map<String, dynamic>? ?? {};
      final sourceTitle = metadata['chapter'] as String? ?? chapterId;

      batch.insert('rag_chunks', {
        'id': chunkId,
        'chapter_id': chapterId,
        'source_title': sourceTitle,
        'chunk_order': i,
        'content': content,
        'created_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      sqliteInserts++;
      
      if (ftsTableExists > 0) {
        batch.insert('rag_chunks_fts', {
          'id': chunkId,
          'chapter_id': chapterId,
          'content': content,
        });
        ftsInserts++;
      }
    }

    print('[RAG] CHUNKS_CREATED=$sqliteInserts');
    print('[RAG] FTS_ROWS_CREATED=$ftsInserts');

    await batch.commit(noResult: true);
  }

  Future<List<RagChunk>> getChunksForChapter(String chapterId) async {
    final db = await _database.database;
    final rows = await db.query(
      'rag_chunks',
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
      orderBy: 'chunk_order ASC, created_at DESC',
    );

    return rows
        .map(
          (row) => RagChunk(
            id: row['id'] as String,
            chapterId: row['chapter_id'] as String,
            sourceTitle: row['source_title'] as String,
            chunkOrder: row['chunk_order'] as int,
            content: row['content'] as String,
          ),
        )
        .toList();
  }

  Future<List<String>> getChunkIdsForChapter(String chapterId) async {
    final db = await _database.database;
    final rows = await db.query(
      'rag_chunks',
      columns: ['id'],
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
      orderBy: 'chunk_order ASC, created_at DESC',
    );

    return rows.map((row) => row['id'] as String).toList();
  }

  Future<int> getChunkCountForChapter(String chapterId) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM rag_chunks WHERE chapter_id = ?',
      [chapterId],
    );

    return (rows.first['c'] as int?) ?? 0;
  }

  Future<RagCheckResult> localRagPreCheck({
    required String chapterId,
    required String query,
    int limit = 4,
  }) async {
    print('[DIAGNOSTICS] LOCAL_RAG_CHECK_START');
    print('[RAG] QUERY=$query');
    final db = await _database.database;
    final stopWords = ['what', 'is', 'the', 'meaning', 'of', 'explain', 'describe', 'tell', 'me', 'about', 'how', 'does', 'work', 'can', 'you', 'give', 'an', 'example', 'a', 'to', 'in', 'for', 'on', 'with', 'by', 'as', 'at', 'dont', 'solution'];
    final words = query.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').split(RegExp(r'\s+'));
    final cleanedWords = words.where((w) => w.isNotEmpty && !stopWords.contains(w)).toList();

    if (query.trim().isEmpty) {
      final chunks = await getChunksForChapter(chapterId);
      print('[RAG] CHUNKS_FOUND=${chunks.length}');
      print('[RAG] TOP_SCORE=0.0');
      print('[DIAGNOSTICS] LOCAL_RAG_CHECK_END');
      return RagCheckResult(
        chunkCount: chunks.length,
        topScore: 0.0,
        chunks: chunks,
      );
    }

    // ── Task C: Try FTS first (rag_chunks_v2_fts primary, rag_chunks_fts secondary), fall back to LIKE ──
    try {
      final ftsQuery = cleanedWords.isEmpty
          ? query.trim()
          : cleanedWords.map((w) => '$w*').join(' OR ');

      final String v2FtsSql = chapterId.isEmpty
          ? '''
            SELECT rc.id, rc.chapter_id, rc.source_title, rc.chunk_order, rc.content, 1.0 as score
            FROM rag_chunks_v2 rc
            INNER JOIN rag_chunks_v2_fts fts ON fts.id = rc.id
            WHERE rag_chunks_v2_fts MATCH ?
            ORDER BY rc.created_at DESC, rc.chunk_order ASC
            LIMIT ?
            '''
          : '''
            SELECT rc.id, rc.chapter_id, rc.source_title, rc.chunk_order, rc.content, 1.0 as score
            FROM rag_chunks_v2 rc
            INNER JOIN rag_chunks_v2_fts fts ON fts.id = rc.id
            WHERE rc.chapter_id = ?
              AND rag_chunks_v2_fts MATCH ?
            ORDER BY rc.created_at DESC, rc.chunk_order ASC
            LIMIT ?
            ''';

      final v2Args = chapterId.isEmpty ? [ftsQuery, limit] : [chapterId, ftsQuery, limit];
      final ftsRows = await db.rawQuery(v2FtsSql, v2Args);

      print('[RETRIEVAL] MODE=FTS_V2');
      print('[LOCAL_RAG] FTS_QUERY=$ftsQuery');

      final chunks = ftsRows
          .map(
            (row) => RagChunk(
              id: row['id'] as String,
              chapterId: row['chapter_id'] as String,
              sourceTitle: row['source_title'] as String,
              chunkOrder: row['chunk_order'] as int,
              content: row['content'] as String,
            ),
          )
          .toList();

      final topScore = chunks.isNotEmpty ? (ftsRows.first['score'] as num).toDouble() : 0.0;

      print('[RAG] CHUNKS_FOUND=${chunks.length}');
      print('[RAG] TOP_SCORE=$topScore');
      print('[DIAGNOSTICS] LOCAL_RAG_CHECK_END');

      return RagCheckResult(
        chunkCount: chunks.length,
        topScore: topScore,
        chunks: chunks,
      );
    } catch (ftsError) {
      // FTS not available — fall back to LIKE
      print('[RETRIEVAL] MODE=LIKE_FALLBACK (FTS error: $ftsError)');
    }

    // ── LIKE fallback ──
    try {
      final cleanQuery = cleanedWords.isEmpty ? query.trim() : cleanedWords.join('%');
      final likeTerm = '%$cleanQuery%';

      final sqlQuery = '''
        SELECT id, chapter_id, source_title, chunk_order, content, -1.0 as score
        FROM rag_chunks
        WHERE chapter_id = ?
          AND content LIKE ?
        ORDER BY created_at DESC, chunk_order ASC
        LIMIT ?
        ''';
      
      print('[LOCAL_RAG] LIKE_QUERY=$likeTerm');
      
      final rows = await db.rawQuery(sqlQuery, [chapterId, likeTerm, limit]);

      final chunks = rows
          .map(
            (row) => RagChunk(
              id: row['id'] as String,
              chapterId: row['chapter_id'] as String,
              sourceTitle: row['source_title'] as String,
              chunkOrder: row['chunk_order'] as int,
              content: row['content'] as String,
            ),
          )
          .toList();

      final topScore = chunks.isNotEmpty ? (rows.first['score'] as num).toDouble() : 0.0;
      
      print('[RAG] CHUNKS_FOUND=${chunks.length}');
      print('[RAG] TOP_SCORE=$topScore');
      print('[DIAGNOSTICS] LOCAL_RAG_CHECK_END');
      
      return RagCheckResult(
        chunkCount: chunks.length,
        topScore: topScore,
        chunks: chunks,
      );
    } catch (e) {
      print('[DIAGNOSTICS] LOCAL_RAG_ERROR=$e');
      print('[DIAGNOSTICS] LOCAL_RAG_AVAILABLE=false');
      
      final chunks = await getChunksForChapter(chapterId);
      print('[RAG] CHUNKS_FOUND=${chunks.length}');
      print('[RAG] TOP_SCORE=0.0');
      print('[DIAGNOSTICS] LOCAL_RAG_CHECK_END');
      return RagCheckResult(
        chunkCount: chunks.length,
        topScore: 0.0,
        chunks: chunks,
      );
    }
  }

  Future<List<RagChunk>> searchChunksForChapter({
    required String chapterId,
    required String query,
    int limit = 10,
  }) async {
    print('[DIAGNOSTICS] RAG_SEARCH_START');
    final stopwatch = Stopwatch()..start();
    final db = await _database.database;
    final normalizedQuery = _buildFtsQuery(query);

    if (normalizedQuery.isEmpty) {
      return getChunksForChapter(chapterId);
    }

    try {
      final rows = await db.rawQuery(
        '''
        SELECT rc.id, rc.chapter_id, rc.source_title, rc.chunk_order, rc.content
        FROM rag_chunks_v2 rc
        INNER JOIN rag_chunks_v2_fts fts ON fts.id = rc.id
        WHERE (${chapterId.trim().isEmpty ? '1=1' : 'fts.chapter_id = ?'})
          AND rag_chunks_v2_fts MATCH ?
        ORDER BY rc.created_at DESC, rc.chunk_order ASC
        LIMIT ?
        ''',
        chapterId.trim().isEmpty ? [normalizedQuery, limit] : [chapterId, normalizedQuery, limit],
      );

      final chunks = rows
          .map(
            (row) => RagChunk(
              id: row['id'] as String,
              chapterId: row['chapter_id'] as String,
              sourceTitle: row['source_title'] as String,
              chunkOrder: row['chunk_order'] as int,
              content: row['content'] as String,
            ),
          )
          .toList();

      if (chunks.isNotEmpty) {
        stopwatch.stop();
        print('[DIAGNOSTICS] RAG_SEARCH_END');
        print('[DIAGNOSTICS] RAG_CHUNK_COUNT=${chunks.length}');
        return chunks;
      }
    } catch (_) {}

    try {
      final rows = await db.rawQuery(
        '''
        SELECT rc.id, rc.chapter_id, rc.source_title, rc.chunk_order, rc.content
        FROM rag_chunks rc
        INNER JOIN rag_chunks_fts fts ON fts.id = rc.id
        WHERE (${chapterId.trim().isEmpty ? '1=1' : 'fts.chapter_id = ?'})
          AND rag_chunks_fts MATCH ?
        ORDER BY rc.created_at DESC, rc.chunk_order ASC
        LIMIT ?
        ''',
        chapterId.trim().isEmpty ? [normalizedQuery, limit] : [chapterId, normalizedQuery, limit],
      );

      final chunks = rows
          .map(
            (row) => RagChunk(
              id: row['id'] as String,
              chapterId: row['chapter_id'] as String,
              sourceTitle: row['source_title'] as String,
              chunkOrder: row['chunk_order'] as int,
              content: row['content'] as String,
            ),
          )
          .toList();

      stopwatch.stop();
      print('[DIAGNOSTICS] RAG_SEARCH_END');
      print('[DIAGNOSTICS] RAG_CHUNK_COUNT=${chunks.length}');
      return chunks;
    } catch (_) {
      final chunks = await getChunksForChapter(chapterId);
      stopwatch.stop();
      print('[DIAGNOSTICS] RAG_SEARCH_END');
      print('[DIAGNOSTICS] RAG_CHUNK_COUNT=${chunks.length}');
      return chunks;
    }
  }

  List<String> _chunkText(String text) {
    final paragraphChunks = text
        .split(RegExp(r'\n\s*\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (paragraphChunks.isEmpty) {
      return const [];
    }

    const maxChars = 420;
    final output = <String>[];

    for (final paragraph in paragraphChunks) {
      if (paragraph.length <= maxChars) {
        output.add(paragraph);
        continue;
      }

      var start = 0;
      while (start < paragraph.length) {
        final end = (start + maxChars).clamp(0, paragraph.length);
        output.add(paragraph.substring(start, end));
        start = end;
      }
    }

    return output;
  }

  String _buildFtsQuery(String query) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.length > 2)
        .toSet()
        .take(8)
        .toList();

    if (terms.isEmpty) {
      return '';
    }

    return terms.map((term) => '$term*').join(' ');
  }
}
