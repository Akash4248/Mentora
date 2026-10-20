import 'dart:async';
import 'dart:io';
import '../../../config/app_environment.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'dart:convert';

class PiHubNode {
  const PiHubNode({required this.host, required this.port, required this.name, this.source = 'unknown'});
  final String host;
  final int port;
  final String name;
  final String source;

  String get baseUrl => 'http://$host${port == 80 ? '' : ':$port'}';

  @override
  String toString() => 'PiHubNode(host=$host, port=$port, name=$name)';
}

/// Production PiHub Discovery Coordinator.
///
/// Discovery flow:
///   1. Load last-known-good IP from persistent cache
///   2. Health check cached IP
///   3. If healthy → use immediately
///   4. If unreachable → scan LAN subnet for PiHub nodes
///   5. Health-check each candidate
///   6. Select fastest healthy node
///   7. Persist discovered IP
///   8. Notify listeners
class PiHubDiscoveryCoordinator {
  PiHubDiscoveryCoordinator() {
    _initializeDefaultNode();
  }

  final StreamController<List<PiHubNode>> _nodes = StreamController<List<PiHubNode>>.broadcast();
  List<PiHubNode> _current = const [];
  bool _isScanning = false;

  Stream<List<PiHubNode>> get discoveryUpdates => _nodes.stream;
  List<PiHubNode> get currentNodes => _current;
  bool get isScanning => _isScanning;

  /// Best known PiHub node (first in the list).
  PiHubNode? get bestNode => _current.isNotEmpty ? _current.first : null;

  static const _cacheKey = 'pihub_last_known_ip';
  static const _cachePortKey = 'pihub_last_known_port';
  static const _persistedUrlKey = 'backend_active_url'; // BackendUrlManager's key
  static const _healthPath = '/health';
  static const _scanTimeoutMs = 500;
  static const _healthTimeoutMs = 5000;

  /// Initialize with default node from .env (seed IP).
  void _initializeDefaultNode() {
    print('[DISCOVERY] DISCOVERY_IGNORE_ENV=${AppEnvironment.ignoreEnvironmentSeed}');
    print('[DISCOVERY] ENV_URL=${AppEnvironment.backendBaseUrl}');

    // Clear any stale cached IP that is identical to the .env seed.
    // The seed is not a discovered node — it is a static config value.
    // Persisting it as a "cache hit" causes discovery to skip the LAN scan
    // and keeps using a potentially dead IP across all restarts.
    _clearEnvMatchingCache();

    if (AppEnvironment.ignoreEnvironmentSeed) {
      print('[DISCOVERY] ENV_SEEDS_DISABLED');
      _current = [];
      return;
    }

    try {
      final backendUrl = AppEnvironment.backendBaseUrl;
      final uri = Uri.parse(backendUrl);
      final host = uri.host.isNotEmpty ? uri.host : '10.28.73.193';
      final port = uri.hasPort ? uri.port : 80;

      _current = [
        PiHubNode(
          host: host,
          port: port,
          name: 'PiHub Gateway (seed)',
          source: 'env',
        ),
      ];

      print('[DISCOVERY] INITIALIZED host=$host port=$port source=env');
      print('[DISCOVERY] INITIAL_SOURCE=env');
    } catch (e) {
      print('[DISCOVERY] INIT_ERROR=$e');
      final uri = Uri.parse(AppEnvironment.backendBaseUrl);
      _current = [
        PiHubNode(host: uri.host, port: 80, name: 'PiHub Gateway (fallback)', source: 'env'),
      ];
      print('[DISCOVERY] INITIAL_SOURCE=env');
    }
  }

