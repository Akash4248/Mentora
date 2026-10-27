import 'dart:convert';

/// Supported visual artifact types for the Mentora 2.0 Visual Runtime.
enum VisualType {
  motionTrajectory('motion.trajectory'),
  stepsSolution('steps.solution'),
  mathFunctionGraph('math.function_graph'),
  simulationLauncher('simulation.launcher'),
  opticsRayDiagram('optics.ray_diagram'),
  geometryConstruction('geometry.construction'),
  circuitSchematic('circuit.schematic'),
  physicsForceDiagram('physics.force_diagram'),
  conceptSequence('concept.sequence'),
  labSetup('lab.setup'),
  unknown('unknown');

  const VisualType(this.identifier);
  final String identifier;

  static VisualType fromIdentifier(String? id) {
    if (id == null) return VisualType.unknown;
    final normalized = id.toLowerCase().trim().replaceAll('-', '_');
    for (final type in values) {
      if (type.identifier == normalized || type.identifier.replaceAll('.', '_') == normalized) {
        return type;
      }
    }
    if (normalized.contains('circuit')) return VisualType.circuitSchematic;
    if (normalized.contains('ray') || normalized.contains('optic')) return VisualType.opticsRayDiagram;
    if (normalized.contains('trajectory') || normalized.contains('projectile')) return VisualType.motionTrajectory;
    if (normalized.contains('force')) return VisualType.physicsForceDiagram;
    if (normalized.contains('solution') || normalized.contains('step')) return VisualType.stepsSolution;
    if (normalized.contains('graph') || normalized.contains('function')) return VisualType.mathFunctionGraph;
    if (normalized.contains('geometry') || normalized.contains('construction') || normalized.contains('shape')) {
      return VisualType.geometryConstruction;
    }
    if (normalized.contains('simulation') || normalized.contains('launcher')) return VisualType.simulationLauncher;
    if (normalized.contains('lab')) return VisualType.labSetup;
    if (normalized.contains('concept')) return VisualType.conceptSequence;
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
        final sanitized = extractBalancedJsonObject(raw);
        final decoded = jsonDecode(sanitized);
        if (decoded is! Map<String, dynamic>) return null;
        map = decoded;
      } else if (raw is Map<String, dynamic>) {
        map = raw;
      } else if (raw is Map) {
        map = Map<String, dynamic>.from(raw);
      } else {
        return null;
      }

      String? typeStr;
      String scenario;
      Map<String, dynamic> inputs;
      String? title;
      String? description;
      Map<String, dynamic>? focus;

      if (map.containsKey('arguments') && map['arguments'] is Map) {
        final args = Map<String, dynamic>.from(map['arguments'] as Map);
        typeStr = (args['type'] ?? map['name'] ?? map['tool']) as String?;
        scenario = (args['scenario'] ?? map['scenario'] ?? args['expression'] ?? '').toString().trim();
        final rawInputs = args['inputs'] ?? map['inputs'] ?? args;
        inputs = rawInputs is Map ? Map<String, dynamic>.from(rawInputs) : const {};
        title = (args['title'] ?? map['title']) as String?;
        description = (args['description'] ?? map['description']) as String?;
        if (args['focus'] is Map) {
          focus = Map<String, dynamic>.from(args['focus'] as Map);
        } else if (map['focus'] is Map) {
          focus = Map<String, dynamic>.from(map['focus'] as Map);
        }
      } else {
        typeStr = (map['type'] ?? map['name']) as String?;
        scenario = (map['scenario'] as String?)?.trim() ?? '';
        final rawInputs = map['inputs'];
        inputs = rawInputs is Map ? Map<String, dynamic>.from(rawInputs) : const {};
        title = map['title'] as String?;
        description = map['description'] as String?;
        if (map['focus'] is Map) {
          focus = Map<String, dynamic>.from(map['focus'] as Map);
        }
      }

      final type = VisualType.fromIdentifier(typeStr);
      final version = map['schema_version'] as int? ?? 1;

      return VisualIntent(
        schemaVersion: version,
        type: type,
        scenario: scenario,
        inputs: inputs,
        focus: focus,
        title: title,
        description: description,
      );
    } catch (_) {
      return null;
    }
  }

  /// Extracts the outermost balanced JSON object `{ ... }` from a string,
  /// ignoring any trailing extraneous characters (such as extra closing braces or trailing markdown).
  static String extractBalancedJsonObject(String raw) {
    final start = raw.indexOf('{');
    if (start == -1) return raw.trim();
    var depth = 0;
    var inString = false;
    var isEscaped = false;
    for (var i = start; i < raw.length; i++) {
      final char = raw[i];
      if (isEscaped) {
        isEscaped = false;
        continue;
      }
      if (char == r'\') {
        isEscaped = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (char == '{') depth++;
        if (char == '}') {
          depth--;
          if (depth == 0) {
            return raw.substring(start, i + 1);
          }
        }
      }
    }
    return raw.substring(start).trim();
  }

  @override
  String toString() =>
      'VisualIntent(version: $schemaVersion, type: ${type.identifier}, scenario: $scenario, inputs: $inputs)';
}
