import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:path/path.dart';
import '../../../config/app_environment.dart';
import '../../../features/course/data/local/app_database.dart';

/// Manages the SQLite database for offline educational content
class EducationalDatabase {
  static final EducationalDatabase _instance = EducationalDatabase._internal();
  static bool _ftsSearchAvailable = true;

  factory EducationalDatabase() {
    return _instance;
  }

  EducationalDatabase._internal();

  /// Get database instance (lazy initialization delegated to AppDatabase)
  static Future<sqflite.Database> get database async {
    return AppDatabase.instance.database;
  }

  /// Initialize the SQLite database with schema
  static Future<sqflite.Database> _initializeDatabase() async {
    AppEnvironment.log('SYNC', 'Initializing educational database...');
    _ftsSearchAvailable = true;

    final databasesPath = await sqflite.getDatabasesPath();
    final path = join(databasesPath, 'educational.db');

    // Delete existing database for fresh schema — REMOVED (dev shortcut, never ship)

    final db = await sqflite.openDatabase(
      path,
      version: 1,
      onConfigure: (db) async {
        // Enable WAL for better concurrent read performance
        await db.rawQuery('PRAGMA journal_mode=WAL');
        // Enforce foreign key constraints (disabled by SQLite default)
        // Required for ON DELETE CASCADE to work on subjects, chapters, concepts, etc.
        await db.rawQuery('PRAGMA foreign_keys=ON');
        // Wait up to 10 seconds on busy locks before throwing exception
        await db.rawQuery('PRAGMA busy_timeout=10000');
      },
      onCreate: (db, version) async {
        AppEnvironment.log('SYNC', 'Creating educational database schema...');
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        AppEnvironment.log('SYNC', 'Upgrading educational database from v$oldVersion to v$newVersion');
        // Future migrations go here — add blocks in ascending version order:
        // if (oldVersion < 2) { await db.execute('ALTER TABLE ...'); }
        // if (oldVersion < 3) { ... }
      },
    );

    AppEnvironment.log('SYNC', 'Educational database initialized successfully');
    return db;
  }

