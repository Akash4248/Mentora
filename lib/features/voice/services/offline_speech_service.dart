import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../chat/application/mentora_agent_session.dart';
import '../../chat/application/mentora_tutor_agent_provider.dart';

class OfflineVoiceResult {
  const OfflineVoiceResult({required this.transcript, required this.answer});

  final String transcript;
  final String answer;
}

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

  /// Transcribes a voice query and answers it through the same tutor agent
  /// used by text chat. Text-to-speech is deliberately left to the caller so
  /// only the final assistant answer is spoken.
  Future<OfflineVoiceResult> processOfflineVoiceQuery({
    required String wavPath,
    required String chapterTitle,
    required int grade,
    String languageCode = 'en',
  }) async {
    final userQuery = await transcribeAudioFile(
      wavPath,
      languageCode: languageCode,
    );
    final question = userQuery.isNotEmpty
        ? userQuery
        : 'Explain $chapterTitle for Grade $grade student.';

    final session = MentoraTutorAgentProvider().createSession(
      topic: chapterTitle,
      grade: grade,
    );

    final buffer = StringBuffer();
    var completedAnswer = '';

    try {
      await for (final event in session.runTurn(question)) {
        switch (event) {
          case TutorTextDeltaEvent(:final delta):
            buffer.write(delta);
          case TutorTurnCompletedEvent(:final text):
            completedAnswer = text;
          case TutorTurnFailedEvent(:final message):
            completedAnswer = '⚠️ $message';
          case TutorTurnAbortedEvent():
            completedAnswer = 'Response cancelled.';
          case TutorToolStatusEvent():
            break;
        }
      }
    } finally {
      await session.dispose();
    }

    var answer = completedAnswer.trim();
    if (answer.isEmpty) {
      answer = buffer.toString().trim();
    }
    if (answer.isEmpty) {
      answer = 'I could not generate an answer. Please try again.';
    }

    return OfflineVoiceResult(transcript: userQuery, answer: answer);
  }
}
