import 'package:flutter/material.dart';
import 'package:offline_tutor_app/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:offline_tutor_app/core/theme/idp_colors.dart';
import 'package:offline_tutor_app/core/theme/idp_theme.dart';
import 'package:offline_tutor_app/core/theme/idp_typography.dart';
import 'grade_sync_screen.dart';
import 'dart:ui';

class GradeSelectionScreen extends StatefulWidget {
  const GradeSelectionScreen({super.key});

  @override
  State<GradeSelectionScreen> createState() => _GradeSelectionScreenState();
}

class _GradeSelectionScreenState extends State<GradeSelectionScreen> {
  int? _selectedGrade;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: IDPColors.background,
      body: Stack(
        children: [
          // Decorative Background Background (like Stitch)
          Positioned(
            top: -50,
            right: -50,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                color: IDPColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 100, sigmaY: 100),
                child: const SizedBox(),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                color: IDPColors.secondary.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                child: const SizedBox(),
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    Expanded(
                      child: CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20.0,
                              vertical: 32.0,
                            ),
                            sliver: SliverList(
                              delegate: SliverChildListDelegate([
                                // Header Section
                                Center(
                                  child: Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      color: IDPColors.primaryContainer,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.school,
                                      color: IDPColors.onPrimaryContainer,
                                      size: 32,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  l10n.whatGradeAreYouStudying,
                                  textAlign: TextAlign.center,
                                  style: IDPTypography.headlineLg.copyWith(
                                    color: IDPColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  l10n.selectYourGradeDescription,
                                  textAlign: TextAlign.center,
                                  style: IDPTypography.bodyMd.copyWith(
                                    color: IDPColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: 32),

                                // Grades List
                                ...List.generate(12, (index) {
                                  final grade = index + 1;
                                  final isSelected = _selectedGrade == grade;
                                  
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12.0),
                                    child: _buildGradeCard(grade, isSelected, l10n),
                                  );
                                }),
                              ]),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Footer Action
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            IDPColors.background,
                            IDPColors.background.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              onPressed: (_selectedGrade == null || _isLoading)
                                  ? null
                                  : _saveAndContinue,
                              style: FilledButton.styleFrom(
                                backgroundColor: IDPColors.primaryContainer,
                                foregroundColor: IDPColors.onPrimaryContainer,
                                disabledBackgroundColor: IDPColors.surfaceContainerHigh,
                                disabledForegroundColor: IDPColors.textHint,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(IDPRadius.full),
                                ),
                                elevation: _selectedGrade != null ? 8 : 0,
                                shadowColor: IDPColors.primaryContainer.withValues(alpha: 0.5),
                              ),
                              child: _isLoading 
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: IDPColors.onPrimaryContainer,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        l10n.continueLabel,
                                        style: IDPTypography.labelMd.copyWith(
                                          fontSize: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward, size: 20),
                                    ],
                                  ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'You can change this later in settings.',
                            style: IDPTypography.caption.copyWith(
                              color: IDPColors.textHint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeCard(int grade, bool isSelected, AppLocalizations l10n) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: isSelected ? IDPColors.surface : IDPColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(IDPRadius.lg),
        border: Border.all(
          color: isSelected ? IDPColors.primary : Colors.transparent,
          width: 2,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: IDPColors.primary.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedGrade = grade;
            });
          },
          borderRadius: BorderRadius.circular(IDPRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Icon/Badge
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: IDPColors.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$grade',
                    style: IDPTypography.titleMd.copyWith(
                      color: IDPColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.gradeLabel(grade),
                        style: IDPTypography.titleMd.copyWith(
                          color: IDPColors.textPrimary,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Offline Curriculum',
                        style: IDPTypography.caption.copyWith(
                          color: IDPColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Check mark
                AnimatedOpacity(
                  opacity: isSelected ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: AnimatedScale(
                    scale: isSelected ? 1.0 : 0.5,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutBack,
                    child: const Icon(
                      Icons.check_circle,
                      color: IDPColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _saveAndContinue() async {
    if (_selectedGrade == null) return;
    
    setState(() {
      _isLoading = true;
    });

    final languageCode = Localizations.localeOf(context).languageCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_grade', _selectedGrade!);

    if (!mounted) return;
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => GradeSyncScreen(
          grade: _selectedGrade!,
          languageCode: languageCode,
        ),
      ),
    );
  }
}
