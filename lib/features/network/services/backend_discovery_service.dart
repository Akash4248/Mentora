import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_environment.dart';
import '../application/pi_hub_discovery_coordinator.dart';
import '../data/backend_availability_cache.dart';
import '../domain/runtime_backend_url.dart';

enum ClassroomConnectionState {
  disconnected,
  discovering,
  connecting,
  connected,
  reconnecting,
}

class ClassroomDescriptor {
  const ClassroomDescriptor({
    required this.classroomId,
    required this.name,
    required this.nodeId,
    required this.gatewayUrl,
    this.studentCount,
    this.latencyMs,
    this.lastConnectedAt,
  });

  final String classroomId;
  final String name;
  final String nodeId;
  final String gatewayUrl;
  final int? studentCount;
  final int? latencyMs;
  final DateTime? lastConnectedAt;

  ClassroomDescriptor copyWith({int? latencyMs, DateTime? lastConnectedAt}) {
    return ClassroomDescriptor(
      classroomId: classroomId,
      name: name,
      nodeId: nodeId,
      gatewayUrl: gatewayUrl,
      studentCount: studentCount,
      latencyMs: latencyMs ?? this.latencyMs,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }
}

/// Finds and maintains the active classroom gateway.
///
/// This preserves the existing discovery API used by voice while exposing
/// classroom-specific state for the P2P and global connection UI.
class BackendDiscoveryService extends ChangeNotifier {
  static final BackendDiscoveryService _instance =
      BackendDiscoveryService._internal();

  factory BackendDiscoveryService() => _instance;

  BackendDiscoveryService._internal() {
    unawaited(_initialize());
  }

  static const _activeUrlKey = 'backend_discovery_active_url';
  static const _classroomIdKey = 'classroom_connection_id';
  static const _classroomNameKey = 'classroom_connection_name';
  static const _nodeIdKey = 'classroom_connection_node_id';

  static const _reconnectDelays = <Duration>[
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];

  final PiHubDiscoveryCoordinator _discovery = PiHubDiscoveryCoordinator();

  ClassroomConnectionState _state = ClassroomConnectionState.disconnected;
  ClassroomDescriptor? _currentClassroom;
  List<ClassroomDescriptor> _availableClassrooms = const [];
  Timer? _healthCheckTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _disposed = false;

  String? get activeEndpoint => _currentClassroom?.gatewayUrl;
  bool get isDiscovering =>
      _state == ClassroomConnectionState.discovering ||
      _state == ClassroomConnectionState.reconnecting;
  ClassroomConnectionState get state => _state;
  ClassroomDescriptor? get currentClassroom => _currentClassroom;
  List<ClassroomDescriptor> get availableClassrooms =>
      List.unmodifiable(_availableClassrooms);
  bool get isConnected => _state == ClassroomConnectionState.connected;

  Future<void> _initialize() async {
    final saved = await _loadPersistedClassroom();
    if (saved != null) {
      _currentClassroom = saved;
      _setState(ClassroomConnectionState.connecting);
      if (await _connectToDescriptor(saved, persist: false)) {
        return;
      }
    }
    await discover(force: true);
  }

  Future<void> discover({bool force = false}) async {
    if (!force &&
        (_state == ClassroomConnectionState.connected ||
            _state == ClassroomConnectionState.connecting ||
            _state == ClassroomConnectionState.discovering ||
            _state == ClassroomConnectionState.reconnecting)) {
      return;
    }

    _healthCheckTimer?.cancel();
    _reconnectTimer?.cancel();
    _setState(ClassroomConnectionState.discovering);

    final discoveredNode = await _discovery.discover();
    if (discoveredNode != null) {
      final descriptor = await _descriptorFor(
        discoveredNode.baseUrl,
        fallbackName: discoveredNode.name,
      );
      if (descriptor != null) {
        _availableClassrooms = <ClassroomDescriptor>[descriptor];
        notifyListeners();
        if (await connect(descriptor)) {
          return;
        }
      }
    }

    final environmentDescriptor = await _descriptorFor(
      AppEnvironment.backendBaseUrl,
      fallbackName: 'Classroom Gateway',
    );
    if (environmentDescriptor != null) {
      _availableClassrooms = <ClassroomDescriptor>[environmentDescriptor];
      notifyListeners();
      if (await connect(environmentDescriptor)) {
        return;
      }
    }

    _currentClassroom = null;
    _setState(ClassroomConnectionState.disconnected);
  }

  Future<bool> connect(ClassroomDescriptor classroom) async {
    _setState(ClassroomConnectionState.connecting);
    return _connectToDescriptor(classroom);
  }

  Future<bool> connectManual(String address) async {
    final normalized = _normalizeUrl(address);
    if (normalized == null) {
      return false;
    }
    _setState(ClassroomConnectionState.connecting);
    final descriptor = await _descriptorFor(
      normalized,
      fallbackName: 'Manual Classroom',
    );
    if (descriptor == null) {
      _setState(ClassroomConnectionState.disconnected);
      return false;
    }
    _availableClassrooms = <ClassroomDescriptor>[descriptor];
    return _connectToDescriptor(descriptor);
  }

