import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import '../../../course/data/local/app_database.dart';

class ChapterVideoResource {
  const ChapterVideoResource({
    this.id,
    required this.chapterId,
    required this.grade,
    required this.subject,
    required this.chapterTitle,
    required this.channelName,
    required this.videoTitle,
    required this.videoUrl,
    required this.videoId,
    required this.rank,
    required this.durationSeconds,
    required this.language,
    required this.description,
  });

  final int? id;
  final String chapterId;
  final int grade;
  final String subject;
  final String chapterTitle;
  final String channelName;
  final String videoTitle;
  final String videoUrl;
  final String videoId;
  final int rank;
  final int durationSeconds;
  final String language;
  final String description;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'chapter_id': chapterId,
      'grade': grade,
      'subject': subject,
      'chapter_title': chapterTitle,
      'channel_name': channelName,
      'video_title': videoTitle,
      'video_url': videoUrl,
      'video_id': videoId,
      'rank': rank,
      'duration_seconds': durationSeconds,
      'language': language,
      'description': description,
    };
  }

  factory ChapterVideoResource.fromMap(Map<String, dynamic> map) {
    return ChapterVideoResource(
      id: map['id'] as int?,
      chapterId: map['chapter_id'] as String? ?? '',
      grade: map['grade'] as int? ?? 0,
      subject: map['subject'] as String? ?? '',
      chapterTitle: map['chapter_title'] as String? ?? '',
      channelName: map['channel_name'] as String? ?? '',
      videoTitle: map['video_title'] as String? ?? '',
      videoUrl: map['video_url'] as String? ?? '',
      videoId: map['video_id'] as String? ?? '',
      rank: map['rank'] as int? ?? 1,
      durationSeconds: map['duration_seconds'] as int? ?? 0,
      language: map['language'] as String? ?? 'en',
      description: map['description'] as String? ?? '',
    );
  }
}

class VideoResourceRepository {
  VideoResourceRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  /// Ensures video resources for the specified [grade] are loaded into local SQLite storage.
  Future<void> ensureSeedVideosForGrade(int grade) async {
    final db = await _database.database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM chapter_video_resources WHERE grade = ?', <Object?>[grade]),
        ) ??
        0;

    final sample = await db.rawQuery('SELECT video_url FROM chapter_video_resources WHERE grade = ? LIMIT 1', <Object?>[grade]);
    final bool hasSyntheticUrls = sample.isNotEmpty && sample.first['video_url']?.toString().contains('MAG_BR') == true;

    if (count > 0 && !hasSyntheticUrls) {
      return;
    }

    try {
      if (hasSyntheticUrls) {
        await db.delete('chapter_video_resources', where: 'grade = ?', whereArgs: <Object?>[grade]);
      }

      final jsonString = await rootBundle.loadString(
        'assets/chapter_video_resources.json',
      );
      final List<dynamic> list = jsonDecode(jsonString);

      // Filter entries matching the requested grade only
      final gradeEntries = list.where((item) => item is Map<String, dynamic> && item['grade'] == grade).toList();

      final batch = db.batch();
      for (final item in gradeEntries) {
        if (item is Map<String, dynamic>) {
          batch.insert(
            'chapter_video_resources',
            <String, dynamic>{
              'chapter_id': item['chapter_id'],
              'grade': grade,
              'subject': item['subject'],
              'chapter_title': item['chapter_title'],
              'channel_name': item['channel_name'],
              'video_title': item['video_title'],
              'video_url': item['video_url'],
              'video_id': item['video_id'],
              'rank': item['rank'],
              'duration_seconds': item['duration_seconds'],
              'language': item['language'],
              'description': item['description'],
              'created_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
      await batch.commit(noResult: true);
      // ignore: avoid_print
      print('[VideoResourceRepository] Loaded and stored ${gradeEntries.length} video resources for Grade $grade in SQLite.');
    } catch (e) {
      // ignore: avoid_print
      print('[VideoResourceRepository] Seed error for Grade $grade: $e');
    }
  }

  /// Store downloaded grade pack videos into local SQLite storage
  Future<void> saveGradeVideos(int grade, List<Map<String, dynamic>> videos) async {
    final db = await _database.database;
    await db.delete('chapter_video_resources', where: 'grade = ?', whereArgs: <Object?>[grade]);

    final batch = db.batch();
    for (final v in videos) {
      batch.insert(
        'chapter_video_resources',
        <String, dynamic>{
          'chapter_id': v['chapter_id'] ?? v['chapter'] ?? '',
          'grade': grade,
          'subject': v['subject'] ?? '',
          'chapter_title': v['chapter_title'] ?? v['title'] ?? '',
          'channel_name': v['channel_name'] ?? v['channel'] ?? 'NCERT',
          'video_title': v['video_title'] ?? v['title'] ?? '',
          'video_url': v['video_url'] ?? v['videoUrl'] ?? '',
          'video_id': v['video_id'] ?? v['id'] ?? '',
          'rank': v['rank'] ?? 1,
          'duration_seconds': v['duration_seconds'] ?? 600,
          'language': v['language'] ?? 'en',
          'description': v['description'] ?? '',
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    // ignore: avoid_print
    print('[VideoResourceRepository] Saved ${videos.length} video URLs to SQLite for Grade $grade.');
  }

  Future<List<ChapterVideoResource>> getVideosForChapter(String chapterId, {int grade = 9}) async {
    await ensureSeedVideosForGrade(grade);
    final db = await _database.database;

    var rows = await db.query(
      'chapter_video_resources',
      where: 'grade = ? AND chapter_id = ?',
      whereArgs: <Object?>[grade, chapterId],
      orderBy: 'rank ASC',
    );

    if (rows.isEmpty) {
      final sanitized = chapterId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '%');
      rows = await db.query(
        'chapter_video_resources',
        where: 'grade = ? AND (chapter_id LIKE ? OR chapter_title LIKE ?)',
        whereArgs: <Object?>[grade, '%$sanitized%', '%$sanitized%'],
        orderBy: 'rank ASC',
      );
    }

    if (rows.isEmpty) {
      rows = await db.query(
        'chapter_video_resources',
        where: 'grade = ?',
        whereArgs: <Object?>[grade],
        orderBy: 'rank ASC',
      );
    }

    return rows.map((r) => ChapterVideoResource.fromMap(r)).toList();
  }
}
