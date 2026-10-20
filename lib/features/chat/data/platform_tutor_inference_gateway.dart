import 'dart:io';

import 'package:flutter/services.dart';

import 'ffi_tutor_inference_gateway.dart';
import '../../network/domain/local_inference_source.dart';
import 'linux_tutor_inference_gateway.dart';
import 'tutor_inference_gateway.dart';

class PlatformTutorInferenceGateway implements TutorInferenceGateway, LocalInferenceSource {
  static const MethodChannel _channel = MethodChannel('offline_tutor/llm');
  static const EventChannel _streamChannel = EventChannel('offline_tutor/llm_stream');
  static const EventChannel _metricsChannel = EventChannel('offline_tutor/llm_metrics');
  
  final FfiTutorInferenceGateway _ffiGateway = FfiTutorInferenceGateway();
  final LinuxTutorInferenceGateway _linuxGateway = LinuxTutorInferenceGateway();

  @override
  bool get isReady => true;

  @override
  Stream<String> streamQuestion(String question) => streamResponse(prompt: question);

  @override
  Future<Map<String, String>> getModelInfo() async => {'provider': 'on-device'};

  @override
  Future<void> ensureModelLoaded() async {}

  @override
  void dispose() {}

  @override
  Stream<String> streamResponse({required String prompt}) async* {
    final stopwatch = Stopwatch()..start();
    String elapsed() => '+${stopwatch.elapsedMilliseconds}ms';

    print('[DIAGNOSTICS] [${elapsed()}] ENTERING PlatformTutorInferenceGateway.streamResponse()');
    print('[DIAGNOSTICS] [${elapsed()}] GENERATION_START (PLATFORM) - promptLength=${prompt.length}');
    Stream<String> sourceStream;

    final ffiReady = await _ffiGateway.isAvailable();
    if (ffiReady) {
      print('[DIAGNOSTICS] [${elapsed()}] Routing through FfiTutorInferenceGateway');
      sourceStream = _ffiGateway.streamResponse(prompt: prompt);
    } else if (Platform.isLinux) {
      print('[DIAGNOSTICS] [${elapsed()}] Routing through LinuxTutorInferenceGateway (llama-cli process)');
      sourceStream = _linuxGateway.streamResponse(prompt: prompt);
    } else {
      print('[DIAGNOSTICS] [${elapsed()}] Routing through MethodChannel (LlamaEngine.kt)');
      sourceStream = _streamChannel
          .receiveBroadcastStream(<String, dynamic>{'question': prompt})
          .where((event) => event is String)
          .cast<String>()
          .where((chunk) => chunk.isNotEmpty);
    }

    var isFirstToken = true;
    var tokenCount = 0;
    try {
      await for (final chunk in sourceStream) {
        tokenCount++;
        if (isFirstToken) {
          print('[DIAGNOSTICS] [${elapsed()}] FIRST_TOKEN (PLATFORM) - TTFT: ${stopwatch.elapsedMilliseconds}ms');
          isFirstToken = false;
        } else if (tokenCount <= 5 || tokenCount % 20 == 0) {
          print('[DIAGNOSTICS] [${elapsed()}] TOKEN #$tokenCount (chunk: ${chunk.length} chars)');
        }
        yield chunk;
      }
    } finally {
      print('[DIAGNOSTICS] [${elapsed()}] GENERATION_END (PLATFORM) - Total: ${stopwatch.elapsedMilliseconds}ms, Tokens: $tokenCount');
    }
  }

  @override
  Stream<Map<String, dynamic>> metricsStream() {
    if (Platform.isLinux) {
      return _linuxGateway.metricsStream();
    }

    return _metricsChannel
        .receiveBroadcastStream()
        .where((event) => event is Map)
        .map((event) => Map<dynamic, dynamic>.from(event as Map))
        .map(
          (map) => <String, dynamic>{
            'totalMs': map['totalMs'],
            'tokens': map['tokens'],
            'tokensPerSec': map['tokensPerSec'],
          },
        );
  }

  @override
  Future<void> stopGeneration() async {
    if (await _ffiGateway.isAvailable()) {
      await _ffiGateway.stopGeneration();
      return;
    }

    if (Platform.isLinux) {
      await _linuxGateway.stopGeneration();
      return;
    }

    await _channel.invokeMethod<Map<dynamic, dynamic>>('stopGeneration');
  }
}

