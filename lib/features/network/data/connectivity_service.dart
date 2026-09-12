import 'dart:async';
import 'dart:io';

/// Represents network connectivity state.
class ConnectivitySnapshot {
  const ConnectivitySnapshot({
    required this.isOnline,
    required this.hasBackend,
    this.backendLatencyMs,
    this.timestamp,
  });

  /// Whether device has any internet connectivity
  final bool isOnline;

  /// Whether backend API is reachable
  final bool hasBackend;

  /// Latency to backend in milliseconds (if reachable)
  final int? backendLatencyMs;

  /// Timestamp of this snapshot
  final DateTime? timestamp;

  /// Create an offline snapshot
  factory ConnectivitySnapshot.offline() {
    return ConnectivitySnapshot(
      isOnline: false,
      hasBackend: false,
      timestamp: DateTime.now(),
    );
  }

  /// Create an online-only snapshot (no backend)
  factory ConnectivitySnapshot.onlineNoBackend() {
    return ConnectivitySnapshot(
      isOnline: true,
      hasBackend: false,
      timestamp: DateTime.now(),
    );
  }

  /// Create a fully connected snapshot
  factory ConnectivitySnapshot.connected({
    int latencyMs = 0,
  }) {
    return ConnectivitySnapshot(
      isOnline: true,
      hasBackend: true,
      backendLatencyMs: latencyMs,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() =>
      'ConnectivitySnapshot(isOnline=$isOnline, hasBackend=$hasBackend, latencyMs=$backendLatencyMs)';
}

/// Service for detecting network connectivity.
class ConnectivityService {
  ConnectivityService({
    this.probeHost = 'google.com',
    this.probePort = 443,
    this.probeTimeoutSeconds = 5,
  });

  /// Host to probe for internet connectivity
  final String probeHost;

  /// Port for connectivity probe
  final int probePort;

  /// Timeout for probe attempt
  final int probeTimeoutSeconds;

  /// Check if device has internet or local backend connectivity
  Future<bool> isConnected({String? backendUrl}) async {
    if (backendUrl != null && backendUrl.isNotEmpty) {
      try {
        final uri = Uri.parse(backendUrl);
        if (uri.host.isNotEmpty && uri.port > 0) {
          final socket = await Socket.connect(
            uri.host,
            uri.port,
            timeout: Duration(seconds: probeTimeoutSeconds),
          );
          socket.destroy();
          return true;
        }
      } catch (_) {}
    }

    try {
      final result = await InternetAddress.lookup(probeHost).timeout(
        Duration(seconds: probeTimeoutSeconds),
        onTimeout: () => throw TimeoutException('Connectivity probe timeout', null),
      );
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Probe backend connectivity with latency
  Future<ConnectivitySnapshot> probeBackend({
    required String backendUrl,
  }) async {
    final isOnline = await isConnected();
    if (!isOnline) {
      return ConnectivitySnapshot.offline();
    }

    try {
      final uri = Uri.parse(backendUrl);
      final stopwatch = Stopwatch()..start();

      final socket = await Socket.connect(
        uri.host,
        uri.port,
        timeout: Duration(seconds: probeTimeoutSeconds),
      );
      socket.destroy();

      stopwatch.stop();
      return ConnectivitySnapshot.connected(
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (_) {
      return ConnectivitySnapshot.onlineNoBackend();
    }
  }

  /// Get current connectivity snapshot
  Future<ConnectivitySnapshot> getSnapshot({
    String? backendUrl,
  }) async {
    final isOnline = await isConnected();

    if (!isOnline) {
      return ConnectivitySnapshot.offline();
    }

    if (backendUrl == null || backendUrl.isEmpty) {
      return ConnectivitySnapshot.onlineNoBackend();
    }

    return probeBackend(backendUrl: backendUrl);
  }
}
