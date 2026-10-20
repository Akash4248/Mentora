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
  HttpClient? _activeHttpClient;
  final Map<String, _LlamaCliCapabilities> _capabilityCache =
      <String, _LlamaCliCapabilities>{};
  static final RegExp _ansiEscape = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');

  @override
  Stream<String> streamResponse({
    required String prompt,
    int? maxTokens,
  }) async* {
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

    if (selected.executable
        .split('/')
        .last
        .toLowerCase()
        .contains('llama-server')) {
      await for (final chunk in _streamFromServer(
        executable: selected.executable,
        model: model,
        maxTokens: maxTokens ?? config.maxTokens,
        prompt: prompt,
      )) {
        yield chunk;
      }
      return;
    }

    final args = _buildArgs(
      model: model,
      maxTokens: maxTokens ?? config.maxTokens,
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
    process.stdout
        .transform(utf8.decoder)
        .listen(
          (chunk) {
            if (chunk.isEmpty) return;
            final cleaned = chunk.replaceAll(_ansiEscape, '');
            if (cleaned.isNotEmpty &&
                !_isLlamaLogChunk(cleaned) &&
                !merged.isClosed) {
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
    process.stderr
        .transform(utf8.decoder)
        .listen(
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
      var receivedOutput = false;
      await for (final chunk in merged.stream) {
        receivedOutput = receivedOutput || chunk.isNotEmpty;
        yield chunk;
      }

      final code = await process.exitCode;
      if (code != 0) {
        final message = stderrBuffer.toString().trim();
        final detail = message.isEmpty
            ? 'Linux inference failed with exit code $code'
            : 'Linux inference failed: $message';
        if (!receivedOutput && _hasUnsupportedType41(detail)) {
          final compatibleRunner = await _configService.autoDetectExecutable();
          if (compatibleRunner != null &&
              compatibleRunner
                  .split('/')
                  .last
                  .toLowerCase()
                  .contains('llama-server') &&
              compatibleRunner != selected.executable) {
            await for (final chunk in _streamFromServer(
              executable: compatibleRunner,
              model: model,
              maxTokens: maxTokens ?? config.maxTokens,
              prompt: prompt,
            )) {
              yield chunk;
            }
            return;
          }
        }
        throw Exception(_addRuntimeCompatibilityHint(detail));
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

  Stream<String> _streamFromServer({
    required String executable,
    required String model,
    required int maxTokens,
    required String prompt,
  }) async* {
    await stopGeneration();
    final port = await _reserveLoopbackPort();
    final process = await Process.start(executable, <String>[
      '--model',
      model,
      '--ctx-size',
      '2048',
      '--predict',
      maxTokens.toString(),
      '--gpu-layers',
      '0',
      '--threads',
      '2',
      '--host',
      '127.0.0.1',
      '--port',
      port.toString(),
      '--no-webui',
    ], runInShell: false);
    _activeProcess = process;
    final logs = StringBuffer();
    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .listen(logs.write);
    final stderrSubscription = process.stderr.transform(utf8.decoder).listen((
      chunk,
    ) {
      logs.write(chunk);
      print('[LLAMA SERVER] ${chunk.trim()}');
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    _activeHttpClient = client;

    try {
      await _waitForServer(
        client: client,
        port: port,
        process: process,
        logs: logs,
      );

      final request = await client.postUrl(
        Uri.parse('http://127.0.0.1:$port/completion'),
      );
      request.headers.contentType = ContentType.json;
      request.write(
        jsonEncode(<String, dynamic>{
          'prompt': prompt,
          'n_predict': maxTokens,
          'temperature': 0.3,
          'top_k': 30,
          'stream': true,
        }),
      );
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await utf8.decoder.bind(response).join();
        throw StateError(
          'llama-server returned HTTP ${response.statusCode}: $body',
        );
      }

      await for (final line
          in response.transform(utf8.decoder).transform(const LineSplitter())) {
        if (!line.startsWith('data:')) continue;
        final data = line.substring('data:'.length).trim();
        if (data.isEmpty || data == '[DONE]') continue;
        final event = jsonDecode(data);
        if (event is! Map<String, dynamic>) continue;
        final error = event['error'];
        if (error != null) {
          throw StateError('llama-server inference failed: $error');
        }
        final content = event['content'];
        if (content is String && content.isNotEmpty) {
          yield content;
        }
      }
    } finally {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
      if (identical(_activeHttpClient, client)) {
        _activeHttpClient = null;
      }
      client.close(force: true);
      if (identical(_activeProcess, process)) {
        await stopGeneration();
      }
    }
  }

  Future<void> _waitForServer({
    required HttpClient client,
    required int port,
    required Process process,
    required StringBuffer logs,
  }) async {
    var processExitCode = -1;
    var processExited = false;
    unawaited(
      process.exitCode.then((code) {
        processExitCode = code;
        processExited = true;
      }),
    );
    final deadline = DateTime.now().add(const Duration(minutes: 2));

    while (DateTime.now().isBefore(deadline)) {
      if (processExited) {
        throw StateError(
          'llama-server exited during model load (code $processExitCode). '
          '${logs.toString().trim()}',
        );
      }
      try {
        final request = await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/health'),
        );
        final response = await request.close().timeout(
          const Duration(seconds: 2),
        );
        await response.drain<void>();
        if (response.statusCode == HttpStatus.ok) return;
      } on SocketException {
        // The server has not bound its local health endpoint yet.
      } on HttpException {
        // The server has not bound its local health endpoint yet.
      } on TimeoutException {
        // Model loading may still be in progress.
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    throw TimeoutException(
      'llama-server did not finish loading the selected model within 2 minutes. '
      '${logs.toString().trim()}',
    );
  }

  Future<int> _reserveLoopbackPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
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
      ], runInShell: false).timeout(const Duration(seconds: 3));
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
    final client = _activeHttpClient;
    _activeHttpClient = null;
    client?.close(force: true);
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

  static String _addRuntimeCompatibilityHint(String message) {
    final normalized = message.toLowerCase();
    if (_hasUnsupportedType41(normalized)) {
      return '$message\n\nThe selected llama.cpp runtime does not support GGUF '
          'tensor type 41. Update the llama-cli/llama-completion/llama-server '
          'binary to a build that supports this model quantization, or choose '
          'a GGUF quantization supported by the installed runtime.';
    }
    return message;
  }

  static bool _hasUnsupportedType41(String message) =>
      message.toLowerCase().contains('invalid ggml type 41') ||
      message.toLowerCase().contains('ggml type 41. should be in [0, 41)');
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
