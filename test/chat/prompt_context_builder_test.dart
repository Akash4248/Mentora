import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/conversation_context_builder.dart';
import 'package:mentora/features/chat/application/prompt_budget_manager.dart';
import 'package:mentora/features/chat/application/reasoning_output_filter.dart';
import 'package:mentora/features/chat/application/streaming_output_normalizer.dart';
import 'package:mentora/features/chat/application/tutor_prompt_builder.dart';
import 'package:mentora/features/chat/domain/tutor_message.dart';
import 'package:mentora/features/course/domain/course_tree.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Prompt and context builder', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('builds compact session summary plus recent conversation', () async {
      final builder = ConversationContextBuilder(
        summaryTriggerMessages: 4,
        budget: const PromptBudgetManager(summaryChars: 260, historyChars: 360),
      );

      final messages = <TutorMessage>[
        _message('What is velocity?', true, 1),
        _message('Velocity means speed with direction.', false, 2),
        _message('Why does acceleration change?', true, 3),
        _message('Acceleration changes when force changes.', false, 4),
        _message('Why does acceleration change?', true, 5),
      ];

      final context = await builder.build(
        sessionId: 'prompt_context_builder_test',
        messages: messages,
        currentQuestion: 'Why does acceleration change?',
        subject: 'Physics',
        chapter: 'Motion',
      );

      expect(context.sessionSummary, contains('Current Topic: Motion'));
      expect(context.recentConversation.join('\n'), contains('Student:'));
      expect(context.recentConversation.join('\n'), contains('Tutor:'));
      expect(
        context.recentConversation.join('\n').length,
        lessThanOrEqualTo(360),
      );
    });

    test('prompt stays under hard budget and prioritizes context order', () {
      final promptBuilder = TutorPromptBuilder(
        budget: const PromptBudgetManager(maxPromptChars: 3900, ragChars: 9000),
      );
      final context = const ConversationContext(
        sessionSummary:
            'Student understands velocity.\nStudent struggles with acceleration.\nCurrent Topic: Motion',
        recentConversation: [
          'Student: Why does it go farther?',
          'Tutor: It goes farther when launch speed increases.',
        ],
      );

      final prompt = promptBuilder.buildChapterPrompt(
        course: const Course(id: 'grade_8', name: 'Grade 8'),
        subject: const Subject(
          id: 'physics',
          courseId: 'grade_8',
          name: 'Physics',
        ),
        chapter: const Chapter(
          id: 'motion',
          subjectId: 'physics',
          title: 'Motion',
          summary:
              'Motion explains distance, speed, velocity, and acceleration.',
        ),
        question: 'Why does it go farther?',
        languageCode: 'en',
        retrievedContext: List.filled(
          5,
          'Projectile motion depends on velocity, angle, gravity, and time in air. ' *
              30,
        ),
        conversationContext: context,
      );

      expect(prompt.length, lessThanOrEqualTo(3900));
      expect(
        prompt.indexOf('Subject: Physics'),
        lessThan(prompt.indexOf('Session summary:')),
      );
      expect(
        prompt.indexOf('Session summary:'),
        lessThan(prompt.indexOf('Recent conversation:')),
      );
      expect(
        prompt.indexOf('Recent conversation:'),
        lessThan(prompt.indexOf('Relevant notes:')),
      );
      expect(
        prompt,
        contains('Do not reveal internal reasoning or chain of thought.'),
      );
      expect(prompt, contains('Student question: Why does it go farther?'));
      expect(promptBuilder.lastAudit['final_prompt'], prompt);
      expect(promptBuilder.lastAudit['retrieved_chunks'], hasLength(3));
      expect(
        promptBuilder.lastAudit['estimated_tokens'] as int,
        lessThanOrEqualTo(1000),
      );
    });

    test('reasoning tags are stripped from final output', () {
      final cleaned = ReasoningOutputFilter.stripComplete(
        'Answer first. <think>hidden chain</think> Visible. <analysis>secret</analysis>',
      );

      expect(cleaned, isNot(contains('hidden chain')));
      expect(cleaned, isNot(contains('secret')));
      expect(cleaned, contains('Answer first.'));
      expect(cleaned, contains('Visible.'));
    });

    test('prompt echo scaffolding is stripped from final output', () {
      final cleaned = ReasoningOutputFilter.stripComplete('''
EDUCATIONAL CONTEXT: ----------------------------------------
[Source 1] (relevance: 0.66) Example note
QUESTION: hi explain this chapter
ANSWER:
A sector is a part of a circle.
''');

      expect(cleaned, isNot(contains('EDUCATIONAL CONTEXT')));
      expect(cleaned, isNot(contains('QUESTION: hi explain this chapter')));
      expect(cleaned, contains('A sector is a part of a circle.'));
    });

    test('streaming normalizer avoids cumulative chunk duplication', () {
      final first = StreamingOutputNormalizer.delta(
        '',
        'Real numbers are all numbers on the number line.',
      );
      final second = StreamingOutputNormalizer.delta(
        'Real numbers are all numbers on the number line.',
        'Real numbers are all numbers on the number line. They include rational and irrational numbers.',
      );

      expect(
        first,
        contains('Real numbers are all numbers on the number line.'),
      );
      expect(second, contains('They include rational and irrational numbers.'));
      expect(
        second,
        isNot(contains('Real numbers are all numbers on the number line.')),
      );
    });
  });
}

TutorMessage _message(String text, bool isUser, int seconds) {
  return TutorMessage(
    text: text,
    isUser: isUser,
    timestamp: DateTime(2026, 1, 1, 0, 0, seconds),
  );
}