  /// Create all database tables
  static Future<void> _createSchema(sqflite.Database db) async {
    // Grades table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS grades (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        gradeNumber INTEGER NOT NULL UNIQUE,
        description TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    // Subjects table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS subjects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        gradeId INTEGER NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        icon TEXT,
        colorHex INTEGER,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (gradeId) REFERENCES grades(id) ON DELETE CASCADE
      )
    ''');

    // Chapters table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS chapters (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        subjectId INTEGER NOT NULL,
        name TEXT NOT NULL,
        sequenceNumber INTEGER NOT NULL,
        summary TEXT,
        content TEXT,
        estimatedReadingMinutes INTEGER,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (subjectId) REFERENCES subjects(id) ON DELETE CASCADE
      )
    ''');

    // Concepts table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS concepts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapterId INTEGER NOT NULL,
        name TEXT NOT NULL,
        sequenceNumber INTEGER NOT NULL,
        definition TEXT,
        examples TEXT,
        relatedConcepts TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (chapterId) REFERENCES chapters(id) ON DELETE CASCADE
      )
    ''');

    // Quizzes table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quizzes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapterId INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        sequenceNumber INTEGER NOT NULL,
        questions TEXT NOT NULL,
        passingScorePercent INTEGER DEFAULT 70,
        maxAttempts INTEGER DEFAULT 3,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (chapterId) REFERENCES chapters(id) ON DELETE CASCADE
      )
    ''');

    // Quiz Questions table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS quiz_questions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        quizId INTEGER NOT NULL,
        sequenceNumber INTEGER NOT NULL,
        question TEXT NOT NULL,
        type TEXT NOT NULL,
        options TEXT,
        correctAnswer TEXT NOT NULL,
        explanation TEXT,
        points INTEGER DEFAULT 1,
        FOREIGN KEY (quizId) REFERENCES quizzes(id) ON DELETE CASCADE
      )
    ''');

    // Flashcards table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS flashcards (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapterId INTEGER NOT NULL,
        term TEXT NOT NULL,
        definition TEXT NOT NULL,
        example TEXT,
        sequenceNumber INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (chapterId) REFERENCES chapters(id) ON DELETE CASCADE
      )
    ''');

    // Educational Packs table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS educational_packs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        packId TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        description TEXT,
        version TEXT NOT NULL,
        localPath TEXT NOT NULL,
        syncState TEXT DEFAULT 'cached',
        downloadProgress REAL DEFAULT 0.0,
        gradeId INTEGER,
        subjectId INTEGER,
        totalChapters INTEGER DEFAULT 0,
        downloadedChapters INTEGER DEFAULT 0,
        lastSyncedAt TEXT,
        nextSyncDueAt TEXT,
        isOfflineAvailable INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        FOREIGN KEY (gradeId) REFERENCES grades(id),
        FOREIGN KEY (subjectId) REFERENCES subjects(id)
      )
    ''');

    // Learner Progress table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS learner_progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        chapterId INTEGER NOT NULL,
        completionState TEXT DEFAULT 'not-started',
        readingProgressPercent INTEGER DEFAULT 0,
        quizAttempts INTEGER,
        quizBestScore INTEGER,
        flashcardsReviewed INTEGER,
        lastAccessedAt TEXT,
        completedAt TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL,
        UNIQUE(chapterId),
        FOREIGN KEY (chapterId) REFERENCES chapters(id) ON DELETE CASCADE
      )
    ''');

    // Create indices for frequently queried fields
    await db.execute('CREATE INDEX idx_subjects_gradeId ON subjects(gradeId)');
    await db.execute('CREATE INDEX idx_chapters_subjectId ON chapters(subjectId)');
    await db.execute('CREATE INDEX idx_concepts_chapterId ON concepts(chapterId)');
    await db.execute('CREATE INDEX idx_quizzes_chapterId ON quizzes(chapterId)');
    await db.execute('CREATE INDEX idx_flashcards_chapterId ON flashcards(chapterId)');
    await db.execute('CREATE INDEX idx_packs_syncState ON educational_packs(syncState)');
    await db.execute('CREATE INDEX idx_progress_state ON learner_progress(completionState)');

    // Create full-text search table for content search.
    // Priority: fts4 (universally supported on Android) → fts3 → no FTS.
    // fts5 is intentionally skipped — it is absent from many Android SQLite builds.
    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS content_fts USING fts4(
          content, title, contentId, type
        );
      ''');
      _ftsSearchAvailable = true;
      print('[FTS] FTS_MODULE=fts4 STATUS=ok');
    } catch (e4) {
      print('[FTS] FTS4_FAILED=$e4 — trying fts3');
      try {
        await db.execute('''
          CREATE VIRTUAL TABLE IF NOT EXISTS content_fts USING fts3(
            content, title, contentId, type
          );
        ''');
        _ftsSearchAvailable = true;
        print('[FTS] FTS_MODULE=fts3 STATUS=ok');
      } catch (e3) {
        _ftsSearchAvailable = false;
        print('[FTS] FTS_MODULE=none STATUS=degraded error=$e3');
      }
    }


    AppEnvironment.log('SYNC', 'Database schema created successfully');
  }

  /// Close database connection
  static Future<void> close() async {
    AppEnvironment.log('SYNC', 'Educational database delegated close');
  }

  /// Delete entire database (use with caution)
  static Future<void> deleteDatabase() async {
    try {
      final databasesPath = await sqflite.getDatabasesPath();
      final path = join(databasesPath, 'educational.db');
      await sqflite.deleteDatabase(path);
      AppEnvironment.log('SYNC', 'Educational database deleted');
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error deleting database: $e');
    }
  }

  static bool get isFullTextSearchAvailable => _ftsSearchAvailable;
}
