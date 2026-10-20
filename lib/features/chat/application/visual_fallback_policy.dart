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
    if (clean.contains('some simulation') ||
        clean.contains('any simulation') ||
        clean == 'show simulation' ||
        clean == 'show me a simulation' ||
        clean.contains('anyway show me some simulation') ||
        clean.contains('show me some simulation')) {
      return const VisualIntent(
        type: VisualType.simulationLauncher,
        scenario: 'phet-bending-light',
        inputs: {'simulation_id': 'phet-bending-light'},
        title: 'Bending Light & Optics Simulation',
        description: 'Explore refraction, reflection, and Snell’s law interactively with PhET.',
      );
    }

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
    if (clean.contains('pendulum') ||
        clean.contains('oscillation') ||
        clean.contains('period of pendulum') ||
        (clean.contains('bob') && clean.contains('string'))) {
      return const VisualIntent(
        type: VisualType.motionTrajectory,
        scenario: 'projectile',
        inputs: {
          'launch_velocity_mps': 10.0,
          'launch_angle_deg': 45.0,
          'gravity_mps2': 9.8,
        },
        title: 'Interactive Pendulum & Motion Lab',
        description: 'Adjust length (L) and gravitational acceleration (g) in real-time.',
      );
    }

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

    // 3. Optics ray diagram matching
    if (clean.contains('concave mirror') ||
        clean.contains('convex mirror') ||
        clean.contains('convex lens') ||
        clean.contains('concave lens') ||
        clean.contains('ray diagram') ||
        clean.contains('visualization of rays') ||
        clean.contains('diagram of rays') ||
        clean.contains('show rays') ||
        clean.contains('light rays') ||
        clean.contains('ray optics') ||
        clean.contains('mirror formula') ||
        clean.contains('lens formula') ||
        (clean.contains('ray') && (clean.contains('visual') || clean.contains('show') || clean.contains('draw') || clean.contains('diagram')))) {
      final isLens = clean.contains('lens');
      final isConvex = clean.contains('convex');
      final scenario = isLens
          ? (isConvex ? 'convex_lens' : 'concave_lens')
          : (clean.contains('convex') ? 'convex_mirror' : 'concave_mirror');

      return VisualIntent(
        type: VisualType.opticsRayDiagram,
        scenario: scenario,
        inputs: {
          'focal_length_cm': 10.0,
          'object_distance_cm': 15.0,
          'object_height_cm': 3.0,
        },
        title: isLens ? 'Thin Lens Ray Diagram' : 'Spherical Mirror Ray Diagram',
        description: 'Ray tracing showing focal point, image location, and magnification.',
      );
    }

    // 4. Sensor Lab intent matching
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

    // 5. Geometry construction matching
    if (clean.contains('pythagor') ||
        clean.contains('right triangle') ||
        clean.contains('hypotenuse') ||
        clean.contains('right angled')) {
      return const VisualIntent(
        type: VisualType.geometryConstruction,
        scenario: 'right_triangle',
        inputs: {'base': 4.0, 'height': 3.0},
        title: 'Right Triangle & Pythagoras Theorem',
        description: 'Interactive geometry showing perpendicular sides, hypotenuse, and right-angle marker.',
      );
    }

    if (clean.contains('circle tangent') ||
        clean.contains('tangents to a circle') ||
        clean.contains('tangents from external point')) {
      return const VisualIntent(
        type: VisualType.geometryConstruction,
        scenario: 'circle_tangents',
        inputs: {'radius': 3.0, 'distance': 6.0},
        title: 'Tangents to a Circle from External Point',
        description: 'Proves that tangents drawn from an external point to a circle are equal in length.',
      );
    }

    if (clean.contains('parallel lines') ||
        clean.contains('transversal') ||
        clean.contains('alternate interior angles')) {
      return const VisualIntent(
        type: VisualType.geometryConstruction,
        scenario: 'parallel_transversal',
        inputs: {'angle': 45.0},
        title: 'Parallel Lines Cut by a Transversal',
        description: 'Shows alternate interior, corresponding, and supplementary angle pairs.',
      );
    }

    // 6. Circuit schematic matching
    if (clean.contains('kirchhoff') ||
        clean.contains('kirchoff') ||
        clean.contains('kcl') ||
        clean.contains('kvl')) {
      return const VisualIntent(
        type: VisualType.circuitSchematic,
        scenario: 'series_circuit',
        inputs: {'voltage': 12.0, 'resistances': [10.0, 20.0]},
        title: "Kirchhoff's Laws & Circuit Loop",
        description: 'Demonstrating KCL (current conservation at junctions) and KVL (voltage drop around closed loops).',
      );
    }

    if (clean.contains('series circuit') ||
        clean.contains('resistors in series') ||
        clean.contains('series resistance')) {
      return const VisualIntent(
        type: VisualType.circuitSchematic,
        scenario: 'series_circuit',
        inputs: {'voltage': 12.0, 'resistances': [10.0, 20.0]},
        title: 'Series Resistor Network',
        description: 'Interactive DC circuit showing Req = R1 + R2 and uniform current flow.',
      );
    }

    if (clean.contains('parallel circuit') ||
        clean.contains('resistors in parallel') ||
        clean.contains('parallel resistance')) {
      return const VisualIntent(
        type: VisualType.circuitSchematic,
        scenario: 'parallel_circuit',
        inputs: {'voltage': 12.0, 'resistances': [10.0, 10.0]},
        title: 'Parallel Resistor Network',
        description: 'Interactive DC circuit showing 1/Req = 1/R1 + 1/R2 and branch currents.',
      );
    }

    if (clean.contains('circuit') ||
        clean.contains("ohm's law") ||
        clean.contains('electric current') ||
        clean.contains('battery and bulb')) {
      return const VisualIntent(
        type: VisualType.circuitSchematic,
        scenario: 'simple_circuit',
        inputs: {'voltage': 12.0, 'resistances': [20.0]},
        title: "Ohm's Law DC Circuit",
        description: 'Interactive circuit demonstrating V = IR, switch toggle, and bulb brightness.',
      );
    }

    return null;
  }
}
