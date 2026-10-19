import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/tutor/presentation/chapter_learning_workspace_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('renders the initial tutor message without a type error', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: ChapterLearningWorkspaceScreen()),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('MENTORA · TUTOR'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