  /// Clears cached IP only if it matches the .env seed (fire-and-forget).
  Future<void> _clearEnvMatchingCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedIp = prefs.getString(_cacheKey);
      final envUri = Uri.parse(AppEnvironment.backendBaseUrl);
      final envHost = envUri.host;
      if (cachedIp != null && cachedIp == envHost) {
        await prefs.remove(_cacheKey);
        await prefs.remove(_cachePortKey);
        await prefs.remove(_persistedUrlKey);
        print('[DISCOVERY] CACHE_CLEARED reason=ENV_SEED_MATCH host=$cachedIp');
      }
    } catch (_) {}
  }

  /// Fully clears all persisted discovery/URL state. Call this for a clean restart.
  static Future<void> clearPersistedCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_cachePortKey);
      await prefs.remove(_persistedUrlKey);
      print('[DISCOVERY] PERSISTED_CACHE_CLEARED');
    } catch (e) {
      print('[DISCOVERY] CACHE_CLEAR_ERROR=$e');
    }
  }

  /// Full discovery flow:
  ///   cached IP → health check → LAN scan → health validate → select best
  Future<PiHubNode?> discover() async {
    if (_isScanning) {
      print('[DISCOVERY] ALREADY_SCANNING — skipping');
      return bestNode;
    }
    _isScanning = true;
    print('[DISCOVERY] CURRENT_STATE=SCAN_START');
    print('[DISCOVERY] SCAN_START');
    print('[DISCOVERY] IS_CONNECTIVITY_ONLINE=true'); // Connectivity is managed elsewhere, assume true if scanning

    try {
      // Step 1: Try cached IP
      print('[DISCOVERY] CACHE_LOOKUP');
      final cached = await _loadCachedNode();
      if (cached != null) {
        print('[DISCOVERY] CACHE_HIT');
        print('[DISCOVERY] SCAN_SKIPPED_REASON=CACHE_HIT');
        print('[DISCOVERY] CACHED_IP=${cached.host}');
        print('[DISCOVERY] CANDIDATE_FOUND ip=${cached.host} source=${cached.source}');
        print('[DISCOVERY] PROMOTION_ATTEMPT');
        if (await _healthCheck(cached)) {
          print('[DISCOVERY] CACHED_IP_HEALTHY=true');
          print('[DISCOVERY] NODE_PROMOTED=${cached.host}');
          print('[DISCOVERY] BACKEND_PROMOTED=true');
          print('[DISCOVERY] PROMOTION_REASON=CACHED_IP_HEALTHY');
          print('[DISCOVERY] SOURCE=${cached.source}');
          _updateNodes([cached]);
          print('[DISCOVERY] SCAN_END');
          print('[DISCOVERY] ACTIVE_BACKEND=${cached.host}');
          return cached;
        }
        print('[DISCOVERY] CACHED_IP_HEALTHY=false');
        print('[DISCOVERY] REJECTION_REASON=CACHE_NODE_UNHEALTHY');
        print('[DISCOVERY] PROMOTION_REJECTED');
        // EVIL CACHE MUST DIE:
        await clearPersistedCache();
        print('[DISCOVERY] CACHE_EVICTED');
      } else {
        print('[DISCOVERY] CACHE_FAILED');
        print('[DISCOVERY] CACHE_MISS');
      }

      // Step 2: LAN subnet scan
      print('[DISCOVERY] STARTING_SCAN');
      print('[DISCOVERY] SCAN_TRIGGERED');
      final candidates = await _scanSubnet();
      
      if (candidates.isNotEmpty) {
        // Step 3: Health check each candidate
        for (final candidate in candidates) {
          print('[DISCOVERY] CANDIDATE=${candidate.host}');
          print('[DISCOVERY] SCAN_CANDIDATE_FOUND ip=${candidate.host} source=${candidate.source}');
          print('[DISCOVERY] PROMOTION_ATTEMPT');
          if (await _healthCheck(candidate)) {
            print('[DISCOVERY] HEALTHY=${candidate.host}');
            print('[DISCOVERY] PROMOTION_SUCCESS=${candidate.host}');
            print('[DISCOVERY] NODE_PROMOTED=${candidate.host}');
            print('[DISCOVERY] BACKEND_PROMOTED=true');
            print('[DISCOVERY] PROMOTION_REASON=LAN_SCAN_HEALTHY');
            print('[DISCOVERY] SOURCE=${candidate.source}');
            await _persistNode(candidate);
            _updateNodes([candidate]);
            print('[DISCOVERY] SCAN_END');
            print('[DISCOVERY] ACTIVE_BACKEND=${candidate.host}');
            return candidate;
          }
          print('[DISCOVERY] REJECTION_REASON=LAN_NODE_UNHEALTHY');
          print('[DISCOVERY] PROMOTION_REJECTED');
        }
      } else {
        print('[DISCOVERY] NO_CANDIDATES_FOUND');
      }

      print('[DISCOVERY] NO_HEALTHY_NODES_FOUND');
      print('[DISCOVERY] PROMOTION_BLOCKER=ALL_CANDIDATES_FAILED');
      
      // Step 4: ENV fallback as last resort
      print('[DISCOVERY] FALLBACK_TO_ENV');
      if (_current.isNotEmpty) {
        final seed = _current.first;
        print('[DISCOVERY] ENV_SEED_ATTEMPT=${seed.host}');
        print('[DISCOVERY] PROMOTION_ATTEMPT');
        if (await _healthCheck(seed)) {
          print('[DISCOVERY] SEED_IP_HEALTHY=true');
          print('[DISCOVERY] NODE_PROMOTED=${seed.host}');
          print('[DISCOVERY] BACKEND_PROMOTED=true');
          print('[DISCOVERY] PROMOTION_REASON=ENV_SEED_HEALTHY');
          print('[DISCOVERY] SOURCE=${seed.source}');
          await _persistNode(seed);
          _updateNodes([seed]);
          print('[DISCOVERY] SCAN_END');
          print('[DISCOVERY] ACTIVE_BACKEND=${seed.host}');
          return seed;
        }
        print('[DISCOVERY] SEED_IP_HEALTHY=false');
        print('[DISCOVERY] REJECTION_REASON=SEED_NODE_UNHEALTHY');
        print('[DISCOVERY] PROMOTION_REJECTED');
      }

      print('[DISCOVERY] NO_HEALTHY_NODES_FOUND');
      print('[DISCOVERY] PROMOTION_BLOCKER=ALL_CANDIDATES_FAILED');
      print('[DISCOVERY] SCAN_END');
      _updateNodes([]);
      return null;
    } finally {
      _isScanning = false;
    }
  }

  /// Legacy scan() method — now delegates to full discover().
  Future<void> scan() async {
    await discover();
  }

  Future<void> registerDevice({required String deviceId}) async {
    AppEnvironment.log('DISCOVERY', 'Registering device: $deviceId');
    if (_current.isEmpty) {
      await scan();
    }
  }

  /// Scan the local /24 subnet for hosts with an open HTTP port in batches.
  Future<List<PiHubNode>> _scanSubnet() async {
    print('[DISCOVERY] SUBNET_SCAN_START');
    final baseIp = await _getSubnetBase();
    if (baseIp == null) {
      print('[DISCOVERY] SUBNET_SCAN_FAILED (no network interface)');
      return [];
    }

    print('[DISCOVERY] SUBNET_BASE=$baseIp');
    final candidates = <PiHubNode>[];
    
    const batchSize = 30; // Prevent FD exhaustion
    for (int i = 1; i <= 254; i += batchSize) {
      final futures = <Future<void>>[];
      for (int j = 0; j < batchSize && (i + j) <= 254; j++) {
        final ip = '$baseIp.${i + j}';
        // Probe port 8000 (primary Mentora Gateway) and port 80 (standard PiHub)
        futures.add(_probeHost(ip, 8000).then((alive) {
          if (alive) {
            candidates.add(PiHubNode(host: ip, port: 8000, name: 'LAN-$ip', source: 'scan'));
          }
        }));
        futures.add(_probeHost(ip, 80).then((alive) {
          if (alive) {
            candidates.add(PiHubNode(host: ip, port: 80, name: 'LAN-$ip', source: 'scan'));
          }
        }));
      }
      await Future.wait(futures);
    }

    print('[DISCOVERY] SUBNET_SCAN_END candidates=${candidates.length}');
    return candidates;
  }

  /// Probe a single host:port with a TCP connect timeout.
  Future<bool> _probeHost(String ip, int port) async {
    try {
      final socket = await Socket.connect(
        ip,
        port,
        timeout: Duration(milliseconds: _scanTimeoutMs),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Health check a PiHub node via GET /health.
  Future<bool> _healthCheck(PiHubNode node) async {
    final targetUrl = 'http://${node.host}:${node.port}$_healthPath';
    print('[DISCOVERY] HEALTH_CHECK_START url=$targetUrl');
    print('[DISCOVERY] TARGET_URL=$targetUrl');
    
    final stopwatch = Stopwatch()..start();
    try {
      final client = HttpClient();
      client.connectionTimeout = Duration(milliseconds: _healthTimeoutMs);
      final uri = Uri.parse(targetUrl);
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        Duration(milliseconds: _healthTimeoutMs),
      );
      
      stopwatch.stop();
      print('[DISCOVERY] HEALTH_CHECK_END status=${response.statusCode} duration_ms=${stopwatch.elapsedMilliseconds}');
      print('[DISCOVERY] STATUS_CODE=${response.statusCode}');
      print('[DISCOVERY] RESPONSE_TIME_MS=${stopwatch.elapsedMilliseconds}');
      print('[DISCOVERY] IS_TIMEOUT=false');
      
      if (response.statusCode == 200) {
        final bodyBytes = await response.expand((bytes) => bytes).toList();
        final body = String.fromCharCodes(bodyBytes);
        print('[DISCOVERY] RESPONSE_BODY=$body');
        
        try {
          final json = jsonDecode(body);
          final isValidStatus = json['status'] == 'healthy' || json['status'] == 'degraded' || json['status'] == 'ok';
          if (json is Map && isValidStatus) {
            print('[DISCOVERY] PAYLOAD_VALID=true');
            client.close(force: true);
            return true;
          } else {
            print('[DISCOVERY] PAYLOAD_VALID=false');
            print('[DISCOVERY] PROMOTION_BLOCKER=PAYLOAD_VALIDATION_FAILED');
          }
        } catch (_) {
           print('[DISCOVERY] PROMOTION_BLOCKER=INVALID_JSON');
        }
      } else {
        print('[DISCOVERY] PROMOTION_BLOCKER=INVALID_STATUS_CODE');
      }
      
      client.close(force: true);
      return false;
    } catch (e) {
      stopwatch.stop();
      print('[DISCOVERY] HEALTH_CHECK_END status=error duration_ms=${stopwatch.elapsedMilliseconds}');
      if (e is TimeoutException) {
        print('[DISCOVERY] IS_TIMEOUT=true');
        print('[DISCOVERY] PROMOTION_BLOCKER=TIMEOUT');
      } else {
        print('[DISCOVERY] IS_TIMEOUT=false');
        print('[DISCOVERY] PROMOTION_BLOCKER=EXCEPTION ($e)');
      }
      return false;
    }
  }

  /// Get the /24 subnet base from the device's network interfaces.
  Future<String?> _getSubnetBase() async {
    try {
      final wifiIP = await NetworkInfo().getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty) {
        print('[DISCOVERY] DEVICE_IP=$wifiIP');
        final parts = wifiIP.split('.');
        if (parts.length == 4) {
          final subnetBase = '${parts[0]}.${parts[1]}.${parts[2]}';
          print('[DISCOVERY] SUBNET_BASE=$subnetBase');
          return subnetBase;
        }
      } else {
        print('[DISCOVERY] DISCOVERY_ABORT_REASON=NO_DEVICE_IP');
      }
    } catch (_) {
      print('[DISCOVERY] DISCOVERY_ABORT_REASON=NETWORK_EXCEPTION');
    }
    return null;
  }

  void _updateNodes(List<PiHubNode> nodes) {
    _current = nodes;
    _nodes.add(nodes);
    if (nodes.isNotEmpty) {
      print('[DISCOVERY] URL_UPDATED=${nodes.first.baseUrl}');
    }
  }

  /// Persist last-known-good node to SharedPreferences.
  Future<void> _persistNode(PiHubNode node) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, node.host);
      await prefs.setInt(_cachePortKey, node.port);
      print('[DISCOVERY] PERSISTED ip=${node.host} port=${node.port}');
    } catch (e) {
      print('[DISCOVERY] PERSIST_ERROR=$e');
    }
  }

  /// Load last-known-good node from SharedPreferences.
  /// Evicts the entry immediately if the IP matches the .env seed (not a real discovery).
  Future<PiHubNode?> _loadCachedNode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ip = prefs.getString(_cacheKey);
      final port = prefs.getInt(_cachePortKey) ?? 80;
      print('[DISCOVERY] CACHE_URL=$ip');
      if (ip == null || ip.isEmpty) {
        print('[DISCOVERY] CACHE_MISS (no entry)');
        return null;
      }

      // Reject cache entries that are identical to the .env seed.
      // The seed is not a "discovered" node; storing it as cache would
      // cause the scan to be skipped even when the seed is unreachable.
      final envHost = Uri.parse(AppEnvironment.backendBaseUrl).host;
      if (ip == envHost) {
        print('[DISCOVERY] CACHE_REJECTED reason=MATCHES_ENV_SEED host=$ip');
        await prefs.remove(_cacheKey);
        await prefs.remove(_cachePortKey);
        return null;
      }

      print('[DISCOVERY] USING_LAST_KNOWN_BACKEND=$ip');
      print('[DISCOVERY] INITIAL_SOURCE=cache');
      return PiHubNode(host: ip, port: port, name: 'PiHub (cached)', source: 'cached');
    } catch (e) {
      print('[DISCOVERY] CACHE_LOAD_ERROR=$e');
    }
    return null;
  }

  Future<void> close() async {
    await _nodes.close();
  }
}
