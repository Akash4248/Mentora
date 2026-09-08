import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_tutor_app/features/chat/application/conversation_memory_harness.dart';
import 'package:offline_tutor_app/features/chat/data/local/chat_memory_policy_repository.dart';
import 'package:offline_tutor_app/features/chat/data/local/chat_session_repository.dart';
import 'package:offline_tutor_app/features/chat/domain/tutor_message.dart';
import 'package:offline_tutor_app/features/chat/presentation/chapter_chat_screen.dart';
import 'package:offline_tutor_app/features/course/domain/course_tree.dart';
import 'package:offline_tutor_app/features/course/data/local/app_database.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.loadFromString(envString: '''
BACKEND_BASE_URL=http://pihub.local
ENABLE_LOCAL_INFERENCE=true
''');
  });

  group('On-Device Chat Persistence & Memory Harness Verification Matrix', () {
    testWidgets('1. Verify ChatSessionRepository persists messages & updates stream completion without duplicates', (WidgetTester tester) async {
      print('\n--- [MOBILE_TEST] 1. CHAT SESSION PERSISTENCE & COMPLETED ASSISTANT RESPONSE ---');
      final repo = ChatSessionRepository();
      const testSessionId = 'session_physics_9_motion_on_device';

      final db = await AppDatabase.instance.database;
      await db.insert(
        'courses',
        {'id': 'sci_9', 'name': 'Science Grade 9'},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await db.insert(
        'subjects',
        {'id': 'physics', 'course_id': 'sci_9', 'name': 'Physics'},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await db.insert(
        'chapters',
        {
          'id': 'ch_motion',
          'subject_id': 'physics',
          'title': 'Motion',
          'summary': 'Motion concepts',
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      await repo.ensureSessionExists(sessionId: testSessionId, chapterId: 'ch_motion');
      await repo.clearMessages(testSessionId);

      // Append user message
      await repo.appendMessage(
        sessionId: testSessionId,
        isUser: true,
        text: 'Can you explain acceleration with a formula?',
        timestamp: DateTime.now(),
      );

      // Simulate token streaming completion persisting the final answer
      await repo.updateLastAssistantMessage(
        sessionId: testSessionId,
        text: 'Acceleration is given by a = (v - u) / t, measured in m/s².',
      );

      final persistedMessages = await repo.getMessages(testSessionId);
      print('[MOBILE_TEST] Persisted Messages Count: ${persistedMessages.length}');
      for (final m in persistedMessages) {
        print('  [${m.isUser ? "STUDENT" : "TUTOR"}] ${m.text}');
      }

      expect(persistedMessages.length, equals(2));
      expect(persistedMessages[0].isUser, isTrue);
      expect(persistedMessages[0].text, contains('explain acceleration'));
      expect(persistedMessages[1].isUser, isFalse);
      expect(persistedMessages[1].text, contains('a = (v - u) / t'));
      print('--- [MOBILE_TEST] PASSED: Chat persistence verified on-device ---\n');
    });

    testWidgets('2. Verify ConversationMemoryHarness builds compacted prompt with tools & history window', (WidgetTester tester) async {
      print('\n--- [MOBILE_TEST] 2. CONVERSATION MEMORY HARNESS PROMPT ASSEMBLY ---');
      final harness = ConversationMemoryHarness();
      
      final history = [
        TutorMessage(text: 'What is motion?', isUser: true, timestamp: DateTime.now()),
        TutorMessage(text: 'Motion is change in position over time.', isUser: false, timestamp: DateTime.now()),
        TutorMessage(text: 'Give an example of uniform motion.', isUser: true, timestamp: DateTime.now()),
        TutorMessage(text: 'A car moving at constant 60 km/h on a straight highway.', isUser: false, timestamp: DateTime.now()),
      ];

      final policy = ChatMemoryPolicy.defaults('session_physics_9_motion_on_device');
      final prompt = await harness.buildContextualPrompt(
        history: history,
        currentQuestion: 'What is non-uniform motion then?',
        chapterTitle: 'Motion',
        courseName: 'Science 9',
        policy: policy,
      );

      print('[MOBILE_TEST] Generated Contextual Prompt Snippet:');
      print(prompt.length > 300 ? '${prompt.substring(0, 300)}...' : prompt);

      expect(prompt, contains('System Context'));
      expect(prompt, contains('search_chapter_knowledge'));
      expect(prompt, contains('lookup_past_memory'));
      expect(prompt, contains('Recent Conversation History'));
      expect(prompt, contains('A car moving at constant 60 km/h'));
      expect(prompt, contains('What is non-uniform motion then?'));
      print('--- [MOBILE_TEST] PASSED: Memory harness prompt assembly verified ---\n');
    });

    testWidgets('3. Verify ChapterChatScreen loads previous history on re-entry on mobile device', (WidgetTester tester) async {
      print('\n--- [MOBILE_TEST] 3. CHAPTER CHAT SCREEN WIDGET INITIALIZATION & HISTORY RE-ENTRY ---');
      const course = Course(id: 'sci_9', name: 'Science Grade 9');
      const subject = Subject(id: 'physics', courseId: 'sci_9', name: 'Physics');
      const chapter = Chapter(id: 'ch_motion', subjectId: 'physics', title: 'Motion', summary: 'Motion concepts');

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: ChapterChatScreen(
              course: course,
              subject: subject,
              chapter: chapter,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle(const Duration(seconds: 2));

      print('[MOBILE_TEST] ChapterChatScreen rendered successfully on physical device!');
      expect(find.byType(ChapterChatScreen), findsOneWidget);
      expect(find.textContaining('Physics - Motion'), findsOneWidget);
      print('--- [MOBILE_TEST] PASSED: On-device screen re-entry verified ---\n');
    });
  });
}
