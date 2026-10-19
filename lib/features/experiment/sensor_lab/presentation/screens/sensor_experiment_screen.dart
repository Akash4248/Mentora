import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../domain/lab_analysis_summary.dart';
import '../../domain/lab_experiment_definition.dart';
import '../../domain/lab_state.dart';
import '../../domain/sensor_sample.dart';
import '../../application/lab_controller.dart';
import '../widgets/live_sensor_graph.dart';

/// Full interactive laboratory workspace screen for sensor-driven physical science experiments.
class SensorExperimentScreen extends StatefulWidget {
  const SensorExperimentScreen({
    super.key,
    required this.definition,
    this.controller,
    this.onCompleted,
  });

  final LabExperimentDefinition definition;
  final LabController? controller;
  final void Function(LabAnalysisSummary summary)? onCompleted;

  @override
  State<SensorExperimentScreen> createState() => _SensorExperimentScreenState();
}

class _SensorExperimentScreenState extends State<SensorExperimentScreen> {
  late final LabController _controller;
  final List<SensorSample> _recentSamples = [];
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = LabController();
      _ownsController = true;
      _controller.initialize(widget.definition);
    }

    _controller.liveSampleStream.listen((sample) {
      if (mounted) {
        setState(() {
          _recentSamples.add(sample);
          if (_recentSamples.length > 120) {
            _recentSamples.removeAt(0);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B132B), // Deep space navy
      appBar: AppBar(
        title: Text(
          widget.definition.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1C2541),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          ValueListenableBuilder<LabStatusUpdate>(
            valueListenable: _controller.statusListenable,
            builder: (context, status, _) {
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: _buildStateBadge(status.state)),
              );
            },
          ),
        ],
      ),
      body: ValueListenableBuilder<LabStatusUpdate>(
        valueListenable: _controller.statusListenable,
        builder: (context, status, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Safety Banner
                _buildSafetyBanner(),
                const SizedBox(height: 12),

                // Real-time Waveform Display
                LiveSensorGraph(
                  samples: _recentSamples,
                  height: 150,
                  yRange: 15.0,
                ),
                const SizedBox(height: 14),

                // Live Physical Gauges
                _buildLiveGauges(status.latestSample),
                const SizedBox(height: 16),

                // Primary Controls
                _buildControlButtons(status.state),
                const SizedBox(height: 16),

                // Results Card (when completed)
                if (status.state == LabLifecycleState.completed &&
                    _controller.latestSummary != null)
                  _buildResultsCard(_controller.latestSummary!),

                // Setup Guide Expansion Tile
                _buildSetupGuide(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStateBadge(LabLifecycleState state) {
    Color bg;
    Color fg;
    String label;

    switch (state) {
      case LabLifecycleState.uninitialized:
        bg = const Color(0xFF334155);
        fg = const Color(0xFF94A3B8);
        label = 'Initializing';
        break;
      case LabLifecycleState.ready:
        bg = const Color(0xFF0369A1);
        fg = const Color(0xFFBAE6FD);
        label = 'Ready';
        break;
      case LabLifecycleState.calibrating:
        bg = const Color(0xFFD97706);
        fg = const Color(0xFFFEF3C7);
        label = 'Calibrating';
        break;
      case LabLifecycleState.recording:
        bg = const Color(0xFFDC2626);
        fg = const Color(0xFFFEE2E2);
        label = 'Recording';
        break;
      case LabLifecycleState.analyzing:
        bg = const Color(0xFF7C3AED);
        fg = const Color(0xFFEDE9FE);
        label = 'Analyzing';
        break;
      case LabLifecycleState.completed:
        bg = const Color(0xFF059669);
        fg = const Color(0xFFD1FAE5);
        label = 'Completed';
        break;
      case LabLifecycleState.error:
        bg = const Color(0xFFB91C1C);
        fg = const Color(0xFFFEE2E2);
        label = 'Error';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSafetyBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.definition.safetyInstructions.first,
              style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveGauges(SensorSample? sample) {
    if (sample == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2541),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'Waiting for sensor stream…',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
          ),
        ),
      );
    }

    final parallelAcc = math.sqrt(sample.x * sample.x + sample.y * sample.y);
    final normalAcc = sample.z.abs();
    final thetaRad = math.atan2(parallelAcc, normalAcc);
    final thetaDeg = thetaRad * (180.0 / math.pi);
    final normalForceRatio = math.cos(thetaRad);
    final frictionCoeff = math.tan(thetaRad);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3A506B)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Live Physics Measurements',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  label: 'Tilt Angle (θ)',
                  value: '${thetaDeg.toStringAsFixed(1)}°',
                  accent: const Color(0xFF38BDF8),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Normal Force (N/mg)',
                  value: normalForceRatio.toStringAsFixed(2),
                  accent: const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricTile(
                  label: 'Static μs (tan θ)',
                  value: frictionCoeff.toStringAsFixed(2),
                  accent: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0B132B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 9),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(LabLifecycleState state) {
    final isRecording = state == LabLifecycleState.recording;

    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isRecording ? null : () => _controller.startRecording(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669), // Emerald 600
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.fiber_manual_record, size: 18),
            label: const Text(
              'Start Recording',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isRecording ? () => _controller.stopRecording() : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626), // Red 600
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: const Icon(Icons.stop, size: 18),
            label: const Text(
              'Stop & Analyze',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultsCard(LabAnalysisSummary summary) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Experiment Analysis Results',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: summary.quality == DataQualityRating.high
                      ? const Color(0xFF059669)
                      : const Color(0xFFD97706),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  summary.quality.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFF334155), height: 20),

          // Derived Metrics Grid
          ...summary.metrics.entries.map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    e.key.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                  Text(
                    '${e.value}',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 8),
          Text(
            'Samples: ${summary.sampleCount} • Duration: ${summary.durationSeconds}s • Jitter: ${summary.jitterMs}ms',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 10),
          ),

          if (summary.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Note: ${summary.warnings.join(' ')}',
                style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 11),
              ),
            ),
          ],

          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () {
              widget.onCompleted?.call(summary);
              Navigator.of(context).pop(summary);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text(
              'Discuss Evidence with Mentora',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupGuide() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1C2541),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: ExpansionTile(
        title: const Text(
          'Setup Instructions & Theoretical Background',
          style: TextStyle(
            color: Color(0xFFCBD5E1),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        iconColor: const Color(0xFF38BDF8),
        collapsedIconColor: const Color(0xFF94A3B8),
        childrenPadding: const EdgeInsets.all(16),
        children: [
          ...widget.definition.setupSteps.asMap().entries.map((e) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${e.key + 1}. ',
                    style: const TextStyle(
                      color: Color(0xFF38BDF8),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.value,
                      style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (widget.definition.theoreticalBackground.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              widget.definition.theoreticalBackground,
              style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
