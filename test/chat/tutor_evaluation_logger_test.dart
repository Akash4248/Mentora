import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/tutor_evaluation_logger.dart';

void main() {
  group('TutorTurnEvaluation', () {
    test('records tool calls, metrics, and logs evaluation summary properly', () {
      final eval = TutorTurnEvaluation(
        sessionId: 'test_session_123',
        grade: 10,
        topic: 'Areas Related to Circles',
        question: 'Calculate the perimeter of a circle with radius 7m',
        strategy: 'workedProblem',
      );

      expect(eval.toolCalls, isEmpty);

      // Start tool call
      eval.startToolCall(
        toolName: 'math.calculate',
        arguments: {'expression': '2 * 3.14159 * 7'},
      );
      expect(eval.toolCalls.length, 1);
      expect(eval.toolCalls.first.toolName, 'math.calculate');
      expect(eval.toolCalls.first.status, 'started');

      // Complete tool call
      eval.completeToolCall(
        toolName: 'math.calculate',
        output: '43.98226',
      );
      expect(eval.toolCalls.first.status, 'completed');
      expect(eval.toolCalls.first.output, '43.98226');

      // Start second tool call
      eval.startToolCall(
        toolName: 'simulation.lookup',
        arguments: {'topic': 'circle perimeter'},
      );
      expect(eval.toolCalls.length, 2);

      eval.completeToolCall(
        toolName: 'simulation.lookup',
        output: 'Found simulation: Circle Geometry Lab',
      );
      expect(eval.toolCalls[1].status, 'completed');

      // Finish turn
      eval.finishTurn(answer: 'The perimeter of the circle is 43.98 meters.');

      expect(eval.finalAnswer, contains('43.98 meters'));
      expect(eval.toolCalls.length, 2);
      expect(eval.endedAt, isNotNull);
    });
  });
}
