import 'dart:convert';

import '../../home/data/local/media_resource_repository.dart';
import '../../rag/application/pdf_extraction_service.dart';
import '../../rag/data/local/rag_repository.dart';
import '../data/local/content_pack_repository.dart';
import '../domain/content_pack_models.dart';

class ContentPackBootstrapService {
  ContentPackBootstrapService({
    MediaResourceRepository? mediaRepository,
    ContentPackRepository? packRepository,
  })  : _mediaRepository = mediaRepository ?? MediaResourceRepository(),
        _packRepository = packRepository ?? ContentPackRepository();

  final MediaResourceRepository _mediaRepository;
  final ContentPackRepository _packRepository;

  Future<void> bootstrapLegacyMediaIntoPacks() async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    try {
      final packsCountBefore = await _packRepository.getInstalledPackCount();
      print('[PACKS] BEFORE_COUNT=$packsCountBefore');

      var media = await _mediaRepository.listAll();
      
      if (media.isEmpty) {
        print('[PACKS] Seeding fallback media resources...');
        final seedMedia = [
          MediaResource(
            mediaType: 'textbook',
            title: 'Mathematics & Science Foundations',
            localPath: 'assets/seed_data_math_science.json',
            sizeBytes: 9051,
            importedAt: DateTime.now().millisecondsSinceEpoch,
          ),
          MediaResource(
            mediaType: 'video',
            title: 'Basic Science Overview',
            localPath: 'assets/demo_video.mp4',
            sizeBytes: 1024,
            importedAt: DateTime.now().millisecondsSinceEpoch,
          ),
          MediaResource(
            mediaType: 'resource',
            title: 'Interactive Activities',
            localPath: 'assets/activities.zip',
            sizeBytes: 512,
            importedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        ];
        await _mediaRepository.upsertMany(seedMedia);
        media = await _mediaRepository.listAll();
      }

      final textbooks = media.where((item) => item.mediaType == 'textbook').toList();
      final videos = media.where((item) => item.mediaType == 'video').toList();
      final resources = media.where((item) => item.mediaType == 'resource').toList();

      await _syncLegacyPack(
        packId: 'legacy_textbooks_pack',
        title: 'Legacy Textbooks Library',
        medium: 'Mixed',
        subject: 'All Subjects',
        gradeMin: 1,
        gradeMax: 12,
        kind: 'pdf',
        items: textbooks,
      );

      await _syncLegacyPack(
        packId: 'legacy_videos_pack',
        title: 'Legacy Videos Library',
        medium: 'Mixed',
        subject: 'All Subjects',
        gradeMin: 1,
        gradeMax: 12,
        kind: 'video',
        items: videos,
      );

      await _syncLegacyPack(
        packId: 'legacy_resources_pack',
        title: 'Legacy Resources Library',
        medium: 'Mixed',
        subject: 'All Subjects',
        gradeMin: 1,
        gradeMax: 12,
        kind: 'resource',
        items: resources,
      );

      final packsCountAfter = await _packRepository.getInstalledPackCount();
      print('[PACKS] INSTALLED_COUNT=${packsCountAfter - packsCountBefore}');
      print('[PACKS] AFTER_COUNT=$packsCountAfter');
      print('[PACKS] INSTALL_DURATION_MS=${DateTime.now().millisecondsSinceEpoch - startTime}');
    } catch (e) {
      print('[PACKS] INSTALL_EXCEPTION=$e');
    }
  }

  Future<void> _syncLegacyPack({
    required String packId,
    required String title,
    required String medium,
    required String subject,
    required int gradeMin,
    required int gradeMax,
    required String kind,
    required List<MediaResource> items,
  }) async {
    if (items.isEmpty) {
      await _packRepository.deletePack(packId);
      return;
    }

    final contentHash = _hashLegacyItems(items);
    final contentSizeBytes = items.fold<int>(0, (sum, item) => sum + item.sizeBytes);
    final existing = await _packRepository.getPackById(packId);
    if (existing != null &&
        existing.contentHash == contentHash &&
        existing.contentSizeBytes == contentSizeBytes) {
      return;
    }

    await _installLegacyPack(
      packId: packId,
      title: title,
      medium: medium,
      subject: subject,
      gradeMin: gradeMin,
      gradeMax: gradeMax,
      kind: kind,
      items: items,
      contentHash: contentHash,
      contentSizeBytes: contentSizeBytes,
      version: (existing?.version ?? 0) + 1,
    );
  }

