import '../domain/follow_up_action.dart';
import '../domain/teaching_strategy.dart';

/// Generates context-sensitive, pedagogical follow-up actions tailored to the
/// active topic, student question, and teaching strategy.
final class FollowUpActionGenerator {
  const FollowUpActionGenerator();

  /// Generates a list of 2-3 relevant follow-up actions.
  List<FollowUpAction> generateFollowUps({
    required String question,
    required String topic,
    required TeachingStrategy strategy,
  }) {
    final tClean = topic.trim().isEmpty ? 'this topic' : topic.trim();

    switch (strategy) {
      case TeachingStrategy.workedProblem:
        return [
          FollowUpAction(
            id: 'fa_worked_another',
            label: 'Show another example',
            intentQuery: 'Show another numerical problem on $tClean with different numbers and solve it step-by-step.',
            targetStrategy: TeachingStrategy.workedProblem,
          ),
          FollowUpAction(
            id: 'fa_worked_why_formula',
            label: 'Why this formula?',
            intentQuery: 'Why is this specific formula used to solve this $tClean problem, and what are its physical assumptions?',
            targetStrategy: TeachingStrategy.conceptualIntuition,
          ),
          FollowUpAction(
            id: 'fa_worked_test_me',
            label: 'Give me a problem to solve',
            intentQuery: 'Give me a similar practice problem on $tClean for me to solve on my own.',
            targetStrategy: TeachingStrategy.workedProblem,
          ),
        ];

      case TeachingStrategy.factualDefinition:
        return [
          FollowUpAction(
            id: 'fa_fact_analogy',
            label: 'Explain with an analogy',
            intentQuery: 'Explain $question in $tClean using an everyday real-world analogy and explain its limitations.',
            targetStrategy: TeachingStrategy.conceptualIntuition,
          ),
          FollowUpAction(
            id: 'fa_fact_worked',
            label: 'Show numerical example',
            intentQuery: 'Show a worked numerical problem applying $tClean with step-by-step calculations.',
            targetStrategy: TeachingStrategy.workedProblem,
          ),
          FollowUpAction(
            id: 'fa_fact_quiz',
            label: 'Test my understanding',
            intentQuery: 'Ask me a quick conceptual question to test if I understood $question in $tClean correctly.',
            targetStrategy: TeachingStrategy.conceptualIntuition,
          ),
        ];

      case TeachingStrategy.conceptualIntuition:
        return [
          FollowUpAction(
            id: 'fa_conc_simpler',
            label: 'Explain more simply',
            intentQuery: 'Explain $question in $tClean even more simply, with everyday examples.',
            targetStrategy: TeachingStrategy.conceptualIntuition,
          ),
          FollowUpAction(
            id: 'fa_conc_math',
            label: 'Show formulas & units',
            intentQuery: 'What are the exact mathematical equations and SI units for $tClean?',
            targetStrategy: TeachingStrategy.factualDefinition,
          ),
          FollowUpAction(
            id: 'fa_conc_sim',
            label: 'Explore visual / simulation',
            intentQuery: 'Show me an interactive simulation for $tClean.',
            targetStrategy: TeachingStrategy.conceptualIntuition,
          ),
        ];

      case TeachingStrategy.stepwiseDerivation:
        return [
          FollowUpAction(
            id: 'fa_deriv_why_step',
            label: 'Explain key step',
            intentQuery: 'Which step in this derivation for $tClean is most critical and why?',
            targetStrategy: TeachingStrategy.conceptualIntuition,
          ),
          FollowUpAction(
            id: 'fa_deriv_practical',
            label: 'Real-world application',
            intentQuery: 'How is this derived equation for $tClean used in everyday applications or vehicles?',
            targetStrategy: TeachingStrategy.conceptualIntuition,
          ),
        ];

      case TeachingStrategy.comparativeContrast:
        return [
          FollowUpAction(
            id: 'fa_comp_table',
            label: 'Summary comparison table',
            intentQuery: 'Provide a structured Markdown comparison table contrasting these concepts in $tClean.',
            targetStrategy: TeachingStrategy.comparativeContrast,
          ),
          FollowUpAction(
            id: 'fa_comp_example',
            label: 'Comparative example',
            intentQuery: 'Give an everyday scenario in $tClean where one quantity is zero but the other is non-zero.',
            targetStrategy: TeachingStrategy.conceptualIntuition,
          ),
        ];
    }
  }
}
