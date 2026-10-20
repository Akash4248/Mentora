import 'dart:async';
import 'dart:io';

import '../config/app_environment.dart';
import '../features/chat/data/llm_admin_channel_service.dart';
import '../features/content_packs/application/content_pack_bootstrap_service.dart';
import '../features/course/data/local/app_database.dart';
import '../features/course/data/local/course_repository.dart';
import '../features/course/data/local/database_auto_repair_service.dart';
import '../features/rag/data/local/rag_repository_v2.dart';
import 'startup_coordinator.dart';

class BackgroundBootstrap {
  BackgroundBootstrap({
    required StartupCoordinator coordinator,
    required CourseRepository courseRepository,
  })  : _coordinator = coordinator,
        _courseRepository = courseRepository;

  final StartupCoordinator _coordinator;
  final CourseRepository _courseRepository;

  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    Future<void>(() async {
      await _run();
    });
  }

  Future<void> _run() async {
    try {
      _coordinator.beginStep('Warming local database');
      await AppDatabase.instance.database;
      
      // Run the database auto-repair to ensure FTS and packs are intact
      await DatabaseAutoRepairService().runAutoRepair();
      
      _coordinator.completeStep('Warming local database');

      _coordinator.beginStep('Seeding courses');
      await _courseRepository.ensureSeedData();
      _coordinator.completeStep('Seeding courses');

      _coordinator.beginStep('Seeding offline retrieval');
      await RagRepositoryV2().ensureSeedChunks();
      _coordinator.completeStep('Seeding offline retrieval');

      _coordinator.beginStep('Deferring content sync');
      _runAsyncBackgroundSync();
      _coordinator.completeStep('Deferring content sync');

      _coordinator.beginStep('Building offline search');
      _coordinator.markOfflineSearchReady();
      _coordinator.completeStep('Building offline search');

      if (Platform.isAndroid) {
        _coordinator.beginStep('Preparing local AI');
        try {
          await LlmAdminChannelService().preloadModel();
          _coordinator.markLocalAiReady();
        } catch (e) {
          AppEnvironment.log('SYNC', '[BackgroundBootstrap] Local AI warmup failed: $e');
        }
        _coordinator.completeStep('Preparing local AI');
      } else {
        _coordinator.markLocalAiReady();
      }

      _coordinator.markBackgroundComplete();
    } catch (e) {
      AppEnvironment.log('SYNC', '[BackgroundBootstrap] Startup warmup failed: $e');
    }
  }

  void _runAsyncBackgroundSync() {
    Future<void>(() async {
      try {
        AppEnvironment.log('SYNC', '[DIAGNOSTICS] BACKGROUND_SYNC_START');
        await Future<void>.delayed(const Duration(seconds: 2));
        
        AppEnvironment.log('SYNC', '[DIAGNOSTICS] SYNC_START');
        // Bulk sync has been replaced by Grade-based Selective Sync (Onboarding + PrefetchService)
        // Background sync is now handled by workmanager in BackgroundPrefetchService
        AppEnvironment.log('SYNC', '[DIAGNOSTICS] SYNC_END');

        // ContentPackBootstrapService is already handled synchronously in runAutoRepair 
        // if the database was empty. However, keeping this ensures updates process cleanly.
        AppEnvironment.log('SYNC', '[DIAGNOSTICS] PACK_INSTALL_START');
        await ContentPackBootstrapService().bootstrapLegacyMediaIntoPacks();
        AppEnvironment.log('SYNC', '[DIAGNOSTICS] PACK_INSTALL_END');
        
        AppEnvironment.log('SYNC', '[DIAGNOSTICS] BACKGROUND_SYNC_COMPLETE');
      } catch (e) {
        AppEnvironment.log('SYNC', 'Async background sync failed: $e');
      }
    });
  }
}
