import '../domain/content_pack_models.dart';

class ContentPackPolicyService {
  const ContentPackPolicyService();

  List<RequiredContentPackRule> get defaultSchoolRules {
    final rules = <RequiredContentPackRule>[];

    void addRule({
      required String id,
      required String title,
      required String medium,
      required String subject,
      required int gradeMin,
      required int gradeMax,
      int minVersion = 1,
    }) {
      rules.add(
        RequiredContentPackRule(
          id: id,
          title: title,
          medium: medium,
          subject: subject,
          gradeMin: gradeMin,
          gradeMax: gradeMax,
          minVersion: minVersion,
          mandatory: true,
        ),
      );
    }

    for (final medium in const <String>['English Medium', 'Kannada Medium']) {
      addRule(
        id: 'math_${medium.startsWith('English') ? 'en' : 'kn'}_6_12',
        title:
            'Mathematics Grades 6-12 (${medium == 'English Medium' ? 'EN' : 'KN'})',
        medium: medium,
        subject: 'Mathematics',
        gradeMin: 6,
        gradeMax: 12,
      );
      addRule(
        id: 'science_${medium.startsWith('English') ? 'en' : 'kn'}_6_12',
        title:
            'Science Grades 6-12 (${medium == 'English Medium' ? 'EN' : 'KN'})',
        medium: medium,
        subject: 'Science',
        gradeMin: 6,
        gradeMax: 12,
      );
      addRule(
        id: 'social_${medium.startsWith('English') ? 'en' : 'kn'}_6_12',
        title:
            'Social Science Grades 6-12 (${medium == 'English Medium' ? 'EN' : 'KN'})',
        medium: medium,
        subject: 'Social Science',
        gradeMin: 6,
        gradeMax: 12,
      );
      addRule(
        id: 'english_${medium.startsWith('English') ? 'en' : 'kn'}_6_12',
        title:
            'English Grades 6-12 (${medium == 'English Medium' ? 'EN' : 'KN'})',
        medium: medium,
        subject: 'English',
        gradeMin: 6,
        gradeMax: 12,
      );
      addRule(
        id: 'kannada_${medium.startsWith('English') ? 'en' : 'kn'}_6_12',
        title:
            'Kannada Grades 6-12 (${medium == 'English Medium' ? 'EN' : 'KN'})',
        medium: medium,
        subject: 'Kannada',
        gradeMin: 6,
        gradeMax: 12,
      );
    }

    return rules;
  }

  ContentPackReadinessReport evaluate({
    required List<ContentPackManifest> installedPacks,
    List<RequiredContentPackRule>? rules,
  }) {
    final activeRules = rules ?? defaultSchoolRules;
    final statuses = <RequiredContentPackStatus>[];

    for (final rule in activeRules) {
      final matchingPacks = <ContentPackManifest>[];
      for (final pack in installedPacks) {
        if (!_isSubjectCompatible(pack.subject, rule.subject)) {
          continue;
        }
        if (!_isMediumCompatible(pack.medium, rule.medium)) {
          continue;
        }
        if (!_coversGrades(pack, rule)) {
          continue;
        }
        if (pack.version < rule.minVersion) {
          continue;
        }
        matchingPacks.add(pack);
      }

      statuses.add(
        RequiredContentPackStatus(rule: rule, matchingPacks: matchingPacks),
      );
    }

    return ContentPackReadinessReport(statuses: statuses);
  }

  bool _isSubjectCompatible(String packSubject, String requiredSubject) {
    final normalizedPack = _normalizeSubject(packSubject);
    final normalizedRequired = _normalizeSubject(requiredSubject);
    if (normalizedPack == 'all subjects') {
      return true;
    }
    return normalizedPack == normalizedRequired;
  }

  bool _isMediumCompatible(String packMedium, String requiredMedium) {
    final normalizedPack = packMedium.trim().toLowerCase();
    final normalizedRequired = requiredMedium.trim().toLowerCase();
    if (normalizedPack == 'mixed') {
      return true;
    }
    return normalizedPack == normalizedRequired;
  }

  bool _coversGrades(ContentPackManifest pack, RequiredContentPackRule rule) {
    return !(pack.gradeMax < rule.gradeMin || pack.gradeMin > rule.gradeMax);
  }

  String _normalizeSubject(String subject) {
    final lower = subject.trim().toLowerCase().replaceAll('_', ' ');
    if (lower == 'maths' || lower == 'mathematics') {
      return 'maths';
    }
    if (lower == 'science') {
      return 'science';
    }
    if (lower == 'english') {
      return 'english';
    }
    if (lower == 'kannada') {
      return 'kannada';
    }
    if (lower == 'social science' || lower == 'socialscience') {
      return 'social science';
    }
    return lower;
  }
}
