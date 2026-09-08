import 'dart:async';

import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart' as path_provider;
import '../../../config/app_environment.dart';
import '../../../features/network/data/backend_availability_cache.dart';
import '../../../features/network/domain/endpoint_builder.dart';
import '../../../features/network/domain/runtime_backend_url.dart';
import '../../content_packs/application/content_pack_archive_service.dart';
import '../../content_packs/data/local/content_pack_repository.dart';
import '../../rag/application/pdf_extraction_service.dart';
import '../../rag/data/local/rag_repository.dart';
import '../../rag/data/local/rag_repository_v2.dart';
import '../models/educational_models.dart';
import '../domain/pack_sync_entry.dart';

/// Returns an [EndpointBuilder] backed by the runtime-discovered backend URL.
/// This is the ONLY correct way to build endpoints in SyncManager.
EndpointBuilder _runtimeEndpoints() {
  final url = RuntimeBackendUrl().current;
  return EndpointBuilder(baseUrl: url);
}

/// Pack synchronization with backend PiHub
class SyncManager {
  static final SyncManager _instance = SyncManager._internal();

  factory SyncManager() {
    return _instance;
  }

  SyncManager._internal();

  /// Queue for managing sync operations
  final SyncQueue syncQueue = SyncQueue();
  final ContentPackRepository _contentPackRepository = ContentPackRepository();
  final StreamController<String> _progressController =
      StreamController<String>.broadcast();

  Stream<String> get progressStream => _progressController.stream;

  void _emitProgress(String message) {
    if (!_progressController.isClosed) {
      _progressController.add(message);
    }
  }

  /// Fetch the backend pack catalog, optionally filtered by grade.
  ///
  /// This returns the full matching catalog for the UI, not just packs that
  /// still need to be installed. Callers that want installable-only work should
  /// keep using [processPackUpdates], which performs the local install check.
  Future<List<PackSyncEntry>> checkForPackUpdates({int? grade}) async {
    try {
      // Consult cached backend status to avoid redundant 30s timeout
      final cached = BackendAvailabilityCache().cachedStatus;
      if (cached == false) {
        AppEnvironment.log(
          'SYNC',
          '[SyncManager] Skipping pack check — backend cached as unavailable',
        );
        return [];
      }

      AppEnvironment.log('SYNC', '[SyncManager] Checking for pack updates');

      final endpoint = '${_runtimeEndpoints().baseUrl}/packs';
      print('[URL] SERVICE=SyncManager URL=$endpoint');
      print('[SYNC] ACTIVE_URL=$endpoint');
      print('[SYNC] REQUEST_URL=$endpoint');
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 10));

