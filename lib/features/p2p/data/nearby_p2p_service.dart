import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:permission_handler/permission_handler.dart';

/// Represents a discovered Nearby peer endpoint.
class DiscoveredNearbyPeer {
  final String endpointId;
  final String endpointName;
  final String serviceId;
  final DateTime discoveredAt;

  DiscoveredNearbyPeer({
    required this.endpointId,
    required this.endpointName,
    required this.serviceId,
    DateTime? discoveredAt,
  }) : discoveredAt = discoveredAt ?? DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredNearbyPeer &&
          runtimeType == other.runtimeType &&
          endpointId == other.endpointId;

  @override
  int get hashCode => endpointId.hashCode;
}

/// Status of a payload transfer.
class NearbyPayloadProgress {
  final int payloadId;
  final String endpointId;
  final int bytesTransferred;
  final int totalBytes;
  final PayloadStatus status;

  NearbyPayloadProgress({
    required this.payloadId,
    required this.endpointId,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.status,
  });

  double get progressFraction =>
      totalBytes > 0 ? (bytesTransferred / totalBytes).clamp(0.0, 1.0) : 0.0;
}

/// High-level service managing Google Nearby Connections (P2P_CLUSTER).
class NearbyP2PService extends ChangeNotifier with WidgetsBindingObserver {
  static const String defaultServiceId = 'org.mentora.p2p';
  final Strategy strategy;

  bool _isAdvertising = false;
  bool _isDiscovering = false;

  bool get isAdvertising => _isAdvertising;
  bool get isDiscovering => _isDiscovering;

  final Map<String, DiscoveredNearbyPeer> _discoveredPeers = {};
  final Set<String> _connectedEndpoints = {};

  List<DiscoveredNearbyPeer> get discoveredPeers => _discoveredPeers.values.toList();
  Set<String> get connectedEndpoints => Set.unmodifiable(_connectedEndpoints);

  final StreamController<NearbyPayloadProgress> _payloadProgressController =
      StreamController<NearbyPayloadProgress>.broadcast();
  final StreamController<Map<String, dynamic>> _receivedBytesController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, String>> _receivedFileController =
      StreamController<Map<String, String>>.broadcast();

  Stream<NearbyPayloadProgress> get payloadProgressStream => _payloadProgressController.stream;
  Stream<Map<String, dynamic>> get receivedBytesStream => _receivedBytesController.stream;
  Stream<Map<String, String>> get receivedFileStream => _receivedFileController.stream;

