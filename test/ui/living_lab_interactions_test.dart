import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/experience/lab_v2/interactions/cause_effect_overlay.dart';
import 'package:mentora/features/experiment/experience/lab_v2/interactions/experiment_activity_feed.dart';
import 'package:mentora/features/experiment/experience/lab_v2/interactions/experiment_narrator.dart';
import 'package:mentora/features/experiment/experience/lab_v2/interactions/insight_card.dart';
import 'package:mentora/features/experiment/experience/lab_v2/interactions/journey_progress.dart';
import 'package:mentora/features/experiment/experience/lab_v2/interactions/simulation_environment.dart';
import 'package:mentora/features/experiment/runtime/runtime_event.dart';
import 'package:mentora/features/experiment/runtime/runtime_event_bus.dart';

void main() {
  testWidgets('control events create visible cause-effect feedback', (
    tester,
  ) async {
    final eventBus = RuntimeEventBus();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              CauseEffectOverlay(eventBus: eventBus),
              ExperimentActivityFeed(eventBus: eventBus),
              ExperimentNarrator(eventBus: eventBus),
            ],
          ),
        ),
      ),
    );

    eventBus.emit(_event('SliderChanged', {'label': 'Length', 'value': 2.5}));
    await tester.pump();

    expect(find.text('Length affected the lab'), findsOneWidget);
    expect(find.text('Length changed'), findsOneWidget);
    expect(
      find.text('Length changed to 2.5. Watch the experiment respond.'),
      findsOneWidget,
    );

    eventBus.dispose();
  });

  testWidgets('conclusion events surface insight cards', (tester) async {
    final eventBus = RuntimeEventBus();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(children: [InsightCard(eventBus: eventBus)]),
        ),
      ),
    );

    eventBus.emit(
      _event('ConclusionGenerated', {
        'conclusion': 'As length increased, period increased.',
      }),
    );
    await tester.pump();

    expect(find.text('Insight'), findsOneWidget);
    expect(find.text('As length increased, period increased.'), findsOneWidget);

    eventBus.dispose();
  });

  testWidgets('environment and journey widgets render lab context', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SimulationEnvironment(mode: 'space'),
              Positioned(
                left: 16,
                top: 16,
                child: JourneyProgress(guidedEngine: null),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(SimulationEnvironment), findsOneWidget);
  });
}

RuntimeEvent _event(String message, [Map<String, dynamic>? metadata]) {
  return RuntimeEvent(
    id: '${message}_${DateTime.now().microsecondsSinceEpoch}',
    timestamp: DateTime.now(),
    type: RuntimeEventType.custom,
    message: message,
    metadata: metadata,
  );
}
