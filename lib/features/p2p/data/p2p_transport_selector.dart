import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'nearby_p2p_service.dart';
import 'p2p_channel_service.dart';

/// Active P2P transport.
///
/// * [nearby] — Google Nearby Connections (P2P_CLUSTER over BT + WiFi).
///   PRIMARY: OS-managed encrypted links, chunked file payloads with
///   progress, no custom crypto or sockets in our code.
/// * [legacyLan] — Raw LAN-TCP + Wi-Fi Direct via `P2PManager.kt`.
///   FALLBACK for devices without Google Play services.
enum P2pTransport { nearby, legacyLan }

/// Picks the best available P2P transport and transparently falls back.
///
/// Startup order: Nearby permissions → Nearby advertise+discover → on any
/// failure, legacy LAN receiver. Send order: route by peer transport, and if
/// the primary send throws, retry via the other transport when the peer
/// carries a usable address for it.
class P2pTransportSelector extends ChangeNotifier {
  P2pTransportSelector({
    NearbyP2PService? nearby,
    P2PChannelService? legacy,
  })  : _nearby = nearby ?? NearbyP2PService(),
        _legacy = legacy ?? P2PChannelService();

  final NearbyP2PService _nearby;
  final P2PChannelService _legacy;

  /// Underlying Nearby service (payload streams, connection control).
  NearbyP2PService get nearby => _nearby;

  /// Underlying legacy LAN channel.
  P2PChannelService get legacy => _legacy;

  P2pTransport _active = P2pTransport.nearby;
  P2pTransport get activeTransport => _active;

  bool _nearbyAvailable = false;
  bool get nearbyAvailable => _nearbyAvailable;

  bool _initialized = false;
  String? _lastFallbackReason;
  String? get lastFallbackReason => _lastFallbackReason;

  /// Idempotent init. Never throws — ends on legacy fallback on failure.
  Future<void> ensureInit({required String userName}) async {
    if (_initialized) return;
    _initialized = true;

    try {
      final granted = await _nearby.checkAndRequestPermissions();
      if (!granted) {
        return _fallBackToLegacy('Nearby permissions denied.');
      }

      final advertising =
          await _nearby.startAdvertising(userName: userName).timeout(
                const Duration(seconds: 8),
                onTimeout: () => false,
              );
      final discovering =
          await _nearby.startDiscovery(userName: userName).timeout(
                const Duration(seconds: 8),
                onTimeout: () => false,
              );

      if (advertising && discovering) {
        _nearbyAvailable = true;
        _setActive(P2pTransport.nearby, null);
        return;
      }
      return _fallBackToLegacy('Nearby advertise/discover unavailable.');
    } on MissingPluginException catch (e) {
      return _fallBackToLegacy('Nearby unavailable: $e');
    } catch (e) {
      return _fallBackToLegacy('Nearby init failed: $e');
    }
  }

  Future<void> _fallBackToLegacy(String reason) async {
    _nearbyAvailable = false;
    _lastFallbackReason = reason;
    try {
      await _legacy.startReceiver();
    } catch (_) {}
    _setActive(P2pTransport.legacyLan, reason);
  }

  void _setActive(P2pTransport transport, String? reason) {
    _active = transport;
    _lastFallbackReason = reason;
    notifyListeners();
  }

  /// Unified peer list: Nearby endpoints first (primary), legacy LAN second.
  /// Nearby peers are mapped to [P2PPeer] with `transport: 'nearby'` and the
  /// endpoint id in both address fields so the screen needs no refactor.
  Future<List<P2PPeer>> discoverPeers() async {
    final merged = <P2PPeer>[];
    final seen = <String>{};

    if (_nearbyAvailable) {
      for (final peer in _nearby.discoveredPeers) {
        if (seen.add(peer.endpointId)) {
          merged.add(P2PPeer(
            name: peer.endpointName,
            address: peer.endpointId,
            transport: 'nearby',
            resolvedAddress: peer.endpointId,
          ));
        }
      }
    }

    try {
      final legacyPeers = await _legacy.listPeers();
      for (final peer in legacyPeers) {
        if (seen.add('lan:${peer.address}')) {
          merged.add(peer);
        }
      }
    } catch (_) {}

    return merged;
  }

  /// Send a file via the peer's transport, falling back when possible.
  Future<P2POperationResult> sendToPeer({
    required P2PPeer peer,
    required String filePath,
  }) async {
    if (peer.transport == 'nearby') {
      try {
        await _nearby.sendFile(peer.address, filePath);
        return const P2POperationResult(
          ok: true,
          message: 'Sent via Nearby Connections (encrypted).',
        );
      } catch (e) {
        // Fall back to legacy LAN only when the peer also has a LAN address
        // (Nearby endpoint ids are opaque and unusable as IPs).
        if (_looksLikeLanAddress(peer.resolvedAddress) &&
            peer.resolvedAddress != peer.address) {
          _lastFallbackReason = 'Nearby send failed, retrying via LAN.';
          notifyListeners();
          return _legacy.sendBundle(
            address: peer.resolvedAddress,
            filePath: filePath,
          );
        }
        return P2POperationResult(ok: false, message: 'Nearby send failed: $e');
      }
    }

    // Legacy LAN peer: straight through (Nearby cannot address IPs).
    try {
      return await _legacy.sendBundle(
        address: peer.address,
        filePath: filePath,
      );
    } catch (e) {
      return P2POperationResult(ok: false, message: 'LAN send failed: $e');
    }
  }

  bool _looksLikeLanAddress(String address) {
    if (address.isEmpty) return false;
    return address.contains('.') || address.contains(':');
  }

  Future<void> shutdown() async {
    try {
      await _nearby.stopAll();
    } catch (_) {}
    try {
      await _legacy.stopReceiver();
    } catch (_) {}
  }

  @override
  void dispose() {
    shutdown();
    _nearby.dispose();
    super.dispose();
  }
}
