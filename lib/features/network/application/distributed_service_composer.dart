import 'package:offline_tutor_app/features/chat/data/tutor_inference_gateway.dart';

import '../../../config/app_environment.dart';
import '../data/backend_api_service.dart';
import '../data/backend_health_monitor.dart';
import '../data/connectivity_service.dart';
import '../data/network_state_service.dart';
import '../domain/backend_config.dart';
import '../domain/inference_router.dart';
import '../domain/local_inference_source.dart';
import '../application/hybrid_inference_service.dart';
import 'confidence_evaluator.dart';
import 'educational_complexity_analyzer.dart';
import 'escalation_coordinator.dart';
import 'stream_transition_manager.dart';
import 'stream_recovery_manager.dart';
import 'subject_routing_coordinator.dart';
import 'intent_detector.dart';
import 'routing_metrics.dart';
import 'stream_coordinator.dart';
import 'pi_hub_discovery_coordinator.dart';
import 'backend_url_manager.dart';
import 'connectivity_controller.dart';
import 'discovery_sync_bridge.dart';
import 'classroom_session_manager.dart';
import 'reconnect_coordinator.dart';
import 'pack_version_manager.dart';
import 'incremental_sync_coordinator.dart';
import 'pack_recovery_manager.dart';
import 'pack_integrity_validator.dart';
import 'incremental_pack_recovery_manager.dart';
import 'local_pack_persistence_coordinator.dart';
import 'transfer_integrity_validator.dart';
import 'distributed_metrics_service.dart';
import 'connectivity_diagnostics.dart';
import 'routing_diagnostics.dart';
import 'sync_diagnostics_manager.dart';
import 'offline_state_persistence.dart';
import 'deferred_sync_manager.dart';
import 'offline_recovery_coordinator.dart';
import 'connectivity_state_coordinator.dart';
import 'distributed_state_publisher.dart';
import 'session_persistence_manager.dart';
import 'heartbeat_recovery_service.dart';
import 'classroom_recovery_coordinator.dart';
import 'classroom_presence_coordinator.dart';
import 'multi_device_recovery_manager.dart';
import 'sync_queue_balancer.dart';
import 'recovery_diagnostics_manager.dart';
import 'classroom_metrics_collector.dart';
import 'distributed_health_tracker.dart';
import 'distributed_state_recovery_coordinator.dart';
import 'connectivity_persistence_manager.dart';
import 'classroom_state_persistence.dart';
import 'persistent_classroom_recovery_manager.dart';
import 'persistent_sync_recovery_manager_v2.dart';
import 'manifest_recovery_coordinator.dart';
import 'deployment_diagnostics_manager.dart';


/// Singleton service composition root for the distributed client.
class DistributedServiceComposer {
  static final DistributedServiceComposer _instance = DistributedServiceComposer._internal();

  factory DistributedServiceComposer() {
    return _instance;
  }

  DistributedServiceComposer._internal();

