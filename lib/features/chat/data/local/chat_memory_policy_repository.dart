import '../../../course/data/local/app_database.dart';
import 'package:sqflite/sqflite.dart';

enum SessionResetPolicy {
  manual,
  chapterOpen,
  inactivity,
}

class ChatMemoryPolicy {
  const ChatMemoryPolicy({
    required this.sessionId,
    required this.shortTermWindow,
    required this.semanticRecallEnabled,
    required this.semanticTopK,
    required this.resetPolicy,
    required this.inactivityMinutes,
  });

  final String sessionId;
  final int shortTermWindow;
  final bool semanticRecallEnabled;
  final int semanticTopK;
  final SessionResetPolicy resetPolicy;
  final int inactivityMinutes;

  static ChatMemoryPolicy defaults(String sessionId) {
    return ChatMemoryPolicy(
      sessionId: sessionId,
      shortTermWindow: 8,
      semanticRecallEnabled: true,
      semanticTopK: 2,
      resetPolicy: SessionResetPolicy.manual,
      inactivityMinutes: 45,
    );
  }

  ChatMemoryPolicy copyWith({
    String? sessionId,
    int? shortTermWindow,
    bool? semanticRecallEnabled,
    int? semanticTopK,
    SessionResetPolicy? resetPolicy,
    int? inactivityMinutes,
  }) {
    return ChatMemoryPolicy(
      sessionId: sessionId ?? this.sessionId,
      shortTermWindow: shortTermWindow ?? this.shortTermWindow,
      semanticRecallEnabled: semanticRecallEnabled ?? this.semanticRecallEnabled,
      semanticTopK: semanticTopK ?? this.semanticTopK,
      resetPolicy: resetPolicy ?? this.resetPolicy,
      inactivityMinutes: inactivityMinutes ?? this.inactivityMinutes,
    );
  }
}

class ChatMemoryPolicyRepository {
  ChatMemoryPolicyRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  Future<ChatMemoryPolicy> getPolicy(String sessionId) => getOrCreatePolicy(sessionId);

  Future<ChatMemoryPolicy> getOrCreatePolicy(String sessionId) async {
    final db = await _database.database;
    final rows = await db.query(
      'chat_memory_policies',
      where: 'session_id = ?',
      whereArgs: <Object?>[sessionId],
      limit: 1,
    );

    if (rows.isEmpty) {
      final defaults = ChatMemoryPolicy.defaults(sessionId);
      await savePolicy(defaults);
      return defaults;
    }

    return _fromRow(rows.first);
  }

  Future<void> savePolicy(ChatMemoryPolicy policy) async {
    final db = await _database.database;
    await db.insert(
      'chat_memory_policies',
      <String, Object?>{
        'session_id': policy.sessionId,
        'short_term_window': policy.shortTermWindow,
        'semantic_recall_enabled': policy.semanticRecallEnabled ? 1 : 0,
        'semantic_top_k': policy.semanticTopK,
        'reset_policy': _policyToDb(policy.resetPolicy),
        'inactivity_minutes': policy.inactivityMinutes,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  ChatMemoryPolicy _fromRow(Map<String, Object?> row) {
    return ChatMemoryPolicy(
      sessionId: row['session_id'] as String,
      shortTermWindow: row['short_term_window'] as int? ?? 8,
      semanticRecallEnabled: (row['semantic_recall_enabled'] as int? ?? 1) == 1,
      semanticTopK: row['semantic_top_k'] as int? ?? 2,
      resetPolicy: _policyFromDb(row['reset_policy'] as String? ?? 'manual'),
      inactivityMinutes: row['inactivity_minutes'] as int? ?? 45,
    );
  }

  String _policyToDb(SessionResetPolicy policy) {
    switch (policy) {
      case SessionResetPolicy.chapterOpen:
        return 'chapter_open';
      case SessionResetPolicy.inactivity:
        return 'inactivity';
      case SessionResetPolicy.manual:
        return 'manual';
    }
  }

  SessionResetPolicy _policyFromDb(String value) {
    switch (value) {
      case 'chapter_open':
        return SessionResetPolicy.chapterOpen;
      case 'inactivity':
        return SessionResetPolicy.inactivity;
      case 'manual':
      default:
        return SessionResetPolicy.manual;
    }
  }
}