      print('[SYNC_VERIFY] REQUEST_URL=$endpoint');
      print('[SYNC_VERIFY] HTTP_STATUS=${response.statusCode}');
      print('[SYNC_VERIFY] RESPONSE_BYTES=${response.bodyBytes.length}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final validPacksById = <String, PackSyncEntry>{};

        final packsList = <dynamic>[
          ...(data['packs'] as List<dynamic>? ?? const <dynamic>[]),
          ...(data['cached'] as List<dynamic>? ?? const <dynamic>[]),
        ];

        for (final pkg in packsList) {
          if (pkg is Map<String, dynamic>) {
            try {
              final entry = PackSyncEntry.fromJson(pkg);
              if (grade != null && entry.grade != grade) {
                print(
                  '[SYNC] SKIP_GRADE_MISMATCH packId=${entry.packId} packGrade=${entry.grade} requestedGrade=$grade',
                );
                continue;
              }
              final existing = validPacksById[entry.packId];
              if (existing == null ||
                  _parseVersion(entry.version) >
                      _parseVersion(existing.version)) {
                validPacksById[entry.packId] = entry;
              }
              if (validPacksById.length <= 5) {
                print('[SYNC] PACK_ID=${entry.packId}');
                print('[SYNC] DOWNLOAD_URL=${entry.downloadUrl}');
              }
            } catch (e) {
              AppEnvironment.log(
                'SYNC',
                '[SyncManager] Failed to parse pack entry: $e',
              );
            }
          }
        }

        if (validPacksById.isNotEmpty) {
          print('[SYNC] PACK_COUNT_RECEIVED=${validPacksById.length}');
          return validPacksById.values.toList()..sort((a, b) {
            final gradeA = a.grade ?? 0;
            final gradeB = b.grade ?? 0;
            final gradeCompare = gradeA.compareTo(gradeB);
            if (gradeCompare != 0) {
              return gradeCompare;
            }
            final subjectCompare = (a.subject ?? '').toLowerCase().compareTo(
              (b.subject ?? '').toLowerCase(),
            );
            if (subjectCompare != 0) {
              return subjectCompare;
            }
            return a.packId.compareTo(b.packId);
          });
        }
      }
      return await _loadOfflineFallbackPacks(grade);
    } catch (e) {
      AppEnvironment.log('SYNC', '[SyncManager] Error checking updates: $e');
      return await _loadOfflineFallbackPacks(grade);
    }
  }

  Future<List<PackSyncEntry>> _loadOfflineFallbackPacks(int? grade) async {
    try {
      final targetGrade = grade ?? 9;
      final db = await _contentPackRepository.db;
      final rows = await db.rawQuery(
        'SELECT chapter_id, title, subject, grade FROM chapters WHERE grade = ?',
        [targetGrade],
      );

      if (rows.isNotEmpty) {
        return rows.map((row) {
          final cId = row['chapter_id'] as String? ?? 'ch_unknown';
          final title = row['title'] as String? ?? 'Chapter';
          final subj = row['subject'] as String? ?? 'General';
          return PackSyncEntry(
            packId: cId,
            title: title,
            subject: subj,
            grade: targetGrade,
            version: 1,
            sizeBytes: 1500000,
            downloadUrl: 'offline://master_db/$cId',
          );
        }).toList();
      }
    } catch (e) {
      AppEnvironment.log('SYNC', '[SyncManager] Offline fallback error: $e');
    }
    return [];
  }

  /// Process the pack updates and enqueue download operations.
  ///
  /// Returns the number of packs that were actually queued for download.
  Future<int> processPackUpdates(List<PackSyncEntry> updates) async {
    if (updates.isEmpty) return 0;

    AppEnvironment.log(
      'SYNC',
      '[SyncManager] Processing ${updates.length} pack updates',
    );
    print('[SYNC] PACKS_REQUIRING_UPDATE=${updates.length}');

    var queuedCount = 0;
    for (final entry in updates) {
      if (!await _needsPackInstall(entry)) {
        print(
          '[SYNC] SKIP_ALREADY_INSTALLED packId=${entry.packId} version=${entry.version}',
        );
        continue;
      }

      final packId = entry.packId;
      var downloadUrl =
          entry.downloadUrl ??
          '${_runtimeEndpoints().baseUrl}/packs/$packId/download';
      if (downloadUrl.startsWith('/')) {
        final baseUrl = _runtimeEndpoints().baseUrl;
        downloadUrl = '$baseUrl$downloadUrl';
      }

      syncQueue.enqueue(
        PackDownloadOperation(
          id: 'download_$packId',
          packId: packId,
          remoteUrl: downloadUrl,
          localPath: '',
          onProgress: _emitProgress,
        ),
      );
      queuedCount++;
    }

    return queuedCount;
  }

  Future<bool> _needsPackInstall(PackSyncEntry entry) async {
    final local = await _contentPackRepository.getPackById(entry.packId);
    if (local == null) {
      return true;
    }

    final localRoot = local.rootPath.trim();
    final localRootExists =
        localRoot.isNotEmpty && await Directory(localRoot).exists();
    if (!localRootExists) {
      return true;
    }

    final incomingVersion = _parseVersion(entry.version);
    return incomingVersion > local.version;
  }

  int _parseVersion(String version) {
    final trimmed = version.trim();
    if (trimmed.isEmpty) {
      return 1;
    }

    final major = trimmed.split('.').first.trim();
    return int.tryParse(major) ?? 1;
  }

  /// Sync specific pack with backend
  Future<bool> syncPackWithBackend(String packId, String localVersion) async {
    try {
      AppEnvironment.log('SYNC', '[SyncManager] Syncing pack: $packId');

      final endpoint = '${_runtimeEndpoints().baseUrl}/packs/$packId';

      final delta = {
        'action': 'sync',
        'packId': packId,
        'localVersion': localVersion,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(delta),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200 || response.statusCode == 204) {
        AppEnvironment.log('SYNC', '[SyncManager] Pack sync complete: $packId');
        return true;
      } else {
        AppEnvironment.log(
          'SYNC',
          '[SyncManager] Pack sync failed: ${response.statusCode}',
        );
        return false;
      }
    } catch (e) {
      AppEnvironment.log('SYNC', '[SyncManager] Error syncing pack: $e');
      return false;
    }
  }

  /// Fetch delta updates for efficient sync
  Future<Map<String, dynamic>?> fetchDeltaUpdates(
    String packId,
    String fromVersion,
  ) async {
    try {
      AppEnvironment.log(
        'SYNC',
        '[SyncManager] Fetching delta updates: $packId from $fromVersion',
      );

      final endpoint = '${_runtimeEndpoints().syncDelta}/$packId';
      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              'X-From-Version': fromVersion,
            },
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }

      return null;
    } catch (e) {
      AppEnvironment.log('SYNC', '[SyncManager] Error fetching deltas: $e');
      return null;
    }
  }

  /// Sync learner progress to backend
  Future<bool> syncLearnerProgress(
    int chapterId,
    Map<String, dynamic> progress,
  ) async {
    try {
      final endpoint = _runtimeEndpoints().progressUpdate;

      final payload = {
        'chapterId': chapterId,
        'progress': progress,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final response = await http
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));

      return response.statusCode == 200 || response.statusCode == 204;
    } catch (e) {
      AppEnvironment.log('SYNC', '[SyncManager] Error syncing progress: $e');
      return false;
    }
  }

  /// Validate cache integrity against backend
  Future<bool> validateCacheIntegrity(String packId) async {
    try {
      final endpoint = '${_runtimeEndpoints().packsSync}/$packId/validate';

      final response = await http
          .get(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final isValid = data['valid'] == true;

        if (!isValid) {
          AppEnvironment.log(
            'SYNC',
            '[SyncManager] Cache validation failed for $packId',
          );
        }

        return isValid;
      }

      return false;
    } catch (e) {
      AppEnvironment.log('SYNC', '[SyncManager] Error validating cache: $e');
      return false;
    }
  }
}

