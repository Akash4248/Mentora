import 'dart:async';

import 'mentora_backend_client.dart';

class BackendDiscoveryService {
  static final BackendDiscoveryService _instance = BackendDiscoveryService._internal();

  factory BackendDiscoveryService() {
    return _instance;
  }

  BackendDiscoveryService._internal();

  Timer? _pollingTimer;
  bool _isProbing = false;

  /// Starts background non-blocking discovery timer.
  void startBackgroundMonitoring({Duration interval = const Duration(seconds: 30)}) {
    _pollingTimer?.cancel();
    
    // Trigger initial probe in background without blocking caller
    unawaited(probeNow());

    _pollingTimer = Timer.periodic(interval, (_) {
      unawaited(probeNow());
    });
  }

  /// Stops background polling timer.
  void stopBackgroundMonitoring() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Triggers an immediate background probe of candidate backend gateway URLs.
  Future<void> probeNow({void Function(DiscoveryProgress progress)? onProgress}) async {
    if (_isProbing) return;
    _isProbing = true;
    try {
      final client = MentoraBackendClient();
      await client.autoDiscoverGatewayUrl(onProgress: onProgress);
    } catch (_) {
      // Ignore background probing errors
    } finally {
      _isProbing = false;
    }
  }
}
