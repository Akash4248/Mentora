import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart';

void main() async {
  sqfliteFfiInit();
  var databaseFactory = databaseFactoryFfi;
  // Resolve via sqflite path — never a hard-coded dev-machine absolute path.
  final databasesPath = await getDatabasesPath();
  final dbPath = '$databasesPath/offline_tutor_stage1.db';
  final db = await databaseFactory.openDatabase(dbPath);

  print('[DB_VERIFY] ==== SQLITE AUDIT ====');
  
  final packsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM material_packs'));
  final itemsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM material_pack_items'));
  final ragCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rag_chunks'));
  final ftsCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM rag_chunks_fts'));

  print('[DB_VERIFY] PACKS_COUNT=\$packsCount');
  print('[DB_VERIFY] ITEMS_COUNT=\$itemsCount');
  print('[DB_VERIFY] RAG_CHUNKS_COUNT=\$ragCount');
  print('[DB_VERIFY] FTS_CHUNKS_COUNT=\$ftsCount');
  
  print('\\n[RAG_VERIFY] ==== RETRIEVAL VERIFICATION ====');
  final queries = [
    'arithmetic progression',
    'quadrilaterals',
    'gravitation',
    'constitutional design',
    'prime numbers'
  ];

  for (final q in queries) {
    print('[RAG_VERIFY] QUERY=\$q');
    final terms = q.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((t) => t.length > 2).map((t) => '\$t*').join(' ');
    
    try {
      final ftsRows = await db.rawQuery('''
        SELECT rc.id, rc.source_title, -1.0 as score
        FROM rag_chunks rc
        INNER JOIN rag_chunks_fts fts ON fts.id = rc.id
        WHERE rag_chunks_fts MATCH ?
        LIMIT 4
      ''', [terms]);
      print('[RAG_VERIFY] FTS_MATCHES=\${ftsRows.length}');
      if (ftsRows.isNotEmpty) {
        final score = ftsRows.first['score'];
        print('[RAG_VERIFY] TOP_SCORE=\$score');
      }
    } catch (e) {
      print('[RAG_VERIFY] FTS_ERROR=\$e');
    }
  }

  await db.close();
}