  Future<void> disconnect({bool forget = false}) async {
    _healthCheckTimer?.cancel();
    _reconnectTimer?.cancel();
    _currentClassroom = null;
    _setState(ClassroomConnectionState.disconnected);
    if (forget) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activeUrlKey);
      await prefs.remove(_classroomIdKey);
      await prefs.remove(_classroomNameKey);
      await prefs.remove(_nodeIdKey);
    }
  }

  Future<bool> _connectToDescriptor(
    ClassroomDescriptor classroom, {
    bool persist = true,
  }) async {
    final health = await _probeGateway(classroom.gatewayUrl);
    if (health == null) {
      _setState(ClassroomConnectionState.disconnected);
      _scheduleReconnect();
      return false;
    }

    final connected = classroom.copyWith(
      latencyMs: health.latencyMs,
      lastConnectedAt: DateTime.now(),
    );
    _currentClassroom = connected;
    RuntimeBackendUrl().updateUrl(connected.gatewayUrl);
    _reconnectAttempt = 0;
    _setState(ClassroomConnectionState.connected);
    if (persist) {
      await _persistClassroom(connected);
    }
    _startHealthChecks();
    return true;
  }

  void _startHealthChecks() {
    _healthCheckTimer?.cancel();
    _healthCheckTimer = Timer.periodic(
      Duration(seconds: AppEnvironment.healthCheckIntervalSeconds),
      (_) async {
        final classroom = _currentClassroom;
        if (classroom == null) {
          return;
        }
        final health = await _probeGateway(classroom.gatewayUrl);
        if (health == null) {
          _healthCheckTimer?.cancel();
          _setState(ClassroomConnectionState.reconnecting);
          _scheduleReconnect();
          return;
        }
        _currentClassroom = classroom.copyWith(
          latencyMs: health.latencyMs,
          lastConnectedAt: DateTime.now(),
        );
        notifyListeners();
      },
    );
  }

  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) {
      return;
    }
    _setState(ClassroomConnectionState.reconnecting);
    final delay =
        _reconnectDelays[_reconnectAttempt.clamp(
          0,
          _reconnectDelays.length - 1,
        )];
    _reconnectAttempt += 1;
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      final saved = _currentClassroom ?? await _loadPersistedClassroom();
      if (saved != null && await _connectToDescriptor(saved, persist: false)) {
        return;
      }
      await discover(force: true);
    });
  }

  Future<ClassroomDescriptor?> _descriptorFor(
    String gatewayUrl, {
    required String fallbackName,
  }) async {
    final health = await _probeGateway(gatewayUrl);
    if (health == null) {
      return null;
    }

    final data = health.data;
    final uri = Uri.parse(gatewayUrl);
    return ClassroomDescriptor(
      classroomId: _readString(data, const [
        'classroom_id',
        'classroomId',
        'id',
      ], fallback: uri.host),
      name: _readString(data, const [
        'classroom_name',
        'classroomName',
        'name',
      ], fallback: fallbackName),
      nodeId: _readString(data, const [
        'node_id',
        'nodeId',
        'hostname',
      ], fallback: uri.host),
      gatewayUrl: gatewayUrl,
      studentCount: _readInt(data, const [
        'student_count',
        'studentCount',
        'connected_students',
      ]),
      latencyMs: health.latencyMs,
      lastConnectedAt: DateTime.now(),
    );
  }

  Future<_GatewayHealth?> _probeGateway(String gatewayUrl) async {
    HttpClient? client;
    try {
      final stopwatch = Stopwatch()..start();
      client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final request = await client
          .getUrl(Uri.parse('$gatewayUrl/health'))
          .timeout(const Duration(seconds: 3));
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      final body = await utf8.decodeStream(response);
      stopwatch.stop();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      Map<String, dynamic> data = const {};
      if (body.trim().isNotEmpty) {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      }
      return _GatewayHealth(
        latencyMs: stopwatch.elapsedMilliseconds,
        data: data,
      );
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<void> _persistClassroom(ClassroomDescriptor classroom) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeUrlKey, classroom.gatewayUrl);
    await prefs.setString(_classroomIdKey, classroom.classroomId);
    await prefs.setString(_classroomNameKey, classroom.name);
    await prefs.setString(_nodeIdKey, classroom.nodeId);
  }

  Future<ClassroomDescriptor?> _loadPersistedClassroom() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_activeUrlKey);
    if (url == null || url.isEmpty) {
      return null;
    }
    return ClassroomDescriptor(
      classroomId: prefs.getString(_classroomIdKey) ?? Uri.parse(url).host,
      name: prefs.getString(_classroomNameKey) ?? 'Saved Classroom',
      nodeId: prefs.getString(_nodeIdKey) ?? Uri.parse(url).host,
      gatewayUrl: url,
    );
  }

  String? _normalizeUrl(String input) {
    final clean = input.trim();
    if (clean.isEmpty) {
      return null;
    }
    final withScheme = clean.contains('://') ? clean : 'http://$clean';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    return uri
        .replace(path: '', query: null, fragment: null)
        .toString()
        .replaceAll(RegExp(r'/$'), '');
  }

  String _readString(
    Map<String, dynamic> data,
    List<String> keys, {
    required String fallback,
  }) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }

  int? _readInt(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is int) {
        return value;
      }
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }

  /// Starts background non-blocking discovery monitoring.
  void startBackgroundMonitoring({Duration interval = const Duration(seconds: 30)}) {
    unawaited(probeNow());
  }

  /// Triggers an immediate background probe.
  Future<void> probeNow({void Function(dynamic progress)? onProgress}) async {
    try {
      await discover(force: true);
    } catch (_) {}
  }

  void _setState(ClassroomConnectionState value) {
    if (_state == value || _disposed) {
      return;
    }
    _state = value;
    if (value == ClassroomConnectionState.connected && _currentClassroom != null) {
      BackendAvailabilityCache().updateStatus(true, url: _currentClassroom!.gatewayUrl);
    } else if (value == ClassroomConnectionState.disconnected) {
      BackendAvailabilityCache().updateStatus(false);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _healthCheckTimer?.cancel();
    _reconnectTimer?.cancel();
    unawaited(_discovery.close());
    super.dispose();
  }
}

class _GatewayHealth {
  const _GatewayHealth({required this.latencyMs, required this.data});

  final int latencyMs;
  final Map<String, dynamic> data;
}