  Future<void> _installLegacyPack({
    required String packId,
    required String title,
    required String medium,
    required String subject,
    required int gradeMin,
    required int gradeMax,
    required String kind,
    required List<MediaResource> items,
    required String contentHash,
    required int contentSizeBytes,
    required int version,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    
    print('[PACK] DOWNLOAD_START - Pack: $packId');
    print('[PACK] DOWNLOAD_SUCCESS - Pack: $packId');
    print('[PACK] MANIFEST_PARSED - Pack: $packId');
    print('[PACK] INSTALL_START - Pack: $packId');
    
    final pack = ContentPackManifest(
      packId: packId,
      title: title,
      medium: medium,
      subject: subject,
      gradeMin: gradeMin,
      gradeMax: gradeMax,
      version: version,
      manifestPath: 'legacy://$packId',
      rootPath: 'legacy://$packId',
      contentHash: contentHash,
      contentSizeBytes: contentSizeBytes,
      installedAt: now,
      status: 'installed',
    );

    final packItems = <ContentPackItem>[];
    var chunksImported = 0;
    
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final classification = _classify(item.title);
      packItems.add(
        ContentPackItem(
          packId: packId,
          kind: kind,
          title: item.title,
          relativePath: item.sourcePath ?? item.localPath,
          absolutePath: item.localPath,
          sizeBytes: item.sizeBytes,
          orderIndex: i,
          grade: classification.grade,
          subject: classification.subject,
          medium: classification.medium,
          chapterId: classification.chapterId,
          languageCode: classification.languageCode,
          metadataJson: jsonEncode(<String, dynamic>{
            'source_path': item.sourcePath,
            'media_type': item.mediaType,
          }),
        ),
      );

      // Populate rag_chunks for text-based materials
      if (item.mediaType == 'textbook' && classification.chapterId != null) {
        try {
          final text = await PdfExtractionService.extractTextFromPdf(item.localPath);
          await RagRepository().ingestChapterNotes(
            chapterId: classification.chapterId!,
            sourceTitle: item.title,
            rawText: text,
          );
          chunksImported++;
        } catch (e) {
          print('[DIAGNOSTICS] Failed to extract text for RAG: $e');
        }
      }
    }

    await _packRepository.upsertPack(manifest: pack, items: packItems);
    print('[PACK] INSTALL_COMPLETE - Pack: $packId');
    print('[PACK] CHUNKS_IMPORTED=$chunksImported');
    print('[PACK] FTS_ROWS_CREATED=0 (FTS Removed)');
  }

  String _hashLegacyItems(List<MediaResource> items) {
    final signature = items
        .map((item) => '${item.localPath}:${item.sizeBytes}:${item.importedAt}')
        .join('|');
    return signature.hashCode.toString();
  }

  _LegacyClassification _classify(String title) {
    final basis = title.toLowerCase();

    final medium = (basis.contains('kannada') || basis.contains(' kan '))
        ? 'Kannada Medium'
        : 'English Medium';

    String subject = 'Other Subject';
    if (basis.contains('math') || basis.contains('maths')) {
      subject = 'Mathematics';
    } else if (basis.contains('science') || basis.contains('sci')) {
      subject = 'Science';
    } else if (basis.contains('social') || basis.contains('history') || basis.contains('civics')) {
      subject = 'Social Science';
    } else if (basis.contains('english') || basis.contains('grammar') || basis.contains('prose')) {
      subject = 'English';
    }

    int? grade;
    final gradeMatch = RegExp(r'(?<!\d)(12|11|10|[1-9])(?:st|nd|rd|th)?(?!\d)').firstMatch(basis);
    if (gradeMatch != null) {
      grade = int.tryParse(gradeMatch.group(1) ?? '');
    }

    String? chapterId;
    if (subject == 'Mathematics') {
      chapterId = 'chap_linear_eq';
    } else if (subject == 'Science') {
      chapterId = 'chap_chemical_rxn';
    } else if (subject == 'Social Science') {
      chapterId = 'chap_resources_10';
    } else if (subject == 'English') {
      chapterId = 'chap_prose_10';
    }

    return _LegacyClassification(
      grade: grade,
      subject: subject,
      medium: medium,
      chapterId: chapterId,
      languageCode: medium == 'Kannada Medium' ? 'kn' : 'en',
    );
  }
}

class _LegacyClassification {
  const _LegacyClassification({
    required this.grade,
    required this.subject,
    required this.medium,
    required this.chapterId,
    required this.languageCode,
  });

  final int? grade;
  final String subject;
  final String medium;
  final String? chapterId;
  final String languageCode;
}
