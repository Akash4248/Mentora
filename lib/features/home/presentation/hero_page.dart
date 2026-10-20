import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:mentora/l10n/app_localizations.dart';
import 'package:mentora/core/theme/idp_colors.dart';
import 'package:mentora/core/theme/idp_typography.dart';
import 'package:mentora/core/theme/idp_theme.dart';

/// Hero/Intro page for the Offline Tutor app - matching Stitch Design
class HeroPage extends StatefulWidget {
  const HeroPage({
    required this.onGetStarted,
    super.key,
  });

  final VoidCallback onGetStarted;

  @override
  State<HeroPage> createState() => _HeroPageState();
}

class _HeroPageState extends State<HeroPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    // Spring-like slide up
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animationController, 
        curve: const SpringCurve(a: 0.15, w: 19.4),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: IDPColors.background,
      body: Stack(
        children: [
          // Animated Background Elements (Gradient mesh)
          Positioned(
            top: -50,
            right: -50,
            child: _buildGlowingOrb(IDPColors.primary.withValues(alpha: 0.1), 300),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: _buildGlowingOrb(IDPColors.secondary.withValues(alpha: 0.05), 250),
          ),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.lg, vertical: IDPSpacing.xxl),
                child: SlideTransition(
                  position: _slideAnimation,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Logo/Icon
                        Container(
                          width: 80,
                          height: 80,
                          decoration: const BoxDecoration(
                            color: IDPColors.primaryLight,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.school,
                            size: 40,
                            color: IDPColors.primary,
                          ),
                        ),
                        const SizedBox(height: IDPSpacing.lg),

                        // Titles
                        Text(
                          "OfflineTutor", // In production use l10n.offlineTutor if desired, but Stitch has "OfflineTutor"
                          style: IDPTypography.displayLg.copyWith(color: IDPColors.primary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: IDPSpacing.sm),
                        Text(
                          "Your Personal AI Tutor",
                          style: IDPTypography.headlineLgMobile.copyWith(color: IDPColors.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: IDPSpacing.md),
                        Text(
                          "Intelligent, accessible learning that stays with you, even when the world goes offline.",
                          style: IDPTypography.bodyLg.copyWith(color: IDPColors.textPrimary),
                          textAlign: TextAlign.center,
                        ),
                        
                        const SizedBox(height: IDPSpacing.xxl),

                        // Action Cards Container (Bento-lite Layout)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth > 600) {
                              return Row(
                                children: [
                                  Expanded(child: _buildLoginCard(
                                    title: "Student Login",
                                    description: "Access your courses and start learning with your AI mentor.",
                                    icon: Icons.face,
                                    color: IDPColors.primary,
                                    lightColor: IDPColors.primaryLight,
                                    onTap: widget.onGetStarted,
                                  )),
                                  const SizedBox(width: IDPSpacing.lg),
                                  Expanded(child: _buildLoginCard(
                                    title: "Teacher Login",
                                    description: "Manage your curriculum and track student progress analytics.",
                                    icon: Icons.co_present,
                                    color: IDPColors.secondary,
                                    lightColor: IDPColors.secondaryLight,
                                    onTap: widget.onGetStarted,
                                  )),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                _buildLoginCard(
                                  title: "Student Login",
                                  description: "Access your courses and start learning with your AI mentor.",
                                  icon: Icons.face,
                                  color: IDPColors.primary,
                                  lightColor: IDPColors.primaryLight,
                                  onTap: widget.onGetStarted,
                                ),
                                const SizedBox(height: IDPSpacing.lg),
                                _buildLoginCard(
                                  title: "Teacher Login",
                                  description: "Manage your curriculum and track student progress analytics.",
                                  icon: Icons.co_present,
                                  color: IDPColors.secondary,
                                  lightColor: IDPColors.secondaryLight,
                                  onTap: widget.onGetStarted,
                                ),
                              ],
                            );
                          }
                        ),

                        const SizedBox(height: IDPSpacing.xxl),

                        // Try Guest Mode
                        TextButton(
                          onPressed: widget.onGetStarted,
                          style: TextButton.styleFrom(
                            foregroundColor: IDPColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.lg, vertical: IDPSpacing.sm),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("Try Guest Mode", style: TextStyle(fontWeight: FontWeight.bold)),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward, size: 16),
                            ],
                          ),
                        ),
                        
                        const SizedBox(height: IDPSpacing.xl),

                        // Footer badges
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildBadge(Icons.verified, "AI Powered"),
                            const SizedBox(width: IDPSpacing.lg),
                            _buildBadge(Icons.signal_cellular_connected_no_internet_4_bar, "Offline First"),
                            const SizedBox(width: IDPSpacing.lg),
                            _buildBadge(Icons.security, "Private"),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowingOrb(Color color, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color,
            blurRadius: size / 2,
            spreadRadius: size / 4,
          ),
        ],
      ),
    );
  }

  Widget _buildLoginCard({
    required String title,
    required String description,
    required IconData icon,
    required Color color,
    required Color lightColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(IDPRadius.md),
      child: Container(
        padding: const EdgeInsets.all(IDPSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(IDPRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: lightColor.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: IDPSpacing.xl),
            Text(title, style: IDPTypography.titleMd),
            const SizedBox(height: IDPSpacing.xs),
            Text(description, style: IDPTypography.labelMd.copyWith(color: IDPColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(IconData icon, String text) {
    return Opacity(
      opacity: 0.4,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: IDPColors.textPrimary),
          const SizedBox(width: IDPSpacing.xs),
          Text(text, style: IDPTypography.caption.copyWith(color: IDPColors.textPrimary)),
        ],
      ),
    );
  }
}

class SpringCurve extends Curve {
  const SpringCurve({
    this.a = 0.15,
    this.w = 19.4,
  });
  final double a;
  final double w;

  @override
  double transformInternal(double t) {
    return -(math.pow(math.e, -t / a) * math.cos(t * w)) + 1;
  }
}
