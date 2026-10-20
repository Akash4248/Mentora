import 'package:flutter_agent_harness/flutter_agent_harness.dart';

import 'capability_descriptor.dart';

/// Central registry managing educational capabilities and converting them to
/// [AgentTool] schemas for the harness agent loop.
final class CapabilityRegistry {
  CapabilityRegistry([Iterable<CapabilityDescriptor> initial = const []]) {
    for (final descriptor in initial) {
      register(descriptor);
    }
  }

  final Map<String, CapabilityDescriptor> _byId = {};
  final Map<String, CapabilityDescriptor> _byToolName = {};

  /// Registers a capability descriptor.
  ///
  /// Throws [ArgumentError] if an identical ID or tool name is already registered,
  /// or if parameter schema is not a valid JSON schema object.
  void register(CapabilityDescriptor descriptor) {
    if (descriptor.id.trim().isEmpty) {
      throw ArgumentError('Capability id must not be empty.');
    }
    if (descriptor.name.trim().isEmpty) {
      throw ArgumentError('Tool name must not be empty.');
    }
    if (_byId.containsKey(descriptor.id)) {
      throw ArgumentError('Duplicate capability id: ${descriptor.id}');
    }
    if (_byToolName.containsKey(descriptor.name)) {
      throw ArgumentError('Duplicate tool name: ${descriptor.name}');
    }

    final schema = descriptor.parameters;
    if (schema['type'] != 'object') {
      throw ArgumentError(
        'Tool parameters schema must declare "type": "object" (was: ${schema['type']}).',
      );
    }

    _byId[descriptor.id] = descriptor;
    _byToolName[descriptor.name] = descriptor;
  }

  /// Looks up a descriptor by its stable ID.
  CapabilityDescriptor? lookupById(String id) => _byId[id];

  /// Looks up a descriptor by its harness tool name.
  CapabilityDescriptor? lookupByToolName(String toolName) =>
      _byToolName[toolName];

  /// All registered descriptors.
  List<CapabilityDescriptor> get all => List.unmodifiable(_byId.values);

  /// Resolves an allowlisted subset of [AgentTool]s for an active request,
  /// filtering by tags or specific IDs to prevent context-window bloat.
  List<AgentTool> resolveTools({
    Set<String>? tags,
    Set<String>? ids,
    int maxTools = 4,
  }) {
    if (maxTools <= 0) return const [];

    final matched = <CapabilityDescriptor>[];
    for (final descriptor in _byId.values) {
      final matchesId = ids != null && ids.contains(descriptor.id);
      final matchesTag =
          tags != null && descriptor.tags.any(tags.contains);

      if (ids != null || tags != null) {
        if (matchesId || matchesTag) {
          matched.add(descriptor);
        }
      } else {
        matched.add(descriptor);
      }

      if (matched.length >= maxTools) break;
    }

    return matched.map((d) => d.tool).toList(growable: false);
  }

  /// Default authorization policy enforcing read-only vs state-changing tiers.
  Future<bool> authorizeCall(
    String toolName,
    Map<String, dynamic> arguments, {
    bool allowStateChanging = false,
  }) async {
    final descriptor = _byToolName[toolName];
    if (descriptor == null) {
      return false;
    }

    switch (descriptor.tier) {
      case CapabilityPermissionTier.readOnly:
        return true;
      case CapabilityPermissionTier.stateChanging:
        return allowStateChanging;
    }
  }
}
