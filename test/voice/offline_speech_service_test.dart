import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/voice/services/offline_speech_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('mentora/tts');
  const sttChannel = MethodChannel('mentora/stt');
  late List<MethodCall> calls;
  late List<MethodCall> sttCalls;

  setUp(() {
    calls = [];
    sttCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'speak':
              return true;
            case 'isLanguageAvailable':
              return true;
            case 'stop':
              return null;
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sttChannel, (call) async {
          sttCalls.add(call);
          switch (call.method) {
            case 'transcribe':
              return 'hello from stt';
            case 'isAvailable':
              return true;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sttChannel, null);
  });

  group('OfflineSpeechService TTS', () {
    test('speaks cleaned text with the requested language', () async {
      final completed = await OfflineSpeechService().speakText(
        '**Hello** [world](https://example.com)',
        languageCode: 'kn',
      );

      expect(completed, isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'speak');
      expect(calls.single.arguments, {'text': 'Hello world', 'language': 'kn'});
    });

    test('returns false when the platform has no voice', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            throw PlatformException(
              code: 'TTS_LANGUAGE_UNAVAILABLE',
              message: 'No voice',
            );
          });

      final completed = await OfflineSpeechService().speakText(
        'ನಮಸ್ಕಾರ',
        languageCode: 'kn',
      );

      expect(completed, isFalse);
    });

    test('does not call the platform for empty text', () async {
      final completed = await OfflineSpeechService().speakText('  **  ');

      expect(completed, isFalse);
      expect(calls, isEmpty);
    });

    test('reports language availability', () async {
      expect(await OfflineSpeechService().isLanguageAvailable('en'), isTrue);
      expect(calls.single.method, 'isLanguageAvailable');
      expect(calls.single.arguments, {'language': 'en'});
    });

    test('stops playback through the native channel', () async {
      await OfflineSpeechService().stopSpeaking();

      expect(calls.single.method, 'stop');
    });
  });

  group('OfflineSpeechService STT', () {
    test('sends wav path and language to native speech recognition', () async {
      final dir = await Directory.systemTemp.createTemp('mentora_stt_');
      final file = File('${dir.path}/sample.wav');
      await file.writeAsBytes(List<int>.generate(256, (index) => index));

      final text = await OfflineSpeechService().transcribeAudioFile(
        file.path,
        languageCode: 'hi',
      );

      expect(text, 'hello from stt');
      expect(sttCalls, hasLength(1));
      expect(sttCalls.single.method, 'transcribe');
      expect(sttCalls.single.arguments, {
        'wavPath': file.path,
        'language': 'hi',
      });

      await dir.delete(recursive: true);
    });

    test('returns empty for a missing recording', () async {
      final text = await OfflineSpeechService().transcribeAudioFile(
        '/does/not/exist.wav',
      );

      expect(text, isEmpty);
      expect(sttCalls, isEmpty);
    });

    test('reports native speech recognition availability', () async {
      expect(
        await OfflineSpeechService().isSttAvailable(languageCode: 'en'),
        isTrue,
      );
      expect(sttCalls.single.method, 'isAvailable');
      expect(sttCalls.single.arguments, {'language': 'en'});
    });
  });
}
