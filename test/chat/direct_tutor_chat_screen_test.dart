import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/presentation/direct_tutor_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'selected_grade': 9,
    });
  });

  testWidgets('renders DirectTutorChatScreen with open topic and starter prompts', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DirectTutorChatScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Mentora AI Tutor'), findsOneWidget);
    expect(find.text('Direct AI Tutor'), findsOneWidget);
    expect(find.text('Class 9'), findsWidgets);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('🔢 Solve Math Problem'), findsOneWidget);
    expect(find.text('⚡ Physics Concept'), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
  });
}
