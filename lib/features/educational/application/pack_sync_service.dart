import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../../config/app_environment.dart';
import '../../../features/network/domain/endpoint_builder.dart';
import '../data/educational_repository.dart';
import '../models/educational_models.dart';
import 'pack_manager.dart';
import 'pack_installer.dart';

/// Synchronizes educational packs with the backend
/// 
/// Responsibilities:
/// - Check for available updates on backend
/// - Download new packs
/// - Update existing packs
/// - Handle sync failures and retries
/// - Track sync progress
class PackSyncService {
  final PackManager _packManager = PackManager();
  final EndpointBuilder _endpoints = EndpointBuilder.fromEnvironment();

  StreamController<SyncProgress>? _progressController;

  /// Stream of sync progress updates
  Stream<SyncProgress> get progressUpdates {
    _progressController ??= StreamController<SyncProgress>.broadcast();
    return _progressController!.stream;
  }

  /// Discover packs from both local storage and backend catalog
  Future<List<EducationalPackModel>> discoverPacks() async {
    try {
      AppEnvironment.log('SYNC', 'Starting pack discovery...');

      // Get local packs
      final localPacks = await _packManager.discoverAvailablePacks();
      
      // Register discovered packs
      for (final pack in localPacks) {
        final existing = await EducationalRepository.getPackByPackId(pack.packId);
        if (existing == null) {
          await _packManager.registerPack(pack);
          AppEnvironment.log('SYNC', 'Registered discovered pack: ${pack.packId}');
        }
      }

      // Try to fetch remote catalog from backend
      final remotePacks = await _fetchRemotePacks();
      
      AppEnvironment.log('SYNC', 'Pack discovery complete: ${localPacks.length} local, ${remotePacks.length} remote');
      
      return [...localPacks, ...remotePacks];
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error discovering packs: $e');
      return [];
    }
  }

