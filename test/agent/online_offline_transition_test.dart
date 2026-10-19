import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/mentora_agent_session.dart';
import 'package:mentora/features/chat/application/mentora_tutor_agent_provider.dart';
import 'package:mentora/features/chat/application/tutor_session_coordinator.dart';
import 'package:mentora/features/chat/domain/tutor_stream_event.dart';
import 'package:mentora/features/network/data/backend_availability_cache.dart';

void main() {
  group('Online/Offline Transition Suite', () {
    test('seamlessly transitions from online SSE to offline local model without tool duplication', () async {
      final cache = BackendAvailabilityCache();
      cache.updateStatus(true);
      var currentProviderCallCount = 0;
      final onlineRequests = <String>[];
      final offlineRequests = <String>[];

      final provider = MentoraTutorAgentProvider(
        streamTutor: ({
          required question,
          required topic,
          required grade,
          cancelToken,
          history = const [],
          tools = const [],
        }) async* {
          currentProviderCallCount++;
          if (cache.isOnline) {
            onlineRequests.add(question);
            yield TutorStreamChunkEvent('Online answer to: $question');
            yield TutorStreamCompletedEvent(
              fullText: 'Online answer to: $question',
              source: 'cloud_sse',
            );
          } else {
            offlineRequests.add(question);
            yield TutorStreamChunkEvent('Offline local answer to: $question');
            yield TutorStreamCompletedEvent(
              fullText: 'Offline local answer to: $question',
              source: 'local_gguf',
            );
          }
        },
      );

      final coordinator = TutorSessionCoordinator(
        agentProvider: provider,
        initialTopic: 'Kinematics',
        initialGrade: 9,
        availabilityCache: cache,
      );

      // Turn 1: Online
      final history = <Map<String, dynamic>>[];
      final turn1 = await coordinator.submitQuestion('What is acceleration?', rawHistory: history).toList();
      final turn1Text = turn1.whereType<TutorTurnCompletedEvent>().single.text;
      expect(turn1Text, contains('Online answer'));
      expect(onlineRequests.length, 1);
      expect(offlineRequests.isEmpty, isTrue);

      history.add({'isUser': true, 'text': 'What is acceleration?'});
      history.add({'isUser': false, 'text': turn1Text});

      // Turn 2: Transition to Offline (e.g. Airplane mode / network drop)
      cache.updateStatus(false);
      expect(cache.isOffline, isTrue);

      final turn2 = await coordinator.submitQuestion('State its unit.', rawHistory: history).toList();
      final turn2Text = turn2.whereType<TutorTurnCompletedEvent>().single.text;
      expect(turn2Text, contains('Offline local answer'));
      expect(offlineRequests.length, 1);
      expect(onlineRequests.length, 1);

      history.add({'isUser': true, 'text': 'State its unit.'});
      history.add({'isUser': false, 'text': turn2Text});

      // Turn 3: Transition Back Online
      cache.updateStatus(true);
      expect(cache.isOnline, isTrue);

      final turn3 = await coordinator.submitQuestion('Give an example.', rawHistory: history).toList();
      final turn3Text = turn3.whereType<TutorTurnCompletedEvent>().single.text;
      expect(turn3Text, contains('Online answer'));
      expect(onlineRequests.length, 2);
      expect(offlineRequests.length, 1);
      expect(currentProviderCallCount, 3);

      await coordinator.dispose();
    });
  });
}
