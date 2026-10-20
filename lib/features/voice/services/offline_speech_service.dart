import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../chat/data/platform_tutor_inference_gateway.dart';

/// On-Device Offline Speech-To-Text & Text-To-Speech engine.
///
/// Functions 100% offline without requiring connection to external servers.
class OfflineSpeechService {
  static final OfflineSpeechService _instance =
      OfflineSpeechService._internal();
  factory OfflineSpeechService() => _instance;
  OfflineSpeechService._internal();

  static const MethodChannel _ttsChannel = MethodChannel('mentora/tts');
  static const MethodChannel _sttChannel = MethodChannel('mentora/stt');
  final PlatformTutorInferenceGateway _llmGateway =
      PlatformTutorInferenceGateway();

  bool _isSpeaking = false;
  bool get isSpeaking => _isSpeaking;

  /// Transcribe audio from recorded WAV file using native STT engine.
  Future<String> transcribeAudioFile(
    String wavPath, {
    String languageCode = 'en',
  }) async {
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
        final result = await _sttChannel.invokeMethod<String>('transcribe', {
          'wavPath': wavPath,
          'language': languageCode,
        });
        if (result != null && result.isNotEmpty) {
          return result;
        }
      } on PlatformException catch (e) {
        debugPrint('[OFFLINE_SPEECH] STT failed: ${e.code} ${e.message}');
      } on MissingPluginException {
        debugPrint('[OFFLINE_SPEECH] Native STT channel is not available.');
      } catch (e) {
        debugPrint('[OFFLINE_SPEECH] STT execution error: $e');
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// Whether ML Kit on-device speech recognition can run for [languageCode].
  Future<bool> isSttAvailable({String languageCode = 'en'}) async {
    try {
      final result = await _sttChannel.invokeMethod<bool>('isAvailable', {
        'language': languageCode,
      });
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Speak AI Tutor response text using native on-device TTS engine.
  ///
  /// Returns `true` when the utterance finished playing, `false` when the
  /// platform has no voice for [languageCode] or speech was cancelled/failed.
  Future<bool> speakText(String text, {String languageCode = 'en'}) async {
    final speechText = _prepareSpeechText(text);
    if (speechText.isEmpty) return false;

    _isSpeaking = true;
    try {
      final result = await _ttsChannel.invokeMethod<bool>('speak', {
        'text': speechText,
        'language': languageCode,
      });
      return result ?? true;
    } on MissingPluginException {
      // Fallback log for platform channel
      debugPrint(
        '[OFFLINE_SPEECH] Native TTS MethodChannel missing fallback: "$speechText"',
      );
      return false;
    } catch (e) {
      debugPrint('[OFFLINE_SPEECH] TTS execution error: $e');
      return false;
    } finally {
      _isSpeaking = false;
    }
  }

  /// Whether the platform TTS engine has an offline voice for [languageCode].
  Future<bool> isLanguageAvailable(String languageCode) async {
    try {
      final result = await _ttsChannel.invokeMethod<bool>(
        'isLanguageAvailable',
        {'language': languageCode},
      );
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Strips lightweight markdown so the voice does not read symbols aloud.
  String _prepareSpeechText(String text) {
    return text
        .replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\([^)]+\)'),
          (match) => match.group(1) ?? '',
        )
        .replaceAll(RegExp(r'[*_#`>]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
    final userQuery = await transcribeAudioFile(
      wavPath,
      languageCode: languageCode,
    );
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
