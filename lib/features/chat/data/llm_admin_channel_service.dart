import 'dart:io';
import 'package:flutter/services.dart';
import '../../settings/services/user_api_key_service.dart';
import 'linux_tutor_inference_gateway.dart';
import 'local/linux_llm_config_service.dart';

class ModelMetadata {
  const ModelMetadata({
    required this.path,
    required this.sizeBytes,
    required this.lastSelectedAtMillis,
  });

  final String path;
  final int sizeBytes;
  final int lastSelectedAtMillis;
}

class GenerationConfig {
  const GenerationConfig({
    required this.maxTokens,
    required this.timeoutMs,
    required this.systemPrompt,
  });

  final int maxTokens;
  final int timeoutMs;
  final String systemPrompt;
}

class EngineStatus {
  const EngineStatus({
    required this.loaded,
    required this.modelPath,
    required this.lastEngineError,
    required this.totalInferenceCount,
    required this.lastInferenceDurationMs,
    required this.avgInferenceDurationMs,
  });

  final bool loaded;
  final String modelPath;
  final String lastEngineError;
  final int totalInferenceCount;
  final int lastInferenceDurationMs;
  final int avgInferenceDurationMs;
}

class LlmAdminChannelService {
  static const MethodChannel _channel = MethodChannel('offline_tutor/llm');
  static const EventChannel _modelCopyProgressChannel = EventChannel('offline_tutor/model_copy_progress');
  final LinuxLlmConfigService _linuxConfigService = LinuxLlmConfigService();

  Stream<int> get modelCopyProgress {
    if (Platform.isLinux) {
      return Stream.value(100);
    }
    return _modelCopyProgressChannel.receiveBroadcastStream().cast<int>();
  }

  Future<String?> getModelPath() async {
    if (Platform.isLinux) {
      final config = await _linuxConfigService.load();
      if (config.modelPath.isNotEmpty) return config.modelPath;
      final autoModel = await _linuxConfigService.autoDetectModelPath();
      if (autoModel != null) {
        await _linuxConfigService.update(modelPath: autoModel);
        return autoModel;
      }
      return '';
    }
    return _channel.invokeMethod<String>('getModelPath');
  }

  Future<bool> setModelPath(String modelPath) async {
    if (Platform.isLinux) {
      final file = File(modelPath);
      if (!await file.exists()) {
        return false;
      }
      await _linuxConfigService.update(modelPath: modelPath);
      final userApiKeyService = await UserApiKeyService.getInstance();
      final fileName = file.uri.pathSegments.last;
      await userApiKeyService.setGgufModelName(fileName);
      return true;
    }
    final response = await _channel.invokeMethod<bool>(
      'setModelPath',
      <String, dynamic>{'modelPath': modelPath},
    );
    return response ?? false;
  }

