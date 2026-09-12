import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'backend_availability_cache.dart';
import '../../../config/app_environment.dart';
import '../../chat/application/streaming_output_normalizer.dart';
import '../domain/backend_config.dart';
import '../domain/backend_response.dart';
import 'backend_http_client.dart';

/// Main service for backend API communication.
/// Handles all interactions with distributed backend infrastructure.
class BackendApiService {
  BackendApiService({
    required BackendConfig config,
    BackendHttpClient? httpClient,
  }) : _config = config,
       _httpClient = httpClient ?? BackendHttpClient(config: config);

  final BackendConfig _config;
  final BackendHttpClient _httpClient;

  /// Check if backend is configured
  bool get isConfigured => _config.isValid;

  /// Get backend configuration (without sensitive data)
  String get configInfo => _config.toString();

  /// Health check - verify backend is reachable
  Future<BackendResponse<Map<String, dynamic>>> healthCheck() async {
    final response = await _httpClient.get('/health');

    if (response.isFailure) {
      return BackendResponse.failure(
        message: response.message ?? 'Health check failed',
        statusCode: response.statusCode,
        error: response.error,
      );
    }

    try {
      final data = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
      return BackendResponse.success(data);
    } catch (error) {
      return BackendResponse.failure(
        message: 'Failed to parse health check response',
        error: error,
      );
    }
  }

  /// Fast check if backend is available
  Future<bool> isBackendAvailable() async {
    final cache = BackendAvailabilityCache();
    final cached = cache.cachedStatus;
    if (cached != null) {
      print('[DIAGNOSTICS] CACHE_HIT');
      print('[DIAGNOSTICS] BACKEND_HEALTH_CHECK_CACHED=$cached');
      return cached;
    }

    print('[DIAGNOSTICS] CACHE_MISS');
    print('[HEALTH] CACHE_MISS');
    print('[URL] SERVICE=BackendApiService URL=${_config.baseUrl}/health');
    final stopwatch = Stopwatch()..start();
    try {
      print('[DIAGNOSTICS] BACKEND_HEALTH_CHECK_START');
      print('[HEALTH] URL=${_config.baseUrl}/health');
      print('[DIAGNOSTICS] HEALTH_URL=${_config.baseUrl}/health');
      final response = await _httpClient.get(
        '/health',
        maxRetries: 0,
        timeout: const Duration(seconds: 3),
      );
      stopwatch.stop();
      final available = response.isSuccess;
      print('[DIAGNOSTICS] BACKEND_HEALTH_CHECK_END');
      print(
        '[DIAGNOSTICS] HEALTH_RESPONSE_TIME=${stopwatch.elapsedMilliseconds}ms',
      );
      print('[HEALTH] RESPONSE_TIME_MS=${stopwatch.elapsedMilliseconds}');
      print('[HEALTH] STATUS_CODE=${response.statusCode}');
      print('[HEALTH] RESPONSE_BODY=${response.data}');
      print('[HEALTH] PAYLOAD_VALID=$available');
      print('[HEALTH] FINAL_RESULT=$available');
      print('[DIAGNOSTICS] BACKEND_AVAILABLE=$available');
      cache.updateStatus(available);
      return available;
    } catch (e) {
      stopwatch.stop();
      print('[DIAGNOSTICS] BACKEND_HEALTH_CHECK_END (FAILED)');
      print(
        '[DIAGNOSTICS] HEALTH_RESPONSE_TIME=${stopwatch.elapsedMilliseconds}ms',
      );
      print('[DIAGNOSTICS] BACKEND_ERROR=$e');
      print('[HEALTH] RESPONSE_TIME_MS=${stopwatch.elapsedMilliseconds}');
      print('[HEALTH] JSON_PARSE_SUCCESS=false');
      print('[HEALTH] FINAL_RESULT=false');
      print('[DIAGNOSTICS] BACKEND_AVAILABLE=false');
      cache.updateStatus(false);
      return false;
    }
  }