  // Services
  late BackendConfig _backendConfig;
  late BackendApiService _backendService;
  late ConnectivityService _connectivityService;
  late NetworkStateService _networkStateService;
  late BackendHealthMonitor _healthMonitor;
  late InferenceRouter _inferenceRouter;
  late HybridInferenceService _hybridInferenceService;
  // New services
  late ConfidenceEvaluator _confidenceEvaluator;
  late EducationalComplexityAnalyzer _educationalComplexityAnalyzer;
  late EscalationCoordinator _escalationCoordinator;
  late StreamTransitionManager _streamTransitionManager;
  late StreamRecoveryManager _streamRecoveryManager;
  late SubjectRoutingCoordinator _subjectRoutingCoordinator;
  late StreamCoordinator _streamCoordinator;
  late RoutingMetricsTracker _routingMetrics;
  late IntentDetector _intentDetector;
  late PiHubDiscoveryCoordinator _piHubDiscoveryCoordinator;
  late BackendUrlManager _backendUrlManager;
  late ConnectivityController _connectivityController;
  late DiscoverySyncBridge _discoverySyncBridge;
  late ClassroomSessionManager _classroomSessionManager;
  late ReconnectCoordinator _reconnectCoordinator;
  late PackVersionManager _packVersionManager;
  late IncrementalSyncCoordinator _incrementalSyncCoordinator;
  late PackRecoveryManager _packRecoveryManager;
  late PackIntegrityValidator _packIntegrityValidator;
  late IncrementalPackRecoveryManager _incrementalPackRecoveryManager;
  late LocalPackPersistenceCoordinator _localPackPersistenceCoordinator;
  late TransferIntegrityValidator _transferIntegrityValidator;
  late DistributedMetricsService _distributedMetricsService;
  late ConnectivityDiagnostics _connectivityDiagnostics;
  late RoutingDiagnostics _routingDiagnostics;
  late SyncDiagnosticsManager _syncDiagnosticsManager;
  late OfflineStatePersistence _offlineStatePersistence;
  late DeferredSyncManager _deferredSyncManager;
  late OfflineRecoveryCoordinator _offlineRecoveryCoordinator;
  late ConnectivityStateCoordinator _connectivityStateCoordinator;
  late DistributedStatePublisher _distributedStatePublisher;
  late SessionPersistenceManager _sessionPersistenceManager;
  late HeartbeatRecoveryService _heartbeatRecoveryService;
  late ClassroomRecoveryCoordinator _classroomRecoveryCoordinator;
  late ClassroomPresenceCoordinator _classroomPresenceCoordinator;
  late MultiDeviceRecoveryManager _multiDeviceRecoveryManager;
  late SyncQueueBalancer _syncQueueBalancer;
  late RecoveryDiagnosticsManager _recoveryDiagnosticsManager;
  late ClassroomMetricsCollector _classroomMetricsCollector;
  late DistributedHealthTracker _distributedHealthTracker;
  late DistributedStateRecoveryCoordinator _distributedStateRecoveryCoordinator;
  late ConnectivityPersistenceManager _connectivityPersistenceManager;
  late ClassroomStatePersistence _classroomStatePersistence;
  late PersistentClassroomRecoveryManager _persistentClassroomRecoveryManager;
  late PersistentSyncRecoveryManager _persistentSyncRecoveryManager;
  late ManifestRecoveryCoordinator _manifestRecoveryCoordinator;
  late DeploymentDiagnosticsCoordinator _deploymentDiagnosticsCoordinator;

  bool _initialized = false;

