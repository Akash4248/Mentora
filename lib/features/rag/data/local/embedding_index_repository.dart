import 'dart:typed_data';
import 'package:sqflite/sqflite.dart';

import '../../../course/data/local/app_database.dart';
import '../../domain/rag_chunk.dart';

class IndexedVectorRecord {
  final RagChunk chunk;
  final Uint8List? vectorBlob;

  IndexedVectorRecord({
    required this.chunk,
    this.vectorBlob,
  });
}

class EmbeddingIndexRepository {
  EmbeddingIndexRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<void> upsertEmbeddingMetadata({
    required String chunkId,
    required String modelName,
    required int dimension,
    Uint8List? vectorBlob,
  }) async {
    final db = await _database.database;
    await db.insert(
      'rag_chunk_embeddings',
      {
        'chunk_id': chunkId,
        'model_name': modelName,
        'dimension': dimension,
        'vector_blob': vectorBlob,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> getIndexedCount() async {
    final db = await _database.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM rag_chunk_embeddings');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> getIndexedCountForChapter({required String chapterId}) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
      FROM rag_chunk_embeddings emb
      INNER JOIN rag_chunks rc ON rc.id = emb.chunk_id
      WHERE rc.chapter_id = ?
      ''',
      [chapterId],
    );

    return (rows.first['c'] as int?) ?? 0;
  }

  Future<bool> isChunkIndexed({required String chunkId}) async {
    final db = await _database.database;
    final rows = await db.query(
      'rag_chunk_embeddings',
      columns: ['chunk_id'],
      where: 'chunk_id = ?',
      whereArgs: [chunkId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<List<IndexedVectorRecord>> getVectorEmbeddingsForChapter({required String chapterId}) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      '''
      SELECT 
        rc.id, rc.chapter_id, rc.source_title, rc.chunk_order, rc.content, rc.created_at,
        emb.vector_blob
      FROM rag_chunks rc
      INNER JOIN rag_chunk_embeddings emb ON rc.id = emb.chunk_id
      WHERE rc.chapter_id = ?
      ORDER BY rc.chunk_order ASC
      ''',
      [chapterId],
    );

    return rows.map((row) {
      final chunk = RagChunk(
        id: row['id'] as String,
        chapterId: row['chapter_id'] as String,
        sourceTitle: row['source_title'] as String,
        chunkOrder: row['chunk_order'] as int,
        content: row['content'] as String,
      );

      final blob = row['vector_blob'];
      final Uint8List? vectorBlob = blob is Uint8List ? blob : null;

      return IndexedVectorRecord(chunk: chunk, vectorBlob: vectorBlob);
    }).toList();
  }
}