  /// Generate an answer using backend AI
  Future<BackendResponse<String>> generateAnswer({
    required String question,
    String? context,
    String? systemPrompt,
    String? language,
    int maxTokens = 512,
  }) async {
    final body = <String, dynamic>{
      'question': question,
      'max_tokens': maxTokens,
      'stream': false,
    };

    if (language != null && language.isNotEmpty) {
      body['language'] = language;
    }
    if (context != null && context.isNotEmpty) {
      body['context'] = context;
    }
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['system_prompt'] = systemPrompt;
    }

    final response = await _httpClient.post('/ai/chat', body: body);

    if (response.isFailure) {
      return BackendResponse.failure(
        message: response.message ?? 'Failed to generate answer',
        statusCode: response.statusCode,
        error: response.error,
      );
    }

    try {
      final data = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
      final answer = data['answer'] as String? ?? '';
      return BackendResponse.success(answer);
    } catch (error) {
      return BackendResponse.failure(
        message: 'Failed to parse answer response',
        error: error,
      );
    }
  }

  /// Stream an answer from backend AI
  Stream<String> streamAnswer({
    required String question,
    String? context,
    String? systemPrompt,
    String? language,
    int maxTokens = 512,
  }) async* {
    AppEnvironment.log('BACKEND', 'Starting streaming answer request');

    final body = <String, dynamic>{
      'question': question,
      'max_tokens': maxTokens,
      'stream': true,
    };

    if (language != null && language.isNotEmpty) {
      body['language'] = language;
    }
    if (context != null && context.isNotEmpty) {
      body['context'] = context;
    }
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      body['system_prompt'] = systemPrompt;
    }

    try {
      await for (final chunk in _httpClient.stream(
        '/ai/chat',
        body: body,
      )) {
        final trimmed = chunk.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) {
          continue;
        }

        if (trimmed.startsWith('data:')) {
          final jsonStr = trimmed.substring(5).trim();
          if (jsonStr == '[DONE]') {
            AppEnvironment.log('BACKEND', 'Stream completed');
            break;
          }
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            final token = data['token'] as String? ?? data['answer'] as String? ?? '';
            if (token.isNotEmpty) {
              yield token;
            }
          } catch (_) {
            // Skip malformed JSON
            continue;
          }
        } else {
          yield trimmed;
        }
      }
    } catch (error) {
      AppEnvironment.log('BACKEND', 'Stream error: $error');
      rethrow;
    }
  }

  /// Retrieve documents for RAG using /rag/search
  Future<BackendResponse<List<String>>> retrieveDocuments({
    required String query,
    int limit = 5,
  }) async {
    final response = await _httpClient.post(
      '/rag/search',
      body: <String, dynamic>{'query': query, 'limit': limit},
    );


    if (response.isFailure) {
      return BackendResponse.failure(
        message: response.message ?? 'Failed to retrieve documents',
        statusCode: response.statusCode,
        error: response.error,
      );
    }

    try {
      final data = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
      final documents = (data['documents'] as List?)?.cast<String>() ?? [];
      return BackendResponse.success(documents);
    } catch (error) {
      return BackendResponse.failure(
        message: 'Failed to parse documents response',
        error: error,
      );
    }
  }

  /// List remote packs from backend
  Future<BackendResponse<List<dynamic>>> listPacks() async {
    final response = await _httpClient.get('/packs');
    if (response.isFailure) {
      return BackendResponse.failure(
        message: response.message ?? 'Failed to list packs',
        statusCode: response.statusCode,
        error: response.error,
      );
    }
    try {
      final data = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
      final packs = data['packs'] as List<dynamic>? ?? [];
      return BackendResponse.success(packs);
    } catch (error) {
      return BackendResponse.failure(
        message: 'Failed to parse packs response',
        error: error,
      );
    }
  }

  /// Get pack manifest
  Future<BackendResponse<Map<String, dynamic>>> getPackManifest(
    String id,
  ) async {
    final response = await _httpClient.get('/packs/$id/manifest');
    if (response.isFailure) {
      return BackendResponse.failure(
        message: response.message ?? 'Failed to get pack manifest',
        statusCode: response.statusCode,
        error: response.error,
      );
    }
    try {
      final data = jsonDecode(response.data ?? '{}') as Map<String, dynamic>;
      return BackendResponse.success(data);
    } catch (error) {
      return BackendResponse.failure(
        message: 'Failed to parse manifest response',
        error: error,
      );
    }
  }

  /// Download pack archive
  Future<String> downloadPack(String id, String savePath) async {
    final uri = Uri.parse('${_config.baseUrl}/packs/$id/download');
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      request.headers.set('Authorization', 'Bearer ${_config.apiKey}');
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Pack download failed with HTTP ${response.statusCode}',
        );
      }
      final file = File(savePath);
      await response.pipe(file.openWrite());
      return savePath;
    } finally {
      client.close(force: true);
    }
  }

  /// Stream an answer from backend AI Tutor
  Stream<String> streamTutorAnswer({
    required String question,
    int? grade,
    String? subject,
    String? chapter,
    String? language,
    String? context,
    List<String>? conversationHistory,
    String? sessionId,
    Map<String, dynamic>? experimentContext,
  }) async* {
    print('[DIAGNOSTICS] ENTERING BackendApiService.streamTutorAnswer()');
    print('[DIAGNOSTICS] REQUEST_START (BACKEND)');
    AppEnvironment.log('BACKEND', 'Starting streaming tutor answer request');

    final body = <String, dynamic>{
      'question': _sanitizeBackendText(question),
      'stream': true,
    };

    if (grade != null) body['grade'] = grade;
    if (subject != null && subject.isNotEmpty) {
      body['subject'] = _sanitizeBackendText(subject);
    }
    if (chapter != null && chapter.isNotEmpty) {
      body['chapter'] = _sanitizeBackendText(chapter);
    }
    if (language != null && language.isNotEmpty) {
      body['language'] = _sanitizeBackendText(language);
    }
    if (context != null && context.isNotEmpty) {
      body['context'] = _sanitizeBackendText(context);
    }
    if (conversationHistory != null && conversationHistory.isNotEmpty) {
      body['conversation_history'] = conversationHistory
          .where((line) => line.trim().isNotEmpty)
          .map(_sanitizeBackendText)
          .toList(growable: false);
    }
    if (sessionId != null && sessionId.isNotEmpty) {
      body['session_id'] = sessionId;
    }
    if (experimentContext != null && experimentContext.isNotEmpty) {
      body['experiment'] = experimentContext;
    }

    // Task E: Log exact request payload for 400 debugging
    print('[BACKEND] REQUEST_JSON=${body.keys.toList()}');
    final sanitizedQuestion = body['question'] as String;
    print(
      '[BACKEND] REQUEST_QUESTION=${sanitizedQuestion.substring(0, sanitizedQuestion.length > 100 ? 100 : sanitizedQuestion.length)}',
    );

    try {
      final startTime = DateTime.now();
      print('[DIAGNOSTICS] REQUEST_SENT (BACKEND)');
      var isFirstToken = true;
      var emittedText = '';
      await for (final chunk in _httpClient.stream('/ai/tutor', body: body)) {
        print("[TRACE] RAW_STREAM_CHUNK=$chunk");
        if (isFirstToken) {
          final firstTokenMs = DateTime.now()
              .difference(startTime)
              .inMilliseconds;
          print('[DIAGNOSTICS] BACKEND_NETWORK_MS=$firstTokenMs');
        }
        final trimmed = chunk.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) {
          continue;
        }

        if (trimmed.startsWith('data:')) {
          final jsonStr = trimmed.substring(5).trim();
          if (jsonStr == '[DONE]') {
            AppEnvironment.log('BACKEND', 'Tutor stream completed');
            break;
          }
          try {
            final data = jsonDecode(jsonStr) as Map<String, dynamic>;
            print("[TRACE] PARSED_JSON=$data");

            final isDone = data['done'] as bool? ?? false;
            final isCorrected = data['corrected'] as bool? ?? false;
            final isStarted = data['started'] as bool? ?? false;
            final isHeartbeat = data['heartbeat'] as bool? ?? false;

            if (isStarted || isHeartbeat) continue;

            final answerField =
                data['token'] as String? ??
                data['answer'] as String? ??
                data['chunk'] as String? ??
                '';
            print("[TRACE] ANSWER_FIELD=$answerField");

            if (isCorrected && answerField.isNotEmpty) {
              // Backend sent a full corrected replacement — signal reset then full text
              print('[TRACE] CORRECTION_RECEIVED len=${answerField.length}');
              yield '\x00RESET\x00';
              yield StreamingOutputNormalizer.clean(answerField);
              emittedText = answerField;
              break;
            }

            if (isDone && answerField.isEmpty) break;

            // Normal incremental token — stream directly
            if (answerField.isNotEmpty) {
              final cleaned = StreamingOutputNormalizer.clean(answerField);
              if (cleaned.isNotEmpty) {
                emittedText += cleaned;
                if (isFirstToken) {
                  print('[DIAGNOSTICS] BACKEND_FIRST_TOKEN');
                  final firstTokenTotal = DateTime.now()
                      .difference(startTime)
                      .inMilliseconds;
                  print('[DIAGNOSTICS] BACKEND_FIRST_TOKEN_MS=$firstTokenTotal');
                  isFirstToken = false;
                }
                print("[TRACE] EMIT_TO_HYBRID=$cleaned");
                print("[TRACE] EMIT_LENGTH=${cleaned.length}");
                yield cleaned;
              }
            }
          } catch (_) {
            continue;
          }
        } else {
          print("[TRACE] EMIT_TO_HYBRID=$trimmed");
          print("[TRACE] EMIT_LENGTH=${trimmed.length}");
          yield trimmed;
        }
      }
      final totalMs = DateTime.now().difference(startTime).inMilliseconds;
      print('[DIAGNOSTICS] BACKEND_STREAM_COMPLETE');
      print('[DIAGNOSTICS] BACKEND_TOTAL_MS=$totalMs');
    } catch (error) {
      AppEnvironment.log('BACKEND', 'Tutor stream error: $error');
      rethrow;
    }
  }

  String _sanitizeBackendText(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (_isAllowedBackendRune(rune)) {
        buffer.writeCharCode(rune);
      } else {
        buffer.write(' ');
      }
    }

    final normalized = buffer
        .toString()
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.length <= 2400) {
      return normalized;
    }

    return normalized.substring(0, 2400).trimRight();
  }

  bool _isAllowedBackendRune(int rune) {
    if (rune == 0x09 || rune == 0x0A || rune == 0x0D || rune == 0x20) {
      return true;
    }
    if (rune >= 0x21 && rune <= 0x7E) {
      return true;
    }
    if (rune >= 0x0C80 && rune <= 0x0CFF) {
      return true;
    }
    return false;
  }

  /// Stream a planner lesson response
  Stream<String> streamPlannerLesson({
    required String topic,
    String? subject,
    int? grade,
    String? language,
  }) async* {
    if (!_config.isValid) {
      yield 'Backend not configured. Please check your settings.';
      return;
    }

    final body = <String, dynamic>{'topic': topic};

    if (subject != null) body['subject'] = subject;
    if (grade != null) body['grade'] = grade;
    if (language != null) body['language'] = language;

    print('[BACKEND] REQUEST_JSON (PLANNER)=${body.keys.toList()}');
    print('[BACKEND] REQUEST_TOPIC=$topic');

    try {
      final startTime = DateTime.now();
      var isFirstToken = true;
      await for (final chunk in _httpClient.stream(
        '/planner/lesson',
        body: body,
      )) {
        if (isFirstToken) {
          final firstTokenMs = DateTime.now()
              .difference(startTime)
              .inMilliseconds;
          print('[DIAGNOSTICS] PLANNER_NETWORK_MS=$firstTokenMs');
          isFirstToken = false;
        }
        final trimmed = chunk.trim();
        if (trimmed.isEmpty || trimmed.startsWith(':')) {
          continue;
        }

        if (trimmed.startsWith('data:')) {
          final jsonStr = trimmed.substring(5).trim();
          if (jsonStr == '[DONE]') {
            break;
          }
          try {
            final data = jsonDecode(jsonStr);
            if (data is Map<String, dynamic> && data.containsKey('chunk')) {
              yield data['chunk'].toString();
            }
          } catch (_) {
            yield jsonStr;
          }
        }
      }
    } catch (e) {
      print('[BACKEND] Error streaming planner lesson: $e');
      yield 'Connection to planner lost. Please try again.';
    }
  }

  /// Close the backend service
  void close() {
    _httpClient.close();
  }
}
