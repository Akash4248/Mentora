import 'sensor_type.dart';

/// Defines an approved physical science experiment that a student can conduct safely.
class LabExperimentDefinition {
  const LabExperimentDefinition({
    required this.id,
    required this.title,
    required this.subject,
    required this.topic,
    required this.description,
    required this.safetyInstructions,
    required this.setupSteps,
    required this.requiredSensors,
    this.maxDuration = const Duration(seconds: 30),
    this.maxSamples = 1000,
    this.targetMetrics = const [],
    this.theoreticalBackground = '',
  });

  final String id;
  final String title;
  final String subject;
  final String topic;
  final String description;
  final List<String> safetyInstructions;
  final List<String> setupSteps;
  final List<SensorType> requiredSensors;
  final Duration maxDuration;
  final int maxSamples;
  final List<String> targetMetrics;
  final String theoreticalBackground;
}

/// Catalog of pre-approved NCERT physical experiments with safety reviews.
abstract final class LabExperimentCatalog {
  /// Incline Plane & Static Friction Experiment.
  /// Phone rests securely on an inclined board or notebook to measure tilt angle and static friction.
  static const inclineFriction = LabExperimentDefinition(
    id: 'exp_incline_friction',
    title: 'Incline Plane & Static Friction Experiment',
    subject: 'Physics',
    topic: 'Laws of Motion — Friction & Incline',
    description:
        'Measure the angle of an inclined plane using the accelerometer to calculate the normal force ratio and the coefficient of static friction at impending slip.',
    safetyInstructions: [
      'Do not slide or drop the phone down the incline.',
      'Place the phone securely flat on the board or book.',
      'If testing friction of an object, place the object on a non-slip board next to or near the phone, or place a light coin/eraser on the phone screen protector.',
      'Ensure a soft surface or cushion at the bottom of the incline.',
    ],
    setupSteps: [
      'Place a sturdy book or board on a flat horizontal table.',
      'Place your phone flat on the board with the screen facing up.',
      'Tap "Calibrate Baseline" while the board is completely flat.',
      'Slowly tilt the board until the object just begins to slide (angle of repose).',
      'Hold the board steady and tap "Start Recording" for 3 seconds.',
      'Tap "Stop & Analyze" to compute the angle, normal force fraction, and static friction coefficient μs.',
    ],
    requiredSensors: [SensorType.accelerometer],
    maxDuration: Duration(seconds: 30),
    maxSamples: 1000,
    targetMetrics: [
      'tilt_angle_deg',
      'static_friction_coeff',
      'normal_force_ratio',
      'parallel_force_ratio',
    ],
    theoreticalBackground:
        'When an object rests on an incline of angle θ in static equilibrium: '
        'Normal force N = mg cos(θ). Downward parallel force F∥ = mg sin(θ). '
        'At impending slip, limiting static friction fs = μs N = mg sin(θ), therefore μs = tan(θ).',
  );

  /// Baseline Gravity & Rest Calibration Experiment.
  static const restGravity = LabExperimentDefinition(
    id: 'exp_rest_gravity',
    title: 'Gravitational Acceleration Calibration',
    subject: 'Physics',
    topic: 'Gravitation — Local Earth Field',
    description:
        'Place the phone completely flat on a table to measure the local gravitational acceleration vector and sensor noise floor.',
    safetyInstructions: [
      'Keep the phone stationary on a stable table away from vibrations.',
      'Do not move or bump the table during sampling.',
    ],
    setupSteps: [
      'Place the phone flat face-up on a stable desk or floor.',
      'Ensure the phone is not resting on cords or uneven surfaces.',
      'Tap "Start Recording" and leave the phone untouched for 5 seconds.',
      'Tap "Stop & Analyze" to calculate observed gravity g, RMS noise floor, and bias.',
    ],
    requiredSensors: [SensorType.accelerometer],
    maxDuration: Duration(seconds: 15),
    maxSamples: 500,
    targetMetrics: [
      'observed_gravity_mps2',
      'noise_rms_mps2',
      'sensor_bias_z_mps2',
    ],
    theoreticalBackground:
        'A stationary accelerometer on Earth observes an upward normal contact force of 1g ≈ 9.8 m/s² along the vertical axis due to Einstein’s equivalence principle.',
  );

  static final List<LabExperimentDefinition> all = [
    inclineFriction,
    restGravity,
  ];

  static LabExperimentDefinition? getById(String id) {
    for (final exp in all) {
      if (exp.id == id) return exp;
    }
    return null;
  }
}
