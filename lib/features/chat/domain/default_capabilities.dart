import 'dart:convert';
import 'package:flutter_agent_harness/flutter_agent_harness.dart';

import '../../experiment/sensor_lab/domain/lab_experiment_definition.dart';
import '../application/educational_tool_calling_engine.dart';
import '../../network/services/mentora_backend_client.dart';
import 'capability_descriptor.dart';
import 'capability_registry.dart';

/// Provides initial, safe, deterministic educational capabilities for Mentora.
abstract final class DefaultCapabilities {
  /// Safe mathematical expression evaluator.
  static CapabilityDescriptor calculate() {
    return CapabilityDescriptor(
      id: 'math.calculate',
      version: '1.0.0',
      displayName: 'Math Calculator',
      description: 'Safely evaluates an arithmetic or algebraic expression.',
      tier: CapabilityPermissionTier.readOnly,
      tags: const {'math', 'calculation', 'stem'},
      tool: AgentTool(
        name: 'calculate',
        description:
            'Safely calculates an arithmetic or algebraic expression (e.g. 2 + 2 or sqrt(16)).',
        label: 'Calculating formula',
        parameters: const {
          'type': 'object',
          'properties': {
            'expression': {
              'type': 'string',
              'description': 'The mathematical expression to evaluate.',
            },
          },
          'required': ['expression'],
          'additionalProperties': false,
        },
        execute: (arguments, cancelToken, onUpdate) async {
          cancelToken?.throwIfCancelled();
          final expr = (arguments['expression'] as String? ?? '').trim();
          if (expr.isEmpty) {
            return ToolExecutionResult.text('Error: Expression cannot be empty.');
          }

          onUpdate?.call(ToolExecutionResult.text('Evaluating: $expr'));
          final result =
              EducationalToolCallingEngine.instance.evaluateMath(expr);
          if (result.isSuccess) {
            return ToolExecutionResult.text('$expr = ${result.outputText}');
          } else {
            return ToolExecutionResult.text(result.outputText);
          }
        },
      ),
    );
  }

  /// Local curriculum simulation lookup.
  static CapabilityDescriptor lookupSimulation({MentoraBackendClient? client}) {
    final backend = client ?? MentoraBackendClient();
    return CapabilityDescriptor(
      id: 'simulation.lookup',
      version: '1.0.0',
      displayName: 'Simulation Finder',
      description: 'Finds an approved interactive NCERT simulation for a topic.',
      tier: CapabilityPermissionTier.readOnly,
      tags: const {'physics', 'simulation', 'lab', 'stem'},
      tool: AgentTool(
        name: 'lookup_simulation',
        description:
            'Looks up an approved interactive NCERT simulation for a science topic.',
        label: 'Finding simulation',
        parameters: const {
          'type': 'object',
          'properties': {
            'topic': {
              'type': 'string',
              'description': 'The chapter or topic name (e.g. Motion, Gravity, Pendulum).',
            },
          },
          'required': ['topic'],
          'additionalProperties': false,
        },
        execute: (arguments, cancelToken, onUpdate) async {
          cancelToken?.throwIfCancelled();
          final topic = (arguments['topic'] as String? ?? '').trim();
          if (topic.isEmpty) {
            return ToolExecutionResult.text('Error: Topic cannot be empty.');
          }

          onUpdate?.call(ToolExecutionResult.text('Searching local simulations for "$topic"'));
          try {
            final sim = await backend.getSimulationForChapter(topic);
            final title = sim['title'] ?? 'Interactive Simulation';
            final desc = sim['description'] ?? '';
            final formulas = (sim['formulas'] as List?)?.join(', ') ?? '';

            final summary = StringBuffer('Found simulation: $title');
            if (desc.isNotEmpty) summary.write(' — $desc');
            if (formulas.isNotEmpty) summary.write(' (Formulas: $formulas)');
            summary.write('\nTo render this interactive visualizer for the student, include a ```mentora-visual block with type "motion.trajectory".');
            return ToolExecutionResult.text(summary.toString());
          } catch (e) {
            return ToolExecutionResult.text(
              'Could not locate simulation for "$topic": $e',
            );
          }
        },
      ),
    );
  }

