import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../data/local/content_pack_repository.dart';
import '../domain/content_pack_models.dart';
import '../../course/data/install/pdf_install_service.dart';
import '../../course/data/local/app_database.dart';
import 'content_pack_sync_service.dart';
import 'package:sqflite/sqflite.dart';

class PackArchiveExportResult {
  const PackArchiveExportResult({
    required this.archivePath,
    required this.packId,
    required this.itemCount,
    required this.sizeBytes,
  });

  final String archivePath;
  final String packId;
  final int itemCount;
  final int sizeBytes;
}

class PackArchiveImportResult {
  const PackArchiveImportResult({
    required this.packId,
    required this.itemCount,
    required this.installedRoot,
    this.pdfResults = const [],
  });

  final String packId;
  final int itemCount;
  final String installedRoot;
  final List<PdfInstallResult> pdfResults;
}

class PackVersionConflictException implements Exception {
  const PackVersionConflictException({
    required this.packId,
    required this.incomingVersion,
    required this.installedVersion,
  });

  final String packId;
  final int incomingVersion;
  final int installedVersion;

  @override
  String toString() {
    return 'Incoming pack version $incomingVersion is not newer than installed version '
        '$installedVersion for $packId';
  }
}

class ContentPackArchiveService {
  ContentPackArchiveService({ContentPackRepository? repository})
    : _repository = repository ?? ContentPackRepository();

  final ContentPackRepository _repository;

