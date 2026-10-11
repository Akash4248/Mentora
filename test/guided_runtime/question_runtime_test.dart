import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/guided_runtime/models/experiment_question.dart';

void main() {
  test('Question validates answer case-insensitively', () {
    const question = ExperimentQuestion(
      id: 'q1',
      question: 'What happens?',
      type: ExperimentQuestionType.multipleChoice,
      correctAnswer: 'Period increases',
    );

    expect(question.isCorrect('period INCREASES'), isTrue);
    expect(question.isCorrect('Period decreases'), isFalse);
  });
}