  /// Fetch pack catalog from backend
  Future<List<EducationalPackModel>> _fetchRemotePacks() async {
    try {
      AppEnvironment.log('SYNC', 'Fetching remote pack catalog...');
      
      if (!AppEnvironment.enableBackend) {
        AppEnvironment.log('SYNC', 'Backend disabled, skipping remote fetch');
        return [];
      }

      final url = Uri.parse(_endpoints.packsCatalog);
      final response = await http.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> packsJson = data is Map ? (data['packs'] as List<dynamic>? ?? []) : (data as List<dynamic>);

        final remotePacks = <EducationalPackModel>[];
        for (final item in packsJson) {
          if (item is Map<String, dynamic>) {
            final packId = item['pack_id']?.toString() ?? item['id']?.toString() ?? '';
            if (packId.isNotEmpty) {
              remotePacks.add(
                EducationalPackModel(
                  packId: packId,
                  name: item['title']?.toString() ?? item['name']?.toString() ?? packId,
                  description: '${item['subject'] ?? 'General'} (Grade ${item['grade'] ?? 6}) • ${item['size_mb'] ?? 5.0} MB',
                  version: item['version']?.toString() ?? '1.0.0',
                  totalChapters: (item['total_chapters'] as num?)?.toInt() ?? 0,
                  localPath: item['download_url']?.toString() ?? '${_endpoints.baseUrl}/packs/$packId/download',
                  isOfflineAvailable: false,
                ),
              );
            }
          }
        }
        AppEnvironment.log('SYNC', 'Fetched ${remotePacks.length} remote packs from gateway catalog');
        return remotePacks;
      }
      return [];
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error fetching remote packs: $e');
      return [];
    }
  }

  /// Sync a specific pack
  /// 
  /// Downloads if not available, updates if newer version exists
  Future<bool> syncPack(String packId) async {
    try {
      AppEnvironment.log('SYNC', 'Syncing pack: $packId');
      
      final pack = await EducationalRepository.getPackByPackId(packId);
      if (pack == null) {
        AppEnvironment.log('SYNC', 'Pack not found: $packId');
        return false;
      }

      // Mark as pending
      await _packManager.queuePackForSync(packId);
      _emitProgress(packId, 0.0, 'Starting sync...');

      // Download if needed
      if (!pack.isOfflineAvailable) {
        final success = await _downloadPack(pack);
        if (!success) {
          AppEnvironment.log('SYNC', 'Failed to download pack: $packId');
          return false;
        }
      }

      // Mark as available offline
      await _packManager.markPackOfflineAvailable(packId);
      _emitProgress(packId, 1.0, 'Sync complete');

      AppEnvironment.log('SYNC', 'Pack synced successfully: $packId');
      return true;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error syncing pack: $e');
      return false;
    }
  }

  /// Sync all available packs
  Future<void> syncAllPacks() async {
    try {
      AppEnvironment.log('SYNC', 'Starting full pack sync...');
      
      final packs = await _packManager.getAllPacks();
      int successCount = 0;

      for (final pack in packs) {
        if (!pack.isOfflineAvailable) {
          final success = await syncPack(pack.packId);
          if (success) successCount++;
        }
      }

      AppEnvironment.log('SYNC', 'Full sync complete: $successCount/${packs.length} packs synced');
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error in full pack sync: $e');
    }
  }

  /// Sync packs for a specific grade
  Future<void> syncGradePacks(int gradeId) async {
    try {
      AppEnvironment.log('SYNC', 'Syncing packs for grade: $gradeId');
      
      final packs = await _packManager.getPacksForGrade(gradeId);
      
      for (final pack in packs) {
        if (!pack.isOfflineAvailable) {
          await syncPack(pack.packId);
        }
      }

      AppEnvironment.log('SYNC', 'Grade pack sync complete: $gradeId');
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error syncing grade packs: $e');
    }
  }

  /// Download a pack from backend
  Future<bool> _downloadPack(EducationalPackModel pack) async {
    try {
      AppEnvironment.log('SYNC', 'Downloading pack from gateway: ${pack.name}');

      if (!AppEnvironment.enableBackend) {
        return await _installPackFromLocal(pack);
      }

      final downloadUrl = pack.localPath.startsWith('http')
          ? pack.localPath
          : '${_endpoints.baseUrl}/packs/${pack.packId}/download';

      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await http.Client().send(request).timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        AppEnvironment.log('SYNC', 'HTTP download returned status ${response.statusCode}, falling back to local source');
        return await _installPackFromLocal(pack);
      }

      final tempDir = Directory.systemTemp;
      final tempZipFile = File('${tempDir.path}/${pack.packId}_download.zip');
      final sink = tempZipFile.openWrite();

      final contentLength = response.contentLength ?? 0;
      int downloadedBytes = 0;

      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          downloadedBytes += chunk.length;
          if (contentLength > 0) {
            final progress = (downloadedBytes / contentLength).clamp(0.0, 0.9);
            _emitProgress(pack.packId, progress, 'Downloading (${(progress * 100).toInt()}%)...');
            _packManager.updatePackProgress(pack.packId, progress: progress, downloadedChapters: 0);
          }
        },
        cancelOnError: true,
      ).asFuture();

      await sink.flush();
      await sink.close();

      AppEnvironment.log('SYNC', 'Downloaded ${pack.packId} (${downloadedBytes} bytes), extracting pack...');
      _emitProgress(pack.packId, 0.95, 'Extracting & verifying pack...');

      final installer = PackInstaller(
        packId: pack.packId,
        sourcePath: tempZipFile.path,
        targetPath: '${Directory.systemTemp.path}/installed_packs/${pack.packId}',
      );

      final success = await installer.install(
        onProgress: (progress) {
          _emitProgress(pack.packId, 0.95 + (progress * 0.05), 'Installing...');
        },
      );

      if (await tempZipFile.exists()) {
        await tempZipFile.delete();
      }

      return success;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error downloading pack via HTTP: $e, falling back to local source');
      return await _installPackFromLocal(pack);
    }
  }

  /// Install pack from local textbooks directory
  Future<bool> _installPackFromLocal(EducationalPackModel pack) async {
    try {
      // Find source directory in textbooks
      final sourcePath = '/home/akash/Desktop/IDP/TEXTBOOKS/${pack.name}';
      final sourceDir = Directory(sourcePath);

      if (!await sourceDir.exists()) {
        AppEnvironment.log('SYNC', 'Local pack directory not found: $sourcePath');
        return false;
      }

      // Create installer
      final installer = PackInstaller(
        packId: pack.packId,
        sourcePath: sourcePath,
        targetPath: pack.localPath,
      );

      // Install with progress tracking
      final success = await installer.install(
        onProgress: (progress) {
          _emitProgress(pack.packId, progress, 'Installing...');
          _packManager.updatePackProgress(pack.packId, progress: progress, downloadedChapters: 0);
        },
      );

      if (success) {
        // Validate after installation
        final validated = await installer.validatePackIntegrity();
        if (!validated) {
          AppEnvironment.log('SYNC', 'Pack validation failed: ${pack.packId}');
          return false;
        }
      }

      return success;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error installing local pack: $e');
      return false;
    }
  }

  /// Check for updates for all packs
  Future<Map<String, String?>> checkForUpdates() async {
    try {
      AppEnvironment.log('SYNC', 'Checking for pack updates...');
      
      final updates = <String, String?>{};
      final packs = await _packManager.getAllPacks();

      for (final pack in packs) {
        final latestVersion = await _getRemotePackVersion(pack.packId);
        if (latestVersion != null && latestVersion != pack.version) {
          updates[pack.packId] = latestVersion;
        }
      }

      AppEnvironment.log('SYNC', 'Update check complete: ${updates.length} updates available');
      return updates;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error checking for updates: $e');
      return {};
    }
  }

  /// Get remote version of a pack
  Future<String?> _getRemotePackVersion(String packId) async {
    try {
      if (!AppEnvironment.enableBackend) return null;
      final url = Uri.parse('${_endpoints.baseUrl}/packs/$packId/manifest');
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['version']?.toString() ?? data['pack_version']?.toString();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Delete a pack and free storage
  Future<bool> deletePack(String packId) async {
    try {
      AppEnvironment.log('SYNC', 'Deleting pack: $packId');
      await _packManager.deletePack(packId);
      return true;
    } catch (e) {
      AppEnvironment.log('SYNC', 'Error deleting pack: $e');
      return false;
    }
  }

  /// Get sync status for a pack
  Future<SyncStatus> getPackSyncStatus(String packId) async {
    try {
      final pack = await EducationalRepository.getPackByPackId(packId);
      if (pack == null) {
        return SyncStatus(
          packId: packId,
          state: 'not_found',
          progress: 0.0,
          message: 'Pack not found',
        );
      }

      return SyncStatus(
        packId: packId,
        state: pack.syncState,
        progress: pack.downloadProgress,
        message: pack.isOfflineAvailable ? 'Available offline' : 'Not downloaded',
      );
    } catch (e) {
      return SyncStatus(
        packId: packId,
        state: 'error',
        progress: 0.0,
        message: 'Error: $e',
      );
    }
  }

  /// Emit progress update
  void _emitProgress(String packId, double progress, String message) {
    _progressController?.add(
      SyncProgress(
        packId: packId,
        progress: progress,
        message: message,
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Close sync service
  Future<void> close() async {
    await _progressController?.close();
    _progressController = null;
  }
}

/// Sync progress information
class SyncProgress {
  final String packId;
  final double progress; // 0.0 to 1.0
  final String message;
  final DateTime timestamp;

  SyncProgress({
    required this.packId,
    required this.progress,
    required this.message,
    required this.timestamp,
  });
}

/// Sync status information
class SyncStatus {
  final String packId;
  final String state; // 'discovered', 'pending', 'downloading', 'synced', 'failed', 'not_found', 'error'
  final double progress;
  final String message;

  SyncStatus({
    required this.packId,
    required this.state,
    required this.progress,
    required this.message,
  });
}
