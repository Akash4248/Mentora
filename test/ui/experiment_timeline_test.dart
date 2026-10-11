import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/experience/workspace/experiment_timeline.dart';

void main() {
  testWidgets('experiment timeline renders workflow labels', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ExperimentTimeline(
            completedStepIds: {'predict', 'run'},
            currentIndex: 2,
          ),
        ),
      ),
    );

    expect(find.text('Predict'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('Observe'), findsOneWidget);
    expect(find.text('Compare'), findsOneWidget);
    expect(find.text('Conclude'), findsOneWidget);
  });
}
