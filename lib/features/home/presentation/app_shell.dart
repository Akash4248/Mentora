import 'package:flutter/material.dart';

import '../../../bootstrap/background_bootstrap.dart';
import '../../../bootstrap/optional_bootstrap.dart';
import '../../../bootstrap/startup_coordinator.dart';
import '../../course/data/local/course_repository.dart';
import '../../language/providers/language_provider.dart';
import '../../onboarding/presentation/grade_selection_screen.dart';
import 'hero_page.dart';
import 'mentora_home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum _AppEntry { loading, intro, onboarding, dashboard }

/// App shell that resolves the one-time intro and persisted onboarding state.
class AppShell extends StatefulWidget {
  const AppShell({
    required this.courseRepository,
    required this.startupCoordinator,
    required this.languageProvider,
    super.key,
  });

  final CourseRepository courseRepository;
  final StartupCoordinator startupCoordinator;
  final LanguageProvider languageProvider;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _introSeenKey = 'app_intro_seen_v1';

  _AppEntry _entry = _AppEntry.loading;
  late final BackgroundBootstrap _backgroundBootstrap;
  late final OptionalBootstrap _optionalBootstrap;

  @override
  void initState() {
    super.initState();
    _backgroundBootstrap = BackgroundBootstrap(
      coordinator: widget.startupCoordinator,
      courseRepository: widget.courseRepository,
    );
    _optionalBootstrap = OptionalBootstrap(
      coordinator: widget.startupCoordinator,
    );
    _resolveEntry();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _backgroundBootstrap.start();
      _optionalBootstrap.start();
    });
  }

  Future<void> _resolveEntry() async {
    final prefs = await SharedPreferences.getInstance();
    final grade = prefs.getInt('selected_grade');
    final introSeen = prefs.getBool(_introSeenKey) ?? (grade != null);

    if (introSeen && !(prefs.getBool(_introSeenKey) ?? false)) {
      await prefs.setBool(_introSeenKey, true);
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _entry = !introSeen
          ? _AppEntry.intro
          : grade == null
          ? _AppEntry.onboarding
          : _AppEntry.dashboard;
    });
  }

  Future<void> _onGetStarted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_introSeenKey, true);
    final grade = prefs.getInt('selected_grade');

    if (!mounted) {
      return;
    }
    setState(() {
      _entry = grade == null ? _AppEntry.onboarding : _AppEntry.dashboard;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.startupCoordinator,
      builder: (context, _) {
        return switch (_entry) {
          _AppEntry.loading => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          _AppEntry.intro => HeroPage(onGetStarted: _onGetStarted),
          _AppEntry.onboarding => const GradeSelectionScreen(),
          _AppEntry.dashboard => const MentoraHomeScreen(),
        };
      },
    );
  }
}
