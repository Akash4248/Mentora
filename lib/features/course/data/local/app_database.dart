import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    final dbPath = await getDatabasesPath();
    final fullPath = path.join(dbPath, 'offline_tutor_stage1.db');

    _database = await openDatabase(
      fullPath,
      version: 20,
      singleInstance: true,
      onConfigure: (db) async {
        // Enable WAL for better concurrent read performance (write-heavy workloads)
        await db.rawQuery('PRAGMA journal_mode=WAL');
        // Enforce foreign key constraints (SQLite disables them by default)
        await db.rawQuery('PRAGMA foreign_keys=ON');
        // Wait up to 10 seconds on busy locks before throwing exception
        await db.rawQuery('PRAGMA busy_timeout=10000');
      },
      onCreate: (db, version) async {
        await _createBaseTables(db);
        await _createRagTables(db);
        await _createRagFtsArtifacts(db);
        await _createRagV2Tables(db);
        await _createRagV2FtsArtifacts(db);
        await _createEmbeddingMetadataTable(db);
        await _createStageThreeTables(db);
        await _createP2PTables(db);
        await _createP2PSecuritySettingsTable(db);
        await _createMediaResourcesTable(db);
        await _createStudyNotesTable(db);
        await _createQuizResultsTable(db);
        await _createChatBenchmarkTables(db);
        await _createIngestionQueueTables(db);
        await _createChatMemoryPolicyTables(db);
        await _createContentPackTables(db);
        await _createTranslationCacheTables(db);
        await _createPendingSyncQueueTable(db);
        await _createChapterVideoResourcesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Migrations must run in ascending version order.
        // Each block is guarded by oldVersion < N so that upgrading across
        // multiple versions (e.g. v1→v20) runs every intermediate step.
        if (oldVersion < 2) {
          await _createRagTables(db);
        }
        if (oldVersion < 3) {
          await _createStageThreeTables(db);
        }
        if (oldVersion < 4) {
          await _createRagFtsArtifacts(db);
          await _createEmbeddingMetadataTable(db);
        }
        if (oldVersion < 5) {
          await _createP2PTables(db);
        }
        if (oldVersion < 6) {
          await db.execute('''
            ALTER TABLE trusted_peers ADD COLUMN alternate_address TEXT;
          ''');
          await _createP2PSecuritySettingsTable(db);
        }
        if (oldVersion < 7) {
          await db.execute('''
            ALTER TABLE learner_progress ADD COLUMN sessions_engaged INTEGER DEFAULT 1;
          ''');
          await db.execute('''
            ALTER TABLE learner_progress ADD COLUMN total_messages INTEGER DEFAULT 0;
          ''');
          await db.execute('''
            ALTER TABLE learner_progress ADD COLUMN mastery_score REAL DEFAULT 0.0;
          ''');
        }
        if (oldVersion < 8) {
          await _createRagV2Tables(db);
          await _createRagV2FtsArtifacts(db);
        }
        if (oldVersion < 9) {
          await _createMediaResourcesTable(db);
        }
        if (oldVersion < 10) {
          await _createStudyNotesTable(db);
        }
        if (oldVersion < 11) {
          await _createQuizResultsTable(db);
        }
        if (oldVersion < 12) {
          await _createChatBenchmarkTables(db);
          await _createIngestionQueueTables(db);
        }
        if (oldVersion < 13) {
          await _createChatMemoryPolicyTables(db);
        }
        if (oldVersion < 14) {
          await _createContentPackTables(db);
        }
        if (oldVersion < 15) {
          await _createRagFtsArtifacts(db);
        }
        if (oldVersion < 16) {
          await _createTranslationCacheTables(db);
        }
        if (oldVersion < 17) {
          // Ensure translation_cache exists for devices that reached v16
          // via onCreate which previously omitted _createTranslationCacheTables.
          await _createTranslationCacheTables(db);
        }
        if (oldVersion < 18) {
          await _createPendingSyncQueueTable(db);
        }
        if (oldVersion < 19) {
          await _createChapterVideoResourcesTable(db);
        }
        if (oldVersion < 20) {
          await _createRagV2FtsArtifacts(db);
        }
      },
    );

    return _database!;
  }

  Future<void> _createBaseTables(Database db) async {
    await db.execute('''
      CREATE TABLE courses (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE subjects (
        id TEXT PRIMARY KEY,
        course_id TEXT NOT NULL,
        name TEXT NOT NULL,
        FOREIGN KEY(course_id) REFERENCES courses(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE chapters (
        id TEXT PRIMARY KEY,
        subject_id TEXT NOT NULL,
        title TEXT NOT NULL,
        summary TEXT NOT NULL,
        FOREIGN KEY(subject_id) REFERENCES subjects(id)
      );
    ''');

    await db.execute('''
      CREATE INDEX idx_subjects_course_id ON subjects(course_id);
    ''');

    await db.execute('''
      CREATE INDEX idx_chapters_subject_id ON chapters(subject_id);
    ''');
  }

  Future<void> _createRagTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rag_chunks (
        id TEXT PRIMARY KEY,
        chapter_id TEXT NOT NULL,
        source_title TEXT NOT NULL,
        chunk_order INTEGER NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(chapter_id) REFERENCES chapters(id)
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rag_chunks_chapter_id
      ON rag_chunks(chapter_id);
    ''');
  }

  Future<void> _createRagFtsArtifacts(Database db) async {
    // Re-enabled FTS5 table for fast RAG lookups with BM25 ranking, fallback to FTS4/FTS3
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS rag_chunks_fts 
        USING fts5(id UNINDEXED, chapter_id UNINDEXED, content, tokenize='unicode61')
      ''');
      print('[FTS] AppDatabase FTS_MODULE=fts5 STATUS=ok');
    } catch (e) {
      try {
        await db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS rag_chunks_fts 
          USING fts4(id, chapter_id, content)
        ''');
        print('[FTS] AppDatabase FTS_MODULE=fts4 STATUS=ok');
      } catch (e2) {
        try {
          await db.execute('''
            CREATE VIRTUAL TABLE IF NOT EXISTS rag_chunks_fts 
            USING fts3(id, chapter_id, content)
          ''');
          print('[FTS] AppDatabase FTS_MODULE=fts3 STATUS=ok');
        } catch (e3) {
          print('[FTS] AppDatabase FTS_MODULE=none STATUS=degraded error=\$e3');
        }
      }
    }
  }

  Future<void> _createRagV2Tables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rag_chunks_v2 (
        id TEXT PRIMARY KEY,
        chapter_id TEXT NOT NULL,
        source_language TEXT DEFAULT 'en',
        source_title TEXT NOT NULL,
        chunk_order INTEGER NOT NULL,
        content_type TEXT NOT NULL,
        content TEXT NOT NULL,
        formulas_json TEXT,
        original_markdown TEXT,
        token_count INTEGER NOT NULL,
        metadata_json TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(chapter_id) REFERENCES chapters(id)
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chunks_v2_chapter_id
      ON rag_chunks_v2(chapter_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chunks_v2_language
      ON rag_chunks_v2(chapter_id, source_language);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chunks_v2_type
      ON rag_chunks_v2(content_type);
    ''');
  }

  Future<void> _createRagV2FtsArtifacts(Database db) async {
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS rag_chunks_v2_fts 
        USING fts4(id UNINDEXED, chapter_id UNINDEXED, content)
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trig_rag_chunks_v2_ai
        AFTER INSERT ON rag_chunks_v2
        BEGIN
          INSERT INTO rag_chunks_v2_fts(id, chapter_id, content)
          VALUES (new.id, new.chapter_id, new.content);
        END;
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trig_rag_chunks_v2_au
        AFTER UPDATE ON rag_chunks_v2
        BEGIN
          UPDATE rag_chunks_v2_fts
          SET chapter_id = new.chapter_id, content = new.content
          WHERE id = old.id;
        END;
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS trig_rag_chunks_v2_ad
        AFTER DELETE ON rag_chunks_v2
        BEGIN
          DELETE FROM rag_chunks_v2_fts WHERE id = old.id;
        END;
      ''');
      print('[FTS] AppDatabase RAG_V2_FTS_STATUS=ok');
    } catch (e) {
      print('[FTS] AppDatabase RAG_V2_FTS_STATUS=degraded error=$e');
    }
  }

  Future<void> _createEmbeddingMetadataTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rag_chunk_embeddings (
        chunk_id TEXT PRIMARY KEY,
        model_name TEXT NOT NULL,
        dimension INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(chunk_id) REFERENCES rag_chunks(id)
      );
    ''');
  }

  Future<void> _createStageThreeTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_sessions (
        id TEXT PRIMARY KEY,
        chapter_id TEXT NOT NULL,
        language_code TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        last_message_at INTEGER NOT NULL,
        FOREIGN KEY(chapter_id) REFERENCES chapters(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        text TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY(session_id) REFERENCES chat_sessions(id)
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS learner_progress (
        chapter_id TEXT PRIMARY KEY,
        questions_asked INTEGER NOT NULL,
        sessions_engaged INTEGER NOT NULL DEFAULT 1,
        total_messages INTEGER NOT NULL DEFAULT 0,
        mastery_score REAL NOT NULL DEFAULT 0.0,
        last_activity_at INTEGER NOT NULL,
        FOREIGN KEY(chapter_id) REFERENCES chapters(id)
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_sessions_chapter_id
      ON chat_sessions(chapter_id);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_messages_session_id
      ON chat_messages(session_id);
    ''');
  }

  Future<void> _createP2PTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trusted_peers (
        address TEXT PRIMARY KEY,
        alternate_address TEXT,
        name TEXT NOT NULL,
        transport TEXT NOT NULL,
        added_at INTEGER NOT NULL
      );
    ''');
  }

  Future<void> _createP2PSecuritySettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS p2p_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');
  }

  Future<void> _createMediaResourcesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS media_resources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        media_type TEXT NOT NULL,
        title TEXT NOT NULL,
        local_path TEXT NOT NULL UNIQUE,
        source_path TEXT,
        size_bytes INTEGER NOT NULL,
        imported_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_media_resources_type
      ON media_resources(media_type, imported_at DESC);
    ''');
  }

  Future<void> _createStudyNotesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS study_notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_study_notes_updated
      ON study_notes(updated_at DESC);
    ''');
  }

  Future<void> _createQuizResultsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quiz_results (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapter_id TEXT NOT NULL,
        score INTEGER NOT NULL,
        total_questions INTEGER NOT NULL,
        answers_json TEXT NOT NULL,
        attempted_at INTEGER NOT NULL,
        FOREIGN KEY(chapter_id) REFERENCES chapters(id)
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_quiz_results_chapter_date
      ON quiz_results(chapter_id, attempted_at DESC);
    ''');
  }

  Future<void> _createChatBenchmarkTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_benchmark_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapter_id TEXT NOT NULL,
        mode TEXT NOT NULL,
        prompt_count INTEGER NOT NULL,
        avg_ttft_ms INTEGER NOT NULL,
        avg_total_ms INTEGER NOT NULL,
        avg_tokens_per_sec REAL NOT NULL,
        created_at INTEGER NOT NULL,
        notes TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_benchmark_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id INTEGER NOT NULL,
        prompt_text TEXT NOT NULL,
        ttft_ms INTEGER NOT NULL,
        total_ms INTEGER NOT NULL,
        tokens INTEGER NOT NULL,
        tokens_per_sec REAL NOT NULL,
        FOREIGN KEY(run_id) REFERENCES chat_benchmark_runs(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_benchmark_runs_chapter
      ON chat_benchmark_runs(chapter_id, created_at DESC);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chat_benchmark_items_run
      ON chat_benchmark_items(run_id);
    ''');
  }

  Future<void> _createIngestionQueueTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS rag_ingestion_jobs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapter_id TEXT NOT NULL,
        status TEXT NOT NULL,
        files_json TEXT NOT NULL,
        current_index INTEGER NOT NULL DEFAULT 0,
        retry_count INTEGER NOT NULL DEFAULT 0,
        max_retries INTEGER NOT NULL DEFAULT 3,
        last_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_rag_ingestion_jobs_status
      ON rag_ingestion_jobs(status, updated_at DESC);
    ''');
  }

  Future<void> _createChatMemoryPolicyTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chat_memory_policies (
        session_id TEXT PRIMARY KEY,
        short_term_window INTEGER NOT NULL DEFAULT 8,
        semantic_recall_enabled INTEGER NOT NULL DEFAULT 1,
        semantic_top_k INTEGER NOT NULL DEFAULT 2,
        reset_policy TEXT NOT NULL DEFAULT 'manual',
        inactivity_minutes INTEGER NOT NULL DEFAULT 45,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY(session_id) REFERENCES chat_sessions(id) ON DELETE CASCADE
      );
    ''');
  }

  Future<void> _createContentPackTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS material_packs (
        pack_id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        medium TEXT NOT NULL,
        subject TEXT NOT NULL,
        grade_min INTEGER NOT NULL,
        grade_max INTEGER NOT NULL,
        version INTEGER NOT NULL,
        manifest_path TEXT NOT NULL,
        root_path TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        content_size_bytes INTEGER NOT NULL,
        installed_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'installed'
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS material_pack_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        pack_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        relative_path TEXT NOT NULL,
        absolute_path TEXT NOT NULL UNIQUE,
        grade INTEGER,
        subject TEXT,
        medium TEXT,
        chapter_id TEXT,
        language_code TEXT,
        order_index INTEGER NOT NULL DEFAULT 0,
        size_bytes INTEGER NOT NULL,
        metadata_json TEXT,
        FOREIGN KEY(pack_id) REFERENCES material_packs(pack_id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_material_pack_items_pack
      ON material_pack_items(pack_id, kind, order_index);
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_material_pack_items_grade_subject
      ON material_pack_items(grade, subject, medium);
    ''');
  }

  Future<void> _createTranslationCacheTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS translation_cache (
        cache_key TEXT PRIMARY KEY,
        artifact_type TEXT NOT NULL,
        content_id TEXT,
        source_language TEXT NOT NULL,
        target_language TEXT NOT NULL,
        source_hash TEXT NOT NULL,
        source_text TEXT NOT NULL,
        translated_text TEXT NOT NULL,
        engine_id TEXT NOT NULL,
        fallback_used INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_translation_cache_lookup
      ON translation_cache(target_language, artifact_type, source_hash);
    ''');
  }

  Future<void> _createPendingSyncQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pending_sync_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        payload_type TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        retry_count INTEGER NOT NULL DEFAULT 0
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_pending_sync_queue_status
      ON pending_sync_queue(status, created_at);
    ''');
  }

  Future<void> _createChapterVideoResourcesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chapter_video_resources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapter_id TEXT NOT NULL,
        grade INTEGER NOT NULL,
        subject TEXT NOT NULL,
        chapter_title TEXT NOT NULL,
        channel_name TEXT NOT NULL,
        video_title TEXT NOT NULL,
        video_url TEXT NOT NULL,
        video_id TEXT NOT NULL,
        rank INTEGER NOT NULL,
        duration_seconds INTEGER DEFAULT 0,
        language TEXT DEFAULT 'en',
        description TEXT DEFAULT '',
        created_at INTEGER DEFAULT 0
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_chapter_video_chapter_id
      ON chapter_video_resources(chapter_id);
    ''');
  }
}