  NearbyP2PService({this.strategy = Strategy.P2P_CLUSTER}) {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      debugPrint('[NearbyP2PService] App lifecycle paused/detached - stopping all endpoints');
      stopAll();
    }
  }

  /// Request permissions required for Nearby Connections.
  Future<bool> checkAndRequestPermissions() async {
    try {
      final statuses = await [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.nearbyWifiDevices,
      ].request();
      return statuses.values.every((status) => status.isGranted || status.isLimited);
    } catch (e) {
      debugPrint('[NearbyP2PService] Permission check error: $e');
      return false;
    }
  }

  /// Start advertising local node to nearby peers.
  Future<bool> startAdvertising({
    required String userName,
    String serviceId = defaultServiceId,
    void Function(String endpointId, ConnectionInfo info)? onConnectionInitiated,
    void Function(String endpointId)? onDisconnected,
  }) async {
    if (_isAdvertising) return true;

    try {
      final success = await Nearby().startAdvertising(
        userName,
        strategy,
        onConnectionInitiated: (endpointId, info) {
          debugPrint('[NearbyP2PService] Connection initiated from $endpointId (${info.endpointName})');
          onConnectionInitiated?.call(endpointId, info);
        },
        onConnectionResult: (endpointId, status) {
          debugPrint('[NearbyP2PService] Connection result for $endpointId: $status');
          if (status == Status.CONNECTED) {
            _connectedEndpoints.add(endpointId);
            notifyListeners();
          } else {
            _connectedEndpoints.remove(endpointId);
            notifyListeners();
          }
        },
        onDisconnected: (endpointId) {
          debugPrint('[NearbyP2PService] Disconnected: $endpointId');
          _connectedEndpoints.remove(endpointId);
          onDisconnected?.call(endpointId);
          notifyListeners();
        },
        serviceId: serviceId,
      );
      _isAdvertising = success;
      notifyListeners();
      return success;
    } catch (e) {
      debugPrint('[NearbyP2PService] startAdvertising error: $e');
      _isAdvertising = false;
      notifyListeners();
      return false;
    }
  }

  /// Start scanning for nearby advertising peers.
  Future<bool> startDiscovery({
    required String userName,
    String serviceId = defaultServiceId,
    void Function(String endpointId, String endpointName, String serviceId)? onEndpointFound,
    void Function(String endpointId)? onEndpointLost,
  }) async {
    if (_isDiscovering) return true;

    try {
      final success = await Nearby().startDiscovery(
        userName,
        strategy,
        onEndpointFound: (endpointId, endpointName, foundServiceId) {
          debugPrint('[NearbyP2PService] Discovered peer: $endpointName ($endpointId)');
          final peer = DiscoveredNearbyPeer(
            endpointId: endpointId,
            endpointName: endpointName,
            serviceId: foundServiceId,
          );
          _discoveredPeers[endpointId] = peer;
          onEndpointFound?.call(endpointId, endpointName, foundServiceId);
          notifyListeners();
        },
        onEndpointLost: (endpointId) {
          if (endpointId != null) {
            debugPrint('[NearbyP2PService] Endpoint lost: $endpointId');
            _discoveredPeers.remove(endpointId);
            onEndpointLost?.call(endpointId);
            notifyListeners();
          }
        },
        serviceId: serviceId,
      );
      _isDiscovering = success;
      notifyListeners();
      return success;
    } catch (e) {
      debugPrint('[NearbyP2PService] startDiscovery error: $e');
      _isDiscovering = false;
      notifyListeners();
      return false;
    }
  }

  /// Stop advertising.
  Future<void> stopAdvertising() async {
    if (!_isAdvertising) return;
    try {
      await Nearby().stopAdvertising();
    } catch (e) {
      debugPrint('[NearbyP2PService] stopAdvertising error: $e');
    } finally {
      _isAdvertising = false;
      notifyListeners();
    }
  }

  /// Stop discovery.
  Future<void> stopDiscovery() async {
    if (!_isDiscovering) return;
    try {
      await Nearby().stopDiscovery();
    } catch (e) {
      debugPrint('[NearbyP2PService] stopDiscovery error: $e');
    } finally {
      _isDiscovering = false;
      _discoveredPeers.clear();
      notifyListeners();
    }
  }

  /// Connect to a discovered peer.
  Future<bool> requestConnection({
    required String userName,
    required String endpointId,
    void Function(String endpointId, ConnectionInfo info)? onConnectionInitiated,
    void Function(String endpointId)? onDisconnected,
  }) async {
    try {
      final success = await Nearby().requestConnection(
        userName,
        endpointId,
        onConnectionInitiated: (id, info) {
          debugPrint('[NearbyP2PService] Outgoing connection initiated to $id');
          onConnectionInitiated?.call(id, info);
        },
        onConnectionResult: (id, status) {
          debugPrint('[NearbyP2PService] Connection result for $id: $status');
          if (status == Status.CONNECTED) {
            _connectedEndpoints.add(id);
            notifyListeners();
          } else {
            _connectedEndpoints.remove(id);
            notifyListeners();
          }
        },
        onDisconnected: (id) {
          debugPrint('[NearbyP2PService] Disconnected: $id');
          _connectedEndpoints.remove(id);
          onDisconnected?.call(id);
          notifyListeners();
        },
      );
      return success;
    } catch (e) {
      debugPrint('[NearbyP2PService] requestConnection error: $e');
      return false;
    }
  }

  /// Accept an incoming or outgoing connection request.
  Future<bool> acceptConnection(String endpointId) async {
    try {
      final success = await Nearby().acceptConnection(
        endpointId,
        onPayLoadRecieved: (id, payload) {
          _handlePayloadReceived(id, payload);
        },
      );
      return success;
    } catch (e) {
      debugPrint('[NearbyP2PService] acceptConnection error: $e');
      return false;
    }
  }

  /// Reject an incoming connection request.
  Future<bool> rejectConnection(String endpointId) async {
    try {
      final success = await Nearby().rejectConnection(endpointId);
      return success;
    } catch (e) {
      debugPrint('[NearbyP2PService] rejectConnection error: $e');
      return false;
    }
  }

  /// Send raw bytes to an endpoint.
  Future<void> sendBytes(String endpointId, Uint8List bytes) async {
    try {
      await Nearby().sendBytesPayload(endpointId, bytes);
    } catch (e) {
      debugPrint('[NearbyP2PService] sendBytes error: $e');
      rethrow;
    }
  }

  /// Send a file payload to an endpoint.
  Future<int> sendFile(String endpointId, String filePath) async {
    try {
      final payloadId = await Nearby().sendFilePayload(endpointId, filePath);
      return payloadId;
    } catch (e) {
      debugPrint('[NearbyP2PService] sendFile error: $e');
      rethrow;
    }
  }

  /// Disconnect from all connected endpoints and stop advertising/discovering.
  Future<void> stopAll() async {
    try {
      await stopAdvertising();
      await stopDiscovery();
      await Nearby().stopAllEndpoints();
      _connectedEndpoints.clear();
      _discoveredPeers.clear();
      notifyListeners();
    } catch (e) {
      debugPrint('[NearbyP2PService] stopAll error: $e');
    }
  }

  /// Copies received file payload from temp location to target path and removes original.
  Future<File> copyFileAndDeleteOriginal(String srcPath, String destPath) async {
    final srcFile = File(srcPath);
    final destFile = await srcFile.copy(destPath);
    try {
      if (await srcFile.exists()) {
        await srcFile.delete();
      }
    } catch (e) {
      debugPrint('[NearbyP2PService] Failed to delete temp payload file: $e');
    }
    return destFile;
  }

  void _handlePayloadReceived(String endpointId, Payload payload) {
    if (payload.type == PayloadType.BYTES && payload.bytes != null) {
      _receivedBytesController.add({
        'endpointId': endpointId,
        'bytes': payload.bytes!,
      });
    } else if (payload.type == PayloadType.FILE && payload.uri != null) {
      _receivedFileController.add({
        'endpointId': endpointId,
        'filePath': payload.uri!,
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    stopAll();
    _payloadProgressController.close();
    _receivedBytesController.close();
    _receivedFileController.close();
    super.dispose();
  }
}
