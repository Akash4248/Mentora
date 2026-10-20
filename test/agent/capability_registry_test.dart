import 'package:flutter_agent_harness/flutter_agent_harness.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/domain/capability_descriptor.dart';
import 'package:mentora/features/chat/domain/capability_registry.dart';
import 'package:mentora/features/chat/domain/default_capabilities.dart';

CapabilityDescriptor _testDescriptor({
  required String id,
  required String toolName,
  CapabilityPermissionTier tier = CapabilityPermissionTier.readOnly,
  Set<String> tags = const {},
  Map<String, dynamic> parameters = const {'type': 'object'},
}) {
  return CapabilityDescriptor(
    id: id,
    version: '1.0.0',
    displayName: toolName,
    description: 'Test descriptor for $id',
    tier: tier,
    tags: tags,
    tool: AgentTool(
      name: toolName,
      description: 'Test tool $toolName',
      parameters: parameters,
      execute: (args, cancelToken, onUpdate) async =>
          ToolExecutionResult.text('Result from $toolName'),
    ),
  );
}

String _resultText(ToolExecutionResult result) =>
    result.content.whereType<TextContent>().map((c) => c.text).join();

void main() {
  group('CapabilityRegistry', () {
    test('registers valid capability descriptors and allows lookup', () {
      final registry = CapabilityRegistry();
      final descriptor = _testDescriptor(
        id: 'test.read',
        toolName: 'test_read',
        parameters: const {
          'type': 'object',
          'properties': {
            'query': {'type': 'string'},
          },
          'required': ['query'],
        },
        tags: const {'test', 'search'},
      );

      registry.register(descriptor);

      expect(registry.lookupById('test.read'), same(descriptor));
      expect(registry.lookupByToolName('test_read'), same(descriptor));
      expect(registry.all, contains(descriptor));
    });

    test('rejects duplicate IDs or duplicate tool names', () {
      final registry = CapabilityRegistry();
      final d1 = _testDescriptor(id: 'cap.one', toolName: 'tool_one');
      final dDuplicateId = _testDescriptor(id: 'cap.one', toolName: 'tool_two');
      final dDuplicateName = _testDescriptor(id: 'cap.two', toolName: 'tool_one');

      registry.register(d1);
      expect(() => registry.register(dDuplicateId), throwsArgumentError);
      expect(() => registry.register(dDuplicateName), throwsArgumentError);
    });

    test('rejects descriptors with non-object JSON schema parameters', () {
      final registry = CapabilityRegistry();
      final invalidSchemaDescriptor = _testDescriptor(
        id: 'cap.invalid',
        toolName: 'tool_invalid',
        parameters: const {'type': 'string'},
      );

      expect(
        () => registry.register(invalidSchemaDescriptor),
        throwsArgumentError,
      );
    });

    test('filters tools by tags and explicit IDs within maxTools budget', () {
      final registry = CapabilityRegistry([
        _testDescriptor(
          id: 'math.calc',
          toolName: 'math_calculate',
          tags: const {'math', 'calc'},
        ),
        _testDescriptor(
          id: 'physics.sim',
          toolName: 'sim_lookup',
          tags: const {'physics', 'sim'},
        ),
        _testDescriptor(
          id: 'notes.save',
          toolName: 'notes_save',
          tier: CapabilityPermissionTier.stateChanging,
          tags: const {'notes'},
        ),
      ]);

      final mathTools = registry.resolveTools(tags: {'math'});
      expect(mathTools.length, 1);
      expect(mathTools.first.name, 'math_calculate');

      final idTools = registry.resolveTools(ids: {'physics.sim'});
      expect(idTools.length, 1);
      expect(idTools.first.name, 'sim_lookup');

      final cappedTools = registry.resolveTools(maxTools: 2);
      expect(cappedTools.length, 2);
    });

    test('enforces authorization policy based on permission tiers', () async {
      final registry = CapabilityRegistry([
        _testDescriptor(
          id: 'read.tool',
          toolName: 'read_tool',
          tier: CapabilityPermissionTier.readOnly,
        ),
        _testDescriptor(
          id: 'write.tool',
          toolName: 'write_tool',
          tier: CapabilityPermissionTier.stateChanging,
        ),
      ]);

      // Read-only is auto-approved
      expect(await registry.authorizeCall('read_tool', {}), isTrue);

      // State-changing is denied by default unless allowStateChanging is passed
      expect(await registry.authorizeCall('write_tool', {}), isFalse);
      expect(
        await registry.authorizeCall('write_tool', {}, allowStateChanging: true),
        isTrue,
      );

      // Unknown tool is denied
      expect(await registry.authorizeCall('unknown_tool', {}), isFalse);
    });

    group('Default Capabilities', () {
      test('math.calculate computes mathematical expressions safely', () async {
        final calcDescriptor = DefaultCapabilities.calculate();
        expect(calcDescriptor.id, 'math.calculate');
        expect(calcDescriptor.tier, CapabilityPermissionTier.readOnly);
        expect(calcDescriptor.name, 'calculate');

        final result1 = await calcDescriptor.tool.execute(
          {'expression': '15 * 4 + 10'},
          null,
          null,
        );
        expect(_resultText(result1), contains('70'));

        final result2 = await calcDescriptor.tool.execute(
          {'expression': 'sqrt(144) / 3'},
          null,
          null,
        );
        expect(_resultText(result2), contains('4'));

        // Invalid expression returns descriptive evaluation error without throwing
        final errorResult = await calcDescriptor.tool.execute(
          {'expression': 'invalid expression %^&*'},
          null,
          null,
        );
        expect(_resultText(errorResult), contains('Calculation error'));
      });

      test('simulation.lookup returns structured interactive lab metadata', () async {
        final simDescriptor = DefaultCapabilities.lookupSimulation();
        expect(simDescriptor.id, 'simulation.lookup');
        expect(simDescriptor.tier, CapabilityPermissionTier.readOnly);
        expect(simDescriptor.name, 'lookup_simulation');

        final result = await simDescriptor.tool.execute(
          {'topic': 'Motion'},
          null,
          null,
        );
        expect(_resultText(result), contains('Interactive Pendulum & Motion Lab'));
        expect(_resultText(result), contains('Formulas:'));
      });

      test('visual.render executes and returns mentora-visual block', () async {
        final visualDescriptor = DefaultCapabilities.showVisualization();
        expect(visualDescriptor.id, 'visual.render');
        expect(visualDescriptor.tier, CapabilityPermissionTier.readOnly);
        expect(visualDescriptor.name, 'show_visualization');

        final result = await visualDescriptor.tool.execute(
          {
            'type': 'circuit.schematic',
            'scenario': 'series_circuit',
            'title': "Kirchhoff's Laws",
            'inputs': {'voltage': 12.0, 'resistances': [10.0, 20.0]},
          },
          null,
          null,
        );
        expect(_resultText(result), contains('mentora-visual'));
        expect(_resultText(result), contains('series_circuit'));
        expect(_resultText(result), contains("Kirchhoff's Laws"));
      });
    });
  });
}
