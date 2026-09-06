import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:offline_tutor_app/features/chat/application/reasoning_output_filter.dart';
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
