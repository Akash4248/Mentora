import '../../experiment/sensor_lab/domain/lab_experiment_definition.dart';
import '../domain/visual_intent.dart';
import 'circuit_engine.dart';
import 'geometry_engine.dart';
import 'kinematics_engine.dart';
import 'optics_engine.dart';
import 'visual_schema_registry.dart';

/// Resolved visual payload ready for rendering by the UI presentation layer.
sealed class ResolvedVisualPayload {
  const ResolvedVisualPayload({
    required this.intent,
  });

  final VisualIntent intent;
}

final class TrajectoryVisualPayload extends ResolvedVisualPayload {
  const TrajectoryVisualPayload({
    required super.intent,
    required this.trajectory,
  });

  final KinematicsTrajectoryResult trajectory;
}

final class SimulationVisualPayload extends ResolvedVisualPayload {
  const SimulationVisualPayload({
    required super.intent,
    required this.simulationId,
    required this.title,
    required this.subject,
    required this.localPath,
  });

  final String simulationId;
  final String title;
  final String subject;
  final String localPath;
}

final class StepsVisualPayload extends ResolvedVisualPayload {
  const StepsVisualPayload({
    required super.intent,
    required this.steps,
  });

  final List<Map<String, dynamic>> steps;
}

final class GraphVisualPayload extends ResolvedVisualPayload {
  const GraphVisualPayload({
    required super.intent,
    required this.formula,
  });

  final String formula;
}

final class LabSetupVisualPayload extends ResolvedVisualPayload {
  const LabSetupVisualPayload({
    required super.intent,
    required this.definition,
  });

  final LabExperimentDefinition definition;
}

final class OpticsVisualPayload extends ResolvedVisualPayload {
  const OpticsVisualPayload({
    required super.intent,
    required this.result,
  });

  final OpticsRayResult result;
}

final class GeometryVisualPayload extends ResolvedVisualPayload {
  const GeometryVisualPayload({
    required super.intent,
    required this.result,
  });

  final GeometryConstructionResult result;
}

final class CircuitVisualPayload extends ResolvedVisualPayload {
  const CircuitVisualPayload({
    required super.intent,
    required this.result,
  });

  final CircuitCalculationResult result;
}

final class FallbackTextVisualPayload extends ResolvedVisualPayload {
  const FallbackTextVisualPayload({
    required super.intent,
    required this.reason,
  });

  final String reason;
}

/// Resolves a [VisualIntent] into an executable, validated [ResolvedVisualPayload],
/// invoking deterministic domain engines ([KinematicsEngine]) for mathematical ground truth.
final class VisualResolver {
  const VisualResolver({
    VisualSchemaRegistry? schemaRegistry,
    KinematicsEngine? kinematicsEngine,
    OpticsEngine? opticsEngine,
    GeometryEngine? geometryEngine,
    CircuitEngine? circuitEngine,
    Map<String, Map<String, String>>? simulationCatalog,
  })  : _schemaRegistry = schemaRegistry ?? const VisualSchemaRegistry(),
        _kinematicsEngine = kinematicsEngine ?? const KinematicsEngine(),
        _opticsEngine = opticsEngine ?? const OpticsEngine(),
        _geometryEngine = geometryEngine ?? const GeometryEngine(),
        _circuitEngine = circuitEngine ?? const CircuitEngine(),
        _simulationCatalog = simulationCatalog ?? _defaultSimulationCatalog;

  final VisualSchemaRegistry _schemaRegistry;
  final KinematicsEngine _kinematicsEngine;
  final OpticsEngine _opticsEngine;
  final GeometryEngine _geometryEngine;
  final CircuitEngine _circuitEngine;
  final Map<String, Map<String, String>> _simulationCatalog;

