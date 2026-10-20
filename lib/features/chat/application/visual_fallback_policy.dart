import '../domain/visual_intent.dart';

/// Fallback policy and deterministic catalog matcher for Mentora 2.0.
///
/// Ensures that:
/// 1. Malformed visual blocks or unsupported types degrade gracefully to clean prose
///    without crashing or obstructing the student experience.
/// 2. If a student specifically inquires about a simulation or physical trajectory and the
///    model omits the visual block, a verified artifact is attached deterministically.
/// 3. Duplicate artifacts are prevented so twin cards never appear.
final class VisualFallbackPolicy {
  const VisualFallbackPolicy();

  /// Deterministically attaches a visual intent from the catalog when the model
  /// omitted one, provided the query contains strong verified topic cues.
  VisualIntent? matchDeterministicFallback({
    required String question,
    required List<VisualIntent> existingIntents,
  }) {
    // If the model already declared an artifact of this type, do not duplicate
    if (existingIntents.isNotEmpty) {
      return null;
    }

    final clean = question.toLowerCase().trim();

    // 1. PhET Simulation Catalog keyword matching
    if (clean.contains('bending light') || clean.contains('refraction sim') || clean.contains('light bending')) {
      return const VisualIntent(
        type: VisualType.simulationLauncher,
        scenario: 'phet-bending-light',
        inputs: {'simulation_id': 'phet-bending-light'},
        title: 'Bending Light Simulation',
        description: 'Explore refraction and Snell’s law with this interactive PhET simulation.',
      );
    }

    if (clean.contains('forces and motion') ||
        clean.contains('friction simulation') ||
        clean.contains('force sim') ||
        clean.contains('net force sim')) {
      return const VisualIntent(
        type: VisualType.simulationLauncher,
        scenario: 'phet-forces-motion',
        inputs: {'simulation_id': 'phet-forces-motion'},
        title: 'Forces and Motion Simulation',
        description: 'Explore friction, acceleration, and Newton’s laws interactively.',
      );
    }

    if (clean.contains('balancing chemical') || clean.contains('chemical equation sim')) {
      return const VisualIntent(
        type: VisualType.simulationLauncher,
        scenario: 'phet-balancing-chemical-equations',
        inputs: {'simulation_id': 'phet-balancing-chemical-equations'},
        title: 'Balancing Chemical Equations',
        description: 'Practice balancing reactions and conserving mass.',
      );
    }

    if (clean.contains('build an atom') || clean.contains('atom simulation')) {
      return const VisualIntent(
        type: VisualType.simulationLauncher,
        scenario: 'phet-build-an-atom',
        inputs: {'simulation_id': 'phet-build-an-atom'},
        title: 'Build an Atom Simulation',
        description: 'Combine protons, neutrons, and electrons to construct chemical elements.',
      );
    }

    if (clean.contains('fraction matcher') || clean.contains('fractions simulation')) {
      return const VisualIntent(
        type: VisualType.simulationLauncher,
        scenario: 'phet-fraction-matcher',
        inputs: {'simulation_id': 'phet-fraction-matcher'},
        title: 'Fraction Matcher',
        description: 'Explore numerical fractions and visual representations.',
      );
    }

    // 2. Trajectory motion intent matching
    if (clean.contains('trajectory of') ||
        clean.contains('toss a ball') ||
        clean.contains('ball thrown upward') ||
        clean.contains('vertical projectile')) {
      return const VisualIntent(
        type: VisualType.motionTrajectory,
        scenario: 'vertical_toss',
        inputs: {
          'initial_velocity_mps': 14.7,
          'gravity_mps2': 9.8,
          'initial_height_m': 0.0,
        },
        focus: {'kind': 'apex'},
        title: 'Vertical Motion Trajectory',
        description: 'Analytical trajectory showing apex height and velocity vectors.',
      );
    }

    // 3. Sensor Lab intent matching
    if (clean.contains('sensor lab') ||
        clean.contains('incline experiment') ||
        clean.contains('friction experiment') ||
        clean.contains('test friction with phone')) {
      return const VisualIntent(
        type: VisualType.labSetup,
        scenario: 'exp_incline_friction',
        inputs: {'experiment_id': 'exp_incline_friction'},
        title: 'Incline Plane & Static Friction Experiment',
        description: 'Measure the tilt angle and static friction coefficient safely with phone accelerometer.',
      );
    }

    return null;
  }
}
