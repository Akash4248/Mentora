import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/three_tier_memory_manager.dart';
import 'package:mentora/features/chat/domain/learner_profile.dart';
import 'package:mentora/features/chat/domain/learning_evidence.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ThreeTierMemoryManager', () {
    late ThreeTierMemoryManager memoryManager;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      memoryManager = ThreeTierMemoryManager();
    });

    group('Tier 1: LearnerProfile', () {
      test('provides default profile and allows user edits and reset', () async {
        final initial = await memoryManager.getProfile(defaultGrade: 9);
        expect(initial.grade, 9);
        expect(initial.preferredLanguage, 'en');
        expect(initial.explanationStyle, 'balanced');
        expect(initial.interests, isEmpty);

        // User edits preferences
        final updated = initial.copyWith(
          explanationStyle: 'step_by_step',
          interests: ['space', 'robotics'],
        );
        await memoryManager.updateProfile(updated);

        final loaded = await memoryManager.getProfile();
        expect(loaded.explanationStyle, 'step_by_step');
        expect(loaded.interests, ['space', 'robotics']);

        // User resets profile
        await memoryManager.resetProfile(defaultGrade: 9);
        final reset = await memoryManager.getProfile();
        expect(reset.explanationStyle, 'balanced');
        expect(reset.interests, isEmpty);
      });
    });

    group('Tier 2: SessionLedger', () {
      test('tracks in-session concepts and tool usage within bounds', () {
        final ledger = memoryManager.getOrCreateLedger(
          sessionId: 'session_1',
          topic: 'Motion',
          grade: 9,
        );

        expect(ledger.questionsCount, 0);
        expect(ledger.keyConceptsTouched, isEmpty);

        ledger.recordQuestion('What is velocity?');
        expect(ledger.questionsCount, 1);

        // Add 10 concepts - list must bound to max 8 items
        for (var i = 1; i <= 10; i++) {
          ledger.recordConcept('Concept $i');
        }
        expect(ledger.keyConceptsTouched.length, 8);
        expect(ledger.keyConceptsTouched.first, 'Concept 3');
        expect(ledger.keyConceptsTouched.last, 'Concept 10');

        ledger.recordTool('calculate', formula: '100 / 10 = 10');
        expect(ledger.lastToolUsed, 'calculate');
        expect(ledger.lastFormulaEvaluated, '100 / 10 = 10');
      });
    });

    group('Tier 3: LearningEvidence', () {
      test('preserves attribution and enforces max 5 items bounding policy', () async {
        final evDirect = LearningEvidence(
          id: 'ev_1',
          topic: 'Motion',
          concept: 'Acceleration',
          sourceType: EvidenceSourceType.directStudentStatement,
          observation: 'Student said: "I get confused by negative acceleration."',
          isMastery: false,
          timestamp: DateTime.now(),
        );

        final evSystem = LearningEvidence(
          id: 'ev_2',
          topic: 'Motion',
          concept: 'Velocity',
          sourceType: EvidenceSourceType.systemObservation,
          observation: 'Student solved velocity numerical correctly on first attempt.',
          isMastery: true,
          timestamp: DateTime.now(),
        );

        await memoryManager.addEvidence(evDirect);
        await memoryManager.addEvidence(evSystem);

        final motionEvidence = await memoryManager.getEvidence(topicFilter: 'Motion');
        expect(motionEvidence.length, 2);
        expect(motionEvidence.first.sourceType, EvidenceSourceType.directStudentStatement);
        expect(motionEvidence.last.sourceType, EvidenceSourceType.systemObservation);

        // Filter for unrelated topic returns empty
        final chemEvidence = await memoryManager.getEvidence(topicFilter: 'Chemistry');
        expect(chemEvidence, isEmpty);

        // Add 4 more items - total must not exceed 5 items
        for (var i = 3; i <= 6; i++) {
          await memoryManager.addEvidence(
            LearningEvidence(
              id: 'ev_$i',
              topic: 'Motion',
              concept: 'Concept $i',
              sourceType: EvidenceSourceType.systemObservation,
              observation: 'Note $i',
              isMastery: true,
              timestamp: DateTime.now(),
            ),
          );
        }

        final allEvidence = await memoryManager.getEvidence();
        expect(allEvidence.length, 5);
        expect(allEvidence.any((e) => e.id == 'ev_1'), isFalse); // ev_1 was evicted
        expect(allEvidence.last.id, 'ev_6');

        // User clears evidence
        await memoryManager.clearEvidence();
        expect(await memoryManager.getEvidence(), isEmpty);
      });
    });

    group('Prompt Serialization', () {
      test('formats bounded memory context only when relevant', () async {
        // Initially with default profile and no evidence, memory prompt is empty
        final emptyPrompt = await memoryManager.formatMemoryForPrompt(topic: 'Motion');
        expect(emptyPrompt, isEmpty);

        // Update profile with non-default style and interests
        await memoryManager.updateProfile(
          LearnerProfile(
            grade: 9,
            preferredLanguage: 'en',
            explanationStyle: 'step_by_step',
            interests: const ['cricket'],
            updatedAt: DateTime.now(),
          ),
        );

        // Add relevant evidence for Motion
        await memoryManager.addEvidence(
          LearningEvidence(
            id: 'ev_m1',
            topic: 'Motion',
            concept: 'Retardation',
            sourceType: EvidenceSourceType.directStudentStatement,
            observation: 'Confused by deceleration vs retardation',
            isMastery: false,
            timestamp: DateTime.now(),
          ),
        );

        final formatted = await memoryManager.formatMemoryForPrompt(
          topic: 'Motion',
          sessionId: 'session_motion',
        );

        expect(formatted, contains('step_by_step'));
        expect(formatted, contains('cricket'));
        expect(formatted, contains('Student stated: struggles with "Retardation"'));

        // Querying for an unrelated topic omits Motion evidence
        final chemPrompt = await memoryManager.formatMemoryForPrompt(topic: 'Acids and Bases');
        expect(chemPrompt, isNot(contains('Retardation')));
      });
    });
  });
}