  static const _defaultSimulationCatalog = {
    'phet-bending-light': {
      'title': 'Bending Light',
      'subject': 'Physics',
      'localPath': 'assets/phet/simulations/placeholder.html',
    },
    'phet-forces-motion': {
      'title': 'Forces and Motion: Basics',
      'subject': 'Physics',
      'localPath': 'assets/phet/simulations/placeholder.html',
    },
    'phet-balancing-chemical-equations': {
      'title': 'Balancing Chemical Equations',
      'subject': 'Chemistry',
      'localPath': 'assets/phet/simulations/placeholder.html',
    },
    'phet-build-an-atom': {
      'title': 'Build an Atom',
      'subject': 'Chemistry',
      'localPath': 'assets/phet/simulations/placeholder.html',
    },
    'phet-fraction-matcher': {
      'title': 'Fraction Matcher',
      'subject': 'Math',
      'localPath': 'assets/phet/simulations/placeholder.html',
    },
  };

  /// Resolves an incoming [VisualIntent] into a mathematically verified visual payload.
  ResolvedVisualPayload resolve(VisualIntent intent) {
    final validation = _schemaRegistry.validate(intent);
    if (!validation.isValid) {
      return FallbackTextVisualPayload(
        intent: intent,
        reason: validation.errors.join('; '),
      );
    }

    try {
      switch (intent.type) {
        case VisualType.motionTrajectory:
          return _resolveMotionTrajectory(intent);

        case VisualType.simulationLauncher:
          return _resolveSimulationLauncher(intent);

        case VisualType.stepsSolution:
          return _resolveStepsSolution(intent);

        case VisualType.mathFunctionGraph:
          return _resolveFunctionGraph(intent);

        case VisualType.labSetup:
          return _resolveLabSetup(intent);

        case VisualType.opticsRayDiagram:
          return _resolveOpticsRayDiagram(intent);

        case VisualType.geometryConstruction:
          return _resolveGeometryConstruction(intent);

        case VisualType.circuitSchematic:
          return _resolveCircuitSchematic(intent);

        case VisualType.physicsForceDiagram:
        case VisualType.conceptSequence:
        case VisualType.unknown:
          return FallbackTextVisualPayload(
            intent: intent,
            reason: 'Visual type ${intent.type.identifier} is deferred to future release.',
          );
      }
    } catch (e) {
      return FallbackTextVisualPayload(
        intent: intent,
        reason: 'Error calculating visual payload: $e',
      );
    }
  }

  TrajectoryVisualPayload _resolveMotionTrajectory(VisualIntent intent) {
    final inputs = intent.inputs;
    final scenario = intent.scenario.toLowerCase();

    final u = (inputs['initial_velocity_mps'] ??
            inputs['launch_velocity_mps'] ??
            inputs['u'] ??
            10.0 as num)
        .toDouble();
    final g = (inputs['gravity_mps2'] ?? inputs['g'] ?? 9.8 as num).toDouble();
    final h0 = (inputs['initial_height_m'] ?? 0.0 as num).toDouble();
    final mass = (inputs['mass_kg'] ?? inputs['m'] as num?)?.toDouble();

    final KinematicsTrajectoryResult trajectory;
    if (scenario.contains('projectile') || inputs.containsKey('launch_angle_deg')) {
      final angle = (inputs['launch_angle_deg'] ?? 45.0 as num).toDouble();
      trajectory = _kinematicsEngine.computeProjectile2D(
        launchVelocityMps: u,
        launchAngleDegrees: angle,
        gravityMps2: g,
        initialHeightMeters: h0,
        massKg: mass,
      );
    } else {
      trajectory = _kinematicsEngine.computeVerticalToss(
        initialVelocityMps: u,
        gravityMps2: g,
        initialHeightMeters: h0,
        massKg: mass,
      );
    }

    return TrajectoryVisualPayload(
      intent: intent,
      trajectory: trajectory,
    );
  }

