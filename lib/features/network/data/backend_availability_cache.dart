import 'dart:async';
import 'package:flutter/foundation.dart';

class BackendAvailabilityCache {
  static final BackendAvailabilityCache _instance = BackendAvailabilityCache._internal();

  factory BackendAvailabilityCache() {
    return _instance;
  }

  BackendAvailabilityCache._internal();

  bool _isAvailable = false;
  String? _cachedUrl;
  DateTime? _lastChecked;
  final Duration _cacheDuration = const Duration(minutes: 5);

  final ValueNotifier<bool> statusNotifier = ValueNotifier<bool>(false);
  final StreamController<bool> _statusController = StreamController<bool>.broadcast();

  Stream<bool> get statusStream => _statusController.stream;

  /// Returns whether backend is currently confirmed online.
  bool get isOnline => _isAvailable == true && cachedStatus == true;

  /// Returns whether backend is offline or unverified.
  bool get isOffline => !isOnline;

  /// Returns the cached availability status, or null if expired/never checked.
  bool? get cachedStatus {
    if (_lastChecked == null) {
      return null;
    }
    
    final age = DateTime.now().difference(_lastChecked!);
    if (age > _cacheDuration) {
      return null;
    }
    
    return _isAvailable;
  }

  /// Returns the cached winner URL if fresh (< 5 min), otherwise null.
  String? get cachedUrl {
    if (cachedStatus == null) return null;
    return _cachedUrl;
  }

  /// Updates the cached status and winner URL.
  void updateStatus(bool available, {String? url}) {
    final changed = _isAvailable != available || _cachedUrl != url;
    _isAvailable = available;
    _cachedUrl = url;
    _lastChecked = DateTime.now();

    if (changed || statusNotifier.value != available) {
      statusNotifier.value = available;
      if (!_statusController.isClosed) {
        _statusController.add(available);
      }
    }
  }

  /// Clears the cache.
  void clear() {
    _isAvailable = false;
    _cachedUrl = null;
    _lastChecked = null;
    statusNotifier.value = false;
    if (!_statusController.isClosed) {
      _statusController.add(false);
    }
  }
}
