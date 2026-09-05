import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:offline_tutor_app/l10n/app_localizations.dart';

import 'bootstrap/critical_bootstrap.dart';
import 'bootstrap/startup_coordinator.dart';
import 'config/app_environment.dart';
import 'features/course/data/local/course_repository.dart';
import 'features/language/providers/language_provider.dart';
import 'features/onboarding/application/background_prefetch_service.dart';
import 'core/observers/app_provider_observer.dart';
import 'core/theme/idp_theme.dart';
import 'features/experiment/runtime/behaviors/behavior_registry.dart';
import 'features/experiment/runtime/effects/effect_registry.dart';
import 'features/experiment/runtime/tools/measurement_registry.dart';
import 'features/home/presentation/mentora_home_screen.dart';
import 'features/assessment/presentation/mentora_practice_screen.dart';
import 'features/progress/presentation/mentora_mastery_screen.dart';
import 'features/course/presentation/subject_chapters_screen.dart';
import 'features/tutor/presentation/chapter_learning_workspace_screen.dart';
import 'features/settings/presentation/mentora_settings_screen.dart';

import 'features/voice/screens/voice_debug_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppEnvironment.initialize();
  await BackgroundPrefetchService.initialize();

  CriticalBootstrap.configureDesktopSqlite();

  // Initialize behavior, effect, and tool registries for all experiments
  BehaviorRegistry.initialize();
  EffectRegistry.initialize();
  MeasurementRegistry.initialize();

  // Language foundation — load persisted preference before first frame
  final languageProvider = LanguageProvider();
  await languageProvider.initialize();

  final startupCoordinator = StartupCoordinator(
    runtimeMode: CriticalBootstrap.resolveRuntimeMode(),
  );

  runApp(
    ProviderScope(
      observers: const [AppProviderObserver()],
      child: OfflineTutorApp(
        courseRepository: CourseRepository(),
        startupCoordinator: startupCoordinator,
        languageProvider: languageProvider,
      ),
    ),
  );
}

class OfflineTutorApp extends StatelessWidget {
  const OfflineTutorApp({
    super.key,
    required this.courseRepository,
    required this.startupCoordinator,
    required this.languageProvider,
  });

  final CourseRepository courseRepository;
  final StartupCoordinator startupCoordinator;
  final LanguageProvider languageProvider;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: languageProvider,
      builder: (context, _) {
        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          debugShowCheckedModeBanner: false,
          theme: IDPTheme.lightTheme,
          locale: Locale(languageProvider.languageCode),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const MentoraHomeScreen(),
          routes: {
            '/home': (context) => const MentoraHomeScreen(),
            '/practice': (context) => const MentoraPracticeScreen(),
            '/mastery': (context) => const MentoraMasteryScreen(),
            '/subject_chapters': (context) => const SubjectChaptersScreen(),
            '/chapter_workspace': (context) => const ChapterLearningWorkspaceScreen(),
            '/settings': (context) => const MentoraSettingsScreen(),
            '/voice_overlay': (context) => const VoiceDebugScreen(),
          },
          onUnknownRoute: (settings) => MaterialPageRoute(
            builder: (context) => const MentoraHomeScreen(),
          ),
        );
      },
    );
  }
}