  Future<PackArchiveExportResult> exportPackArchive(String packId) async {
    final entry = await _repository.buildCatalogEntry(packId);
    final items = await _repository.listItemsForPack(packId);

    final exportRoot = await _repository.packRootDirectory;
    final exportDir = Directory(p.join(exportRoot.path, 'exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final archiveName =
        '${entry.manifest.packId}_v${entry.manifest.version}_$now.otpack';
    final archivePath = p.join(exportDir.path, archiveName);

    final tempDir = await Directory.systemTemp.createTemp('pack_export_');
    try {
      final manifestMap = _buildArchiveManifest(entry.manifest, items);
      final manifestFile = File(p.join(tempDir.path, 'pack_manifest.json'));
      await manifestFile.writeAsString(jsonEncode(manifestMap));

      final encoder = ZipFileEncoder();
      encoder.create(archivePath);
      encoder.addFile(manifestFile, 'pack_manifest.json');

      for (final item in items) {
        final source = File(item.absolutePath);
        if (!await source.exists()) {
          continue;
        }
        final relative = _normalizeRelative(item.relativePath);
        encoder.addFile(source, p.join('content', relative));
      }

      encoder.close();

      final archiveFile = File(archivePath);
      final stat = await archiveFile.stat();
      return PackArchiveExportResult(
        archivePath: archivePath,
        packId: packId,
        itemCount: items.length,
        sizeBytes: stat.size,
      );
    } finally {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  Future<PackArchiveImportResult> importPackArchive(
    String archivePath, {
    bool allowReplaceSameOrOlder = false,
    void Function(String message)? onProgress,
    RemoteContentPack? remotePackOverride,
  }) async {
    final db = await AppDatabase.instance.database;
    final packsBefore = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM material_packs'),
    );
    final itemsBefore = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM material_pack_items'),
    );
    final ragBefore = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM rag_chunks'),
    );
    final ftsTableExists =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='rag_chunks_fts'",
          ),
        ) ??
        0;
    final ftsBefore = ftsTableExists > 0
        ? Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM rag_chunks_fts'),
          )
        : 0;
    print('PACKS_BEFORE=$packsBefore');
    print('ITEMS_BEFORE=$itemsBefore');
    print('RAG_BEFORE=$ragBefore');
    print('FTS_BEFORE=$ftsBefore');

    final archiveFile = File(archivePath);
    if (!await archiveFile.exists()) {
      throw Exception('Pack archive not found: $archivePath');
    }

    final root = await _repository.packRootDirectory;
    final unpackDir = Directory(
      p.join(
        root.path,
        'installed',
        'incoming_${DateTime.now().millisecondsSinceEpoch}',
      ),
    );
    await unpackDir.create(recursive: true);

    try {
      final stat = await archiveFile.stat();
      print('[PACK] ARCHIVE_PATH=$archivePath');
      print('[PACK] ARCHIVE_SIZE=${stat.size}');
      print('[PACK_VERIFY] ARCHIVE_OPENED');

      final bytes = await archiveFile.readAsBytes();
      late final Archive decodedArchive;

      try {
        final gzipBytes = GZipDecoder().decodeBytes(bytes);
        decodedArchive = TarDecoder().decodeBytes(gzipBytes);
      } catch (_) {
        try {
          decodedArchive = ZipDecoder().decodeBytes(bytes);
        } catch (e) {
          throw Exception('Failed to decode archive: $e');
        }
      }

      for (final file in decodedArchive) {
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File(p.join(unpackDir.path, file.name));
          outFile.createSync(recursive: true);
          outFile.writeAsBytesSync(data);
        }
      }
    } catch (e) {
      throw Exception('Extraction failed: $e');
    }

    File? manifestFile;
    Directory? packRootDir;

    final allEntities = await unpackDir.list(recursive: true).toList();
    for (final entity in allEntities) {
      if (entity is File) {
        final name = p.basename(entity.path);
        if (name == 'pack_manifest.json' || name == 'manifest.json') {
          manifestFile = entity;
          packRootDir = entity.parent;
          break;
        }
      }
    }

    if (manifestFile == null) {
      throw Exception(
        'Invalid pack archive: missing pack_manifest.json or manifest.json',
      );
    }
    if (packRootDir == null) {
      throw Exception('Invalid pack archive: missing pack root directory');
    }

    print('[PACK] MANIFEST_FOUND=${p.basename(manifestFile.path)}');

    final raw = await manifestFile.readAsString();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;

    var manifest = decoded['manifest'] as Map<String, dynamic>?;
    var items = decoded['items'] as List<dynamic>?;

    // Handle new backend flat manifest format
    if (manifest == null) {
      manifest = decoded;
    }

    if (items == null) {
      items = [];
      final files = await packRootDir.list(recursive: true).toList();
      for (final f in files) {
        if (f is File &&
            f.path.endsWith('.json') &&
            f.path != manifestFile.path) {
          final relative = p.relative(f.path, from: packRootDir.path);
          String kind = 'other';
          if (relative.endsWith('content.json'))
            kind = 'content_json';
          else if (relative.endsWith('quizzes.json'))
            kind = 'quiz';
          else if (relative.endsWith('flashcards.json'))
            kind = 'flashcard';
          else if (relative.endsWith('summaries.json'))
            kind = 'summary';
          else if (relative.endsWith('glossary.json'))
            kind = 'glossary';

          items.add({
            'relativePath': relative,
            'kind': kind,
            'title': p.basenameWithoutExtension(relative),
          });
        }
      }
    }

    if (manifest.isEmpty) {
      throw Exception('Invalid pack archive: empty manifest');
    }

    final basePackId =
        manifest['packId'] as String? ?? manifest['pack_id'] as String?;
    final packId = remotePackOverride?.packId ?? basePackId;
    
    if (packId == null || packId.trim().isEmpty) {
      throw Exception('Invalid pack archive: packId missing');
    }

    print('[PACK] INSTALL_START=$packId');
    print('[PACK] EXTRACTION_COMPLETE=$packId');

    // Version might be an int (1) or string ("1.0.0")
    int incomingVersion = 1;
    final rawVersion = manifest['version'];
    if (rawVersion is int) {
      incomingVersion = rawVersion;
    } else if (rawVersion is String) {
      final parts = rawVersion.split('.');
      if (parts.isNotEmpty) {
        incomingVersion = int.tryParse(parts.first) ?? 1;
      }
    }

    final existingPack = await _repository.getPackById(packId);
    if (!allowReplaceSameOrOlder &&
        existingPack != null &&
        incomingVersion <= existingPack.version) {
      throw PackVersionConflictException(
        packId: packId,
        incomingVersion: incomingVersion,
        installedVersion: existingPack.version,
      );
    }

    var contentDir = Directory(p.join(packRootDir.path, 'content'));
    if (!await contentDir.exists()) {
      contentDir = packRootDir;
    }

    await _reuseExistingSourcePdfIfAvailable(
      existingPack: existingPack,
      targetChapterRootPath: contentDir.path,
      onProgress: onProgress,
    );

    onProgress?.call('Finalizing Chapter...');
    final pdfResults = await _installChapterPdfIfPossible(
      manifest: manifest,
      chapterRootPath: contentDir.path,
      packId: packId,
      onProgress: onProgress,
    );
    final failedPdfResults = pdfResults.where(
      (result) => !result.installSuccess,
    );
    if (failedPdfResults.isNotEmpty) {
      // PDF is optional — log a warning but do NOT block the pack import.
      // The pack content (quizzes, flashcards, concepts, etc.) is still valid
      // and should be usable without a source PDF.
      print(
        '[PACK] PDF_WARNING packId=$packId: '
        '${failedPdfResults.map((r) => r.failureReason).join('; ')}',
      );
    }

    final packItems = <ContentPackItem>[];
    var totalSize = 0;

    int contentJsonCount = 0;
    int flashcardCount = 0;
    int quizCount = 0;
    int summaryCount = 0;
    int glossaryCount = 0;

    for (var i = 0; i < items.length; i++) {
      final item = items[i] as Map<String, dynamic>;
      final relative = _normalizeRelative(
        item['relativePath'] as String? ?? '',
      );
      if (relative.isEmpty) {
        continue;
      }
      final absolute = p.join(contentDir.path, relative);
      final file = File(absolute);
      if (!await file.exists()) {
        continue;
      }
      final stat = await file.stat();
      totalSize += stat.size;
      packItems.add(
        ContentPackItem(
          packId: packId,
          kind: (item['kind'] as String? ?? 'other').toLowerCase(),
          title: item['title'] as String? ?? p.basename(relative),
          relativePath: relative,
          absolutePath: absolute,
          grade: remotePackOverride?.gradeMin ?? item['grade'] as int?,
          subject: remotePackOverride?.subject ?? item['subject'] as String?,
          medium: remotePackOverride?.medium ?? item['medium'] as String?,
          chapterId: remotePackOverride?.chapter ?? item['chapterId'] as String?,
          languageCode: item['languageCode'] as String?,
          orderIndex: item['orderIndex'] as int? ?? i,
          sizeBytes: stat.size,
          metadataJson: item['metadataJson'] as String?,
        ),
      );

      final kindLower = (item['kind'] as String? ?? 'other').toLowerCase();
      if (kindLower == 'json' || kindLower == 'content_json')
        contentJsonCount++;
      if (kindLower == 'flashcard') flashcardCount++;
      if (kindLower == 'quiz') quizCount++;
      if (kindLower == 'summary') summaryCount++;
      if (kindLower == 'glossary') glossaryCount++;
    }

    final sourcePdf = File(p.join(contentDir.path, 'source.pdf'));
    final alreadyIndexedSourcePdf = packItems.any(
      (item) => _normalizeRelative(item.relativePath) == 'source.pdf',
    );
    if (await sourcePdf.exists() && !alreadyIndexedSourcePdf) {
      final stat = await sourcePdf.stat();
      if (stat.size > 0) {
        totalSize += stat.size;
        packItems.add(
          ContentPackItem(
            packId: packId,
            kind: 'pdf',
            title: 'Source PDF',
            relativePath: 'source.pdf',
            absolutePath: sourcePdf.path,
            grade: remotePackOverride?.gradeMin ?? _readGrade(manifest),
            subject: remotePackOverride?.subject ?? manifest['subject']?.toString(),
            medium: remotePackOverride?.medium ?? manifest['medium']?.toString(),
            chapterId: packId,
            languageCode: _readLanguage(manifest),
            orderIndex: packItems.length,
            sizeBytes: stat.size,
            metadataJson: jsonEncode({
              'pdfDownloaded': pdfResults.any((r) => r.pdfDownloaded),
              'pdfReused': pdfResults.any((r) => r.pdfReused),
            }),
          ),
        );
      }
    }

    print('[PACK] CONTENT_ROWS=$contentJsonCount');
    print('[PACK] FLASHCARDS=$flashcardCount');
    print('[PACK] QUIZZES=$quizCount');
    print('[PACK] SUMMARIES=$summaryCount');
    print('[PACK] GLOSSARY=$glossaryCount');

    final installedAt = DateTime.now().millisecondsSinceEpoch;
    final hash = sha256
        .convert(
          utf8.encode('$packId:$installedAt:$totalSize:${packItems.length}'),
        )
        .toString();

    final packManifest = ContentPackManifest(
      packId: packId,
      title: remotePackOverride?.title ?? manifest['title'] as String? ?? packId,
      medium: remotePackOverride?.medium ?? manifest['medium'] as String? ?? 'Mixed',
      subject: remotePackOverride?.subject ?? manifest['subject'] as String? ?? 'All Subjects',
      gradeMin: remotePackOverride?.gradeMin ?? _readGrade(manifest) ?? 1,
      gradeMax: remotePackOverride?.gradeMax ?? _readGrade(manifest) ?? 12,
      version: incomingVersion,
      manifestPath: manifestFile.path,
      rootPath: contentDir.path,
      contentHash: hash,
      contentSizeBytes: totalSize,
      installedAt: installedAt,
      status: 'installed',
    );

    await _repository.upsertPack(manifest: packManifest, items: packItems);

    final packsAfter =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM material_packs'),
        ) ??
        0;
    final itemsAfter =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM material_pack_items'),
        ) ??
        0;
    final ragAfter =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM rag_chunks'),
        ) ??
        0;
    final ftsAfter = ftsTableExists > 0
        ? (Sqflite.firstIntValue(
                await db.rawQuery('SELECT COUNT(*) FROM rag_chunks_fts'),
              ) ??
              0)
        : 0;

    print('PACKS_AFTER=$packsAfter');
    print('ITEMS_AFTER=$itemsAfter');
    print('RAG_AFTER=$ragAfter');
    print('FTS_AFTER=$ftsAfter');

    final sqliteRowsAdded = (itemsAfter - (itemsBefore ?? 0));
    final ragRowsAdded = (ragAfter - (ragBefore ?? 0));
    final ftsRowsAdded = (ftsAfter - (ftsBefore ?? 0));

    print('[PACK] SQLITE_ROWS_ADDED=$sqliteRowsAdded');
    print('[PACK] RAG_ROWS_ADDED=$ragRowsAdded');
    print('[PACK] FTS_ROWS_ADDED=$ftsRowsAdded');

    return PackArchiveImportResult(
      packId: packId,
      itemCount: packItems.length,
      installedRoot: contentDir.path,
      pdfResults: pdfResults,
    );
  }

  Future<List<PdfInstallResult>> _installChapterPdfIfPossible({
    required Map<String, dynamic> manifest,
    required String chapterRootPath,
    required String packId,
    void Function(String message)? onProgress,
  }) async {
    final artifactCounts = manifest['artifact_counts'];
    final isSimulationPack =
        packId == 'phet_simulations_v1' ||
        (artifactCounts is Map &&
            (artifactCounts['simulations'] as num? ?? 0) > 0);
    if (isSimulationPack) {
      print('[PDF_INSTALL] SKIPPED packId=$packId reason=simulation-pack');
      return const [];
    }

    final grade = _readGrade(manifest);
    final rawSubject = manifest['subject']?.toString().trim() ?? '';
    // Normalize subject for PDF resolve (backend uses "maths" not "mathematics")
    final subject = rawSubject.toLowerCase() == 'mathematics' ? 'maths' : rawSubject;
    final chapter = manifest['chapter']?.toString().trim().isNotEmpty == true
        ? manifest['chapter'].toString().trim()
        : manifest['title']?.toString().trim() ?? '';
    if (grade == null || subject.isEmpty || chapter.isEmpty) {
      print('[PDF_INSTALL] SKIPPED packId=$packId reason=missing metadata');
      return const [];
    }

    onProgress?.call('Downloading PDF...');
    final result = await PdfInstallService().installChapterPdf(
      chapterRootPath: chapterRootPath,
      chapterId: packId,
      grade: grade,
      subject: subject,
      chapter: chapter,
      medium: manifest['medium']?.toString(),
      language: _readLanguage(manifest),
      onProgress: onProgress,
    );
    print('[PDF_INSTALL] REPORT=${jsonEncode(result.toJson())}');
    return [result];
  }

  Future<void> _reuseExistingSourcePdfIfAvailable({
    required ContentPackManifest? existingPack,
    required String targetChapterRootPath,
    void Function(String message)? onProgress,
  }) async {
    if (existingPack == null || existingPack.rootPath.trim().isEmpty) return;
    final previousPdf = File(p.join(existingPack.rootPath, 'source.pdf'));
    if (!await previousPdf.exists()) return;
    final previousStat = await previousPdf.stat();
    if (previousStat.size <= 0) return;

    final targetPdf = File(p.join(targetChapterRootPath, 'source.pdf'));
    if (await targetPdf.exists()) return;
    onProgress?.call('Saving PDF...');
    await targetPdf.parent.create(recursive: true);
    await previousPdf.copy(targetPdf.path);
  }

  int? _readGrade(Map<String, dynamic> manifest) {
    final candidates = [
      manifest['grade'],
      manifest['gradeMin'],
      manifest['grade_min'],
    ];
    for (final candidate in candidates) {
      if (candidate is int) return candidate;
      if (candidate is num) return candidate.toInt();
      if (candidate is String) {
        final match = RegExp(r'\d+').firstMatch(candidate);
        if (match != null) return int.tryParse(match.group(0)!);
      }
    }
    return null;
  }

  String? _readLanguage(Map<String, dynamic> manifest) {
    final candidates = [
      manifest['language'],
      manifest['languageCode'],
      manifest['language_code'],
      manifest['medium'],
    ];
    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  Map<String, dynamic> _buildArchiveManifest(
    ContentPackManifest manifest,
    List<ContentPackItem> items,
  ) {
    return <String, dynamic>{
      'manifest': <String, dynamic>{
        'packId': manifest.packId,
        'title': manifest.title,
        'medium': manifest.medium,
        'subject': manifest.subject,
        'gradeMin': manifest.gradeMin,
        'gradeMax': manifest.gradeMax,
        'version': manifest.version,
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
      },
      'items': items
          .map(
            (item) => <String, dynamic>{
              'kind': item.kind,
              'title': item.title,
              'relativePath': _normalizeRelative(item.relativePath),
              'grade': item.grade,
              'subject': item.subject,
              'medium': item.medium,
              'chapterId': item.chapterId,
              'languageCode': item.languageCode,
              'orderIndex': item.orderIndex,
              'metadataJson': item.metadataJson,
            },
          )
          .toList(),
    };
  }

  String _normalizeRelative(String value) {
    var normalized = value.replaceAll('\\\\', '/').replaceAll('\\', '/');
    normalized = normalized.replaceAll(RegExp(r'^/+'), '');
    return normalized;
  }
}
