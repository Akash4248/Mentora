import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/visualization_first/visualization_first.dart';

void main() {
  group('Visualization-first runtime profiles', () {
    test('all built-in profiles certify as alive within 3 seconds', () {
      final certifier = VisualizationFirstCertifier();
      final results = certifier.certifyAll(AnimationFirstPresetRegistry.all);

      expect(results, hasLength(5));
      for (final result in results) {
        expect(
          result.passed,
          isTrue,
          reason: '${result.presetId} failed: ${result.failures.join(', ')}',
        );
        expect(result.hasIdleMotion, isTrue);
        expect(result.startsWithinThreeSeconds, isTrue);
        expect(result.hasParameterResponse, isTrue);
      }
    });

    test('every profile has at least one supported motion type', () {
      for (final profile in AnimationFirstPresetRegistry.all) {
        expect(profile.idleMotions, isNotEmpty);
        expect(
          profile.idleMotions.any((motion) {
            return VisualMotionSpec.supportedMotionTypes.contains(
              motion.motionType,
            );
          }),
          isTrue,
          reason: '${profile.presetId} needs move/rotate/pulse/orbit/etc.',
        );
      }
    });

    test('particle systems are generic and mobile safe', () {
      expect(
        GenericParticleLibrary.all.map((p) => p.id),
        contains('flow_particles'),
      );
      expect(
        GenericParticleLibrary.all.map((p) => p.id),
        contains('heat_particles'),
      );
      expect(
        GenericParticleLibrary.all.map((p) => p.id),
        contains('water_particles'),
      );
      expect(
        GenericParticleLibrary.all.map((p) => p.id),
        contains('spark_particles'),
      );
      expect(
        GenericParticleLibrary.all.map((p) => p.id),
        contains('motion_trails'),
      );

      for (final profile in GenericParticleLibrary.all) {
        expect(profile.isMobileSafe, isTrue);
      }
    });

    test('animated graph profiles are valid and lightweight', () {
      for (final profile in AnimatedGraphProfileRegistry.all) {
        expect(profile.isValid, isTrue);
      }
      expect(
        AnimatedGraphProfileRegistry.barChart.enterAnimation,
        'bars_grow_from_zero',
      );
      expect(
        AnimatedGraphProfileRegistry.scatterPlot.updateAnimation,
        'pulse_new_point',
      );
    });

    test('visual narration is rule based and action-oriented', () {
      final narrator = VisualEventNarrator();
      final text = narrator.narrate(
        VisualCauseEffectEvent(
          sourceId: 'pendulum.length',
          targetId: 'preset_pendulum_bob',
          changedValueLabel: '2m',
          visualResponse: 'pulse',
        ),
      );

      expect(text, contains('Pendulum length changed'));
      expect(text, contains('swing responds'));
    });

    test('focus requests remain short and valid', () {
      final request = const VisualFocusPolicy().forTaskReference(
        referencedId: 'preset_graph',
        category: 'graph',
        taskText: 'Observe the graph point.',
      );

      expect(request.isValid, isTrue);
      expect(request.durationSeconds <= 3, isTrue);
    });
  });
}