  Future<ModelMetadata> getModelMetadata() async {
    if (Platform.isLinux) {
      var config = await _linuxConfigService.load();
      var path = config.modelPath;
      if (path.isEmpty || !await File(path).exists()) {
        final autoModel = await _linuxConfigService.autoDetectModelPath();
        if (autoModel != null) {
          path = autoModel;
          await _linuxConfigService.update(modelPath: autoModel);
        }
      }
      if (path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          final stat = await file.stat();
          return ModelMetadata(
            path: path,
            sizeBytes: stat.size,
            lastSelectedAtMillis: stat.modified.millisecondsSinceEpoch,
          );
        }
      }
      return const ModelMetadata(
        path: '',
        sizeBytes: 0,
        lastSelectedAtMillis: 0,
      );
    }
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'getModelMetadata',
    );

    return ModelMetadata(
      path: response?['path'] as String? ?? '',
      sizeBytes: response?['sizeBytes'] as int? ?? 0,
      lastSelectedAtMillis: response?['lastSelectedAtMillis'] as int? ?? 0,
    );
  }

  Future<GenerationConfig> getGenerationConfig() async {
    if (Platform.isLinux) {
      final config = await _linuxConfigService.load();
      return GenerationConfig(
        maxTokens: config.maxTokens,
        timeoutMs: 120000,
        systemPrompt: 'You are a helpful NCERT offline AI tutor.',
      );
    }
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'getGenerationConfig',
    );

    return GenerationConfig(
      maxTokens: response?['maxTokens'] as int? ?? 256,
      timeoutMs: response?['timeoutMs'] as int? ?? 120000,
      systemPrompt: response?['systemPrompt'] as String? ?? '',
    );
  }

  Future<GenerationConfig> updateGenerationConfig({
    int? maxTokens,
    int? timeoutMs,
    String? systemPrompt,
  }) async {
    if (Platform.isLinux) {
      final config = await _linuxConfigService.update(
        maxTokens: maxTokens,
      );
      return GenerationConfig(
        maxTokens: config.maxTokens,
        timeoutMs: timeoutMs ?? 120000,
        systemPrompt: systemPrompt ?? '',
      );
    }
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'updateGenerationConfig',
      <String, dynamic>{
        'maxTokens': maxTokens,
        'timeoutMs': timeoutMs,
        'systemPrompt': systemPrompt,
      },
    );

    return GenerationConfig(
      maxTokens: response?['maxTokens'] as int? ?? 256,
      timeoutMs: response?['timeoutMs'] as int? ?? 120000,
      systemPrompt: response?['systemPrompt'] as String? ?? '',
    );
  }

  Future<EngineStatus> getEngineStatus() async {
    if (Platform.isLinux) {
      var config = await _linuxConfigService.load();
      if (config.modelPath.isEmpty || !await File(config.modelPath).exists()) {
        final autoModel = await _linuxConfigService.autoDetectModelPath();
        if (autoModel != null) {
          config = await _linuxConfigService.update(modelPath: autoModel);
        }
      }
      final validation = await _linuxConfigService.validate(config);
      return EngineStatus(
        loaded: validation.ready,
        modelPath: config.modelPath,
        lastEngineError: validation.ready ? '' : validation.message,
        totalInferenceCount: 0,
        lastInferenceDurationMs: 0,
        avgInferenceDurationMs: 0,
      );
    }
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'getEngineStatus',
    );

    return EngineStatus(
      loaded: response?['loaded'] as bool? ?? false,
      modelPath: response?['modelPath'] as String? ?? '',
      lastEngineError: response?['lastEngineError'] as String? ?? '',
      totalInferenceCount: response?['totalInferenceCount'] as int? ?? 0,
      lastInferenceDurationMs: response?['lastInferenceDurationMs'] as int? ?? 0,
      avgInferenceDurationMs: response?['avgInferenceDurationMs'] as int? ?? 0,
    );
  }

  Future<bool> preloadModel() async {
    if (Platform.isLinux) {
      final config = await _linuxConfigService.load();
      final validation = await _linuxConfigService.validate(config);
      return validation.ready;
    }
    final response = await _channel.invokeMethod<bool>('preloadModel');
    return response ?? false;
  }

  Future<Map<String, dynamic>> runPerformanceProbe({
    int iterations = 1,
  }) async {
    if (Platform.isLinux) {
      final gateway = LinuxTutorInferenceGateway();
      final stopwatch = Stopwatch()..start();
      try {
        final stream = gateway.streamResponse(prompt: 'Hello');
        var count = 0;
        await for (final chunk in stream) {
          count += chunk.length;
        }
        stopwatch.stop();
        return <String, dynamic>{
          'ok': count > 0,
          'msPerInference': stopwatch.elapsedMilliseconds,
          'details': 'Linux llama.cpp subprocess probe succeeded ($count chars).',
        };
      } catch (e) {
        stopwatch.stop();
        return <String, dynamic>{
          'ok': false,
          'msPerInference': 0,
          'details': e.toString(),
        };
      }
    }
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'runPerformanceProbe',
      <String, dynamic>{'iterations': iterations},
    );
    return response ?? const <String, dynamic>{};
  }

  Future<bool> resetEngine() async {
    if (Platform.isLinux) {
      final gateway = LinuxTutorInferenceGateway();
      await gateway.stopGeneration();
      return true;
    }
    final response = await _channel.invokeMethod<bool>('resetEngine');
    return response ?? false;
  }

  Future<Map<String, dynamic>> runEngineSelfTest() async {
    if (Platform.isLinux) {
      final config = await _linuxConfigService.load();
      final validation = await _linuxConfigService.validate(config);
      return <String, dynamic>{
        'ok': validation.ready,
        'message': validation.message,
        'executable': validation.resolvedExecutablePath ?? config.executablePath,
        'modelPath': config.modelPath,
      };
    }
    final response = await _channel.invokeMapMethod<String, dynamic>(
      'runEngineSelfTest',
    );
    return response ?? const <String, dynamic>{};
  }
}
