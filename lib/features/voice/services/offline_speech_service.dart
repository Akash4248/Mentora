import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../../chat/data/platform_tutor_inference_gateway.dart';

/// On-Device Offline Speech-To-Text & Text-To-Speech engine.
///
/// Functions 100% offline without requiring connection to external servers.
class OfflineSpeechService {
  static final OfflineSpeechService _instance = OfflineSpeechService._internal();
  factory OfflineSpeechService() => _instance;
  OfflineSpeechService._internal();

  static const MethodChannel _ttsChannel = MethodChannel('offline_tutor_app/tts');
  final PlatformTutorInferenceGateway _llmGateway = PlatformTutorInferenceGateway();

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  /// Transcribe audio from recorded WAV file using native STT engine.
  Future<String> transcribeAudioFile(String wavPath, {String languageCode = 'en'}) async {
    final file = File(wavPath);
    if (!await file.exists()) {
      return '';
    }

    try {
      final size = await file.length();
      if (size < 100) {
        return '';
      }
      try {
        final result = await _ttsChannel.invokeMethod<String>('transcribe', {
          'wavPath': wavPath,
          'language': languageCode,
        });
        if (result != null && result.isNotEmpty) {
          return result;
        }
      } catch (_) {}
      return '';
    } catch (_) {
      return '';
    }
  }

  /// Speak AI Tutor response text using native on-device TTS engine.
  Future<void> speakText(String text, {String languageCode = 'en'}) async {
    if (text.trim().isEmpty) return;

    _isSpeaking = true;
    try {
      await _ttsChannel.invokeMethod('speak', {
        'text': text,
        'language': languageCode,
      });
    } on MissingPluginException {
      // Fallback log for platform channel
      print('[OFFLINE_SPEECH] Native TTS MethodChannel missing fallback: "$text"');
    } catch (e) {
      print('[OFFLINE_SPEECH] TTS execution error: $e');
    } finally {
      _isSpeaking = false;
    }
  }

  /// Stop current TTS playback.
  Future<void> stopSpeaking() async {
    _isSpeaking = false;
    try {
      await _ttsChannel.invokeMethod('stop');
    } catch (_) {}
  }

  /// Process voice query fully offline: STT -> GGUF LLM -> TTS
  Future<String> processOfflineVoiceQuery({
    required String wavPath,
    required String chapterTitle,
    required int grade,
    String languageCode = 'en',
  }) async {
    final userQuery = await transcribeAudioFile(wavPath, languageCode: languageCode);
    final prompt = userQuery.isNotEmpty
        ? userQuery
        : 'Explain $chapterTitle for Grade $grade student.';

    final stream = _llmGateway.streamResponse(
      prompt: 'Topic: $chapterTitle\nQuestion: $prompt',
    );

    final buffer = StringBuffer();
    await for (final chunk in stream) {
      buffer.write(chunk);
    }

    final cleanAnswer = buffer.toString().trim();
    if (cleanAnswer.isNotEmpty) {
      unawaited(speakText(cleanAnswer, languageCode: languageCode));
    }
    return cleanAnswer;
  }
}
