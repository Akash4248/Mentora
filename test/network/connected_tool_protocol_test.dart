import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/chat/domain/default_capabilities.dart';
import 'package:mentora/features/chat/domain/tutor_stream_event.dart';
import 'package:mentora/features/network/data/backend_availability_cache.dart';
import 'package:mentora/features/network/services/mentora_backend_client.dart';

class _MockHttpAdapter implements HttpClientAdapter {
  _MockHttpAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) => handler(options);

  @override
  void close({bool force = false}) {}
}

void main() {
  group('Connected Tool Protocol', () {
    setUp(() {
      BackendAvailabilityCache().updateStatus(true, url: 'http://test-gateway:8000');
    });

    test('serializes tools into POST /ai/tutor payload correctly', () async {
      RequestOptions? capturedOptions;

      final mockDio = Dio(BaseOptions(baseUrl: 'http://test-gateway:8000'));
      mockDio.httpClientAdapter = _MockHttpAdapter((options) async {
        capturedOptions = options;
        const sse = 'data: {"chunk": "ok"}\n\ndata: [DONE]\n\n';
        return ResponseBody.fromString(
          sse,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/event-stream'],
          },
        );
      });

      final client = MentoraBackendClient(dioClient: mockDio);
      final calcTool = DefaultCapabilities.calculate().tool;

      final events = await client.streamAiTutor(
        question: 'Calculate 2+2',
        topic: 'Math',
        grade: 9,
        tools: [calcTool],
      ).toList();

      expect(capturedOptions, isNotNull);
      expect(capturedOptions!.path, '/ai/tutor');

      final data = capturedOptions!.data as Map<String, dynamic>;
      expect(data['question'], 'Calculate 2+2');
      expect(data['topic'], 'Math');
      expect(data['grade'], 9);
      expect(data['stream'], isTrue);

      final toolsJson = data['tools'] as List<dynamic>;
      expect(toolsJson.length, 1);
      final firstTool = toolsJson.first as Map<String, dynamic>;
      expect(firstTool['name'], 'calculate');
      expect(firstTool['description'], contains('calculates'));
      expect(firstTool['parameters'], isA<Map<String, dynamic>>());

      expect(events.whereType<TutorStreamChunkEvent>().single.chunk, 'ok');
    });

    test('parses SSE tool_call payload into TutorStreamToolCallEvent', () async {
      final mockDio = Dio(BaseOptions(baseUrl: 'http://test-gateway:8000'));
      mockDio.httpClientAdapter = _MockHttpAdapter((options) async {
        const sse = '''
data: {"started": true}

data: {"tool_call": {"id": "call_pi_1", "name": "calculate", "arguments": {"expression": "9.8 * 2"}}}

data: [DONE]
''';
        return ResponseBody.fromString(
          sse,
          200,
          headers: {
            Headers.contentTypeHeader: ['text/event-stream'],
          },
        );
      });

      final client = MentoraBackendClient(dioClient: mockDio);
      final calcTool = DefaultCapabilities.calculate().tool;

      final events = await client.streamAiTutor(
        question: 'What is g * 2?',
        topic: 'Physics',
        grade: 9,
        tools: [calcTool],
      ).toList();

      final toolCalls = events.whereType<TutorStreamToolCallEvent>().toList();
      expect(toolCalls.length, 1);
      final call = toolCalls.single;
      expect(call.id, 'call_pi_1');
      expect(call.name, 'calculate');
      expect(call.arguments, {'expression': '9.8 * 2'});
    });
  });
}