  /// Initialize all services
  Future<void> initialize({
    required BackendConfig backendConfig,
    required TutorInferenceGateway platformGateway,
  }) async {
    if (_initialized) {
      return;
    }

    _backendConfig = backendConfig;

    // Backend communication
    _backendService = BackendApiService(config: _backendConfig);

    // Connectivity monitoring
    _connectivityService = ConnectivityService();
    _networkStateService = NetworkStateService(
      connectivityService: _connectivityService,
    );
    
    AppEnvironment.log(
      'BACKEND',
      'Network state service initialized: ${AppEnvironment.backendBaseUrl}',
    );

    // Health monitoring
    _healthMonitor = BackendHealthMonitor(
      backendService: _backendService,
    );

    // Local inference adapter
    final localInference = platformGateway as LocalInferenceSource;

    // Inference routing
    _inferenceRouter = InferenceRouter(
      networkStateService: _networkStateService,
      localInference: localInference,
    );

    // Additional helpers
    _confidenceEvaluator = ConfidenceEvaluator();
    _educationalComplexityAnalyzer = EducationalComplexityAnalyzer();
    _escalationCoordinator = EscalationCoordinator();
    _streamTransitionManager = StreamTransitionManager();
    _streamRecoveryManager = StreamRecoveryManager();
    _subjectRoutingCoordinator = SubjectRoutingCoordinator();
    _streamCoordinator = StreamCoordinator();
    _routingMetrics = RoutingMetricsTracker();
    _intentDetector = IntentDetector();
    _piHubDiscoveryCoordinator = PiHubDiscoveryCoordinator();
    _backendUrlManager = BackendUrlManager(initialUrl: backendConfig.baseUrl);
    _connectivityController = ConnectivityController();
    _discoverySyncBridge = DiscoverySyncBridge(
      discovery: _piHubDiscoveryCoordinator,
      urlManager: _backendUrlManager,
      connectivity: _connectivityController,
      onSyncRequested: () async {
        // Bulk sync replaced by Grade-based Selective Sync.
        // Discovery correctly updates the URL, but automatic full sync is disabled.
      },
    );
    _discoverySyncBridge.start();

    // CRITICAL: Fire discovery as a deferred background task.
    // Delayed 5 seconds to ensure the UI renders completely before any
    // connectivity state transitions (online/syncing) trigger widget rebuilds
    // that freeze the My Learning and Dashboard screens on startup.
    print('[DISCOVERY] BOOTSTRAP_DISCOVERY_SCHEDULED (+5s)');
    Future<void>.delayed(const Duration(seconds: 5), () {
      print('[DISCOVERY] BOOTSTRAP_DISCOVERY_TRIGGERED');
      _discoverySyncBridge.discoverAndSync().catchError((e) {
        print('[DISCOVERY] BOOTSTRAP_DISCOVERY_ERROR=$e');
      });
    });

    // Wire URL changes to BackendConfig so all HTTP requests use new URL
    _backendUrlManager.urlChanges.listen((newUrl) {
      _backendConfig.updateUrl(newUrl);
    });
    _classroomSessionManager = ClassroomSessionManager();
    _reconnectCoordinator = ReconnectCoordinator(sessions: _classroomSessionManager);
    _packVersionManager = PackVersionManager();
    _incrementalSyncCoordinator = IncrementalSyncCoordinator(versions: _packVersionManager);
    _packRecoveryManager = const PackRecoveryManager();
    _packIntegrityValidator = const PackIntegrityValidator();
    _incrementalPackRecoveryManager = const IncrementalPackRecoveryManager();
    _localPackPersistenceCoordinator = LocalPackPersistenceCoordinator();
    _persistentSyncRecoveryManager = PersistentSyncRecoveryManager();
    _transferIntegrityValidator = const TransferIntegrityValidator();
    _distributedMetricsService = DistributedMetricsService();
    _connectivityDiagnostics = const ConnectivityDiagnostics();
    _routingDiagnostics = const RoutingDiagnostics();
    _syncDiagnosticsManager = SyncDiagnosticsManager();
    _offlineStatePersistence = OfflineStatePersistence();
    _deferredSyncManager = DeferredSyncManager();
    _offlineRecoveryCoordinator = OfflineRecoveryCoordinator(
      persistence: _offlineStatePersistence,
      deferredSync: _deferredSyncManager,
    );
    _connectivityStateCoordinator = ConnectivityStateCoordinator();
    _distributedStatePublisher = DistributedStatePublisher();
    _sessionPersistenceManager = SessionPersistenceManager();
    _heartbeatRecoveryService = HeartbeatRecoveryService(sessions: _classroomSessionManager);
    _classroomRecoveryCoordinator = ClassroomRecoveryCoordinator(
      persistence: _sessionPersistenceManager,
      sessions: _classroomSessionManager,
      heartbeatRecovery: _heartbeatRecoveryService,
    );
    _classroomPresenceCoordinator = ClassroomPresenceCoordinator();
    _multiDeviceRecoveryManager = MultiDeviceRecoveryManager();
    _syncQueueBalancer = SyncQueueBalancer();
    _recoveryDiagnosticsManager = RecoveryDiagnosticsManager();
    _classroomMetricsCollector = ClassroomMetricsCollector();
    _distributedHealthTracker = DistributedHealthTracker();
    _distributedStateRecoveryCoordinator = DistributedStateRecoveryCoordinator();
    _connectivityPersistenceManager = ConnectivityPersistenceManager();
    _classroomStatePersistence = ClassroomStatePersistence();

    // Enhanced recovery managers
    _persistentClassroomRecoveryManager = PersistentClassroomRecoveryManager(
      persistence: _sessionPersistenceManager,
      sessions: _classroomSessionManager,
    );
    _persistentSyncRecoveryManager = PersistentSyncRecoveryManager();
    _manifestRecoveryCoordinator = ManifestRecoveryCoordinator(
      versionManager: _packVersionManager,
    );
    _deploymentDiagnosticsCoordinator = DeploymentDiagnosticsCoordinator();

    // Hybrid inference orchestration
    _hybridInferenceService = HybridInferenceService(
      localInference: localInference,
      backendService: _backendService,
      healthMonitor: _healthMonitor,
      router: _inferenceRouter,
      networkState: _networkStateService,
      confidenceEvaluator: _confidenceEvaluator,
      streamCoordinator: _streamCoordinator,
      metricsTracker: _routingMetrics,
      intentDetector: _intentDetector,
    );

    // Start background services
    await _networkStateService.start();
    await _healthMonitor.start();

    _initialized = true;
  }

