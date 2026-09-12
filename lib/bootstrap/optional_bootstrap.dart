import '../config/app_environment.dart';
import '../features/chat/data/platform_tutor_inference_gateway.dart';
import '../features/educational/application/network_resilience.dart';
import '../features/educational/application/sync_manager.dart';
import '../features/network/application/distributed_service_composer.dart';
import '../features/network/domain/backend_config.dart';
import '../features/network/services/backend_discovery_service.dart';
import 'runtime_mode.dart';
import 'startup_coordinator.dart';

class OptionalBootstrap {
  OptionalBootstrap({required StartupCoordinator coordinator}) : _coordinator = coordinator;

  final StartupCoordinator _coordinator;
  bool _started = false;

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    Future<void>(() async {
      await _run();
    });
  }

  Future<void> _run() async {
    if (_coordinator.runtimeMode == RuntimeMode.offline || !AppEnvironment.enableBackend) {
      _coordinator.markOptionalComplete();
      return;
    }

    try {
      _coordinator.beginStep('Connecting backend services');
      final backendConfig = BackendConfig.fromEnvironment();
      if (backendConfig == null) {
        _coordinator.completeStep('Connecting backend services', detail: 'Backend config unavailable');
        return;
      }

      await DistributedServiceComposer().initialize(
        backendConfig: backendConfig,
        platformGateway: PlatformTutorInferenceGateway(),
      );
      _coordinator.markBackendConnected();
      _coordinator.completeStep('Connecting backend services');

      _coordinator.beginStep('Starting resilience monitoring');
      NetworkResilienceCoordinator().startMonitoring();
      BackendDiscoveryService().startBackgroundMonitoring();
      _coordinator.completeStep('Starting resilience monitoring');

      _coordinator.beginStep('Checking pack versions');
      _coordinator.markSyncReady();
      _coordinator.completeStep('Checking pack versions');
    } catch (e) {
      AppEnvironment.log('SYNC', '[OptionalBootstrap] Optional services failed: $e');
    } finally {
      _coordinator.markOptionalComplete();
    }
  }
}
