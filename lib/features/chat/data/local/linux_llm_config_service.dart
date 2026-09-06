import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class LinuxLlmConfig {
  const LinuxLlmConfig({
    required this.modelPath,
    required this.executablePath,
    required this.maxTokens,
  });

  final String modelPath;
  final String executablePath;
  final int maxTokens;

  bool get isReady => modelPath.trim().isNotEmpty && executablePath.trim().isNotEmpty;

  LinuxLlmConfig copyWith({
    String? modelPath,
    String? executablePath,
    int? maxTokens,
  }) {
    return LinuxLlmConfig(
      modelPath: modelPath ?? this.modelPath,
      executablePath: executablePath ?? this.executablePath,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'modelPath': modelPath,
      'executablePath': executablePath,
      'maxTokens': maxTokens,
    };
  }

  static LinuxLlmConfig fromJson(Map<String, dynamic> json) {
    return LinuxLlmConfig(
      modelPath: (json['modelPath'] as String?) ?? '',
      executablePath: (json['executablePath'] as String?) ?? '',
      maxTokens: (json['maxTokens'] as int?) ?? 192,
    );
  }

  static const LinuxLlmConfig defaults = LinuxLlmConfig(
    modelPath: '',
    executablePath: '/home/akash/Desktop/IDP/llama.cpp/build/bin/llama-cli',
    maxTokens: 192,
  );
}

class LinuxLlmConfigService {
  Future<LinuxLlmConfig> load() async {
    try {
      final file = await _configFile();
      if (!await file.exists()) {
        return LinuxLlmConfig.defaults;
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return LinuxLlmConfig.defaults;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return LinuxLlmConfig.defaults;
      }
      return LinuxLlmConfig.fromJson(decoded);
    } catch (_) {
      return LinuxLlmConfig.defaults;
    }
  }

  Future<LinuxLlmConfig> save(LinuxLlmConfig config) async {
    final file = await _configFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(config.toJson()));
    return config;
  }

  Future<LinuxLlmConfig> update({
    String? modelPath,
    String? executablePath,
    int? maxTokens,
  }) async {
    final current = await load();
    final next = current.copyWith(
      modelPath: modelPath,
      executablePath: executablePath,
      maxTokens: maxTokens,
    );
    return save(next);
  }

  Future<String?> autoDetectExecutable() async {
    final candidates = <String>[
      '/home/akash/Desktop/IDP/llama.cpp/build/bin/llama-completion',
      '/home/akash/Desktop/IDP/llama.cpp/build/bin/llama-cli',
      '/usr/local/bin/llama-completion',
      '/usr/local/bin/llama-cli',
      '/usr/bin/llama-completion',
      '/usr/bin/llama-cli',
      'llama-completion',
      'llama-cli',
    ];

    for (final candidate in candidates) {
      final resolved = await _resolveExecutable(candidate);
      if (resolved != null) {
        return resolved;
      }
    }

    return null;
  }

  /// Copies the selected model file into the app support directory to
  /// improve local access performance. Returns the new model path.
  Future<String> copyModelToAppStorage(String modelPath) async {
    final src = File(modelPath);
    if (!await src.exists()) {
      throw Exception('Model file not found: $modelPath');
    }

    final dir = await getApplicationSupportDirectory();
    final modelsDir = Directory('${dir.path}/models');
    await modelsDir.create(recursive: true);
    final dest = File('${modelsDir.path}/${src.uri.pathSegments.last}');
    await src.copy(dest.path);
    return dest.path;
  }

  Future<LinuxLlmValidationResult> validate(LinuxLlmConfig config) async {
    final executable = config.executablePath.trim();
    final modelPath = config.modelPath.trim();

    if (executable.isEmpty) {
      return const LinuxLlmValidationResult(
        ready: false,
        message: 'Select llama runner binary first (llama-completion or llama-cli).',
      );
    }

    final resolvedExecutable = await _resolveExecutable(executable);
    if (resolvedExecutable == null) {
      return LinuxLlmValidationResult(
        ready: false,
        message: 'Binary not found or not executable: $executable',
      );
    }

    if (modelPath.isEmpty) {
      return const LinuxLlmValidationResult(
        ready: false,
        message: 'Select GGUF model file.',
      );
    }

    final modelFile = File(modelPath);
    if (!await modelFile.exists()) {
      return LinuxLlmValidationResult(
        ready: false,
        message: 'Model file not found: $modelPath',
      );
    }

    return LinuxLlmValidationResult(
      ready: true,
      message: 'Linux model pipeline ready.',
      resolvedExecutablePath: resolvedExecutable,
    );
  }

  Future<String?> _resolveExecutable(String rawPath) async {
    final value = rawPath.trim();
    if (value.isEmpty) {
      return null;
    }

    if (value.contains('/')) {
      final file = File(value);
      if (!await file.exists()) {
        return null;
      }
      return value;
    }

    try {
      final whichResult = await Process.run('which', <String>[value]);
      if (whichResult.exitCode == 0) {
        final resolved = (whichResult.stdout as String?)?.trim() ?? '';
        if (resolved.isNotEmpty) {
          return resolved;
        }
      }
    } catch (_) {
      // Ignore lookup errors and report unresolved.
    }

    return null;
  }

  Future<File> _configFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return File('${dir.path}/linux_llm_config.json');
    } catch (_) {
      final home = Platform.environment['HOME'] ?? '.';
      return File('$home/.config/mentora/linux_llm_config.json');
    }
  }
}

class LinuxLlmValidationResult {
  const LinuxLlmValidationResult({
    required this.ready,
    required this.message,
    this.resolvedExecutablePath,
  });

  final bool ready;
  final String message;
  final String? resolvedExecutablePath;
}
