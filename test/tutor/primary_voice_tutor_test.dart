import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mentora/features/language/providers/language_provider.dart';
import 'package:mentora/features/language/widgets/language_selector.dart';
import 'package:mentora/l10n/app_localizations.dart';
import 'package:mentora/features/tutor/screens/primary_voice_tutor_screen.dart';
import 'package:mentora/features/tutor/widgets/huge_mic_button.dart';
import 'package:mentora/features/tutor/widgets/large_response_card.dart';
import 'package:mentora/features/voice/widgets/tutor_avatar.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  Widget wrap(Widget child) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    );
  }

  testWidgets('PrimaryVoiceTutorScreen renders expected simplified widgets', (tester) async {
    final languageProvider = LanguageProvider();

    await tester.pumpWidget(wrap(PrimaryVoiceTutorScreen(
      languageProvider: languageProvider,
    )));

    expect(find.byType(TutorAvatar), findsOneWidget);
    expect(find.byType(LargeResponseCard), findsOneWidget);
    expect(find.byType(HugeMicButton), findsOneWidget);
    expect(find.byType(LanguageSelector), findsOneWidget);

    // Should contain the placeholder text initially
    expect(find.text('Tap the mic to ask a question!'), findsOneWidget);
  });
}
