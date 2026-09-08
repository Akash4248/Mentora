import '../../../course/data/local/app_database.dart';
import '../../domain/tutor_message.dart';
import 'package:sqflite/sqflite.dart';

class ChatSessionRepository {
  ChatSessionRepository({AppDatabase? database})
      : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  /// Ensures a chat_sessions row exists for the session ID.
  Future<void> ensureSessionExists({
    required String sessionId,
    required String chapterId,
    String languageCode = 'en',
  }) async {
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'chat_sessions',
      {
        'id': sessionId,
        'chapter_id': chapterId,
        'language_code': languageCode,
        'started_at': now,
        'last_message_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> appendMessage({
    required String sessionId,
    required bool isUser,
    required String text,
    required DateTime timestamp,
  }) async {
    if (text.trim() == 'Thinking...' && !isUser) return;

    final db = await _database.database;
    final createdAt = timestamp.millisecondsSinceEpoch;

    await db.insert('chat_messages', {
      'session_id': sessionId,
      'role': isUser ? 'user' : 'assistant',
      'text': text,
      'created_at': createdAt,
    });

    await db.update(
      'chat_sessions',
      {'last_message_at': createdAt},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Updates the last assistant message text for [sessionId], or appends if not present.
  Future<void> updateLastAssistantMessage({
    required String sessionId,
    required String text,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'chat_messages',
      where: 'session_id = ? AND role = ?',
      whereArgs: [sessionId, 'assistant'],
      orderBy: 'created_at DESC',
      limit: 1,
    );

    if (rows.isNotEmpty) {
      final lastId = rows.first['id'];
      if (lastId != null) {
        await db.update(
          'chat_messages',
          {'text': text},
          where: 'id = ?',
          whereArgs: [lastId],
        );
      } else {
        final createdAt = rows.first['created_at'];
        await db.update(
          'chat_messages',
          {'text': text},
          where: 'session_id = ? AND created_at = ?',
          whereArgs: [sessionId, createdAt],
        );
      }
    } else {
      await appendMessage(
        sessionId: sessionId,
        isUser: false,
        text: text,
        timestamp: DateTime.now(),
      );
    }
  }

  /// Replaces the full session message list to ensure clean sync with UI state.
  Future<void> replaceSessionMessages({
    required String sessionId,
    required List<TutorMessage> messages,
  }) async {
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete(
        'chat_messages',
        where: 'session_id = ?',
        whereArgs: [sessionId],
      );

      for (final m in messages) {
        if (m.text.trim() == 'Thinking...' && !m.isUser) continue;

        await txn.insert('chat_messages', {
          'session_id': sessionId,
          'role': m.isUser ? 'user' : 'assistant',
          'text': m.text,
          'created_at': m.timestamp.millisecondsSinceEpoch,
        });
      }
    });
  }

  Future<List<TutorMessage>> getMessages(String sessionId) async {
    final db = await _database.database;
    final rows = await db.query(
      'chat_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'created_at ASC',
    );

    return rows
        .where((row) => (row['text'] as String?)?.trim() != 'Thinking...')
        .map(
          (row) => TutorMessage(
            text: row['text'] as String,
            isUser: (row['role'] as String) == 'user',
            timestamp: DateTime.fromMillisecondsSinceEpoch(
              row['created_at'] as int,
            ),
          ),
        )
        .toList();
  }

  Future<void> clearMessages(String sessionId) async {
    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.delete(
      'chat_messages',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );

    await db.update(
      'chat_sessions',
      {'last_message_at': now},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }
}
