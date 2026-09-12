import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/course/data/local/app_database.dart';
import '../domain/chunk_v2.dart';
import 'formula_extractor.dart';
import 'multilingual_processor.dart';

/// Ingestion pipeline: Load seed JSON → Extract formulas → Store in DB
class RagIngestionService {
  RagIngestionService({
    AppDatabase? database,
  })  : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  /// Ingest seed data from JSON asset file
  Future<IngestionResult> ingestSeedData(String assetPath) async {
    try {
      final jsonStr = await rootBundle.loadString(assetPath);
      final data = jsonDecode(jsonStr) as Map<String, dynamic>;
      return ingestFromJson(data);
    } catch (e) {
      return IngestionResult(
        success: false,
        message: 'Failed to load seed data: $e',
      );
    }
  }

  /// Ingest from parsed JSON data
  Future<IngestionResult> ingestFromJson(Map<String, dynamic> data) async {
    try {
      final db = await _database.database;

      // 1. Ingest courses
      final courseList = (data['courses'] as List?);
      if (courseList != null) {
        for (final course in courseList) {
          await db.insert(
            'courses',
            {
              'id': course['id'],
              'name': course['name'],
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      // 2. Ingest subjects
      final subjectList = (data['subjects'] as List?);
      if (subjectList != null) {
        for (final subject in subjectList) {
          await db.insert(
            'subjects',
            {
              'id': subject['id'],
              'course_id': subject['courseId'],
              'name': subject['name'],
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      // 3. Ingest chapters
      final chapterList = (data['chapters'] as List?);
      if (chapterList != null) {
        for (final chapter in chapterList) {
          await db.insert(
            'chapters',
            {
              'id': chapter['id'],
              'subject_id': chapter['subjectId'],
              'title': chapter['title'],
              'summary': chapter['summary'],
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }

      // 4. Ingest chunks with full processing pipeline
      final chunkList = (data['chunks'] as List?);
      int chunksInserted = 0;

      if (chunkList != null) {
        for (final chunkData in chunkList) {
          final chunk = _parseChunkFromJson(chunkData);
          await _ingestChunk(db, chunk);
          chunksInserted++;
        }
      }

      return IngestionResult(
        success: true,
        message: 'Ingestion complete',
        coursesIngested: courseList?.length ?? 0,
        subjectsIngested: subjectList?.length ?? 0,
        chaptersIngested: chapterList?.length ?? 0,
        chunksIngested: chunksInserted,
      );
    } catch (e) {
      return IngestionResult(
        success: false,
        message: 'Ingestion failed: $e',
      );
    }
  }

  /// Process and store a single chunk
  Future<void> _ingestChunk(Database db, ChunkV2 chunk) async {
    // Detect and normalize language
    final detectedLang = MultilingualProcessor.detectLanguage(chunk.content);
    String processedContent = chunk.content;

    if (detectedLang == 'kn') {
      processedContent = MultilingualProcessor.normalizeKannada(chunk.content);
      processedContent = MultilingualProcessor.cleanMixedLanguage(processedContent);
    }

    // Extract formulas from content
    final formulasFromContent =
        FormulaExtractor.extractFormulas(processedContent);

    // Merge with provided formulas
    final allFormulas = <String, Formula>{};
    for (final f in chunk.formulas) {
      allFormulas[f.original] = f;
    }
    for (final f in formulasFromContent) {
      allFormulas[f.original] = f;
    }

    // Create final chunk with all formulas
    final finalChunk = ChunkV2(
      id: chunk.id,
      chapterId: chunk.chapterId,
      sourceTitle: chunk.sourceTitle,
      sourceLanguage: detectedLang,
      content: processedContent,
      contentType: chunk.contentType,
      chunkOrder: chunk.chunkOrder,
      createdAt: chunk.createdAt,
      tokenCount: _estimateTokenCount(processedContent),
      originalMarkdown: chunk.originalMarkdown,
      formulas: allFormulas.values.toList(),
      metadata: chunk.metadata,
    );

    // Insert into database
    await db.insert(
      'rag_chunks_v2',
      {
        'id': finalChunk.id,
        'chapter_id': finalChunk.chapterId,
        'source_title': finalChunk.sourceTitle,
        'source_language': finalChunk.sourceLanguage,
        'content': finalChunk.content,
        'content_type': finalChunk.contentType,
        'chunk_order': finalChunk.chunkOrder,
        'token_count': finalChunk.tokenCount,
        'formulas_json': finalChunk.formulasJson,
        'original_markdown': finalChunk.originalMarkdown,
        'metadata_json': finalChunk.metadataJson,
        'created_at': finalChunk.createdAt.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Parse chunk from JSON (with formula objects)
  ChunkV2 _parseChunkFromJson(Map<String, dynamic> data) {
    final formulasJson = data['formulas'] as List? ?? [];
    final formulas = formulasJson.map((f) {
      return Formula.fromJson(f as Map<String, dynamic>);
    }).toList();

    final metadataRaw = (data['metadata'] as Map?) ?? {};
    final metadata = Map<String, dynamic>.from(metadataRaw);

    return ChunkV2(
      id: data['id'] as String,
      chapterId: data['chapterId'] as String,
      sourceTitle: data['sourceTitle'] as String,
      sourceLanguage: data['sourceLanguage'] as String? ?? 'en',
      content: data['content'] as String,
      contentType: data['contentType'] as String,
      chunkOrder: data['chunkOrder'] as int? ?? 0,
      createdAt: DateTime.now(),
      tokenCount: data['tokenCount'] as int? ?? 0,
      originalMarkdown: data['originalMarkdown'] as String?,
      formulas: formulas,
      metadata: metadata,
    );
  }

  /// Estimate token count (rough heuristic: ~4 chars per token)
  int _estimateTokenCount(String text) {
    return (text.length / 4).ceil();
  }

  /// Initialize vocabulary from chapter for semantic search (no-op)
  Future<void> initializeChapterSemantics(String chapterId) async {}
}

/// Result of ingestion operation
class IngestionResult {
  final bool success;
  final String message;
  final int coursesIngested;
  final int subjectsIngested;
  final int chaptersIngested;
  final int chunksIngested;

  IngestionResult({
    required this.success,
    required this.message,
    this.coursesIngested = 0,
    this.subjectsIngested = 0,
    this.chaptersIngested = 0,
    this.chunksIngested = 0,
  });

  @override
  String toString() => '''
IngestionResult(
  success: $success,
  message: $message,
  courses: $coursesIngested,
  subjects: $subjectsIngested,
  chapters: $chaptersIngested,
  chunks: $chunksIngested
)''';
}
