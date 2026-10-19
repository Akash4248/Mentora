import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mentora/l10n/app_localizations.dart';

import 'bootstrap/critical_bootstrap.dart';
import 'bootstrap/startup_coordinator.dart';
import 'config/app_environment.dart';
import 'features/course/data/local/course_repository.dart';
import 'features/language/providers/language_provider.dart';
import 'features/onboarding/application/background_prefetch_service.dart';
import 'core/observers/app_provider_observer.dart';
import 'core/theme/idp_theme.dart';
import 'features/home/presentation/app_shell.dart';
import 'features/home/presentation/mentora_home_screen.dart';
import 'features/assessment/presentation/mentora_practice_screen.dart';
import 'features/progress/presentation/mentora_mastery_screen.dart';
import 'features/course/presentation/subject_chapters_screen.dart';
import 'features/tutor/presentation/chapter_learning_workspace_screen.dart';
import 'features/settings/presentation/mentora_settings_screen.dart';
import 'features/progress/presentation/progress_dashboard_screen.dart';
import 'features/content_packs/presentation/content_pack_installer_screen.dart';
import 'features/rag/presentation/screens/document_rag_ingestion_screen.dart';

import 'features/voice/screens/voice_debug_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppEnvironment.initialize();
  await BackgroundPrefetchService.initialize();

  CriticalBootstrap.configureDesktopSqlite();

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
          darkTheme: IDPTheme.darkTheme,
          themeMode: ThemeMode.light,
          locale: Locale(languageProvider.languageCode),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: AppShell(
            courseRepository: courseRepository,
            startupCoordinator: startupCoordinator,
            languageProvider: languageProvider,
          ),
          routes: {
            '/home': (context) => const MentoraHomeScreen(),
            '/practice': (context) => const MentoraPracticeScreen(),
            '/mastery': (context) => const MentoraMasteryScreen(),
            '/progress_dashboard': (context) => ProgressDashboardScreen(
                  courseRepository: courseRepository,
                  languageCode: languageProvider.languageCode,
                ),
            '/content_packs': (context) => const ContentPackInstallerScreen(),
            '/document_rag': (context) => const DocumentRagIngestionScreen(),
            '/subject_chapters': (context) => const SubjectChaptersScreen(),
            '/chapter_workspace': (context) => const ChapterLearningWorkspaceScreen(),
            '/settings': (context) => const MentoraSettingsScreen(),
            '/voice_overlay': (context) => const VoiceDebugScreen(),
          },
          onUnknownRoute: (settings) {
            debugPrint('[ROUTE] Unknown route requested: ${settings.name}');
            return MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('Page not found')),
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.search_off_outlined, size: 48),
                      const SizedBox(height: 12),
                      Text('No page for "${settings.name}".',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const MentoraHomeScreen()),
                            (route) => false,
                          );
                        },
                        child: const Text('Back to Home'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
