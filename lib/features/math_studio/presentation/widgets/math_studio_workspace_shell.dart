import 'package:flutter/material.dart';

import '../../../../core/theme/idp_colors.dart';
import '../../../home/presentation/mentora_home_screen.dart';

class MathStudioWorkspaceShell extends StatelessWidget {
  final String title;
  final Color accentColor;
  final List<Widget> children;
  final List<Widget> actions;
  final double maxContentWidth;

  const MathStudioWorkspaceShell({
    super.key,
    required this.title,
    required this.accentColor,
    required this.children,
    this.actions = const [],
    this.maxContentWidth = 960,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;

    return Scaffold(
      backgroundColor: IDPColors.background,
      appBar: AppBar(
        title: Text(title, style: IDPTypography.titleMedium.copyWith(color: accentColor)),
        backgroundColor: IDPColors.surface.withValues(alpha: 0.8),
        foregroundColor: accentColor,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: accentColor),
        shape: Border(bottom: BorderSide(color: IDPColors.outlineVariant.withValues(alpha: 0.5))),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded),
            tooltip: 'Home Dashboard',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MentoraHomeScreen(initialTabIndex: 0)),
                (route) => false,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.functions_rounded),
            tooltip: 'Math Studio',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MentoraHomeScreen(initialTabIndex: 3)),
                (route) => false,
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MentoraHomeScreen(initialTabIndex: 4)),
                (route) => false,
              );
            },
          ),
          ...actions,
        ],
      ),
      body: SafeArea(
        child: Scrollbar(
          thumbVisibility: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              24 + bottomPadding + bottomInset,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
