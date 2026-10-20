import 'package:flutter/material.dart';

// Re-export the rest of the IDP design tokens so any file importing
// idp_colors.dart also sees IDPSpacing, IDPRadius, and IDPTypography.
// This keeps the half-finished UI migration compiling without rewriting
// every import line across the math_studio and other feature screens.
export 'idp_typography.dart';
export 'idp_spacing.dart';

class IDPColors {
  // Brand - from Stitch Design System
  static const Color primary = Color(0xFF3F51B5); // Deep Indigo
  static const Color primaryLight = Color(0xFF7986CB); // Lighter shade (approximate)
  static const Color primaryDark = Color(0xFF303F9F); // Darker shade (approximate)
  
  static const Color secondary = Color(0xFF10B981); // Emerald Green
  static const Color secondaryLight = Color(0xFF34D399); // Lighter shade (approximate)

  // Surface & Background
  static const Color background = Color(0xFFF8FAFC); // Base Layer Light
  static const Color surface = Color(0xFFFFFFFF); // Cards Light
  static const Color backgroundDark = Color(0xFF0F172A); // Base Layer Dark
  static const Color surfaceDark = Color(0xFF1E293B); // Cards Dark
  static const Color surfaceVariant = Color(0xFFF1F5F9); // Tonal Layer
  static const Color surfaceVariantDark = Color(0xFF334155); // Tonal Layer Dark
  static const Color textOnDark = Color(0xFFF1F5F9); // Primary text on dark
  static const Color borderDark = Color(0xFF334155); // Borders on dark

  // Text
  static const Color textPrimary = Color(0xFF1E293B);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textHint = Color(0xFF94A3B8);

  // Semantic
  static const Color success = Color(0xFF10B981);
  static const Color successLight = Color(0xFFDCFCE7);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFEF4444);
  static const Color errorLight = Color(0xFFFEE2E2);

  // Material 3 / Stitch specific additions
  static const Color primaryContainer = Color(0xFFE0E7FF);
  static const Color onPrimaryContainer = Color(0xFF312E81);
  static const Color secondaryContainer = Color(0xFFD1FAE5);
  static const Color onSecondaryContainer = Color(0xFF064E3B);
  static const Color surfaceContainerHigh = Color(0xFFE2E8F0);
  static const Color surfaceContainerHighest = Color(0xFFCBD5E1);
  static const Color outlineVariant = Color(0xFFCBD5E1);
  static const Color primaryFixed = Color(0xFFE0E7FF);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onError = Color(0xFFFFFFFF);
  
  // New Missing Colors
  static const Color onSurface = Color(0xFF1E293B);
  static const Color onSurfaceVariant = Color(0xFF64748B);
  static const Color surfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color surfaceContainerLow = Color(0xFFF8FAFC);
  static const Color secondaryFixedDim = Color(0xFF34D399);
  
  static const Color tertiary = Color(0xFFF59E0B);
  static const Color tertiaryFixed = Color(0xFFFEF3C7);
  static const Color onTertiaryFixedVariant = Color(0xFF92400E);
  // Missing
  static const Color onBackground = Color(0xFF0F172A);
  static const Color surfaceContainer = Color(0xFFF1F5F9);
  
  // Borders & Dividers
  static const Color border = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFF1F5F9);

  // Material 3 outline token (border/divider tone). Used by widgets that
  // follow M3's `outline` naming. Equivalent to `outlineVariant` here since
  // the design system does not define a separate stronger outline.
  static const Color outline = outlineVariant;

  // Material 3 error container tokens.
  static const Color errorContainer = errorLight;
  static const Color onErrorContainer = Color(0xFF7F1D1D);

  // Material 3 tertiary container tokens.
  static const Color tertiaryContainer = tertiaryFixed;
  static const Color onTertiaryContainer = onTertiaryFixedVariant;
  static const Color tertiaryFixedDim = Color(0xFFFBBF24);

  // Subject Specific Colors (Keeping original if they exist, but maybe aligning them later)
  static Color getSubjectColor(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('math')) return const Color(0xFF6366F1);
    if (lower.contains('science')) return const Color(0xFF0D9488);
    if (lower.contains('english')) return const Color(0xFFD97706);
    if (lower.contains('kannada')) return const Color(0xFFDC2626);
    if (lower.contains('social')) return const Color(0xFF8B5CF6);
    return primary;
  }
}
