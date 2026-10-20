import 'package:flutter/material.dart';

import '../../../../core/theme/idp_colors.dart';
import '../../../experiment/phet/models/experiment_descriptor.dart';
import '../../../experiment/phet/presentation/experiment_player_screen.dart';
import '../../application/visual_resolver.dart';

/// Card component that invites the student to launch a verified simulation (e.g. PhET).
class SimulationCard extends StatelessWidget {
  const SimulationCard({
    required this.payload,
    super.key,
  });

  final SimulationVisualPayload payload;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: IDPColors.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.science_rounded, color: IDPColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payload.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0E7FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            payload.subject,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4338CA),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          '• PhET Interactive Lab',
                          style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (payload.intent.description != null && payload.intent.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              payload.intent.description!,
              style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Open Interactive Simulation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: IDPColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                final descriptor = ExperimentDescriptor(
                  id: payload.simulationId,
                  slug: payload.simulationId.replaceAll('phet-', ''),
                  title: payload.title,
                  subject: payload.subject,
                  provider: 'PhET',
                  launchLocation: payload.localPath,
                  launchSource: ExperimentLaunchSource.bundledFallback,
                );

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ExperimentPlayerScreen(experiment: descriptor),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
