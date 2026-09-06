import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';

import '../../../content_packs/data/local/content_pack_repository.dart';
import '../../domain/course_tree.dart';
import 'app_database.dart';

class CourseRepository {
  CourseRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;
  final ContentPackRepository _packRepository = ContentPackRepository();

  static const List<String> _upperSubjects = <String>[
    'Mathematics',
    'English',
    'Kannada',
    'Science',
    'Social Science',
    'Computer (Optional)',
  ];

  Future<void> ensureSeedData() async {
    final db = await _database.database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM chapters'),
        ) ??
        0;

    if (count >= 256) {
      return;
    }

    final batch = db.batch();

    for (var grade = 6; grade <= 12; grade++) {
      batch.insert(
        'courses',
        <String, String>{
          'id': 'course_$grade',
          'name': 'Class $grade',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    try {
      final jsonString = await rootBundle.loadString(
        'assets/curriculum_256_chapters.json',
      );
      final List<dynamic> list = jsonDecode(jsonString);
      final seenSubjects = <String>{};

      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final chapterId = item['chapter_id'] as String;
          final grade = item['grade'] as int;
          final subjectName = item['subject'] as String;
          final chapterTitle = item['chapter_title'] as String;
          final description =
              item['description'] as String? ?? 'Chapter on $chapterTitle';

          final subjectSlug = _subjectKey(subjectName).replaceAll(
            RegExp(r'[^a-z0-9]+'),
            '_',
          );
          final subjectId = 'sub_${subjectSlug}_$grade';

          if (seenSubjects.add(subjectId)) {
            batch.insert(
              'subjects',
              <String, String>{
                'id': subjectId,
                'course_id': 'course_$grade',
                'name': _displaySubjectName(subjectName),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }

          batch.insert(
            'chapters',
            <String, String>{
              'id': chapterId,
              'subject_id': subjectId,
              'title': chapterTitle,
              'summary': description,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    } catch (e) {
      // ignore: avoid_print
      print('[CourseRepository] Seed error: $e');
    }

    await batch.commit(noResult: true);
  }

  Future<List<Course>> getCourses({String languageCode = 'en'}) async {
    await ensureSeedData();
    final db = await _database.database;
    final rows = await db.query('courses', orderBy: 'name ASC');

    final all = rows
        .map(
          (row) => Course(id: row['id'] as String, name: row['name'] as String),
        )
        .toList();

    final filtered = all.where((course) {
      final match = RegExp(r'^course_(\d+)$').firstMatch(course.id);
      if (match == null) {
        return false;
      }
      final grade = int.tryParse(match.group(1) ?? '');
      return grade != null && grade >= 6 && grade <= 12;
    }).toList();

    filtered.sort((a, b) {
      final ga = int.parse(RegExp(r'\d+').firstMatch(a.id)!.group(0)!);
      final gb = int.parse(RegExp(r'\d+').firstMatch(b.id)!.group(0)!);
      return ga.compareTo(gb);
    });

    return _localizeCourses(filtered, languageCode);
  }

  Future<List<Subject>> getSubjects(
    String courseId, {
    String languageCode = 'en',
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'subjects',
      where: 'course_id = ?',
      whereArgs: [courseId],
      orderBy: 'name ASC',
    );

    final all = rows
        .map(
          (row) => Subject(
            id: row['id'] as String,
            courseId: row['course_id'] as String,
            name: row['name'] as String,
          ),
        )
        .toList();

    final gradeMatch = RegExp(r'^course_(\d+)$').firstMatch(courseId);
    final grade = int.tryParse(gradeMatch?.group(1) ?? '');
    if (grade == null) {
      return _localizeSubjects(all, languageCode);
    }

    final merged = <String, Subject>{};
    for (final subject in all) {
      merged[_subjectKey(subject.name)] = subject;
    }

    final installedSubjects = await _installedPackSubjects(
      grade: grade,
      courseId: courseId,
    );
    for (final subject in installedSubjects) {
      merged.putIfAbsent(_subjectKey(subject.name), () => subject);
    }

    final subjects = merged.values.toList()
      ..sort((a, b) {
        final ai = _subjectSortIndex(a.name);
        final bi = _subjectSortIndex(b.name);
        if (ai != bi) {
          return ai.compareTo(bi);
        }
        return a.name.compareTo(b.name);
      });

    return _localizeSubjects(subjects, languageCode);
  }

  Future<List<Chapter>> getChapters(
    String subjectId, {
    String languageCode = 'en',
  }) async {
    final db = await _database.database;
    final subjectRows = await db.query(
      'subjects',
      where: 'id = ?',
      whereArgs: [subjectId],
      limit: 1,
    );
    String? subjectName;
    String? courseId;

    if (subjectRows.isNotEmpty) {
      final subjectRow = subjectRows.first;
      subjectName = subjectRow['name'] as String? ?? '';
      courseId = subjectRow['course_id'] as String? ?? '';
    } else {
      subjectName = _subjectNameFromSubjectId(subjectId);
      courseId = _courseIdFromSubjectId(subjectId);
    }

    final grade = courseId == null ? null : _gradeFromCourseId(courseId);

    final localChapters = <Chapter>[];
    if (grade != null && subjectName != null && subjectName.isNotEmpty) {
      final installedPackChapters = await _chaptersFromInstalledPacks(
        grade: grade,
        subjectName: subjectName,
        subjectId: subjectId,
      );
      localChapters.addAll(installedPackChapters);
    }

    if (subjectRows.isEmpty) {
      return _localizeChapters(localChapters, languageCode);
    }

    final rows = await db.query(
      'chapters',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      orderBy: 'title ASC',
    );

    final chapters = rows
        .map(
          (row) => Chapter(
            id: row['id'] as String,
            subjectId: row['subject_id'] as String,
            title: row['title'] as String,
            summary: row['summary'] as String,
          ),
        )
        .toList();
    final merged = <String, Chapter>{};

    for (final chapter in localChapters) {
      merged[_chapterKey(chapter)] = chapter;
    }

    for (final chapter in chapters) {
      merged.putIfAbsent(_chapterKey(chapter), () => chapter);
    }

    final mergedChapters = merged.values.toList()
      ..sort((a, b) {
        final titleCompare = a.title.compareTo(b.title);
        if (titleCompare != 0) {
          return titleCompare;
        }
        return a.id.compareTo(b.id);
      });

    return _localizeChapters(mergedChapters, languageCode);
  }

  Future<List<Chapter>> _chaptersFromInstalledPacks({
    required int grade,
    required String subjectName,
    required String subjectId,
  }) async {
    final packs = await _packRepository.listInstalledPacks();
    final normalizedSubject = _normalizeSubjectName(subjectName);
    final chapters = <Chapter>[];

    for (final pack in packs) {
      if (pack.gradeMin > grade || pack.gradeMax < grade) {
        continue;
      }

      if (_normalizeSubjectName(pack.subject) != normalizedSubject) {
        continue;
      }

      final title = _packTitle(pack);
      chapters.add(
        Chapter(
          id: pack.packId,
          subjectId: subjectId,
          title: title,
          summary: title,
        ),
      );
    }

    return chapters;
  }

  String _packTitle(dynamic pack) {
    final rawTitle = (pack.title as String?)?.trim() ?? '';
    if (rawTitle.isNotEmpty) {
      return _capitalize(rawTitle);
    }
    return 'Untitled Chapter';
  }

  int? _gradeFromCourseId(String courseId) {
    final match = RegExp(r'^course_(\d+)$').firstMatch(courseId);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1) ?? '');
  }

  String _normalizeSubjectName(String name) {
    final lower = name.toLowerCase().trim();
    if (lower == 'maths' || lower == 'mathematics') {
      return 'mathematics';
    }
    if (lower == 'science') {
      return 'science';
    }
    if (lower == 'english') {
      return 'english';
    }
    if (lower == 'kannada') {
      return 'kannada';
    }
    if (lower == 'social science' ||
        lower == 'social_science' ||
        lower == 'socialscience') {
      return 'social science';
    }
    return lower;
  }

  String _displaySubjectName(String name) {
    final normalized = name.trim().replaceAll('_', ' ');
    if (normalized.isEmpty) {
      return '';
    }

    final lower = normalized.toLowerCase();
    if (lower == 'maths' || lower == 'mathematics') {
      return 'Mathematics';
    }
    if (lower == 'science') {
      return 'Science';
    }
    if (lower == 'english') {
      return 'English';
    }
    if (lower == 'kannada') {
      return 'Kannada';
    }
    if (lower == 'social science' || lower == 'socialscience') {
      return 'Social Science';
    }
    return _capitalize(normalized);
  }

  String _subjectKey(String name) {
    return _normalizeSubjectName(name);
  }

  String _chapterKey(Chapter chapter) {
    return '${chapter.subjectId}::${chapter.id}::${chapter.title}'
        .toLowerCase();
  }

  int _subjectSortIndex(String name) {
    final index = _upperSubjects.indexWhere(
      (subject) => _subjectKey(subject) == _subjectKey(name),
    );
    return index == -1 ? _upperSubjects.length : index;
  }

  String _subjectIdFromName(String subjectName, int grade) {
    final slug = _subjectKey(
      subjectName,
    ).replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return 'sub_${slug}_$grade';
  }

  String? _subjectNameFromSubjectId(String subjectId) {
    final db = RegExp(r'^sub_(.+?)_(\d+)$').firstMatch(subjectId);
    if (db == null) {
      return null;
    }

    final slug = db.group(1)?.replaceAll('_', ' ').trim() ?? '';
    if (slug.isEmpty) {
      return null;
    }
    return _displaySubjectName(slug);
  }

  String? _courseIdFromSubjectId(String subjectId) {
    final match = RegExp(r'_(\d+)$').firstMatch(subjectId);
    if (match == null) {
      return null;
    }
    return 'course_${match.group(1)}';
  }

  Future<List<Subject>> _installedPackSubjects({
    required int grade,
    required String courseId,
  }) async {
    final packs = await _packRepository.listInstalledPacks();
    final subjects = <Subject>[];
    final seen = <String>{};

    for (final pack in packs) {
      if (pack.gradeMin > grade || pack.gradeMax < grade) {
        continue;
      }

      final subjectName = _displaySubjectName(pack.subject);
      if (subjectName.isEmpty) {
        continue;
      }

      final key = _subjectKey(subjectName);
      if (!seen.add(key)) {
        continue;
      }

      subjects.add(
        Subject(
          id: _subjectIdFromName(subjectName, grade),
          courseId: courseId,
          name: subjectName,
        ),
      );
    }

    return subjects;
  }

  String _capitalize(String text) {
    if (text.isEmpty) {
      return text;
    }
    return text
        .split(' ')
        .map((word) {
          if (word.isEmpty) {
            return '';
          }
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        })
        .join(' ');
  }

  Future<List<Chapter>> getAllChapters({String languageCode = 'en'}) async {
    final db = await _database.database;
    final rows = await db.query('chapters', orderBy: 'title ASC');

    final chaptersById = <String, Chapter>{};
    for (final row in rows) {
      final chapter = Chapter(
        id: row['id'] as String,
        subjectId: row['subject_id'] as String,
        title: row['title'] as String,
        summary: row['summary'] as String,
      );
      chaptersById[chapter.id] = chapter;
    }

    final installedPacks = await _packRepository.listInstalledPacks();
    for (final pack in installedPacks) {
      final subjectName = _displaySubjectName(pack.subject);
      if (subjectName.isEmpty) {
        continue;
      }

      final grade = pack.gradeMin;
      final chapter = Chapter(
        id: pack.packId,
        subjectId: _subjectIdFromName(subjectName, grade),
        title: _packTitle(pack),
        summary: _packTitle(pack),
      );
      chaptersById[chapter.id] = chapter;
    }

    final chapters = chaptersById.values.toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    return _localizeChapters(chapters, languageCode);
  }

  // NOTE: Course/subject/chapter names are proper nouns and technical terms
  // (e.g. "Mathematics", "Science", "Real Numbers") that remain in English.
  // LLM-based translation was removed — it spawned parallel inference threads
  // on every screen load, causing the app to freeze. UI labels use l10n instead.
  Future<List<Course>> _localizeCourses(
    List<Course> courses,
    String languageCode,
  ) async => courses;

  Future<List<Subject>> _localizeSubjects(
    List<Subject> subjects,
    String languageCode,
  ) async => subjects;

  Future<List<Chapter>> _localizeChapters(
    List<Chapter> chapters,
    String languageCode,
  ) async => chapters;
}