  ResolvedVisualPayload _resolveSimulationLauncher(VisualIntent intent) {
    final inputs = intent.inputs;
    final simId = (inputs['simulation_id'] ?? inputs['id'] ?? intent.scenario).toString().trim();

    final metadata = _simulationCatalog[simId];
    if (metadata != null) {
      return SimulationVisualPayload(
        intent: intent,
        simulationId: simId,
        title: metadata['title'] ?? simId,
        subject: metadata['subject'] ?? 'Science',
        localPath: metadata['localPath'] ?? 'assets/phet/simulations/placeholder.html',
      );
    }

    return SimulationVisualPayload(
      intent: intent,
      simulationId: simId,
      title: intent.title ?? simId,
      subject: 'Science',
      localPath: 'assets/phet/simulations/placeholder.html',
    );
  }

  StepsVisualPayload _resolveStepsSolution(VisualIntent intent) {
    final rawSteps = intent.inputs['steps'] as List;
    final formatted = rawSteps.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    return StepsVisualPayload(
      intent: intent,
      steps: formatted,
    );
  }

  GraphVisualPayload _resolveFunctionGraph(VisualIntent intent) {
    final formula = intent.inputs['formula'] ?? intent.inputs['function'] ?? intent.scenario;
    return GraphVisualPayload(
      intent: intent,
      formula: formula.toString(),
    );
  }

  LabSetupVisualPayload _resolveLabSetup(VisualIntent intent) {
    final expId = (intent.inputs['experiment_id'] ?? intent.inputs['id'] ?? intent.scenario)
        .toString()
        .trim();
    final definition = LabExperimentCatalog.getById(expId) ??
        LabExperimentCatalog.inclineFriction;
    return LabSetupVisualPayload(
      intent: intent,
      definition: definition,
    );
  }

  OpticsVisualPayload _resolveOpticsRayDiagram(VisualIntent intent) {
    final inputs = intent.inputs;
    final scenario = OpticsScenario.fromIdentifier(intent.scenario);
    final rawF = inputs['focal_length_cm'] ?? inputs['f'] ?? 10.0;
    final rawU = inputs['object_distance_cm'] ?? inputs['u'] ?? 15.0;
    final rawH = inputs['object_height_cm'] ?? inputs['height'] ?? 3.0;

    final focalLength = (rawF as num).toDouble();
    final objectDistance = (rawU as num).toDouble();
    final objectHeight = (rawH as num).toDouble();

    final result = _opticsEngine.solve(
      scenario: scenario,
      focalLengthCm: focalLength,
      objectDistanceCm: objectDistance,
      objectHeightCm: objectHeight,
    );

    return OpticsVisualPayload(
      intent: intent,
      result: result,
    );
  }

  GeometryVisualPayload _resolveGeometryConstruction(VisualIntent intent) {
    final scenario = GeometryScenario.fromIdentifier(intent.scenario);
    final result = _geometryEngine.solve(
      scenario: scenario,
      inputs: intent.inputs,
    );

    return GeometryVisualPayload(
      intent: intent,
      result: result,
    );
  }

  CircuitVisualPayload _resolveCircuitSchematic(VisualIntent intent) {
    final inputs = intent.inputs;
    final scenario = CircuitScenario.fromIdentifier(intent.scenario);
    final rawV = inputs['voltage'] ?? inputs['v'] ?? inputs['voltage_v'] ?? 12.0;
    final voltage = (rawV as num).toDouble();
    final isClosed = (inputs['switch_closed'] ?? inputs['closed'] ?? true) as bool;

    List<double>? resistances;
    final rawR = inputs['resistances'] ?? inputs['resistance'] ?? inputs['r'];
    if (rawR is List) {
      resistances = rawR.map((e) => (e as num).toDouble()).toList();
    } else if (rawR is num) {
      resistances = [rawR.toDouble()];
    }

    final result = _circuitEngine.solve(
      scenario: scenario,
      voltageVolts: voltage,
      isSwitchClosed: isClosed,
      resistances: resistances,
    );

    return CircuitVisualPayload(
      intent: intent,
      result: result,
    );
  }
}