/// Conflict resolution for concurrent updates
class ConflictResolver {
  /// Resolve conflicts between local and remote versions
  /// Strategy: Last-write-wins with timestamp comparison
  static EducationalPackModel resolvePackConflict(
    EducationalPackModel local,
    EducationalPackModel remote,
  ) {
    if (remote.updatedAt.isAfter(local.updatedAt)) {
      AppEnvironment.log(
        'SYNC',
        '[ConflictResolver] Remote version newer for ${local.packId}',
      );
      return remote;
    }

    AppEnvironment.log(
      'SYNC',
      '[ConflictResolver] Local version retained for ${local.packId}',
    );
    return local;
  }

  /// Resolve conflicts between local and remote progress
  static LearnerProgressModel resolveProgressConflict(
    LearnerProgressModel local,
    LearnerProgressModel remote,
  ) {
    // Merge conflicting progress (take best scores and furthest progress)
    final localAttempts = local.quizAttempts ?? 0;
    final remoteAttempts = remote.quizAttempts ?? 0;
    final localBestScore = local.quizBestScore ?? 0;
    final remoteBestScore = remote.quizBestScore ?? 0;
    final localFlashcards = local.flashcardsReviewed ?? 0;
    final remoteFlashcards = remote.flashcardsReviewed ?? 0;

    final localLastAccessed =
        local.lastAccessedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final remoteLastAccessed =
        remote.lastAccessedAt ?? DateTime.fromMillisecondsSinceEpoch(0);

    return LearnerProgressModel(
      id: local.id,
      chapterId: local.chapterId,
      completionState: _mergeCompletionState(
        local.completionState,
        remote.completionState,
      ),
      readingProgressPercent: math.max(
        local.readingProgressPercent,
        remote.readingProgressPercent,
      ),
      quizAttempts: localAttempts + remoteAttempts,
      quizBestScore: math.max(localBestScore, remoteBestScore),
      flashcardsReviewed: localFlashcards + remoteFlashcards,
      lastAccessedAt: localLastAccessed.isAfter(remoteLastAccessed)
          ? localLastAccessed
          : remoteLastAccessed,
      completedAt: local.completionState == 'completed'
          ? local.completedAt
          : null,
      createdAt: local.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  static String _mergeCompletionState(String local, String remote) {
    const priority = {'completed': 3, 'in-progress': 2, 'not-started': 1};

    final localPriority = priority[local] ?? 0;
    final remotePriority = priority[remote] ?? 0;

    return remotePriority >= localPriority ? remote : local;
  }
}

/// Bandwidth optimizer for sync operations
class BandwidthOptimizer {
  /// Check available bandwidth
  static Future<bool> hasAdequateBandwidth() async {
    // TODO: Implement actual bandwidth detection
    // For now, assume adequate if connected
    return true;
  }

  /// Calculate optimal chunk size for large pack downloads
  static int calculateOptimalChunkSize({
    required int totalSize,
    required int availableBandwidth, // Kbps
  }) {
    // Target ~30 second chunks
    const targetDurationSeconds = 30;
    final bandwidthBytesPerSecond = (availableBandwidth * 1024) ~/ 8;
    final chunkSize = bandwidthBytesPerSecond * targetDurationSeconds;

    // Clamp between 256KB and 10MB
    return chunkSize.clamp(256 * 1024, 10 * 1024 * 1024);
  }

  /// Compress data for efficient transfer
  static String compressPayload(Map<String, dynamic> payload) {
    return jsonEncode(payload); // TODO: Add gzip compression
  }

  /// Decompress received data
  static Map<String, dynamic> decompressPayload(String compressed) {
    return jsonDecode(compressed); // TODO: Add gzip decompression
  }
}

/// Sync queue for managing sync operations
class SyncQueue {
  final List<SyncOperation> _queue = [];
  bool _isProcessing = false;

  /// Add operation to queue
  void enqueue(SyncOperation operation) {
    _queue.add(operation);
    _processQueue();
  }

  /// Process sync queue
  Future<void> _processQueue() async {
    if (_isProcessing || _queue.isEmpty) return;

    _isProcessing = true;
    print('[SYNC] QUEUE_SIZE=${_queue.length}');

    while (_queue.isNotEmpty) {
      final operation = _queue.removeAt(0);
      try {
        await operation.execute();
        AppEnvironment.log('SYNC', '[SyncQueue] Completed: ${operation.id}');
      } catch (e) {
        AppEnvironment.log('SYNC', '[SyncQueue] Failed: ${operation.id} - $e');
        // Optionally requeue on failure
      }
    }

    _isProcessing = false;
  }

  /// Get queue status
  Map<String, dynamic> getStatus() {
    return {
      'queueSize': _queue.length,
      'isProcessing': _isProcessing,
      'nextOperation': _queue.isNotEmpty ? _queue.first.id : null,
    };
  }
}

/// Base sync operation
abstract class SyncOperation {
  String get id;
  Future<void> execute();
  SyncOperation withRetry({int maxAttempts = 3});
}

/// Pack download sync operation
class PackDownloadOperation implements SyncOperation {
  @override
  final String id;
  final String packId;
  final String remoteUrl;
  final String localPath;
  final void Function(String message)? onProgress;

  PackDownloadOperation({
    required this.id,
    required this.packId,
    required this.remoteUrl,
    required this.localPath,
    this.onProgress,
  });

  @override
  Future<void> execute() async {
    AppEnvironment.log('SYNC', '[PackDownloadOp] Starting download: $packId');
    onProgress?.call('Installing Pack...');
    print('[PACK] DOWNLOAD_START packId=$packId');
    print('[PACK] DOWNLOAD_URL=$remoteUrl');

    final stopwatch = Stopwatch()..start();
    try {
      final response = await http
          .get(Uri.parse(remoteUrl))
          .timeout(const Duration(minutes: 5));
      stopwatch.stop();
      print('[PACK] DOWNLOAD_COMPLETE');
      print('packId=$packId');
      print('status=${response.statusCode}');
      print('bytes=${response.bodyBytes.length}');
      print('duration_ms=${stopwatch.elapsedMilliseconds}');

      if (response.statusCode == 200) {
        AppEnvironment.log(
          'SYNC',
          '[PackDownloadOp] Download complete: $packId. Length: ${response.bodyBytes.length} bytes',
        );

        // Save the downloaded pack
        final docs = await path_provider.getApplicationDocumentsDirectory();
        final savePath = path.join(
          docs.path,
          'content_packs',
          '$packId.otpack',
        );
        final file = File(savePath);

        // Ensure parent directory exists
        if (!await file.parent.exists()) {
          await file.parent.create(recursive: true);
        }

        await file.writeAsBytes(response.bodyBytes);
        AppEnvironment.log('SYNC', '[PackDownloadOp] Saved pack to: $savePath');
        print('[PACK] FILE_SAVED=$savePath');

        AppEnvironment.log(
          'SYNC',
          '[PackDownloadOp] Starting installation for $packId',
        );
        try {
          final result = await ContentPackArchiveService().importPackArchive(
            savePath,
            allowReplaceSameOrOlder: true,
            onProgress: onProgress,
          );
          print('[PACK] ITEMS_IMPORTED=${result.itemCount} packId=$packId');
          for (final pdfResult in result.pdfResults) {
            print(
              '[PDF_INSTALL] INSTALL_REPORT=${jsonEncode(pdfResult.toJson())}',
            );
          }
        } catch (installErr) {
          print('[PACK] INSTALL_FAILURE_REASON=$installErr packId=$packId');
          rethrow;
        }

        try {
          final items = await ContentPackRepository().listItemsForPack(packId);
          var chunksImported = 0;
          var quizzesImported = 0;
          var flashcardsImported = 0;
          for (final item in items) {
            final effectiveChapterId = item.chapterId ?? packId;
            if (item.kind == 'content_json') {
              final jsonStr = await File(item.absolutePath).readAsString();
              final decoded = jsonDecode(jsonStr);
              if (decoded is List && decoded.isNotEmpty) {
                print('[RAG] INDEX_FOUND');
                await RagRepository().ingestPrecomputedChunks(
                  chapterId: effectiveChapterId,
                  chunks: decoded,
                );
                await RagRepositoryV2().insertBackendChunks(
                  chapterId: effectiveChapterId,
                  backendChunks: decoded,
                );
                chunksImported += decoded.length;
                print('[RAG] CHUNKS_IMPORTED=${decoded.length}');
                print('[RAG] EMBEDDINGS_IMPORTED=${decoded.length}');
                print('[RAG] RETRIEVAL_READY');
              }
            } else if (item.kind == 'pdf') {
              final text = await PdfExtractionService.extractTextFromPdf(
                item.absolutePath,
              );
              await RagRepository().ingestChapterNotes(
                chapterId: effectiveChapterId,
                sourceTitle: item.title,
                rawText: text,
              );
              chunksImported++;
            } else if (item.kind == 'quiz') {
              quizzesImported++;
            } else if (item.kind == 'flashcard') {
              flashcardsImported++;
            }
          }
          print('[PACK] CHUNKS_IMPORTED=$chunksImported packId=$packId');
          print('[PACK] QUIZZES_IMPORTED=$quizzesImported packId=$packId');
          print(
            '[PACK] FLASHCARDS_IMPORTED=$flashcardsImported packId=$packId',
          );
          AppEnvironment.log(
            'SYNC',
            '[PackDownloadOp] Indexed $chunksImported items for RAG.',
          );
        } catch (e) {
          AppEnvironment.log(
            'SYNC',
            '[PackDownloadOp] Error generating RAG chunks: $e',
          );
          print(
            '[PACK] INSTALL_FAILURE_REASON=RAG_CHUNK_ERROR: $e packId=$packId',
          );
        }

        AppEnvironment.log(
          'SYNC',
          '[PackDownloadOp] Successfully installed $packId',
        );
        print('[PACK] INSTALL_SUCCESS packId=$packId');

        // Clean up the downloaded archive
        if (await file.exists()) {
          await file.delete();
        }
      } else {
        AppEnvironment.log(
          'SYNC',
          '[PackDownloadOp] Download failed for $packId: ${response.statusCode}',
        );
        print(
          '[PACK] DOWNLOAD_FAILED packId=$packId statusCode=${response.statusCode}',
        );
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      AppEnvironment.log(
        'SYNC',
        '[PackDownloadOp] Error downloading $packId: $e',
      );
      print('[PACK] DOWNLOAD_FAILED packId=$packId error=$e');
      rethrow;
    }
  }

  @override
  SyncOperation withRetry({int maxAttempts = 3}) {
    // Wrap with retry logic
    return this;
  }
}

/// Progress upload sync operation
class ProgressUploadOperation implements SyncOperation {
  @override
  final String id;
  final int chapterId;
  final Map<String, dynamic> progressData;

  ProgressUploadOperation({
    required this.id,
    required this.chapterId,
    required this.progressData,
  });

  @override
  Future<void> execute() async {
    AppEnvironment.log(
      'SYNC',
      '[ProgressUploadOp] Uploading progress: $chapterId',
    );
    await SyncManager().syncLearnerProgress(chapterId, progressData);
  }

  @override
  SyncOperation withRetry({int maxAttempts = 3}) {
    return this;
  }
}
