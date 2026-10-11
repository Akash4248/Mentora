import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mentora/features/language/models/app_language.dart';
import 'package:mentora/features/tutor/models/conversation_message.dart';
import 'package:mentora/features/tutor/widgets/conversation_bubble.dart';

void main() {
  group('ConversationBubble', () {
    Widget wrap(Widget child) {
      return MaterialApp(home: Scaffold(body: child));
    }

    testWidgets('StudentBubble renders text', (tester) async {
      final msg = ConversationMessage(
        id: 'msg_1',
        role: MessageRole.student,
        text: 'What is photosynthesis?',
        language: AppLanguage.english,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(wrap(StudentBubble(message: msg)));
      expect(find.text('What is photosynthesis?'), findsOneWidget);
    });

    testWidgets('TutorBubble renders text', (tester) async {
      final msg = ConversationMessage(
        id: 'msg_2',
        role: MessageRole.assistant,
        text: 'ಸಂಕೀರ್ಣ ಪ್ರಕ್ರಿಯೆ',
        language: AppLanguage.kannada,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(wrap(TutorBubble(message: msg)));
      expect(find.text('ಸಂಕೀರ್ಣ ಪ್ರಕ್ರಿಯೆ'), findsOneWidget);
    });

    testWidgets('SystemBubble renders text', (tester) async {
      final msg = ConversationMessage(
        id: 'msg_3',
        role: MessageRole.system,
        text: 'Session started',
        language: AppLanguage.english,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(wrap(SystemBubble(message: msg)));
      expect(find.text('Session started'), findsOneWidget);
    });

    testWidgets('ConversationBubble routes to correct type', (tester) async {
      final studentMsg = ConversationMessage(
        id: 'msg_4',
        role: MessageRole.student,
        text: 'Student message',
        language: AppLanguage.english,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(wrap(ConversationBubble(message: studentMsg)));
      expect(find.byType(StudentBubble), findsOneWidget);

      final tutorMsg = ConversationMessage(
        id: 'msg_5',
        role: MessageRole.assistant,
        text: 'Tutor response',
        language: AppLanguage.kannada,
        timestamp: DateTime.now(),
      );

      await tester.pumpWidget(wrap(ConversationBubble(message: tutorMsg)));
      expect(find.byType(TutorBubble), findsOneWidget);
    });
  });
}
