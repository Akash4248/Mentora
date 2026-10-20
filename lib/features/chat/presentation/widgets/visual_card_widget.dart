import 'package:flutter/material.dart';

import '../../application/visual_resolver.dart';
import '../../domain/visual_intent.dart';
import 'geometry_canvas.dart';
import 'motion_trajectory_canvas.dart';
import 'ray_optics_canvas.dart';
import 'simulation_card.dart';
import 'solution_step_card.dart';
import '../../../experiment/sensor_lab/presentation/widgets/lab_setup_card.dart';

/// Presentation dispatcher that resolves a [VisualIntent] and renders the corresponding
/// native educational card component.
class VisualCardWidget extends StatelessWidget {
  const VisualCardWidget({
    required this.intent,
    this.resolver = const VisualResolver(),
    super.key,
  });

  final VisualIntent intent;
  final VisualResolver resolver;

  @override
  Widget build(BuildContext context) {
    final payload = resolver.resolve(intent);

    switch (payload) {
      case TrajectoryVisualPayload():
        return MotionTrajectoryCanvas(payload: payload);

      case OpticsVisualPayload():
        return RayOpticsCanvas(payload: payload);

      case GeometryVisualPayload():
        return GeometryCanvas(payload: payload);

      case SimulationVisualPayload():
        return SimulationCard(payload: payload);

      case StepsVisualPayload():
        return SolutionStepCard(payload: payload);

      case GraphVisualPayload():
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.stacked_line_chart_rounded, color: Color(0xFF0284C7)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Function Graph: ${payload.formula}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        );

      case LabSetupVisualPayload():
        return LabSetupCard(definition: payload.definition);

      case FallbackTextVisualPayload():
        // Graceful fallback: do not crash, display nothing or a minor indicator
        return const SizedBox.shrink();
    }
  }
}
