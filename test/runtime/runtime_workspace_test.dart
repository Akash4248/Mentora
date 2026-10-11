import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/presentation/runtime_workspace/runtime_orientation_lock.dart';
import 'package:mentora/features/experiment/presentation/runtime_workspace/runtime_toolbar.dart';
import 'package:mentora/features/experiment/presentation/runtime_workspace/runtime_view_mode.dart';
import 'package:mentora/features/experiment/presentation/runtime_workspace/runtime_workspace.dart';
import 'package:mentora/features/experiment/presentation/runtime_workspace/runtime_workspace_layout_manager.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_layout.dart';
import 'package:mentora/features/experiment/runtime/models/runtime_object_state.dart';
import 'package:mentora/features/experiment/runtime/object_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('runtime workspace', () {
    test('object categorization places objects in student zones', () {
      final layout = RuntimeWorkspaceLayoutManager().build([
        _state('display_1', 'numericDisplay'),
        _state('control_1', 'slider'),
        _state('graph_1', 'scatterPlot'),
        _state('data_1', 'table'),
        _state('hidden_1', 'gauge', visible: false),
      ]);

      expect(layout.displays.map((state) => state.objectId), ['display_1']);
      expect(layout.controls.map((state) => state.objectId), ['control_1']);
      expect(layout.visualizations.map((state) => state.objectId), ['graph_1']);
      expect(layout.data.map((state) => state.objectId), ['data_1']);
    });

    testWidgets('student workspace is experiment-first and hides internals', (
      tester,
    ) async {
      final registry = ObjectRegistry()
        ..registerObjectState(
          _state(
            'temperature_display',
            'numericDisplay',
            state: {'label': 'Temperature', 'value': 25, 'unit': 'C'},
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 520,
              child: RuntimeWorkspace(
                objectRegistry: registry,
                simulationCanvas: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Temperature'), findsOneWidget);
      expect(find.textContaining('25'), findsOneWidget);
      expect(find.text('Experiment Workspace'), findsNothing);
      expect(find.text('Displays'), findsNothing);
      expect(find.text('No displays configured.'), findsNothing);
      expect(find.text('Variables'), findsNothing);
      expect(find.text('Rules'), findsNothing);
      expect(find.text('Bindings'), findsNothing);
    });

    testWidgets('debug toggle opens and closes developer mode', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: _RuntimeModeHarness()));

      expect(find.text('Experiment Canvas'), findsOneWidget);
      expect(find.text('Variables'), findsNothing);

      await tester.tap(find.text('Debug'));
      await tester.pumpAndSettle();

      expect(find.text('Developer Panel'), findsOneWidget);
      expect(find.text('Variables'), findsOneWidget);

      await tester.tap(find.text('Student'));
      await tester.pumpAndSettle();

      expect(find.text('Developer Panel'), findsNothing);
      expect(find.text('Variables'), findsNothing);
    });

    test('landscape lock and restore call SystemChrome orientations', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            calls.add(call);
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await RuntimeOrientationLock.lockLandscape();
      await RuntimeOrientationLock.restore();

      expect(calls.length, 2);
      expect(calls.first.method, 'SystemChrome.setPreferredOrientations');
      expect(
        calls.first.arguments,
        containsAll([
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.landscapeRight',
        ]),
      );
      expect(calls.last.method, 'SystemChrome.setPreferredOrientations');
      expect(
        calls.last.arguments,
        containsAll([
          'DeviceOrientation.portraitUp',
          'DeviceOrientation.landscapeLeft',
          'DeviceOrientation.portraitDown',
          'DeviceOrientation.landscapeRight',
        ]),
      );
    });
  });
}

class _RuntimeModeHarness extends StatefulWidget {
  const _RuntimeModeHarness();

  @override
  State<_RuntimeModeHarness> createState() => _RuntimeModeHarnessState();
}

class _RuntimeModeHarnessState extends State<_RuntimeModeHarness> {
  RuntimeViewMode mode = RuntimeViewMode.student;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          RuntimeToolbar(
            experimentName: 'Mode Test',
            status: 'RUNNING',
            elapsed: const Duration(seconds: 5),
            warningCount: 0,
            developerMode: mode == RuntimeViewMode.developer,
            onToggleDebug: () {
              setState(() {
                mode = mode == RuntimeViewMode.student
                    ? RuntimeViewMode.developer
                    : RuntimeViewMode.student;
              });
            },
          ),
          const Expanded(child: Center(child: Text('Experiment Canvas'))),
          if (mode == RuntimeViewMode.developer)
            const SizedBox(
              height: 80,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [Text('Developer Panel'), Text('Variables')],
              ),
            ),
        ],
      ),
    );
  }
}

RuntimeObjectState _state(
  String id,
  String type, {
  bool visible = true,
  Map<String, dynamic> state = const {},
}) {
  return RuntimeObjectState(
    objectId: id,
    objectType: type,
    state: state,
    visible: visible,
    updatedAt: DateTime(2026, 6, 10),
    layout: const RuntimeObjectLayout(
      x: 0,
      y: 0,
      width: 180,
      height: 96,
      alignment: 'center',
    ),
  );
}
