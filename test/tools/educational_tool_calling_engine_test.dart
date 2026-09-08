import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tutor_app/features/chat/application/educational_tool_calling_engine.dart';

void main() {
  group('EducationalToolCallingEngine Tests', () {
    test('evaluateMath evaluates simple arithmetic correctly', () {
      final engine = EducationalToolCallingEngine.instance;
      final result = engine.evaluateMath('10 + 5 * 2');
      expect(result.isSuccess, true);
      expect(result.outputText, '20');
    });

    test('evaluateMath handles parentheses and powers', () {
      final engine = EducationalToolCallingEngine.instance;
      final result = engine.evaluateMath('2 * (3 + 4) ^ 2');
      expect(result.isSuccess, true);
      expect(result.outputText, '98');
    });

    test('evaluateMath handles pi constant and trigonometric functions', () {
      final engine = EducationalToolCallingEngine.instance;
      final result = engine.evaluateMath('sin(pi / 2)');
      expect(result.isSuccess, true);
      expect(double.parse(result.outputText), closeTo(1.0, 0.01));
    });

    test('processAndExecuteToolCalls replaces calculate tool tags inline', () {
      final engine = EducationalToolCallingEngine.instance;
      const input = 'The total area is [TOOL: calculate("10 * 5")] square units.';
      final processed = engine.processAndExecuteToolCalls(input);
      expect(processed, 'The total area is `10 * 5 = 50` square units.');
    });

    test('processAndExecuteToolCalls handles unquoted tool calls', () {
      final engine = EducationalToolCallingEngine.instance;
      const input = 'Result: calculate("100 / 4")';
      final processed = engine.processAndExecuteToolCalls(input);
      expect(processed, 'Result: `100 / 4 = 25`');
    });
  });
}
