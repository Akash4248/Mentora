import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/home/presentation/mentora_home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'user_name': 'Akash',
      'selected_grade': 9,
    });
  });

  testWidgets('MentoraHomeScreen renders Direct AI Tutor shortcuts and handles navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        routes: {
          '/': (context) => const MentoraHomeScreen(),
          '/direct_tutor': (context) => const Scaffold(
                body: Text('Direct Tutor Target Screen'),
              ),
        },
        initialRoute: '/',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Verify Floating Action Button
    expect(find.text('Ask AI Tutor'), findsOneWidget);

    // 2. Verify AppBar Action Icon
    expect(find.byTooltip('Direct AI Tutor'), findsOneWidget);

    // 3. Verify Quick Action Card
    expect(find.text('Direct AI Tutor'), findsOneWidget);
    expect(find.text('Ask any question directly — no chapter packs required!'), findsOneWidget);

    // 4. Tap the Quick Action Card and verify navigation
    await tester.tap(find.text('Direct AI Tutor'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Direct Tutor Target Screen'), findsOneWidget);
  });
}