  /// Proposes an approved physical science experiment from the local catalog.
  static CapabilityDescriptor proposeLab() {
    return CapabilityDescriptor(
      id: 'lab.propose',
      version: '1.0.0',
      displayName: 'Sensor Lab Proposer',
      description: 'Proposes an approved physical science experiment from the local catalog.',
      tier: CapabilityPermissionTier.readOnly,
      tags: const {'physics', 'sensor', 'lab', 'experiment', 'stem'},
      tool: AgentTool(
        name: 'propose_experiment',
        description:
            'Proposes an approved physical science experiment with safety rules and setup steps.',
        label: 'Preparing sensor lab',
        parameters: const {
          'type': 'object',
          'properties': {
            'topic': {
              'type': 'string',
              'description': 'The physical topic (e.g. friction, incline, gravity).',
            },
          },
          'required': ['topic'],
          'additionalProperties': false,
        },
        execute: (arguments, cancelToken, onUpdate) async {
          cancelToken?.throwIfCancelled();
          final topic = (arguments['topic'] as String? ?? '').toLowerCase();

          LabExperimentDefinition exp;
          if (topic.contains('grav') || topic.contains('free') || topic.contains('earth')) {
            exp = LabExperimentCatalog.restGravity;
          } else {
            exp = LabExperimentCatalog.inclineFriction;
          }

          return ToolExecutionResult.text(
            'Proposing Experiment: ${exp.title} (${exp.subject} - ${exp.topic}).\n'
            'Safety: ${exp.safetyInstructions.first}\n'
            'Setup: ${exp.setupSteps.take(2).join(' ')}',
          );
        },
      ),
    );
  }

  /// Interactive scientific, circuit, trajectory, or geometric visualizer capability.
  static CapabilityDescriptor showVisualization() {
    return CapabilityDescriptor(
      id: 'visual.render',
      version: '1.0.0',
      displayName: 'Interactive Visualizer',
      description:
          'Renders an interactive scientific simulation, dynamic circuit, trajectory, or diagram.',
      tier: CapabilityPermissionTier.readOnly,
      tags: const {'physics', 'math', 'visual', 'circuit', 'simulation', 'stem'},
      tool: AgentTool(
        name: 'show_visualization',
        description:
            'Renders an interactive dynamic visualizer, circuit schematic, physics simulation, or geometry canvas for the student.',
        label: 'Rendering visualizer',
        parameters: const {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'description':
                  'The visualizer type: "circuit.schematic", "motion.trajectory", "optics.ray_diagram", "geometry.construction", or "simulation.launcher".',
            },
            'scenario': {
              'type': 'string',
              'description':
                  'The scenario name (e.g. "series_circuit", "simple_circuit", "projectile", "concave_mirror", "convex_lens", "right_triangle").',
            },
            'title': {
              'type': 'string',
              'description': 'A student-friendly title for the visualizer card.',
            },
            'inputs': {
              'type': 'object',
              'description':
                  'Numeric input parameters for the simulation or schematic (e.g. voltage, resistances, launch_velocity_mps, focal_length_cm).',
            },
          },
          'required': ['type', 'scenario'],
          'additionalProperties': true,
        },
        execute: (arguments, cancelToken, onUpdate) async {
          cancelToken?.throwIfCancelled();
          final type = (arguments['type'] as String? ?? 'circuit.schematic').trim();
          final scenario = (arguments['scenario'] as String? ?? 'simple_circuit').trim();
          final title = (arguments['title'] as String? ?? 'Interactive Visualizer').trim();
          final inputs = arguments['inputs'] is Map
              ? Map<String, dynamic>.from(arguments['inputs'] as Map)
              : <String, dynamic>{};

          onUpdate?.call(ToolExecutionResult.text('Preparing $title visualizer…'));

          final visualJson = jsonEncode({
            'type': type,
            'scenario': scenario,
            'title': title,
            'inputs': inputs,
          });

          return ToolExecutionResult.text(
            'Visualizer rendered successfully.\n\n```mentora-visual\n$visualJson\n```',
          );
        },
      ),
    );
  }

  /// Returns a [CapabilityRegistry] populated with default safe educational tools.
  static CapabilityRegistry createDefaultRegistry({
    MentoraBackendClient? client,
  }) {
    return CapabilityRegistry([
      calculate(),
      lookupSimulation(client: client),
      proposeLab(),
      showVisualization(),
    ]);
  }
}
