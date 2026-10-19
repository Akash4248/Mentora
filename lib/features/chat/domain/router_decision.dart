/// Target routes determined by the first-pass deterministic router.
enum TutorRoute {
  /// Explicit numerical calculation or arithmetic expression evaluation.
  calculation,

  /// Step-by-step mathematical or physical equation derivation.
  derivation,

  /// Interactive NCERT simulation or virtual lab lookup.
  simulationLookup,

  /// Direct intent to launch or explore phone sensor laboratory routes.
  labRoute,

  /// Core conceptual explanation, definitions, analogies, and intuitions.
  conceptualExplanation,

  /// General curriculum or factual inquiry.
  generalFactual,
}

/// Output of [DeterministicFastPathRouter] containing the classified route,
/// confidence score, decision explanations, and allowlisted capability IDs.
final class RouterDecision {
  const RouterDecision({
    required this.route,
    required this.confidence,
    required this.reasons,
    this.selectedCapabilityIds = const {},
  });

  /// The selected routing path.
  final TutorRoute route;

  /// Confidence score between 0.0 (uncertain) and 1.0 (exact match).
  final double confidence;

  /// Explanatory diagnostic reasons backing the routing choice.
  final List<String> reasons;

  /// Allowlisted capability IDs resolved for this specific turn.
  final Set<String> selectedCapabilityIds;

  /// True if confidence is high (>= 0.75), indicating high routing certainty.
  bool get isHighConfidence => confidence >= 0.75;

  @override
  String toString() =>
      'RouterDecision(route: $route, confidence: $confidence, capabilities: $selectedCapabilityIds)';
}
