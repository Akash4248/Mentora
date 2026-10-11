import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/builder/templates/experiment_templates.dart';
import 'package:mentora/features/experiment/runtime/runtime_loader.dart';

void main() {
  group('Visualization-first runtime integration', () {
    test('built-in templates attach active visualization profiles', () {
      final expectedProfiles = {
        'Free Fall Experiment': 'freeFall',
        'Heart Rate Monitor': 'heartRate',
        'Pendulum Motion': 'pendulum',
        'Plant Growth': 'plantGrowth',
        'Water Cycle': 'waterCycle',
      };

      for (final template in ExperimentTemplates.allTemplates) {
        final world = RuntimeLoader.loadFromManifest(template);
        final title = template['scene']?['name']?.toString() ?? '';
        final state = world.visualizationState;

        expect(state, isNotNull, reason: '$title should attach a profile.');
        expect(state!.activeProfile.presetId, expectedProfiles[title]);
        expect(state.activeEnvironment.id, isNotEmpty);
        expect(state.activeAnimations, greaterThan(0));
        expect(state.particlesSpawned, lessThanOrEqualTo(50));
        world.dispose();
      }
    });

    test('idle animation changes actor state before run is pressed', () {
      final world = RuntimeLoader.loadFromManifest(
        ExperimentTemplates.pendulum,
      );
      final actorBefore = world.simulationCanvas.actor('preset_pendulum_rod');

      expect(actorBefore, isNotNull);
      world.tick(1 / 60);
      world.tick(1 / 60);
      world.tick(1 / 60);

      final actorAfter = world.simulationCanvas.actor('preset_pendulum_rod');
      expect(actorAfter, isNotNull);
      expect(actorAfter!.rotation, isNot(equals(actorBefore!.rotation)));
      expect(world.clock.isRunning, isFalse);
      world.dispose();
    });

    test('visual response events are emitted for parameter changes', () async {
      final world = RuntimeLoader.loadFromManifest(
        ExperimentTemplates.heartRate,
      );
      final events = <String>[];
      final sub = world.eventBus.stream.listen((event) {
        events.add(event.message);
      });

      world.variables.updateVariable('var_pulse', 90);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(events, contains('VisualResponseTriggered'));
      expect(events, contains('VisualNarrationShown'));
      await sub.cancel();
      world.dispose();
    });
  });
}
