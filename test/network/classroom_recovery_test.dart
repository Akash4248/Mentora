import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:mentora/features/network/application/classroom_recovery_coordinator.dart';
import 'package:mentora/features/network/application/classroom_session_manager.dart';
import 'package:mentora/features/network/application/heartbeat_recovery_service.dart';
import 'package:mentora/features/network/application/session_persistence_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dotenv.loadFromString(envString: 'BACKEND_BASE_URL=http://10.28.73.193\nENABLE_STRUCTURED_LOGGING=false');
  });

  test('session persistence round-trips classroom metadata', () async {
    final persistence = SessionPersistenceManager();

    await persistence.saveSession('session-a', <String, dynamic>{
      'courseId': 'course_6',
      'chapterId': 'chapter_1',
      'languageCode': 'en',
    });

    final loaded = await persistence.loadSession('session-a');

    expect(loaded, isNotNull);
    expect(loaded!['sessionId'], 'session-a');
    expect(loaded['courseId'], 'course_6');
    expect(loaded['chapterId'], 'chapter_1');
  });

  test('classroom recovery restores disconnected sessions', () async {
    final persistence = SessionPersistenceManager();
    final sessions = ClassroomSessionManager();
    final heartbeat = HeartbeatRecoveryService(sessions: sessions);
    final recovery = ClassroomRecoveryCoordinator(
      persistence: persistence,
      sessions: sessions,
      heartbeatRecovery: heartbeat,
    );

    await persistence.saveSession('session-b', <String, dynamic>{
      'courseId': 'course_7',
      'chapterId': 'chapter_2',
      'languageCode': 'kn',
    });

    final restored = await recovery.restoreIfNeeded('session-b');

    expect(restored, isTrue);
    expect(sessions.current.connected, isTrue);
    expect(sessions.current.sessionId, 'session-b');
  });
}
