class BackendAvailabilityCache {
  static final BackendAvailabilityCache _instance = BackendAvailabilityCache._internal();

  factory BackendAvailabilityCache() {
    return _instance;
  }

  BackendAvailabilityCache._internal();

  bool? _isAvailable;
  String? _cachedUrl;
  DateTime? _lastChecked;
  final Duration _cacheDuration = const Duration(minutes: 5);

  /// Returns the cached availability status, or null if expired/never checked.
  bool? get cachedStatus {
    if (_isAvailable == null || _lastChecked == null) {
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
    _isAvailable = available;
    _cachedUrl = url;
    _lastChecked = DateTime.now();
  }

  /// Clears the cache.
  void clear() {
    _isAvailable = null;
    _cachedUrl = null;
    _lastChecked = null;
  }
}
