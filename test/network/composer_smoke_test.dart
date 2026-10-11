import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'package:mentora/features/network/application/classroom_session_manager.dart';
import 'package:mentora/features/network/application/deferred_sync_manager.dart';
import 'package:mentora/features/network/application/offline_recovery_coordinator.dart';
import 'package:mentora/features/network/application/offline_state_persistence.dart';
import 'package:mentora/features/network/application/pack_version_manager.dart';
import 'package:mentora/features/network/application/incremental_sync_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dotenv.loadFromString(envString: 'BACKEND_BASE_URL=http://10.28.73.193\nENABLE_STRUCTURED_LOGGING=false');
  });

  test('offline recovery stores and recovers state', () {
    final persistence = OfflineStatePersistence();
    final deferred = DeferredSyncManager();
    final recovery = OfflineRecoveryCoordinator(
      persistence: persistence,
      deferredSync: deferred,
    );

    recovery.markOffline('backend_down');
    expect(persistence.load<String>('offline_reason'), 'backend_down');
  });

  test('incremental sync processes queued manifests', () async {
    final versions = PackVersionManager();
    final sync = IncrementalSyncCoordinator(versions: versions);
    sync.enqueue(
      const IncrementalSyncTask(
        manifest: PackManifest(packId: 'math', version: 2, checksum: 'abc'),
        payload: {'bytes': 100},
      ),
    );

    final emitted = <String>[];
    await for (final item in sync.process()) {
      emitted.add(item);
    }

    expect(emitted, contains('synced:math@2'));
    expect(versions.needsUpdate(const PackManifest(packId: 'math', version: 2, checksum: 'abc')), false);
  });

  test('pack version manager detects updates', () {
    final versions = PackVersionManager();
    const current = PackManifest(packId: 'science', version: 1, checksum: 'aaa');
    const incoming = PackManifest(packId: 'science', version: 2, checksum: 'bbb');

    versions.record(current);

    expect(versions.needsUpdate(incoming), true);
  });

  test('classroom session register and heartbeat update state', () async {
    final sessions = ClassroomSessionManager();
    await sessions.register('session-1');
    await sessions.heartbeat();

    expect(sessions.current.connected, true);
    expect(sessions.current.sessionId, 'session-1');
  });
}
