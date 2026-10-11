import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mentora/features/language/models/app_language.dart';
import 'package:mentora/features/language/services/language_service.dart';
import 'package:mentora/features/language/providers/language_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  // ─── AppLanguage model ───────────────────────────────────────────

  group('AppLanguage', () {
    test('fromCode returns correct language for known codes', () {
      expect(AppLanguage.fromCode('en'), AppLanguage.english);
      expect(AppLanguage.fromCode('kn'), AppLanguage.kannada);
    });

    test('fromCode returns english for unrecognized codes', () {
      expect(AppLanguage.fromCode('fr'), AppLanguage.english);
      expect(AppLanguage.fromCode(''), AppLanguage.english);
    });

    test('each language has correct metadata', () {
      expect(AppLanguage.english.code, 'en');
      expect(AppLanguage.english.displayName, 'English');
      expect(AppLanguage.english.nativeName, 'English');

      expect(AppLanguage.kannada.code, 'kn');
      expect(AppLanguage.kannada.nativeName, 'ಕನ್ನಡ');
    });

    test('isRtl is false for all languages', () {
      for (final lang in AppLanguage.values) {
        expect(lang.isRtl, isFalse);
      }
    });
  });

  // ─── LanguageService persistence ─────────────────────────────────

  group('LanguageService', () {
    test('returns english when nothing is saved', () async {
      final service = LanguageService();
      final lang = await service.loadSavedLanguage();
      expect(lang, AppLanguage.english);
    });

    test('round-trips a language preference', () async {
      final service = LanguageService();
      await service.saveLanguage(AppLanguage.kannada);
      final loaded = await service.loadSavedLanguage();
      expect(loaded, AppLanguage.kannada);
    });
  });

  // ─── LanguageProvider ────────────────────────────────────────────

  group('LanguageProvider', () {
    test('initializes to english by default', () async {
      final provider = LanguageProvider();
      await provider.initialize();

      expect(provider.initialized, isTrue);
      expect(provider.currentLanguage, AppLanguage.english);
      expect(provider.languageCode, 'en');
    });

    test('setLanguage updates current and persists', () async {
      final provider = LanguageProvider();
      await provider.initialize();

      await provider.setLanguage(AppLanguage.kannada);

      expect(provider.currentLanguage, AppLanguage.kannada);
      expect(provider.languageCode, 'kn');

      // Create a fresh provider to confirm persistence
      final provider2 = LanguageProvider();
      await provider2.initialize();
      expect(provider2.currentLanguage, AppLanguage.kannada);
    });

    test('notifies listeners on language change', () async {
      final provider = LanguageProvider();
      await provider.initialize();

      int notifyCount = 0;
      provider.addListener(() => notifyCount++);

      await provider.setLanguage(AppLanguage.kannada);
      expect(notifyCount, 1);

      // Setting same language again should not notify
      await provider.setLanguage(AppLanguage.kannada);
      expect(notifyCount, 1);
    });

    test('initialize only runs once', () async {
      final provider = LanguageProvider();
      await provider.initialize();
      await provider.setLanguage(AppLanguage.kannada);

      // Second initialize should not reset to english
      await provider.initialize();
      expect(provider.currentLanguage, AppLanguage.kannada);
    });
  });
}
