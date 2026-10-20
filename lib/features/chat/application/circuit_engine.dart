import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Supported DC circuit scenarios for NCERT Grades 8–12 Science/Physics.
enum CircuitScenario {
  simple('simple_circuit'),
  series('series_circuit'),
  parallel('parallel_circuit'),
  ohmsLaw('ohms_law');

  const CircuitScenario(this.identifier);
  final String identifier;

  static CircuitScenario fromIdentifier(String? id) {
    final clean = id?.toLowerCase().trim() ?? '';
    for (final s in values) {
      if (s.identifier == clean) return s;
    }
    if (clean.contains('series')) return series;
    if (clean.contains('parallel')) return parallel;
    if (clean.contains('ohm')) return ohmsLaw;
    return simple;
  }
}

/// The complete calculated electrical state of a DC circuit.
@immutable
final class CircuitCalculationResult {
  const CircuitCalculationResult({
    required this.scenario,
    required this.voltageVolts,
    required this.isSwitchClosed,
    required this.equivalentResistanceOhms,
    required this.totalCurrentAmps,
    required this.totalPowerWatts,
    required this.branchCurrentsAmps,
    required this.componentVoltages,
    required this.bulbBrightnessFactor,
    required this.theoremNote,
    required this.resistances,
  });

  final CircuitScenario scenario;
  final double voltageVolts;
  final bool isSwitchClosed;
  final double equivalentResistanceOhms;
  final double totalCurrentAmps;
  final double totalPowerWatts;
  final List<double> branchCurrentsAmps;
  final List<double> componentVoltages;
  final double bulbBrightnessFactor;
  final String theoremNote;
  final List<double> resistances;

  bool get hasCurrent => isSwitchClosed && totalCurrentAmps > 0;
}

/// Deterministic domain engine for DC circuits, Ohm's law, and resistor networks.
///
/// Implements analytical ground truth calculations for:
/// - Single-loop circuits ($I = V / R$, $P = V I$).
/// - Series resistor networks ($R_{eq} = R_1 + R_2 + \dots$, $I$ constant, $V_i = I R_i$).
/// - Parallel resistor networks ($1/R_{eq} = 1/R_1 + 1/R_2 + \dots$, $V$ constant, $I_i = V / R_i$).
/// - Open circuit condition ($I = 0$, $V_R = 0$, Bulb OFF).
final class CircuitEngine {
  const CircuitEngine();

  /// Solves a DC circuit state based on scenario, voltage, switch state, and component resistances.
  CircuitCalculationResult solve({
    required CircuitScenario scenario,
    required double voltageVolts,
    bool isSwitchClosed = true,
    List<double>? resistances,
  }) {
    final v = math.max(0.1, voltageVolts.abs());
    final defaultR = resistances != null && resistances.isNotEmpty
        ? resistances.map((r) => math.max(0.1, r.abs())).toList()
        : [10.0, 10.0];

    double req;
    final branchCurrents = <double>[];
    final componentVoltages = <double>[];
    final String note;

    switch (scenario) {
      case CircuitScenario.simple:
      case CircuitScenario.ohmsLaw:
        final r = defaultR.first;
        req = r;
        if (!isSwitchClosed) {
          return _openCircuitResult(scenario, v, req, [r]);
        }
        final i = v / req;
        final p = v * i;
        branchCurrents.add(i);
        componentVoltages.add(v);
        note = "Ohm's Law: I = V / R = ${v.toStringAsFixed(1)} V / ${r.toStringAsFixed(1)} Ω = ${i.toStringAsFixed(2)} A";
        return CircuitCalculationResult(
          scenario: scenario,
          voltageVolts: v,
          isSwitchClosed: true,
          equivalentResistanceOhms: req,
          totalCurrentAmps: i,
          totalPowerWatts: p,
          branchCurrentsAmps: branchCurrents,
          componentVoltages: componentVoltages,
          bulbBrightnessFactor: math.min(1.0, p / 10.0),
          theoremNote: note,
          resistances: [r],
        );

      case CircuitScenario.series:
        final r1 = defaultR.isNotEmpty ? defaultR[0] : 10.0;
        final r2 = defaultR.length > 1 ? defaultR[1] : 10.0;
        req = r1 + r2;

        if (!isSwitchClosed) {
          return _openCircuitResult(scenario, v, req, [r1, r2]);
        }

        final i = v / req;
        final v1 = i * r1;
        final v2 = i * r2;
        final p = v * i;

        branchCurrents.addAll([i, i]);
        componentVoltages.addAll([v1, v2]);
        note = 'Series: Req = R₁ + R₂ = ${r1.toStringAsFixed(1)} + ${r2.toStringAsFixed(1)} = ${req.toStringAsFixed(1)} Ω (Current I = ${i.toStringAsFixed(2)} A)';

        return CircuitCalculationResult(
          scenario: scenario,
          voltageVolts: v,
          isSwitchClosed: true,
          equivalentResistanceOhms: req,
          totalCurrentAmps: i,
          totalPowerWatts: p,
          branchCurrentsAmps: branchCurrents,
          componentVoltages: componentVoltages,
          bulbBrightnessFactor: math.min(1.0, p / 12.0),
          theoremNote: note,
          resistances: [r1, r2],
        );

      case CircuitScenario.parallel:
        final r1 = defaultR.isNotEmpty ? defaultR[0] : 10.0;
        final r2 = defaultR.length > 1 ? defaultR[1] : 10.0;
        req = (r1 * r2) / (r1 + r2);

        if (!isSwitchClosed) {
          return _openCircuitResult(scenario, v, req, [r1, r2]);
        }

        final i1 = v / r1;
        final i2 = v / r2;
        final iTotal = i1 + i2;
        final p = v * iTotal;

        branchCurrents.addAll([i1, i2]);
        componentVoltages.addAll([v, v]);
        note = 'Parallel: 1/Req = 1/R₁ + 1/R₂ => Req = ${req.toStringAsFixed(1)} Ω (Total I = I₁ + I₂ = ${iTotal.toStringAsFixed(2)} A)';

        return CircuitCalculationResult(
          scenario: scenario,
          voltageVolts: v,
          isSwitchClosed: true,
          equivalentResistanceOhms: req,
          totalCurrentAmps: iTotal,
          totalPowerWatts: p,
          branchCurrentsAmps: branchCurrents,
          componentVoltages: componentVoltages,
          bulbBrightnessFactor: math.min(1.0, p / 15.0),
          theoremNote: note,
          resistances: [r1, r2],
        );
    }
  }

  CircuitCalculationResult _openCircuitResult(
    CircuitScenario scenario,
    double v,
    double req,
    List<double> resistances,
  ) {
    return CircuitCalculationResult(
      scenario: scenario,
      voltageVolts: v,
      isSwitchClosed: false,
      equivalentResistanceOhms: req,
      totalCurrentAmps: 0.0,
      totalPowerWatts: 0.0,
      branchCurrentsAmps: List.filled(resistances.length, 0.0),
      componentVoltages: List.filled(resistances.length, 0.0),
      bulbBrightnessFactor: 0.0,
      theoremNote: 'Open Circuit: Switch is OFF. No current flows (I = 0.00 A).',
      resistances: resistances,
    );
  }
}
