import 'dart:async';

class ConceptNode {
  final String conceptId;
  final String name;
  final String subject;
  final int grade;
  final String chapterId;
  final String difficulty;
  final String summary;
  final List<String> learningObjectives;

  ConceptNode({
    required this.conceptId,
    required this.name,
    required this.subject,
    required this.grade,
    required this.chapterId,
    required this.difficulty,
    required this.summary,
    required this.learningObjectives,
  });

  factory ConceptNode.fromJson(Map<String, dynamic> json) {
    return ConceptNode(
      conceptId: json['concept_id'] ?? '',
      name: json['name'] ?? '',
      subject: json['subject'] ?? 'Physics',
      grade: json['grade'] ?? 11,
      chapterId: json['chapter_id'] ?? '',
      difficulty: json['difficulty'] ?? 'intermediate',
      summary: json['summary'] ?? '',
      learningObjectives: List<String>.from(json['learning_objectives'] ?? []),
    );
  }
}

class ConceptEdge {
  final String sourceConceptId;
  final String targetConceptId;
  final String relationType;
  final double weight;

  ConceptEdge({
    required this.sourceConceptId,
    required this.targetConceptId,
    this.relationType = 'PREREQUISITE',
    this.weight = 1.0,
  });
}

class KnowledgeGapAnalysis {
  final String targetConceptId;
  final String targetConceptName;
  final List<ConceptNode> missingPrerequisites;
  final String remediationStrategy;
  final double readinessScore; // 0.0 to 1.0

  KnowledgeGapAnalysis({
    required this.targetConceptId,
    required this.targetConceptName,
    required this.missingPrerequisites,
    required this.remediationStrategy,
    required this.readinessScore,
  });
}

class KnowledgeGapResolver {
  final Map<String, ConceptNode> _nodes = {};
  final List<ConceptEdge> _edges = [];
  final Set<String> _masteredConceptIds = {};

  KnowledgeGapResolver();

  /// Loads concept nodes and dependency edges into the graph engine.
  void loadGraphData(List<ConceptNode> nodes, List<ConceptEdge> edges) {
    _nodes.clear();
    for (final node in nodes) {
      _nodes[node.conceptId] = node;
    }
    _edges.clear();
    _edges.addAll(edges);
  }

  /// Records a concept as mastered by the student.
  void markConceptMastered(String conceptId) {
    _masteredConceptIds.add(conceptId);
  }

  /// Evaluates readiness for a target concept and identifies prerequisite knowledge gaps.
  KnowledgeGapAnalysis analyzeKnowledgeGap(String targetConceptId) {
    final targetNode = _nodes[targetConceptId] ??
        ConceptNode(
          conceptId: targetConceptId,
          name: targetConceptId.replaceAll('_', ' ').toUpperCase(),
          subject: 'Physics',
          grade: 11,
          chapterId: 'class_11_physics_ch1',
          difficulty: 'intermediate',
          summary: 'Target concept subject node',
          learningObjectives: [],
        );

    // Find direct and indirect prerequisites (sources where target is the destination)
    final directPrereqIds = _edges
        .where((e) => e.targetConceptId == targetConceptId && e.relationType == 'PREREQUISITE')
        .map((e) => e.sourceConceptId)
        .toList();

    final List<ConceptNode> missingPrereqs = [];

    for (final prereqId in directPrereqIds) {
      if (!_masteredConceptIds.contains(prereqId)) {
        if (_nodes.containsKey(prereqId)) {
          missingPrereqs.add(_nodes[prereqId]!);
        } else {
          missingPrereqs.add(
            ConceptNode(
              conceptId: prereqId,
              name: prereqId.replaceAll('_', ' ').toUpperCase(),
              subject: targetNode.subject,
              grade: targetNode.grade,
              chapterId: targetNode.chapterId,
              difficulty: 'basic',
              summary: 'Prerequisite foundational topic',
              learningObjectives: ['Prerequisite mastery'],
            ),
          );
        }
      }
    }

    final totalPrereqs = directPrereqIds.length;
    final masteredPrereqs = totalPrereqs - missingPrereqs.length;
    final readiness = totalPrereqs == 0 ? 1.0 : (masteredPrereqs / totalPrereqs);

    String strategy;
    if (missingPrereqs.isEmpty) {
      strategy = 'Student has all prerequisite mastery. Ready to proceed with ${targetNode.name}.';
    } else {
      final names = missingPrereqs.map((m) => m.name).join(', ');
      strategy = 'Prerequisite gap detected! Review the following concepts before proceeding: $names.';
    }

    return KnowledgeGapAnalysis(
      targetConceptId: targetConceptId,
      targetConceptName: targetNode.name,
      missingPrerequisites: missingPrereqs,
      remediationStrategy: strategy,
      readinessScore: readiness,
    );
  }
}
