import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/data/visual_artifact_store.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('VisualArtifactStore', () {
    late VisualArtifactStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      store = VisualArtifactStore();
    });

    test('saves and retrieves artifacts by session ID and message index', () async {
      const intent1 = VisualIntent(
        schemaVersion: 1,
        type: VisualType.motionTrajectory,
        scenario: 'vertical_toss',
        inputs: {'initial_velocity_mps': 14.7},
      );

      const intent2 = VisualIntent(
        schemaVersion: 1,
        type: VisualType.simulationLauncher,
        scenario: 'phet-bending-light',
        inputs: {'simulation_id': 'phet-bending-light'},
      );

      await store.saveArtifacts(
        sessionId: 'session_abc',
        messageIndex: 3,
        artifacts: [intent1, intent2],
      );

      final retrieved = await store.getArtifacts(
        sessionId: 'session_abc',
        messageIndex: 3,
      );

      expect(retrieved.length, 2);
      expect(retrieved[0].type, VisualType.motionTrajectory);
      expect(retrieved[0].scenario, 'vertical_toss');
      expect(retrieved[1].type, VisualType.simulationLauncher);
      expect(retrieved[1].scenario, 'phet-bending-light');
    });

    test('returns empty list for non-existent session or message index', () async {
      final retrieved = await store.getArtifacts(
        sessionId: 'empty_session',
        messageIndex: 0,
      );
      expect(retrieved, isEmpty);
    });

    test('clearSession removes all artifacts for that session', () async {
      const intent = VisualIntent(
        schemaVersion: 1,
        type: VisualType.motionTrajectory,
        scenario: 'vertical_toss',
      );

      await store.saveArtifacts(
        sessionId: 'to_clear',
        messageIndex: 1,
        artifacts: [intent],
      );

      await store.saveArtifacts(
        sessionId: 'to_clear',
        messageIndex: 2,
        artifacts: [intent],
      );

      await store.clearSession('to_clear');

      final at1 = await store.getArtifacts(sessionId: 'to_clear', messageIndex: 1);
      final at2 = await store.getArtifacts(sessionId: 'to_clear', messageIndex: 2);
      expect(at1, isEmpty);
      expect(at2, isEmpty);
    });
  });
}
