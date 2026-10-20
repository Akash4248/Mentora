import 'dart:convert';

/// Supported visual artifact types for the Mentora 2.0 Visual Runtime.
enum VisualType {
  motionTrajectory('motion.trajectory'),
  stepsSolution('steps.solution'),
  mathFunctionGraph('math.function_graph'),
  simulationLauncher('simulation.launcher'),
  opticsRayDiagram('optics.ray_diagram'),
  geometryConstruction('geometry.construction'),
  physicsForceDiagram('physics.force_diagram'),
  conceptSequence('concept.sequence'),
  labSetup('lab.setup'),
  unknown('unknown');

  const VisualType(this.identifier);
  final String identifier;

  static VisualType fromIdentifier(String? id) {
    if (id == null) return VisualType.unknown;
    for (final type in values) {
      if (type.identifier == id) return type;
    }
    return VisualType.unknown;
  }
}

/// Versioned, typed domain contract representing a model's or app's request to render
/// an educational visual artifact.
///
/// Invariant: The model supplies physical initial conditions, scenario intent,
/// and educational focus (e.g. apex), but NEVER generates drawing code, pixel coordinates,
/// or raw canvas strokes.
final class VisualIntent {
  const VisualIntent({
    this.schemaVersion = 1,
    required this.type,
    required this.scenario,
    this.inputs = const {},
    this.focus,
    this.title,
    this.description,
  });

  /// The version of the visual schema contract (defaults to 1).
  final int schemaVersion;

  /// The verified category of visual renderer required.
  final VisualType type;

  /// High-level physical or educational scenario (e.g. 'vertical_toss', 'linear_acceleration').
  final String scenario;

  /// Parameter map containing physical quantities, formulas, or catalog IDs.
  final Map<String, dynamic> inputs;

  /// Specific educational highlight or focal area (e.g. {'kind': 'apex'}).
  final Map<String, dynamic>? focus;

  /// Optional human-readable title for card headers.
  final String? title;

  /// Optional caption or educational takeaway.
  final String? description;

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'type': type.identifier,
        'scenario': scenario,
        'inputs': inputs,
        if (focus != null) 'focus': focus,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
      };

  /// Safely attempts to parse a [VisualIntent] from a JSON object or string.
  static VisualIntent? tryParse(dynamic raw) {
    if (raw == null) return null;
    try {
      final Map<String, dynamic> map;
      if (raw is String) {
        final decoded = jsonDecode(raw.trim());
        if (decoded is! Map<String, dynamic>) return null;
        map = decoded;
      } else if (raw is Map<String, dynamic>) {
        map = raw;
      } else if (raw is Map) {
        map = Map<String, dynamic>.from(raw);
      } else {
        return null;
      }

      final typeStr = map['type'] as String?;
      final type = VisualType.fromIdentifier(typeStr);
      final scenario = (map['scenario'] as String?)?.trim() ?? '';

      final rawInputs = map['inputs'];
      final Map<String, dynamic> inputs;
      if (rawInputs is Map) {
        inputs = Map<String, dynamic>.from(rawInputs);
      } else {
        inputs = const {};
      }

      final rawFocus = map['focus'];
      final Map<String, dynamic>? focus =
          rawFocus is Map ? Map<String, dynamic>.from(rawFocus) : null;

      final version = map['schema_version'] as int? ?? 1;

      return VisualIntent(
        schemaVersion: version,
        type: type,
        scenario: scenario,
        inputs: inputs,
        focus: focus,
        title: map['title'] as String?,
        description: map['description'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() =>
      'VisualIntent(version: $schemaVersion, type: ${type.identifier}, scenario: $scenario, inputs: $inputs)';
}
