import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/mentora_agent_session.dart';
import 'package:mentora/features/chat/application/mentora_tutor_agent_provider.dart';

void main() {
  group('MentoraTutorAgentProvider', () {
    test(
      'routes harness context through the configured tutor provider',
      () async {
        String? receivedQuestion;
        String? receivedTopic;
        int? receivedGrade;
        final provider = MentoraTutorAgentProvider(
          queryTutor:
              ({
                required question,
                required topic,
                required grade,
                cancelToken,
              }) async {
                receivedQuestion = question;
                receivedTopic = topic;
                receivedGrade = grade;
                return const {
                  'answer': 'Motion is a change in position.',
                  'source': 'backend_llm',
                };
              },
        );
        final session = provider.createSession(
          topic: 'Motion',
          grade: 9,
          initialMessages: [
            UserMessage.text('What is position?'),
            _assistantMessage('Position describes location.'),
          ],
        );

        final events = await session.runTurn('Define motion.').toList();

        expect(receivedQuestion, contains('Position describes location.'));
        expect(receivedQuestion, contains('Define motion.'));
        expect(receivedTopic, 'Motion');
        expect(receivedGrade, 9);
        expect(
          events.whereType<TutorTurnCompletedEvent>().single.text,
          'Motion is a change in position.',
        );
        await session.dispose();
      },
    );

    test(
      'reports backend and local runtime failures as failed turns',
      () async {
        final provider = MentoraTutorAgentProvider(
          queryTutor:
              ({
                required question,
                required topic,
                required grade,
                cancelToken,
              }) async => const {
                'answer': 'The selected model uses unsupported GGML type 41.',
                'source': 'local_llm_execution_error',
              },
        );
        final session = provider.createSession(topic: 'Motion', grade: 9);

        final events = await session.runTurn('Define motion.').toList();

        expect(
          events.whereType<TutorTurnFailedEvent>().single.message,
          contains('unsupported GGML type 41'),
        );
        expect(events.whereType<TutorTurnCompletedEvent>(), isEmpty);
        await session.dispose();
      },
    );
  });
}

AssistantMessage _assistantMessage(String text) => AssistantMessage(
  content: [TextContent(text: text)],
  api: 'mentora-routed',
  provider: 'mentora',
  model: 'mentora-default',
  usage: Usage.zero,
  stopReason: StopReason.stop,
  timestamp: DateTime.utc(2026),
);
