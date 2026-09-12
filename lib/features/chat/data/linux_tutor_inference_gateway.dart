import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'local/linux_llm_config_service.dart';
import 'tutor_inference_gateway.dart';

class LinuxTutorInferenceGateway implements TutorInferenceGateway {
  LinuxTutorInferenceGateway({LinuxLlmConfigService? configService})
    : _configService = configService ?? LinuxLlmConfigService();

  final LinuxLlmConfigService _configService;
  Process? _activeProcess;
  final Map<String, _LlamaCliCapabilities> _capabilityCache =
      <String, _LlamaCliCapabilities>{};
  static final RegExp _ansiEscape = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

  @override
  Stream<String> streamResponse({required String prompt}) async* {
    final config = await _configService.load();
    final executable = config.executablePath.trim();
    final model = config.modelPath.trim();

    if (executable.isEmpty || model.isEmpty) {
      throw Exception(
        'Linux model is not configured. Select executable and model path in chat settings.',
      );
    }

    final resolvedExecutable = await _configService.autoDetectExecutable();
    final executableToUse =
        resolvedExecutable != null &&
            executable == LinuxLlmConfig.defaults.executablePath
        ? resolvedExecutable
        : executable;

    if (executableToUse.contains('/')) {
      final execFile = File(executableToUse);
      if (!await execFile.exists()) {
        throw Exception('LLM executable not found: $executableToUse');
      }
    }

    final modelFile = File(model);
    if (!await modelFile.exists()) {
      throw Exception('Model file not found: $model');
    }

    final capabilities = await _detectCapabilities(executableToUse);

    final selected = await _selectExecutionTarget(
      executable: executableToUse,
      capabilities: capabilities,
    );

    final args = _buildArgs(
      model: model,
      maxTokens: config.maxTokens,
      prompt: prompt,
      executable: selected.executable,
      capabilities: selected.capabilities,
    );

    await stopGeneration();

    final process = await Process.start(
      selected.executable,
      args,
      runInShell: false,
    );
    _activeProcess = process;

    final stderrBuffer = StringBuffer();
    // Merge stdout and stderr into a single stream because some llama.cpp builds
    // emit tokens to stderr instead of (or in addition to) stdout. Without this,
    // those builds produce zero visible output and the UI hangs on 'Thinking...'.
    final merged = StreamController<String>();

    var stdoutDone = false;
    var stderrDone = false;
    // Close the merged controller only after BOTH sinks finish, so stderr tokens
    // arriving after stdout closes are not dropped.
    void _closeWhenComplete() {
      if (stdoutDone && stderrDone && !merged.isClosed) {
        merged.close();
      }
    }

    // Forward stdout chunks into the merged stream.
    process.stdout.transform(utf8.decoder).listen(
      (chunk) {
        if (chunk.isEmpty) return;
        final cleaned = chunk.replaceAll(_ansiEscape, '');
        if (cleaned.isNotEmpty && !_isLlamaLogChunk(cleaned) && !merged.isClosed) {
          merged.add(cleaned);
        }
      },
      onError: merged.addError,
      onDone: () {
        stdoutDone = true;
        _closeWhenComplete();
      },
    );

    // Capture stderr continuously for diagnostic logs and error reporting.
    // We log it to the console buffer, but DO NOT yield stderr lines into
    // the chat UI stream so initialization telemetry never leaks into user bubbles.
    process.stderr.transform(utf8.decoder).listen(
      (chunk) {
        if (chunk.isEmpty) return;
        stderrBuffer.write(chunk);
        final cleaned = chunk.replaceAll(_ansiEscape, '');
        if (cleaned.isNotEmpty) {
          // Print diagnostics to console for developer troubleshooting.
          // ignore: avoid_print
          print('[LLAMA STDERR] ${cleaned.trim()}');
        }
      },
      onError: merged.addError,
      onDone: () {
        stderrDone = true;
        _closeWhenComplete();
      },
    );

    try {
      // Yield whatever we get from either stream (even if it includes partial
      // lines or stderr noise), so the UI can progress instead of hanging.
      await for (final chunk in merged.stream) {
        yield chunk;
      }

      final code = await process.exitCode;
      if (code != 0) {
        final message = stderrBuffer.toString().trim();
        throw Exception(
          message.isEmpty
              ? 'Linux inference failed with exit code $code'
              : 'Linux inference failed: $message',
        );
      }
    } finally {
      if (!merged.isClosed) {
        merged.close();
      }
      if (identical(_activeProcess, process)) {
        _activeProcess = null;
      }
    }
  }

  @override
  Stream<Map<String, dynamic>> metricsStream() {
    return const Stream<Map<String, dynamic>>.empty();
  }

