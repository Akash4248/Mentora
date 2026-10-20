import 'package:sqflite/sqflite.dart';
import 'app_database.dart';
import '../../../content_packs/application/content_pack_bootstrap_service.dart';

class DatabaseAutoRepairService {
  Future<void> runAutoRepair() async {
    print('[DB] AUTO_REPAIR_START');
    
    try {
      final db = await AppDatabase.instance.database;
      
      // Check tables
      final packsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM material_packs')) ?? 0;
      final chunksCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rag_chunks')) ?? 0;
      
      int ftsCount = 0;
      final ftsTableExists = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='rag_chunks_fts'")) ?? 0;
          
      if (ftsTableExists > 0) {
        ftsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rag_chunks_fts')) ?? 0;
      }

      print('[DB] Diagnostics before repair: PACKS=$packsCount, CHUNKS=$chunksCount, FTS=$ftsCount');

      // 1. Repair FTS Table & Index if missing or out of sync
      if (ftsTableExists == 0) {
        print('[DB] Repairing missing rag_chunks_fts table...');
        try {
          await db.execute('''
            CREATE VIRTUAL TABLE IF NOT EXISTS rag_chunks_fts 
            USING fts5(id UNINDEXED, chapter_id UNINDEXED, content, tokenize='unicode61')
          ''');
        } catch (e) {
          try {
            await db.execute('''
              CREATE VIRTUAL TABLE IF NOT EXISTS rag_chunks_fts 
              USING fts4(id, chapter_id, content)
            ''');
          } catch (e2) {
            try {
              await db.execute('''
                CREATE VIRTUAL TABLE IF NOT EXISTS rag_chunks_fts 
                USING fts3(id, chapter_id, content)
              ''');
            } catch (e3) {
              print('[DB] FTS not supported, skipping FTS repair');
            }
          }
        }
        ftsCount = 0;
      }
      
      // If we have chunks but no FTS index rows, rebuild the index (if FTS table exists)
      final ftsTableExistsNow = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='rag_chunks_fts'")) ?? 0;
      if (chunksCount > 0 && ftsCount == 0 && ftsTableExistsNow > 0) {
        print('[DB] Rebuilding FTS index from $chunksCount chunks...');
        await db.execute('INSERT INTO rag_chunks_fts(id, chapter_id, content) SELECT id, chapter_id, content FROM rag_chunks');
      }

      // 2. Repair Content Packs if missing
      if (packsCount == 0) {
        print('[DB] Repairing missing content packs...');
        final bootstrapService = ContentPackBootstrapService();
        await bootstrapService.bootstrapLegacyMediaIntoPacks();
      }

      // Startup validation as requested
      final packsCountFinal = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM material_packs')) ?? 0;
      final subjectsCountFinal = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM subjects')) ?? 0;
      final chaptersCountFinal = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM chapters')) ?? 0;
      final chunksCountFinal = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rag_chunks')) ?? 0;
      int ftsCountFinal = 0;
      final ftsTableExistsFinal = Sqflite.firstIntValue(await db.rawQuery(
          "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='rag_chunks_fts'")) ?? 0;
      if (ftsTableExistsFinal > 0) {
        ftsCountFinal = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rag_chunks_fts')) ?? 0;
      }

      print('[DB] Validation PACKS > 0: ${packsCountFinal > 0} ($packsCountFinal)');
      print('[DB] Validation SUBJECTS > 0: ${subjectsCountFinal > 0} ($subjectsCountFinal)');
      print('[DB] Validation CHAPTERS > 0: ${chaptersCountFinal > 0} ($chaptersCountFinal)');
      print('[DB] Validation CHUNKS > 0: ${chunksCountFinal > 0} ($chunksCountFinal)');
      print('[DB] Validation FTS > 0: ${ftsCountFinal > 0} ($ftsCountFinal)');

      print('[DB] AUTO_REPAIR_COMPLETE');
    } catch (e) {
      print('[DB] AUTO_REPAIR_FAILED: $e');
    }
  }
}
