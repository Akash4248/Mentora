import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/network/application/confidence_evaluator.dart';
import 'package:mentora/features/network/application/educational_complexity_analyzer.dart';
import 'package:mentora/features/network/application/stream_recovery_manager.dart';
import 'package:mentora/features/network/application/stream_transition_manager.dart';

void main() {
  test('confidence evaluator flags repeated and incomplete text', () {
    final evaluator = ConfidenceEvaluator();
    final score = evaluator.evaluate('This is a repeated repeated repeated response:');

    expect(score.score, lessThan(0.8));
    expect(score.reasons, contains('repetition'));
    expect(score.reasons, contains('incomplete'));
  });

  test('educational complexity analyzer detects math and complexity', () {
    const analyzer = EducationalComplexityAnalyzer();
    final result = analyzer.analyze('Explain how to solve this algebra equation step by step and show work');

    expect(result.subject, 'math');
    expect(result.score, greaterThan(0.4));
  });

  test('stream recovery retries after failure', () async {
    var attempts = 0;
    final recovery = StreamRecoveryManager(maxAttempts: 1);

    final output = <String>[];
    await for (final chunk in recovery.recover(() {
      attempts += 1;
      if (attempts == 1) {
        return Stream<String>.error(StateError('boom'));
      }
      return Stream<String>.fromIterable(const ['ok']);
    })) {
      output.add(chunk);
    }

    expect(attempts, 2);
    expect(output, contains('ok'));
  });

  test('stream transition upgrades from primary to secondary', () async {
    final transition = StreamTransitionManager(transitionWindow: Duration.zero);
    final output = <String>[];

    await for (final chunk in transition.upgradeStream(
      primary: Stream<String>.fromIterable(const ['local']),
      secondary: Stream<String>.fromIterable(const ['backend']),
    )) {
      output.add(chunk);
    }

    expect(output, ['local', 'backend']);
  });
}
