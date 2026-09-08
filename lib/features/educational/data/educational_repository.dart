import '../../../config/app_environment.dart';
import '../models/educational_models.dart';
import 'educational_database.dart';

/// Repository for educational content CRUD operations
/// 
/// Provides a clean interface for all educational database operations.
/// This abstraction layer separates business logic from database details.
class EducationalRepository {
  // ===== GRADE OPERATIONS =====

  static Future<int> insertGrade(GradeModel grade) async {
    try {
      final db = await EducationalDatabase.database;
      final id = await db.insert('grades', grade.toMap());
      AppEnvironment.log('SYNC', 'Grade inserted: ${grade.name} (id: $id)');
      return id;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error inserting grade: $e');
      rethrow;
    }
  }

  static Future<List<GradeModel>> getAllGrades() async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query('grades', orderBy: 'gradeNumber ASC');
      return List.generate(maps.length, (i) => GradeModel.fromMap(maps[i]));
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching grades: $e');
      return [];
    }
  }

  static Future<GradeModel?> getGradeById(int id) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query('grades', where: 'id = ?', whereArgs: [id]);
      if (maps.isNotEmpty) return GradeModel.fromMap(maps.first);
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching grade: $e');
    }
    return null;
  }

  static Future<void> updateGrade(GradeModel grade) async {
    try {
      final db = await EducationalDatabase.database;
      await db.update('grades', grade.toMap(), where: 'id = ?', whereArgs: [grade.id]);
      AppEnvironment.log('SYNC', 'Grade updated: ${grade.name}');
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error updating grade: $e');
      rethrow;
    }
  }

  // ===== SUBJECT OPERATIONS =====

  static Future<int> insertSubject(SubjectModel subject) async {
    try {
      final db = await EducationalDatabase.database;
      final id = await db.insert('subjects', subject.toMap());
      AppEnvironment.log('SYNC', 'Subject inserted: ${subject.name} (id: $id)');
      return id;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error inserting subject: $e');
      rethrow;
    }
  }

  static Future<List<SubjectModel>> getSubjectsByGradeId(int gradeId) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query('subjects', where: 'gradeId = ?', whereArgs: [gradeId]);
      return List.generate(maps.length, (i) => SubjectModel.fromMap(maps[i]));
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching subjects: $e');
      return [];
    }
  }

  static Future<SubjectModel?> getSubjectById(int id) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query('subjects', where: 'id = ?', whereArgs: [id]);
      if (maps.isNotEmpty) return SubjectModel.fromMap(maps.first);
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching subject: $e');
    }
    return null;
  }

  // ===== CHAPTER OPERATIONS =====

  static Future<int> insertChapter(ChapterModel chapter) async {
    try {
      final db = await EducationalDatabase.database;
      final id = await db.insert('chapters', chapter.toMap());
      AppEnvironment.log('SYNC', 'Chapter inserted: ${chapter.name} (id: $id)');
      return id;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error inserting chapter: $e');
      rethrow;
    }
  }

  static Future<List<ChapterModel>> getChaptersBySubjectId(int subjectId) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query(
        'chapters',
        where: 'subjectId = ?',
        whereArgs: [subjectId],
        orderBy: 'sequenceNumber ASC',
      );
      return List.generate(maps.length, (i) => ChapterModel.fromMap(maps[i]));
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching chapters: $e');
      return [];
    }
  }

  static Future<ChapterModel?> getChapterById(int id) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query('chapters', where: 'id = ?', whereArgs: [id]);
      if (maps.isNotEmpty) return ChapterModel.fromMap(maps.first);
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching chapter: $e');
    }
    return null;
  }

  // ===== CONCEPT OPERATIONS =====

  static Future<int> insertConcept(ConceptModel concept) async {
    try {
      final db = await EducationalDatabase.database;
      final id = await db.insert('concepts', concept.toMap());
      AppEnvironment.log('SYNC', 'Concept inserted: ${concept.name} (id: $id)');
      return id;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error inserting concept: $e');
      rethrow;
    }
  }

  static Future<List<ConceptModel>> getConceptsByChapterId(int chapterId) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query(
        'concepts',
        where: 'chapterId = ?',
        whereArgs: [chapterId],
        orderBy: 'sequenceNumber ASC',
      );
      return List.generate(maps.length, (i) => ConceptModel.fromMap(maps[i]));
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching concepts: $e');
      return [];
    }
  }

  // ===== QUIZ OPERATIONS =====

  static Future<int> insertQuiz(QuizModel quiz) async {
    try {
      final db = await EducationalDatabase.database;
      final id = await db.insert('quizzes', quiz.toMap());
      AppEnvironment.log('SYNC', 'Quiz inserted: ${quiz.title} (id: $id)');
      return id;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error inserting quiz: $e');
      rethrow;
    }
  }

  static Future<List<QuizModel>> getQuizzesByChapterId(int chapterId) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query(
        'quizzes',
        where: 'chapterId = ?',
        whereArgs: [chapterId],
      );
      return List.generate(maps.length, (i) => QuizModel.fromMap(maps[i]));
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching quizzes: $e');
      return [];
    }
  }

  static Future<List<QuizQuestion>> getQuizQuestions(int quizId) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query(
        'quiz_questions',
        where: 'quizId = ?',
        whereArgs: [quizId],
        orderBy: 'sequenceNumber ASC',
      );
      return List.generate(maps.length, (i) => QuizQuestion.fromMap(maps[i]));
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching quiz questions: $e');
      return [];
    }
  }

  static Future<int> insertQuizQuestion(QuizQuestion question) async {
    try {
      final db = await EducationalDatabase.database;
      final id = await db.insert('quiz_questions', question.toMap());
      return id;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error inserting quiz question: $e');
      rethrow;
    }
  }

  // ===== FLASHCARD OPERATIONS =====

  static Future<int> insertFlashcard(FlashcardModel flashcard) async {
    try {
      final db = await EducationalDatabase.database;
      final id = await db.insert('flashcards', flashcard.toMap());
      AppEnvironment.log('SYNC', 'Flashcard inserted: ${flashcard.term} (id: $id)');
      return id;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error inserting flashcard: $e');
      rethrow;
    }
  }

  static Future<List<FlashcardModel>> getFlashcardsByChapterId(int chapterId) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query(
        'flashcards',
        where: 'chapterId = ?',
        whereArgs: [chapterId],
        orderBy: 'sequenceNumber ASC',
      );
      return List.generate(maps.length, (i) => FlashcardModel.fromMap(maps[i]));
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching flashcards: $e');
      return [];
    }
  }

  static Future<List<FlashcardModel>> getFlashcardsByChapterTitle(String title) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.rawQuery('''
        SELECT f.* FROM flashcards f
        JOIN chapters c ON f.chapterId = c.id
        WHERE c.title LIKE ? OR c.title LIKE ?
        ORDER BY f.sequenceNumber ASC
      ''', ['%$title%', '$title']);
      if (maps.isNotEmpty) {
        return List.generate(maps.length, (i) => FlashcardModel.fromMap(maps[i]));
      }
      final fallback = await db.query('flashcards', limit: 20);
      return List.generate(fallback.length, (i) => FlashcardModel.fromMap(fallback[i]));
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching flashcards by title: $e');
      return [];
    }
  }

  // ===== PACK OPERATIONS =====

  static Future<int> insertPack(EducationalPackModel pack) async {
    try {
      final db = await EducationalDatabase.database;
      final id = await db.insert('educational_packs', pack.toMap());
      AppEnvironment.log('SYNC', 'Pack inserted: ${pack.name} (id: $id)');
      return id;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error inserting pack: $e');
      rethrow;
    }
  }

  static Future<List<EducationalPackModel>> getAllPacks() async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query('educational_packs', orderBy: 'updatedAt DESC');
      return List.generate(maps.length, (i) => EducationalPackModel.fromMap(maps[i]));
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching packs: $e');
      return [];
    }
  }

  static Future<List<EducationalPackModel>> getPacksByGradeId(int gradeId) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query(
        'educational_packs',
        where: 'gradeId = ?',
        whereArgs: [gradeId],
      );
      return List.generate(maps.length, (i) => EducationalPackModel.fromMap(maps[i]));
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching grade packs: $e');
      return [];
    }
  }

  static Future<EducationalPackModel?> getPackByPackId(String packId) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query(
        'educational_packs',
        where: 'packId = ?',
        whereArgs: [packId],
      );
      if (maps.isNotEmpty) return EducationalPackModel.fromMap(maps.first);
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching pack: $e');
    }
    return null;
  }

  static Future<void> updatePack(EducationalPackModel pack) async {
    try {
      final db = await EducationalDatabase.database;
      await db.update(
        'educational_packs',
        pack.toMap(),
        where: 'packId = ?',
        whereArgs: [pack.packId],
      );
      AppEnvironment.log('SYNC', 'Pack updated: ${pack.name}');
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error updating pack: $e');
      rethrow;
    }
  }

  // ===== PROGRESS OPERATIONS =====

  static Future<int> insertProgress(LearnerProgressModel progress) async {
    try {
      final db = await EducationalDatabase.database;
      final id = await db.insert('learner_progress', progress.toMap());
      return id;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error inserting progress: $e');
      rethrow;
    }
  }

  static Future<LearnerProgressModel?> getProgressByChapterId(int chapterId) async {
    try {
      final db = await EducationalDatabase.database;
      final maps = await db.query(
        'learner_progress',
        where: 'chapterId = ?',
        whereArgs: [chapterId],
      );
      if (maps.isNotEmpty) return LearnerProgressModel.fromMap(maps.first);
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching progress: $e');
    }
    return null;
  }

  static Future<void> updateProgress(LearnerProgressModel progress) async {
    try {
      final db = await EducationalDatabase.database;
      await db.update(
        'learner_progress',
        progress.toMap(),
        where: 'chapterId = ?',
        whereArgs: [progress.chapterId],
      );
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error updating progress: $e');
      rethrow;
    }
  }

  // ===== SEARCH OPERATIONS =====

  static Future<List<dynamic>> searchContent(String query) async {
    try {
      final db = await EducationalDatabase.database;
      if (EducationalDatabase.isFullTextSearchAvailable) {
        return await db.rawQuery(
          '''
          SELECT * FROM content_fts WHERE content_fts MATCH ?
          ''',
          [query],
        );
      }

      final likeQuery = '%$query%';
      final results = <Map<String, Object?>>[];

      results.addAll(await db.rawQuery(
        '''
        SELECT 'concept' AS type, CAST(id AS TEXT) AS contentId, name AS title, definition AS content
        FROM concepts
        WHERE name LIKE ? OR definition LIKE ?
        ''',
        [likeQuery, likeQuery],
      ));

      results.addAll(await db.rawQuery(
        '''
        SELECT 'chapter' AS type, CAST(id AS TEXT) AS contentId, name AS title, COALESCE(summary, content, '') AS content
        FROM chapters
        WHERE name LIKE ? OR summary LIKE ? OR content LIKE ?
        ''',
        [likeQuery, likeQuery, likeQuery],
      ));

      results.addAll(await db.rawQuery(
        '''
        SELECT 'flashcard' AS type, CAST(id AS TEXT) AS contentId, term AS title, definition AS content
        FROM flashcards
        WHERE term LIKE ? OR definition LIKE ?
        ''',
        [likeQuery, likeQuery],
      ));

      return results;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error searching content: $e');
      return [];
    }
  }
}
