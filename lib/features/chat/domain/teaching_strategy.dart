/// Core teaching strategies selected by Mentora to structure explanations adaptively.
enum TeachingStrategy {
  /// Direct factual definition, primary formula, and SI units without forced analogies.
  factualDefinition,

  /// Intuitive concept explanation anchored by an everyday analogy with explicit limitations.
  conceptualIntuition,

  /// Step-by-step numerical solution: Given -> Formula -> Substitution -> Calculation -> Final Unit.
  workedProblem,

  /// Mathematical or physical derivation showing algebraic progression and rationale.
  stepwiseDerivation,

  /// Structured side-by-side comparison of two related concepts (e.g. speed vs. velocity).
  comparativeContrast,
}