  Future<_LlamaCliCapabilities> _detectCapabilities(String executable) async {
    final cached = _capabilityCache[executable];
    if (cached != null) {
      return cached;
    }

    try {
      final result = await Process.run(executable, const <String>[
        '--help',
      ], runInShell: false);
      final help = '${result.stdout}\n${result.stderr}'.toLowerCase();
      final detected = _LlamaCliCapabilities(
        supportsLongPrompt: help.contains('--prompt'),
        supportsNoDisplayPrompt: help.contains('--no-display-prompt'),
        supportsNoConversation:
            help.contains('--no-conversation') || help.contains('-no-cnv'),
        supportsSimpleIo: help.contains('--simple-io'),
        supportsNoPerf: help.contains('--no-perf'),
      );
      _capabilityCache[executable] = detected;
      return detected;
    } catch (_) {
      const fallback = _LlamaCliCapabilities(
        supportsLongPrompt: false,
        supportsNoDisplayPrompt: false,
        supportsNoConversation: false,
        supportsSimpleIo: false,
        supportsNoPerf: false,
      );
      _capabilityCache[executable] = fallback;
      return fallback;
    }
  }

  List<String> _buildArgs({
    required String model,
    required int maxTokens,
    required String prompt,
    required String executable,
    required _LlamaCliCapabilities capabilities,
  }) {
    final args = <String>[
      '-m',
      model,
      '-n',
      maxTokens.toString(),
      capabilities.supportsLongPrompt ? '--prompt' : '-p',
      prompt,
      '--temp',
      '0.3',
      '--top-k',
      '30',
    ];

    final exeName = executable.split('/').last.toLowerCase();
    if (exeName.contains('llama-completion') &&
        capabilities.supportsNoConversation) {
      // Prevent REPL-style session that never exits and blocks UI completion.
      args.add('--no-conversation');
    }

    if (capabilities.supportsNoDisplayPrompt) {
      args.add('--no-display-prompt');
    }

    if (capabilities.supportsSimpleIo) {
      args.add('--simple-io');
    }

    if (capabilities.supportsNoPerf) {
      args.add('--no-perf');
    }

    return args;
  }

  Future<({String executable, _LlamaCliCapabilities capabilities})>
  _selectExecutionTarget({
    required String executable,
    required _LlamaCliCapabilities capabilities,
  }) async {
    final exeName = executable.split('/').last.toLowerCase();
    if (!exeName.contains('llama-cli')) {
      return (executable: executable, capabilities: capabilities);
    }

    final completionPath = await _findLlamaCompletion(executable);
    if (completionPath == null) {
      return (executable: executable, capabilities: capabilities);
    }

    final completionCapabilities = await _detectCapabilities(completionPath);
    return (executable: completionPath, capabilities: completionCapabilities);
  }

  Future<String?> _findLlamaCompletion(String selectedExecutable) async {
    final candidates = <String>[];
    if (selectedExecutable.contains('/')) {
      final sibling = selectedExecutable.replaceAll(
        'llama-cli',
        'llama-completion',
      );
      candidates.add(sibling);
    }
    candidates.addAll(const <String>[
      '/home/akash/Desktop/IDP/llama.cpp/build/bin/llama-completion',
      '/usr/local/bin/llama-completion',
      '/usr/bin/llama-completion',
      'llama-completion',
    ]);

    for (final candidate in candidates) {
      try {
        if (candidate.contains('/')) {
          final file = File(candidate);
          if (await file.exists()) {
            return candidate;
          }
        } else {
          final which = await Process.run('which', <String>[candidate]);
          if (which.exitCode == 0) {
            final resolved = (which.stdout as String?)?.trim() ?? '';
            if (resolved.isNotEmpty) {
              return resolved;
            }
          }
        }
      } catch (_) {
        // Try the next candidate.
      }
    }

    return null;
  }

  @override
  Future<void> stopGeneration() async {
    final process = _activeProcess;
    if (process == null) {
      return;
    }

    try {
      process.kill(ProcessSignal.sigint);
      await process.exitCode.timeout(
        const Duration(milliseconds: 600),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (_) {
      process.kill(ProcessSignal.sigkill);
    } finally {
      _activeProcess = null;
    }
  }

  static bool _isLlamaLogChunk(String chunk) {
    final lower = chunk.toLowerCase().trim();
    if (lower.isEmpty) return true;
    return lower.startsWith('build:') ||
        lower.startsWith('main:') ||
        lower.startsWith('llama_') ||
        lower.startsWith('common_') ||
        lower.startsWith('print_info:') ||
        lower.startsWith('load_tensors:') ||
        lower.startsWith('sched_reserve:') ||
        lower.startsWith('system_info:') ||
        lower.startsWith('sampler ') ||
        lower.startsWith('generate:') ||
        lower.startsWith('load:') ||
        lower.startsWith('cpu_mapped') ||
        lower.startsWith('cpu_repack') ||
        lower.startsWith('memory breakdown') ||
        lower.startsWith('[llama stderr]') ||
        lower.contains('fitting params to device memory') ||
        lower.contains('loaded meta data with');
  }
}

class _LlamaCliCapabilities {
  const _LlamaCliCapabilities({
    required this.supportsLongPrompt,
    required this.supportsNoDisplayPrompt,
    required this.supportsNoConversation,
    required this.supportsSimpleIo,
    required this.supportsNoPerf,
  });

  final bool supportsLongPrompt;
  final bool supportsNoDisplayPrompt;
  final bool supportsNoConversation;
  final bool supportsSimpleIo;
  final bool supportsNoPerf;
}
