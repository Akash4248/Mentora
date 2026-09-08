import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tutor_app/features/tutor/application/knowledge_gap_resolver.dart';

void main() {
  group('KnowledgeGapResolver Tests', () {
    late KnowledgeGapResolver resolver;

    setUp(() {
      resolver = KnowledgeGapResolver();

      final nodes = [
        ConceptNode(
          conceptId: 'c_vectors',
          name: 'Vectors & Scalars',
          subject: 'Physics',
          grade: 11,
          chapterId: 'ch1',
          difficulty: 'basic',
          summary: 'Basics of vectors',
          learningObjectives: ['Vector addition'],
        ),
        ConceptNode(
          conceptId: 'c_kinematics',
          name: 'Kinematics in 2D',
          subject: 'Physics',
          grade: 11,
          chapterId: 'ch1',
          difficulty: 'intermediate',
          summary: 'Projectile motion',
          learningObjectives: ['2D motion'],
        ),
      ];

      final edges = [
        ConceptEdge(
          sourceConceptId: 'c_vectors',
          targetConceptId: 'c_kinematics',
          relationType: 'PREREQUISITE',
        ),
      ];

      resolver.loadGraphData(nodes, edges);
    });

    test('Detects missing prerequisite when student has not mastered it', () {
      final analysis = resolver.analyzeKnowledgeGap('c_kinematics');

      expect(analysis.targetConceptId, equals('c_kinematics'));
      expect(analysis.missingPrerequisites.length, equals(1));
      expect(analysis.missingPrerequisites.first.conceptId, equals('c_vectors'));
      expect(analysis.readinessScore, equals(0.0));
      expect(analysis.remediationStrategy, contains('Prerequisite gap detected'));
    });

    test('Reports 100% readiness when student masters prerequisite', () {
      resolver.markConceptMastered('c_vectors');
      final analysis = resolver.analyzeKnowledgeGap('c_kinematics');

      expect(analysis.missingPrerequisites, isEmpty);
      expect(analysis.readinessScore, equals(1.0));
      expect(analysis.remediationStrategy, contains('Student has all prerequisite mastery'));
    });
  });
}