  // Getters
  BackendConfig get backendConfig => _backendConfig;
  BackendApiService get backendService => _backendService;
  ConnectivityService get connectivityService => _connectivityService;
  NetworkStateService get networkStateService => _networkStateService;
  BackendHealthMonitor get healthMonitor => _healthMonitor;
  InferenceRouter get inferenceRouter => _inferenceRouter;
  HybridInferenceService get hybridInferenceService => _hybridInferenceService;
  EscalationCoordinator get escalationCoordinator => _escalationCoordinator;
  StreamTransitionManager get streamTransitionManager => _streamTransitionManager;
  StreamRecoveryManager get streamRecoveryManager => _streamRecoveryManager;
  EducationalComplexityAnalyzer get educationalComplexityAnalyzer => _educationalComplexityAnalyzer;
  SubjectRoutingCoordinator get subjectRoutingCoordinator => _subjectRoutingCoordinator;
  PiHubDiscoveryCoordinator get piHubDiscoveryCoordinator => _piHubDiscoveryCoordinator;
  BackendUrlManager get backendUrlManager => _backendUrlManager;
  ConnectivityController get connectivityController => _connectivityController;
  DiscoverySyncBridge get discoverySyncBridge => _discoverySyncBridge;
  ClassroomSessionManager get classroomSessionManager => _classroomSessionManager;
  ReconnectCoordinator get reconnectCoordinator => _reconnectCoordinator;
  PackVersionManager get packVersionManager => _packVersionManager;
  IncrementalSyncCoordinator get incrementalSyncCoordinator => _incrementalSyncCoordinator;
  PackRecoveryManager get packRecoveryManager => _packRecoveryManager;
  PackIntegrityValidator get packIntegrityValidator => _packIntegrityValidator;
  IncrementalPackRecoveryManager get incrementalPackRecoveryManager => _incrementalPackRecoveryManager;
  LocalPackPersistenceCoordinator get localPackPersistenceCoordinator => _localPackPersistenceCoordinator;
  TransferIntegrityValidator get transferIntegrityValidator => _transferIntegrityValidator;
  DistributedMetricsService get distributedMetricsService => _distributedMetricsService;
  ConnectivityDiagnostics get connectivityDiagnostics => _connectivityDiagnostics;
  RoutingDiagnostics get routingDiagnostics => _routingDiagnostics;
  SyncDiagnosticsManager get syncDiagnosticsManager => _syncDiagnosticsManager;
  OfflineRecoveryCoordinator get offlineRecoveryCoordinator => _offlineRecoveryCoordinator;
  ConnectivityStateCoordinator get connectivityStateCoordinator => _connectivityStateCoordinator;
  DistributedStatePublisher get distributedStatePublisher => _distributedStatePublisher;
  SessionPersistenceManager get sessionPersistenceManager => _sessionPersistenceManager;
  HeartbeatRecoveryService get heartbeatRecoveryService => _heartbeatRecoveryService;
  ClassroomRecoveryCoordinator get classroomRecoveryCoordinator => _classroomRecoveryCoordinator;
  ClassroomPresenceCoordinator get classroomPresenceCoordinator => _classroomPresenceCoordinator;
  MultiDeviceRecoveryManager get multiDeviceRecoveryManager => _multiDeviceRecoveryManager;
  SyncQueueBalancer get syncQueueBalancer => _syncQueueBalancer;
  RecoveryDiagnosticsManager get recoveryDiagnosticsManager => _recoveryDiagnosticsManager;
  ClassroomMetricsCollector get classroomMetricsCollector => _classroomMetricsCollector;
  DistributedHealthTracker get distributedHealthTracker => _distributedHealthTracker;
  DistributedStateRecoveryCoordinator get distributedStateRecoveryCoordinator => _distributedStateRecoveryCoordinator;
  ConnectivityPersistenceManager get connectivityPersistenceManager => _connectivityPersistenceManager;
  ClassroomStatePersistence get classroomStatePersistence => _classroomStatePersistence;
  PersistentClassroomRecoveryManager get persistentClassroomRecoveryManager => _persistentClassroomRecoveryManager;
  PersistentSyncRecoveryManager get persistentSyncRecoveryManager => _persistentSyncRecoveryManager;
  ManifestRecoveryCoordinator get manifestRecoveryCoordinator => _manifestRecoveryCoordinator;
  DeploymentDiagnosticsCoordinator get deploymentDiagnosticsCoordinator => _deploymentDiagnosticsCoordinator;

  /// Check if services are initialized
  bool get isInitialized => _initialized;

  /// Shutdown all services
  void shutdown() {
    if (!_initialized) return;

    _networkStateService.stop();
    _healthMonitor.stop();
    _hybridInferenceService.close();
    _backendService.close();
    _networkStateService.close();
    _healthMonitor.close();
    _piHubDiscoveryCoordinator.close();
    _classroomSessionManager.close();
    _distributedStatePublisher.close();

    _initialized = false;
  }
}
