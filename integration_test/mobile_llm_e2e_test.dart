import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_tutor_app/features/chat/application/reasoning_output_filter.dart';
import 'package:offline_tutor_app/features/chat/application/conversation_memory_harness.dart';
import 'package:offline_tutor_app/features/chat/data/local/chat_session_repository.dart';
import 'package:offline_tutor_app/features/chat/data/local/chat_memory_policy_repository.dart';
import 'package:offline_tutor_app/features/chat/domain/tutor_message.dart';
import 'package:offline_tutor_app/features/course/data/local/app_database.dart';
import 'package:offline_tutor_app/features/network/services/mentora_backend_client.dart';
import 'package:offline_tutor_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Mobile On-Device LLM & Backend Integration Tests', () {
    testWidgets('App launches on Android mobile device (moto g34 5G)', (WidgetTester tester) async {
      await app.main();
      await tester.pumpAndSettle(const Duration(seconds: 3));

      print('[MOBILE_TEST] App successfully launched on Android mobile device!');
      expect(find.byType(app.OfflineTutorApp), findsOneWidget);
    });

    testWidgets('ReasoningOutputFilter cleans ChatML stop tokens on mobile', (WidgetTester tester) async {
      final filter = ReasoningOutputFilter();
      const rawMobileStream = '''
### Motion Explained

Acceleration is the rate of change of velocity.
<|im_end|>
''';

      final cleaned = filter.push(rawMobileStream) + filter.flush();
      print('[MOBILE_TEST] Cleaned output: "$cleaned"');

      expect(cleaned, isNot(contains('<|im_end|>')));
      expect(cleaned, contains('Acceleration is the rate of change of velocity.'));
    });

    testWidgets('ChatSessionRepository persists messages and prevents duplicate placeholder pollution', (WidgetTester tester) async {
      final repo = ChatSessionRepository();
      const testSessionId = 'test_session_chapter_motion_9';
      final db = await AppDatabase.instance.database;
      await db.execute("INSERT OR IGNORE INTO courses (id, name) VALUES ('c1', 'Physics 9')");
      await db.execute("INSERT OR IGNORE INTO subjects (id, course_id, name) VALUES ('s1', 'c1', 'Physics')");
      await db.execute(
        "INSERT OR IGNORE INTO chapters (id, subject_id, title, summary) VALUES ('motion_ch1', 's1', 'Motion', 'Intro to Motion')",
      );

      await repo.ensureSessionExists(sessionId: testSessionId, chapterId: 'motion_ch1');
      await repo.clearMessages(testSessionId);

      // Append user message and completed assistant response
      await repo.appendMessage(
        sessionId: testSessionId,
        isUser: true,
        text: 'What is acceleration?',
        timestamp: DateTime.now(),
      );
      await repo.updateLastAssistantMessage(
        sessionId: testSessionId,
        text: 'Acceleration is the rate of change of velocity over time.',
      );

      final loadedMessages = await repo.getMessages(testSessionId);
      print('[MOBILE_TEST] Loaded Messages Count: ${loadedMessages.length}');
      for (final m in loadedMessages) {
        print('  [${m.isUser ? 'USER' : 'ASSISTANT'}] ${m.text}');
      }

      expect(loadedMessages.length, equals(2));
      expect(loadedMessages.first.text, equals('What is acceleration?'));
      expect(loadedMessages.last.text, contains('rate of change of velocity'));
    });

    testWidgets('ConversationMemoryHarness builds compacted multi-turn prompt context', (WidgetTester tester) async {
      final harness = ConversationMemoryHarness();
      final history = [
        TutorMessage(text: 'Hello Tutor!', isUser: true, timestamp: DateTime.now()),
        TutorMessage(text: 'Welcome to Physics!', isUser: false, timestamp: DateTime.now()),
        TutorMessage(text: 'What is distance?', isUser: true, timestamp: DateTime.now()),
        TutorMessage(text: 'Distance is scalar path length.', isUser: false, timestamp: DateTime.now()),
      ];

      final prompt = await harness.buildContextualPrompt(
        history: history,
        currentQuestion: 'How does it differ from displacement?',
        chapterTitle: 'Motion',
        courseName: 'Physics 9',
        policy: ChatMemoryPolicy.defaults('session_test'),
      );

      print('[MOBILE_TEST] Harness Prompt Context:\n$prompt');
      expect(prompt, contains('System Context'));
      expect(prompt, contains('Recent Conversation History'));
      expect(prompt, contains('Distance is scalar path length'));
      expect(prompt, contains('How does it differ from displacement?'));
    });

    testWidgets('MentoraBackendClient returns offline response or local LLM on mobile', (WidgetTester tester) async {
      final client = MentoraBackendClient();
      client.setBaseUrl('http://127.0.0.1:9999');

      final reply = await client.queryAiTutor(
        question: 'Explain velocity in 1 sentence.',
        topic: 'Motion',
        grade: 9,
      );

      print('[MOBILE_TEST] Offline Fallback Source: ${reply['source']}');
      print('[MOBILE_TEST] Offline Fallback Answer:\n${reply['answer']}');

      expect(reply['source'], isNotNull);
      expect(reply['answer'], isNotEmpty);
      expect(reply['answer'], isNot(contains('<|im_end|>')));
    });
  });
}
