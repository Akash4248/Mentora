import 'dart:async';

import '../../simulation_context/providers/simulation_context_provider.dart';
import '../runtime/runtime_event_bus.dart';
import '../runtime/runtime_world.dart';

/// Bridges the local experiment RuntimeWorld state to the global SimulationContextNotifier
/// so that the Tutor (via ConversationProvider) can access the current state of
/// the experiment when the user asks a question.
class ExperimentContextBridge {
  final SimulationContextNotifier _notifier;
  final RuntimeEventBus _eventBus;
  final RuntimeWorld _world;
  final String _experimentId;
  final String _experimentName;
  
  StreamSubscription? _subscription;
  Timer? _debounceTimer;

  ExperimentContextBridge({
    required SimulationContextNotifier notifier,
    required RuntimeEventBus eventBus,
    required RuntimeWorld world,
    required String experimentId,
    required String experimentName,
  })  : _notifier = notifier,
        _eventBus = eventBus,
        _world = world,
        _experimentId = experimentId,
        _experimentName = experimentName {
    _init();
  }

  void _init() {
    // Listen to all runtime events
    _subscription = _eventBus.stream.listen((event) {
      _scheduleUpdate();
    });
    // Initial population
    _performUpdate();
  }

  void _scheduleUpdate() {
    if (_debounceTimer?.isActive ?? false) return;
    _debounceTimer = Timer(const Duration(milliseconds: 200), () {
      _performUpdate();
    });
  }

  void _performUpdate() {
    final variables = <String, dynamic>{};
    
    // Extract state from the world's objects
    for (final state in _world.objects.allObjectStates) {
      final itemData = <String, dynamic>{};
      if (state.state.isNotEmpty) {
        itemData['properties'] = state.state;
      }
      itemData['state'] = {
        'visible': state.visible,
      };
      variables[state.objectId] = itemData;
    }
    
    // Extract simple variables
    for (final variable in _world.variables.getAllVariables()) {
      variables[variable.id] = variable.value;
    }

    final currentState = _world.clock.isPaused ? 'Paused' : 'Active';

    _notifier.update(
      experimentId: _experimentId,
      experimentName: _experimentName,
      variables: variables,
      currentState: currentState,
    );
  }

  void dispose() {
    _debounceTimer?.cancel();
    _subscription?.cancel();
    _notifier.clear();
  }
}
