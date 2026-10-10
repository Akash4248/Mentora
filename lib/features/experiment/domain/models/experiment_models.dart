import '../enums/experiment_enums.dart';

class ExperimentManifest {
  final String id;
  final String title;
  final String description;
  final String subject;
  final String grade;
  final String chapter;
  final String topic;
  final ExperimentDifficulty difficulty;
  final List<String> requiredSensors;
  final List<ExperimentExecutionMode> supportedModes;
  final List<ExperimentStep> steps;
  final List<ExperimentVisualization> visualizations;
  final int estimatedDurationMinutes;
  final bool supportsSimulation;
  final bool supportsSensorExecution;
  final bool supportsObservationMode;
  final DateTime createdAt;
  final DateTime updatedAt;

  ExperimentManifest({
    required this.id,
    required this.title,
    required this.description,
    required this.subject,
    required this.grade,
    required this.chapter,
    required this.topic,
    required this.difficulty,
    required this.requiredSensors,
    required this.supportedModes,
    required this.steps,
    required this.visualizations,
    required this.estimatedDurationMinutes,
    required this.supportsSimulation,
    required this.supportsSensorExecution,
    required this.supportsObservationMode,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'subject': subject,
        'grade': grade,
        'chapter': chapter,
        'topic': topic,
        'difficulty': difficulty.name,
        'requiredSensors': requiredSensors,
        'steps': steps.map((s) => {'id': s.id, 'title': s.title, 'description': s.description, 'expectedOutcome': s.expectedOutcome, 'order': s.order}).toList(),
        'estimatedDurationMinutes': estimatedDurationMinutes,
      };
}

class ExperimentStep {
  final String id;
  final String title;
  final String description;
  final String expectedOutcome;
  final int order;

  ExperimentStep({
    required this.id,
    required this.title,
    required this.description,
    required this.expectedOutcome,
    required this.order,
  });
}

class ExperimentVariable {
  final String name;
  final String type;
  final dynamic defaultValue;
  final dynamic minValue;
  final dynamic maxValue;

  ExperimentVariable({
    required this.name,
    required this.type,
    this.defaultValue,
    this.minValue,
    this.maxValue,
  });
}

class ExperimentVisualization {
  final String type;
  final String title;
  final Map<String, dynamic> configuration;

  ExperimentVisualization({
    required this.type,
    required this.title,
    required this.configuration,
  });
}

class ExperimentRun {
  final String id;
  final String experimentId;
  final ExperimentExecutionMode mode;
  final DateTime startedAt;
  final DateTime? completedAt;
  final ExperimentStatus status;

  ExperimentRun({
    required this.id,
    required this.experimentId,
    required this.mode,
    required this.startedAt,
    this.completedAt,
    required this.status,
  });
}

class ExperimentResult {
  final String experimentId;
  final String runId;
  final Map<String, dynamic> measurements;
  final List<String> observations;
  final String conclusions;

  ExperimentResult({
    required this.experimentId,
    required this.runId,
    required this.measurements,
    required this.observations,
    required this.conclusions,
  });
}
