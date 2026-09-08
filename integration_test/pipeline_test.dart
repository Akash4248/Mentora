import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offline_tutor_app/features/network/application/pi_hub_discovery_coordinator.dart';
import 'package:offline_tutor_app/features/network/application/backend_url_manager.dart';
import 'package:offline_tutor_app/features/network/domain/backend_config.dart';
import 'package:offline_tutor_app/features/network/data/backend_api_service.dart';
import 'package:offline_tutor_app/features/educational/application/sync_manager.dart';
import 'package:offline_tutor_app/features/rag/data/local/rag_repository.dart';
import 'package:offline_tutor_app/config/app_environment.dart';
import 'package:offline_tutor_app/features/course/data/local/app_database.dart';
import 'package:sqflite/sqflite.dart';
import 'package:offline_tutor_app/features/network/domain/runtime_backend_url.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  });

  testWidgets('E2E Sync Pipeline Validation', (tester) async {
    print('\n--- START E2E SYNC VALIDATION ---');
    
    dotenv.loadFromString(envString: '''
DISCOVERY_IGNORE_ENV=false
BACKEND_BASE_URL=http://10.28.73.193
''');
    AppEnvironment.initialize();

    final config = BackendConfig(baseUrl: 'http://10.28.73.193', apiKey: 'dummy');
    final backendService = BackendApiService(config: config);
    final urlManager = BackendUrlManager(initialUrl: config.baseUrl);
    urlManager.urlChanges.listen((newUrl) {
      config.updateUrl(newUrl);
    });

    final discovery = PiHubDiscoveryCoordinator();
    discovery.discoveryUpdates.listen((nodes) {
      if (nodes.isNotEmpty) {
        urlManager.updateUrl(nodes.first.baseUrl);
      }
    });

    // 1. Discover Backend
    await discovery.discover();
    final isAvailable = await backendService.isBackendAvailable();
    print('BACKEND_AVAILABLE=$isAvailable');

    // 2. Clear Database to test from scratch
    final db = await AppDatabase.instance.database;
    await db.execute('DELETE FROM material_packs');
    await db.execute('DELETE FROM material_pack_items');
    await db.execute('DELETE FROM rag_chunks');
    await db.execute('DELETE FROM rag_chunks_fts');
    
    var packsBefore = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM material_packs'));
    var ragChunksBefore = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rag_chunks'));
    var ftsRowsBefore = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rag_chunks_fts'));
    print('PACKS_BEFORE=$packsBefore');
    print('RAG_CHUNKS_BEFORE=$ragChunksBefore');
    print('FTS_ROWS_BEFORE=$ftsRowsBefore');

    // 3. Trigger Sync Check
    final manager = SyncManager();
    final updates = await manager.checkForPackUpdates();
    await manager.processPackUpdates(updates);

    // 4. Wait for SyncQueue to drain
    print('Waiting for downloads and extraction...');
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 2));
      final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM material_packs'));
      if (count != null && count > 0) {
        break; // Pack is installed
      }
    }
    // Give it a few more seconds for RAG extraction
    await Future.delayed(const Duration(seconds: 15));

    // 5. Query final DB state
    var packsAfter = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM material_packs'));
    var itemsAfter = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM material_pack_items'));
    var ragChunksAfter = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rag_chunks'));
    var ftsRowsAfter = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rag_chunks_fts'));
    print('PACKS_AFTER=$packsAfter');
    print('CONTENT_ROWS_IMPORTED=$itemsAfter');
    print('RAG_CHUNKS_AFTER=$ragChunksAfter');
    print('FTS_ROWS_AFTER=$ftsRowsAfter');

    // 6. Retrieval Verification
    print('\n[RAG_VERIFY] ==== RETRIEVAL VERIFICATION ====');
    final queries = [
      'arithmetic progression',
      'quadrilaterals',
      'gravitation',
      'constitutional design',
      'prime numbers'
    ];

    for (final q in queries) {
      final terms = q.toLowerCase().split(' ').where((t) => t.length > 2).map((t) => '$t*').join(' ');
      try {
        final matches = await db.rawQuery('''
            SELECT rc.id, rc.source_title
            FROM rag_chunks rc
            INNER JOIN rag_chunks_fts fts ON fts.id = rc.id
            WHERE rag_chunks_fts MATCH ?
            LIMIT 4
        ''', [terms]);
        print('[RAG_VERIFY] QUERY=$q FTS_MATCHES=${matches.length}');
      } catch (e) {
        print('[RAG_VERIFY] QUERY=$q FTS_ERROR=$e');
      }
    }

    print('--- END E2E SYNC VALIDATION ---\n');
  });
}
