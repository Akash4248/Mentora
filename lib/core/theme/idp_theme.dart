import 'package:flutter/material.dart';
import 'idp_colors.dart';
import 'idp_typography.dart';
import 'idp_spacing.dart';

export 'idp_colors.dart';
export 'idp_typography.dart';
export 'idp_spacing.dart';

class IDPTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: IDPColors.primary,
        primary: IDPColors.primary,
        secondary: IDPColors.secondary,
        surface: IDPColors.background, // Base Layer
        surfaceContainer: IDPColors.surface, // Cards
        error: IDPColors.error,
        background: IDPColors.background,
      ),
      scaffoldBackgroundColor: IDPColors.background,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white.withValues(alpha: 0.8), // Glassmorphism hint
        foregroundColor: IDPColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: IDPTypography.titleMd,
      ),
      cardTheme: CardThemeData(
        color: IDPColors.surface,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.04), // 0px 4px 20px rgba(0, 0, 0, 0.04)
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IDPRadius.md), // 24px
          side: const BorderSide(color: IDPColors.border, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: IDPColors.primary,
          foregroundColor: Colors.white,
          elevation: 2, // high-elevation shadow
          padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.lg, vertical: IDPSpacing.md),
          minimumSize: const Size(48, 48), // Touch target
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IDPRadius.pill)),
          textStyle: IDPTypography.labelMd,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: IDPColors.primary,
          side: const BorderSide(color: IDPColors.primary, width: 2), // 2px border of primary
          padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.lg, vertical: IDPSpacing.md),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IDPRadius.pill)),
          textStyle: IDPTypography.labelMd,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: IDPColors.textPrimary, // Ghost style
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IDPRadius.pill)),
          textStyle: IDPTypography.labelMd,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), // 12px corner radius
          borderSide: const BorderSide(color: IDPColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: IDPColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: IDPColors.secondary, width: 2), // Thicken and Electric Blue
        ),
        labelStyle: IDPTypography.labelMd,
        hintStyle: IDPTypography.caption,
      ),
      dividerTheme: const DividerThemeData(
        color: IDPColors.divider,
        thickness: 1,
        space: IDPSpacing.lg,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: IDPColors.secondary, // Emerald Green
        linearTrackColor: IDPColors.surfaceVariant,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: IDPColors.primary,
        brightness: Brightness.dark,
        primary: IDPColors.primaryLight,
        secondary: IDPColors.secondary,
        surface: IDPColors.surfaceDark,
        surfaceContainer: IDPColors.surfaceVariantDark,
        error: IDPColors.error,
        background: IDPColors.backgroundDark,
      ),
      scaffoldBackgroundColor: IDPColors.backgroundDark,
      appBarTheme: AppBarTheme(
        backgroundColor: IDPColors.backgroundDark.withValues(alpha: 0.85),
        foregroundColor: IDPColors.textOnDark,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: IDPTypography.titleMd.copyWith(color: IDPColors.textOnDark),
      ),
      cardTheme: CardThemeData(
        color: IDPColors.surfaceDark,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(IDPRadius.md),
          side: const BorderSide(color: IDPColors.borderDark, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: IDPColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.lg, vertical: IDPSpacing.md),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IDPRadius.pill)),
          textStyle: IDPTypography.labelMd,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: IDPColors.primaryLight,
          side: const BorderSide(color: IDPColors.primaryLight, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.lg, vertical: IDPSpacing.md),
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IDPRadius.pill)),
          textStyle: IDPTypography.labelMd,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: IDPColors.textOnDark,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IDPRadius.pill)),
          textStyle: IDPTypography.labelMd,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: IDPColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: IDPColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: IDPColors.secondary, width: 2),
        ),
        labelStyle: IDPTypography.labelMd.copyWith(color: IDPColors.textOnDark),
        hintStyle: IDPTypography.caption.copyWith(color: IDPColors.textHint),
      ),
      dividerTheme: const DividerThemeData(
        color: IDPColors.borderDark,
        thickness: 1,
        space: IDPSpacing.lg,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: IDPColors.secondary,
        linearTrackColor: IDPColors.surfaceVariantDark,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
