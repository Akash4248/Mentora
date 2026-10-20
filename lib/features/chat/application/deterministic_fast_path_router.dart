import '../domain/router_decision.dart';

/// Deterministic, low-latency, first-pass intent and capability router.
///
/// Avoids fragile single-keyword rules that misclassify inquiries. For example,
/// "What is the formula of acceleration?" is classified as a conceptual question,
/// not an arithmetic calculation.
final class DeterministicFastPathRouter {
  const DeterministicFastPathRouter();

  /// Routes an incoming student question and decides which capability IDs
  /// (if any) should be exposed to the model.
  RouterDecision route({
    required String question,
    required String topic,
    int grade = 9,
  }) {
    final clean = question.trim().toLowerCase();
    final reasons = <String>[];

    if (clean.isEmpty) {
      return const RouterDecision(
        route: TutorRoute.generalFactual,
        confidence: 0.1,
        reasons: ['Empty query; falling back to general factual'],
        selectedCapabilityIds: {},
      );
    }

    // 1. Simulation lookup intent
    if (_isSimulationIntent(clean, reasons)) {
      return RouterDecision(
        route: TutorRoute.simulationLookup,
        confidence: 0.95,
        reasons: reasons,
        selectedCapabilityIds: const {'simulation.lookup'},
      );
    }

    // 2. Phone sensor lab intent
    if (_isLabIntent(clean, reasons)) {
      return RouterDecision(
        route: TutorRoute.labRoute,
        confidence: 0.90,
        reasons: reasons,
        selectedCapabilityIds: const {},
      );
    }

    // 3. Mathematical derivation intent
    if (_isDerivationIntent(clean, reasons)) {
      return RouterDecision(
        route: TutorRoute.derivation,
        confidence: 0.90,
        reasons: reasons,
        selectedCapabilityIds: const {},
      );
    }

    // 4. Arithmetic / numerical calculation intent
    if (_isCalculationIntent(clean, reasons)) {
      return RouterDecision(
        route: TutorRoute.calculation,
        confidence: 0.95,
        reasons: reasons,
        selectedCapabilityIds: const {'math.calculate'},
      );
    }

    // 5. Conceptual inquiry / definition
    if (_isConceptualIntent(clean, reasons)) {
      return RouterDecision(
        route: TutorRoute.conceptualExplanation,
        confidence: 0.85,
        reasons: reasons,
        selectedCapabilityIds: const {},
      );
    }

    // 6. General fallback
    return RouterDecision(
      route: TutorRoute.generalFactual,
      confidence: 0.50,
      reasons: const ['Query did not match specific fast path; using general factual strategy.'],
      selectedCapabilityIds: const {},
    );
  }

  bool _isSimulationIntent(String clean, List<String> reasons) {
    if (clean.startsWith('what does simulation mean') ||
        clean.startsWith('define simulation')) {
      return false;
    }

    final simulationTriggers = [
      'simulation for',
      'interactive simulation',
      'show me a simulation',
      'open simulation',
      'find simulation',
      'lookup simulation',
      'phet simulation',
      'interactive lab',
      'virtual lab',
      'run simulation',
    ];

    for (final trigger in simulationTriggers) {
      if (clean.contains(trigger)) {
        reasons.add('Matched simulation trigger "$trigger"');
        return true;
      }
    }
    return false;
  }

  bool _isLabIntent(String clean, List<String> reasons) {
    final labTriggers = [
      'phone sensor',
      'accelerometer experiment',
      'measure with phone',
      'sensor lab',
      'test with sensor',
      'gyroscope experiment',
      'phone toss experiment',
    ];

    for (final trigger in labTriggers) {
      if (clean.contains(trigger)) {
        reasons.add('Matched sensor lab trigger "$trigger"');
        return true;
      }
    }
    return false;
  }

  bool _isDerivationIntent(String clean, List<String> reasons) {
    if (clean.startsWith('derive') ||
        clean.contains('derivation') ||
        clean.contains('prove that')) {
      reasons.add('Matched derivation intent');
      return true;
    }
    return false;
  }

  bool _isCalculationIntent(String clean, List<String> reasons) {
    // Explicit non-calculation guards
    if (clean.startsWith('what is the formula') ||
        clean.startsWith('give the formula') ||
        clean.startsWith('state the formula') ||
        clean.startsWith('define')) {
      return false;
    }

    // Direct arithmetic command triggers
    final calcCommands = [
      'calculate',
      'compute',
      'evaluate',
      'what is the value of',
      'solve the numerical',
      'find the numerical value',
    ];

    for (final cmd in calcCommands) {
      if (clean.contains(cmd)) {
        reasons.add('Matched calculation command "$cmd"');
        return true;
      }
    }

    // Standalone mathematical expression pattern: e.g. "15 * 4 + 10", "sqrt(16) / 2", "100 / 10"
    final mathExpressionRegex = RegExp(
      r'^\s*(?:what is\s+)?(?:\d+(?:\.\d+)?|\b(?:sqrt|sin|cos|tan)\([^)]+\))(?:\s*[\+\-\*\/\^]\s*(?:\d+(?:\.\d+)?|\b(?:sqrt|sin|cos|tan)\([^)]+\)))+\s*\??$',
    );

    if (mathExpressionRegex.hasMatch(clean)) {
      reasons.add('Matched raw mathematical expression pattern');
      return true;
    }

    // Numerical physics problem query: e.g. "distance is 100m, time is 10s, find speed"
    if ((clean.contains('find speed') ||
            clean.contains('find velocity') ||
            clean.contains('find acceleration') ||
            clean.contains('find distance')) &&
        RegExp(r'\d+\s*(?:m|s|m\/s|km|hr|kg|n)').hasMatch(clean)) {
      reasons.add('Matched numerical physics word problem with values');
      return true;
    }

    return false;
  }

  bool _isConceptualIntent(String clean, List<String> reasons) {
    final conceptualPrefixes = [
      'what is',
      'what are',
      'define',
      'explain',
      'why does',
      'why is',
      'how does',
      'how do',
      'difference between',
      'distinguish between',
      'state newton',
      'state kepler',
      'describe',
    ];

    for (final prefix in conceptualPrefixes) {
      if (clean.startsWith(prefix)) {
        reasons.add('Matched conceptual prefix "$prefix"');
        return true;
      }
    }
    return false;
  }
}
