import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/application/visual_fallback_policy.dart';
import 'package:mentora/features/chat/application/visual_resolver.dart';
import 'package:mentora/features/chat/application/visual_schema_registry.dart';
import 'package:mentora/features/chat/domain/visual_intent.dart';

void main() {
  group('Lab Visual Runtime Integration Suite', () {
    const registry = VisualSchemaRegistry();
    const resolver = VisualResolver();
    const fallbackPolicy = VisualFallbackPolicy();

    test('VisualSchemaRegistry validates and approves valid lab.setup intent', () {
      const intent = VisualIntent(
        type: VisualType.labSetup,
        scenario: 'exp_incline_friction',
        inputs: {'experiment_id': 'exp_incline_friction'},
        title: 'Incline Friction Lab',
      );

      final report = registry.validate(intent);
      expect(report.isValid, isTrue);
      expect(report.errors, isEmpty);
    });

    test('VisualSchemaRegistry rejects lab.setup with empty experiment_id', () {
      const invalidIntent = VisualIntent(
        type: VisualType.labSetup,
        scenario: '',
        inputs: {'experiment_id': ''},
      );

      final report = registry.validate(invalidIntent);
      expect(report.isValid, isFalse);
      expect(report.errors.first, contains('requires a non-empty experiment_id'));
    });

    test('VisualResolver resolves lab.setup intent into LabSetupVisualPayload with definition', () {
      const intent = VisualIntent(
        type: VisualType.labSetup,
        scenario: 'exp_incline_friction',
        inputs: {'experiment_id': 'exp_incline_friction'},
      );

      final payload = resolver.resolve(intent);
      expect(payload, isA<LabSetupVisualPayload>());

      final labPayload = payload as LabSetupVisualPayload;
      expect(labPayload.definition.id, 'exp_incline_friction');
      expect(labPayload.definition.title, contains('Incline Plane'));
      expect(labPayload.definition.safetyInstructions, isNotEmpty);
    });

    test('VisualFallbackPolicy deterministically matches sensor lab queries to lab.setup', () {
      final fallback = fallbackPolicy.matchDeterministicFallback(
        question: 'Can we do an incline experiment to test friction with phone sensor?',
        existingIntents: const [],
      );

      expect(fallback, isNotNull);
      expect(fallback!.type, VisualType.labSetup);
      expect(fallback.scenario, 'exp_incline_friction');
      expect(fallback.title, contains('Incline Plane'));
    });
  });
}
