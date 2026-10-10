import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../course/data/local/app_database.dart';
import '../../domain/content_pack_models.dart';

class ContentPackRepository {
  ContentPackRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<Directory> get packRootDirectory async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'content_packs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<List<ContentPackManifest>> listInstalledPacks() async {
    final db = await _database.database;
    final rows = await db.query(
      'material_packs',
      orderBy: 'installed_at DESC, title ASC',
    );
    return rows
        .map((row) => ContentPackManifest.fromMap(row))
        .toList();
  }

  Future<ContentPackManifest?> getPackById(String packId) async {
    final db = await _database.database;
    final rows = await db.query(
      'material_packs',
      where: 'pack_id = ?',
      whereArgs: <Object?>[packId],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return ContentPackManifest.fromMap(rows.first);
  }

  Future<List<ContentPackItem>> listItemsForPack(String packId) async {
    final db = await _database.database;
    final rows = await db.query(
      'material_pack_items',
      where: 'pack_id = ?',
      whereArgs: <Object?>[packId],
      orderBy: 'kind ASC, order_index ASC, title ASC',
    );
    return rows.map((row) => ContentPackItem.fromMap(row)).toList();
  }

  Future<List<ContentPackItem>> listItemsByKind(String kind) async {
    final db = await _database.database;
    if (kind.toLowerCase() == 'pdf') {
      final rows = await db.query(
        'material_pack_items',
        where: "kind IN ('pdf', 'textbook', 'document') OR LOWER(absolute_path) LIKE '%.pdf'",
        orderBy: 'grade ASC, subject ASC, medium ASC, order_index ASC',
      );
      return rows.map((row) => ContentPackItem.fromMap(row)).toList();
    }
    final rows = await db.query(
      'material_pack_items',
      where: 'kind = ?',
      whereArgs: <Object?>[kind],
      orderBy: 'grade ASC, subject ASC, medium ASC, order_index ASC',
    );
    return rows.map((row) => ContentPackItem.fromMap(row)).toList();
  }

  Future<ContentPackItem?> findPdfItemForChapter({
    String? chapterTitle,
    String? subject,
    int? grade,
    String? packId,
  }) async {
    final db = await _database.database;
    var query = "WHERE (kind IN ('pdf', 'textbook', 'document') OR LOWER(absolute_path) LIKE '%.pdf')";
    final args = <Object?>[];

    if (packId != null && packId.isNotEmpty) {
      query += " AND pack_id = ?";
      args.add(packId);
    }
    if (grade != null) {
      query += " AND (grade = ? OR grade IS NULL)";
      args.add(grade);
    }

    final rows = await db.rawQuery(
      'SELECT * FROM material_pack_items $query ORDER BY order_index ASC',
      args,
    );
    final items = rows.map((r) => ContentPackItem.fromMap(r)).toList();

    // 1. Exact or substring match on title/chapterId
    if (chapterTitle != null && chapterTitle.isNotEmpty) {
      final clean = chapterTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      for (final item in items) {
        final itemTitle = item.title.toLowerCase();
        final chapId = (item.chapterId ?? '').toLowerCase();
        if (itemTitle.contains(clean) || chapId.contains(clean) || clean.contains(itemTitle)) {
          if (File(item.absolutePath).existsSync()) return item;
        }
      }
    }

    // 2. Return first existing PDF file for the grade/pack
    for (final item in items) {
      if (File(item.absolutePath).existsSync()) return item;
    }

    // 3. Fallback check installed pack root directories for source.pdf
    final packs = await listInstalledPacks();
    for (final pack in packs) {
      if (grade != null && pack.gradeMin != grade && pack.gradeMax != grade) continue;
      final pdfFile = File(p.join(pack.rootPath, 'source.pdf'));
      if (pdfFile.existsSync()) {
        return ContentPackItem(
          packId: pack.packId,
          kind: 'pdf',
          title: pack.title,
          relativePath: 'source.pdf',
          absolutePath: pdfFile.path,
          sizeBytes: pdfFile.existsSync() ? pdfFile.lengthSync() : 0,
          orderIndex: 0,
          grade: pack.gradeMin,
          subject: pack.subject,
          medium: pack.medium,
        );
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> findFlashcardsForChapter({
    String? chapterTitle,
    String? subject,
    int? grade,
    String? packId,
  }) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      "SELECT * FROM material_pack_items WHERE (kind = 'flashcard' OR LOWER(relative_path) LIKE '%flashcards.json')",
    );
    var items = rows.map((r) => ContentPackItem.fromMap(r)).toList();

    if (packId != null && packId.isNotEmpty) {
      items = items.where((i) => i.packId == packId).toList();
    }
    if (grade != null) {
      items = items.where((i) => i.grade == null || i.grade == grade).toList();
    }
    if (subject != null && subject.isNotEmpty) {
      final sLower = subject.toLowerCase();
      items = items.where((i) => i.subject == null || i.subject!.toLowerCase().contains(sLower)).toList();
    }

    if (chapterTitle != null && chapterTitle.isNotEmpty) {
      final clean = chapterTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      if (clean.isNotEmpty) {
        final matching = items.where((i) {
          final itemTitle = i.title.toLowerCase();
          final chapId = (i.chapterId ?? '').toLowerCase();
          final rel = i.relativePath.toLowerCase();
          return itemTitle.contains(clean) || chapId.contains(clean) || rel.contains(clean) || clean.contains(itemTitle);
        }).toList();

        if (matching.isNotEmpty) {
          items = matching;
        }
      }
    }

    for (final item in items) {
      final file = File(item.absolutePath);
      if (file.existsSync()) {
        try {
          final content = await file.readAsString();
          final List<dynamic> decoded = jsonDecode(content);
          return decoded.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        } catch (_) {}
      }
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> findQuizQuestionsForChapter({
    String? chapterTitle,
    String? subject,
    int? grade,
    String? packId,
  }) async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      "SELECT * FROM material_pack_items WHERE (kind = 'quiz' OR LOWER(relative_path) LIKE '%quizzes.json')",
    );
    var items = rows.map((r) => ContentPackItem.fromMap(r)).toList();

    if (packId != null && packId.isNotEmpty) {
      items = items.where((i) => i.packId == packId).toList();
    }
    if (grade != null) {
      items = items.where((i) => i.grade == null || i.grade == grade).toList();
    }
    if (subject != null && subject.isNotEmpty) {
      final sLower = subject.toLowerCase();
      items = items.where((i) => i.subject == null || i.subject!.toLowerCase().contains(sLower)).toList();
    }

    if (chapterTitle != null && chapterTitle.isNotEmpty) {
      final clean = chapterTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
      if (clean.isNotEmpty) {
        final matching = items.where((i) {
          final itemTitle = i.title.toLowerCase();
          final chapId = (i.chapterId ?? '').toLowerCase();
          final rel = i.relativePath.toLowerCase();
          return itemTitle.contains(clean) || chapId.contains(clean) || rel.contains(clean) || clean.contains(itemTitle);
        }).toList();

        if (matching.isNotEmpty) {
          items = matching;
        }
      }
    }

    for (final item in items) {
      final file = File(item.absolutePath);
      if (file.existsSync()) {
        try {
          final content = await file.readAsString();
          final List<dynamic> decoded = jsonDecode(content);
          return decoded.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
        } catch (_) {}
      }
    }
    return const [];
  }

  Future<void> upsertPack({
    required ContentPackManifest manifest,
    required List<ContentPackItem> items,
  }) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.insert(
        'material_packs',
        manifest.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.delete(
        'material_pack_items',
        where: 'pack_id = ?',
        whereArgs: <Object?>[manifest.packId],
      );
      for (final item in items) {
        await txn.insert(
          'material_pack_items',
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> deletePack(String packId) async {
    final db = await _database.database;
    await db.delete(
      'material_packs',
      where: 'pack_id = ?',
      whereArgs: <Object?>[packId],
    );
  }

  Future<ContentPackCatalogEntry> buildCatalogEntry(String packId) async {
    final db = await _database.database;
    final packRows = await db.query(
      'material_packs',
      where: 'pack_id = ?',
      whereArgs: <Object?>[packId],
      limit: 1,
    );
    if (packRows.isEmpty) {
      throw StateError('Pack not found: $packId');
    }

    final manifest = ContentPackManifest.fromMap(packRows.first);
    final itemRows = await db.query(
      'material_pack_items',
      where: 'pack_id = ?',
      whereArgs: <Object?>[packId],
    );

    var pdfCount = 0;
    var videoCount = 0;
    var quizCount = 0;
    var otherCount = 0;
    for (final row in itemRows) {
      final kind = (row['kind'] as String? ?? 'other').toLowerCase();
      if (kind == 'pdf') {
        pdfCount += 1;
      } else if (kind == 'video') {
        videoCount += 1;
      } else if (kind == 'quiz') {
        quizCount += 1;
      } else {
        otherCount += 1;
      }
    }

    return ContentPackCatalogEntry(
      manifest: manifest,
      itemCount: itemRows.length,
      pdfCount: pdfCount,
      videoCount: videoCount,
      quizCount: quizCount,
      otherCount: otherCount,
    );
  }

  Future<int> getInstalledPackCount() async {
    final db = await _database.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM material_packs');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<int> getInstalledItemCount() async {
    final db = await _database.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM material_pack_items');
    return (rows.first['c'] as int?) ?? 0;
  }
}
