import 'package:flutter_agent_harness/flutter_agent_harness.dart';

enum CapabilityPermissionTier {
  readOnly,
  stateChanging,
}

/// A declaratively registered educational capability wrapping an [AgentTool].
final class CapabilityDescriptor {
  const CapabilityDescriptor({
    required this.id,
    required this.version,
    required this.displayName,
    required this.description,
    required this.tier,
    required this.tool,
    this.tags = const {},
  });

  /// Stable unique identifier, e.g. 'math.calculate', 'simulation.lookup'.
  final String id;

  /// Semantic version of the capability, e.g. '1.0.0'.
  final String version;

  /// Human-readable title for UI progress display.
  final String displayName;

  /// Explanation of when and how the capability should be selected.
  final String description;

  /// Permission tier controlling whether explicit user confirmation is needed.
  final CapabilityPermissionTier tier;

  /// Pinned harness [AgentTool] implementation.
  final AgentTool tool;

  /// Categorical tags used for request-time resolution, e.g. {'math', 'physics'}.
  final Set<String> tags;

  /// Name of the underlying AgentTool.
  String get name => tool.name;

  /// Tool parameter schema.
  Map<String, dynamic> get parameters => tool.parameters;
}
