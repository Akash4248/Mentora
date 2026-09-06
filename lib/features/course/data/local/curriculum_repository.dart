import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../content_packs/data/local/content_pack_repository.dart';
import '../../domain/curriculum_models.dart';
import 'course_repository.dart';

class CurriculumRepository {
  CurriculumRepository({ContentPackRepository? packRepository})
    : _packRepo = packRepository ?? ContentPackRepository();

  final ContentPackRepository _packRepo;

  Future<List<CurriculumGrade>> getCurriculum({
    String languageCode = 'en',
  }) async {
    final installedPacks = await _packRepo.listInstalledPacks();
    final Map<int, Map<String, List<CurriculumChapter>>> grouped = {};

    for (final pack in installedPacks) {
      try {
        final manifestFile = File(pack.manifestPath);
        if (!await manifestFile.exists()) {
          continue;
        }

        final manifestContent = await manifestFile.readAsString();
        final manifestData =
            jsonDecode(manifestContent) as Map<String, dynamic>;

        // Extract and normalize metadata
        final grade = manifestData['grade'] as int? ?? pack.gradeMin;
        final rawSubject = manifestData['subject'] as String? ?? pack.subject;
        final subject = _normalizeSubjectName(rawSubject);
        final chapterTitle = manifestData['chapter'] as String? ?? pack.title;

        // Load summary from summaries.json if manifest has none
        var summary = manifestData['summary'] as String? ?? '';
        if (summary.isEmpty) {
          final summariesFile = File(p.join(pack.rootPath, 'summaries.json'));
          if (await summariesFile.exists()) {
            try {
              final sumContent = await summariesFile.readAsString();
              final List<dynamic> sumList = jsonDecode(sumContent);
              if (sumList.isNotEmpty) {
                final firstItem = sumList.first as Map<String, dynamic>;
                summary = firstItem['text'] as String? ?? '';
              }
            } catch (_) {}
          }
        }

        final language = manifestData['language'] as String? ?? 'english';

        final chapter = CurriculumChapter(
          packId: pack.packId,
          title: _capitalize(chapterTitle),
          subject: subject,
          grade: grade,
          rootPath: pack.rootPath,
          summary: summary,
          language: language,
        );

        grouped.putIfAbsent(grade, () => {});
        grouped[grade]!.putIfAbsent(subject, () => []);
        grouped[grade]![subject]!.add(chapter);
      } catch (e) {
        print('[CURRICULUM] Error parsing pack manifest ${pack.packId}: $e');
      }
    }

    final List<CurriculumGrade> curriculum = [];
    grouped.forEach((grade, subjectMap) {
      final List<CurriculumSubject> subjects = [];
      subjectMap.forEach((subjectName, chapters) {
        // Sort chapters alphabetically by title
        chapters.sort((a, b) => a.title.compareTo(b.title));
        subjects.add(
          CurriculumSubject(
            name: subjectName,
            grade: grade,
            chapters: chapters,
          ),
        );
      });
      subjects.sort((a, b) => a.name.compareTo(b.name));
      curriculum.add(CurriculumGrade(grade: grade, subjects: subjects));
    });

    curriculum.sort((a, b) => a.grade.compareTo(b.grade));

    if (curriculum.isEmpty) {
      final courseRepo = CourseRepository();
      final courses = await courseRepo.getCourses(languageCode: languageCode);

      for (final course in courses) {
        final match = RegExp(r'\d+').firstMatch(course.id);
        if (match == null) continue;
        final grade = int.parse(match.group(0)!);

        final subjects = await courseRepo.getSubjects(
          course.id,
          languageCode: languageCode,
        );
        final currSubjects = <CurriculumSubject>[];

        for (final subject in subjects) {
          final chapters = await courseRepo.getChapters(
            subject.id,
            languageCode: languageCode,
          );
          final currChapters = chapters
              .map(
                (ch) => CurriculumChapter(
                  packId: ch.id,
                  title: ch.title,
                  subject: subject.name,
                  grade: grade,
                  rootPath: '',
                  summary: ch.summary,
                  language: 'en',
                ),
              )
              .toList();

          currSubjects.add(
            CurriculumSubject(
              name: subject.name,
              grade: grade,
              chapters: currChapters,
            ),
          );
        }

        curriculum.add(
          CurriculumGrade(
            grade: grade,
            subjects: currSubjects,
          ),
        );
      }
    }

    return curriculum;
  }

  String _normalizeSubjectName(String name) {
    final lower = name.toLowerCase().trim();
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
    if (lower == 'social science' ||
        lower == 'social_science' ||
        lower == 'socialscience') {
      return 'Social Science';
    }
    return _capitalize(name);
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
}
