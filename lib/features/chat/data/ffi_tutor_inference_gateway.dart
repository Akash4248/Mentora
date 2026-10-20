import 'dart:async';

import 'tutor_inference_gateway.dart';

class FfiTutorInferenceGateway implements TutorInferenceGateway {
  bool? _isAvailableCache;
  DateTime? _lastCheckTime;
  static const Duration _cacheTtl = Duration(seconds: 5);

  bool _isGenerating = false;
  StreamController<Map<String, dynamic>>? _metricsController;

  /// Checks whether native llama FFI libraries are available on this platform.
  /// Result is cached for 5 seconds to prevent excessive I/O checks.
  Future<bool> isAvailable() async {
    final now = DateTime.now();
    if (_isAvailableCache != null && _lastCheckTime != null) {
      if (now.difference(_lastCheckTime!) < _cacheTtl) {
        return _isAvailableCache!;
      }
    }

    _lastCheckTime = now;
    _isAvailableCache = _checkNativeLibraryAvailability();
    return _isAvailableCache!;
  }

  bool _checkNativeLibraryAvailability() {
    // Return false until FFI isolate streaming is bound to native C symbols.
    // This allows PlatformTutorInferenceGateway to fall back to MethodChannel (LlamaEngine.kt on Android)
    // or LinuxTutorInferenceGateway on desktop.
    return false;
  }

  @override
  Stream<String> streamResponse({required String prompt}) async* {
    _isGenerating = true;
    _metricsController ??= StreamController<Map<String, dynamic>>.broadcast();

    final stopwatch = Stopwatch()..start();
    var tokenCount = 0;

    try {
      final ready = await isAvailable();
      if (!ready) {
        throw UnsupportedError(
          'Native llama FFI library (libllama.so/libfllama.so) is not available.',
        );
      }

      await for (final token in _streamFfiIsolate(prompt)) {
        if (!_isGenerating) break;
        tokenCount++;
        stopwatch.stop();
        _metricsController?.add(<String, dynamic>{
          'totalMs': stopwatch.elapsedMilliseconds,
          'tokens': tokenCount,
          'tokensPerSec':
              tokenCount / (stopwatch.elapsedMilliseconds / 1000.0 + 0.001),
        });
        stopwatch.start();
        yield token;
      }
    } finally {
      _isGenerating = false;
      stopwatch.stop();
    }
  }

  Stream<String> _streamFfiIsolate(String prompt) async* {
    // High-performance isolate streaming interface
    yield '';
  }

  @override
  Stream<Map<String, dynamic>> metricsStream() {
    _metricsController ??= StreamController<Map<String, dynamic>>.broadcast();
    return _metricsController!.stream;
  }

  @override
  Future<void> stopGeneration() async {
    _isGenerating = false;
  }
}
