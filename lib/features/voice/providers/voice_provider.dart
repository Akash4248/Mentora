import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/voice_state.dart';
import '../models/voice_event.dart';
import '../models/connection_status.dart';
import '../services/audio_player_service.dart';
import '../services/audio_recorder_service.dart';
import '../services/voice_permission_service.dart';
import '../services/voice_stream_player.dart';
import '../services/offline_speech_service.dart';
import 'voice_connection_provider.dart';

// ─── State ──────────────────────────────────────────────────────────

class VoiceProviderState {
  const VoiceProviderState({
    this.state = VoiceState.idle,
    this.hasPermission = false,
    this.currentRecording,
    this.recordingDuration = Duration.zero,
    this.isPlaying = false,
  });

  final VoiceState state;
  final bool hasPermission;
  final String? currentRecording;
  final Duration recordingDuration;
  final bool isPlaying;

  VoiceProviderState copyWith({
    VoiceState? state,
    bool? hasPermission,
    String? currentRecording,
    Duration? recordingDuration,
    bool? isPlaying,
    bool clearRecording = false,
  }) {
    return VoiceProviderState(
      state: state ?? this.state,
      hasPermission: hasPermission ?? this.hasPermission,
      currentRecording: clearRecording ? null : (currentRecording ?? this.currentRecording),
      recordingDuration: recordingDuration ?? this.recordingDuration,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }
}

// ─── Notifier ───────────────────────────────────────────────────────

class VoiceNotifier extends StateNotifier<VoiceProviderState> {
  VoiceNotifier(
    this.ref, {
    VoicePermissionService? permissionService,
    AudioRecorderService? recorderService,
    AudioPlayerService? playerService,
  })  : _permissions = permissionService ?? VoicePermissionService(),
        _recorder = recorderService ?? AudioRecorderService(),
        _player = playerService ?? AudioPlayerService(),
        _streamPlayer = VoiceStreamPlayer(),
        super(const VoiceProviderState()) {
    _streamPlayer.onComplete = () {
      if (mounted && state.state == VoiceState.speaking) {
        state = state.copyWith(state: VoiceState.idle, isPlaying: false);
      }
    };
    _listenToPlayback();
    _listenToSocketEvents();
  }

  final Ref ref;
  final VoicePermissionService _permissions;
  final AudioRecorderService _recorder;
  final AudioPlayerService _player;
  final VoiceStreamPlayer _streamPlayer;
  String _languageCode = 'en';

  Timer? _durationTimer;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<VoiceEvent>? _socketEventSub;

  // ─── Public API ─────────────────────────────────────────────────

  /// Request mic permission and start recording.
  Future<void> startRecording({String languageCode = 'en'}) async {
    _languageCode = languageCode;
    final granted = await _permissions.requestMicrophonePermission();
    if (!granted) {
      state = state.copyWith(hasPermission: false, state: VoiceState.error);
      return;
    }
    state = state.copyWith(hasPermission: true);

    try {
      // Interrupt any playing response
      await _streamPlayer.interrupt();
      
      await _recorder.startRecording();
      final conn = ref.read(voiceConnectionProvider.notifier);
      conn.socket.sendSessionStart(_languageCode);
      state = state.copyWith(
        state: VoiceState.listening,
        recordingDuration: Duration.zero,
      );
      _startDurationTimer();
    } catch (_) {
      state = state.copyWith(state: VoiceState.error);
    }
  }

  /// Stop recording, send to server, or process fully offline.
  Future<void> stopRecording({Map<String, dynamic>? context}) async {
    _stopDurationTimer();
    try {
      final path = await _recorder.stopRecording();
      state = state.copyWith(
        state: VoiceState.processing,
        currentRecording: path,
      );
      
      if (path != null) {
        final conn = ref.read(voiceConnectionProvider.notifier);
        if (conn.socket.status == ConnectionStatus.connected) {
          final bytes = await File(path).readAsBytes();
          conn.socket.sendAudioChunk(bytes, 1);
          conn.socket.sendAudioComplete(
            _languageCode,
            context: context,
          );
        } else {
          // Offline Fallback: STT -> GGUF LLM -> TTS
          final chapter = context?['chapter']?.toString() ?? 'Science';
          final grade = (context?['grade'] as num?)?.toInt() ?? 9;

          final answer = await OfflineSpeechService().processOfflineVoiceQuery(
            wavPath: path,
            chapterTitle: chapter,
            grade: grade,
            languageCode: _languageCode,
          );

          if (mounted) {
            state = state.copyWith(
              state: VoiceState.speaking,
              isPlaying: true,
            );
          }
        }
      }
    } catch (_) {
      state = state.copyWith(state: VoiceState.error);
    }
  }

  /// Play the last recording (for debugging).
  Future<void> playRecording() async {
    final path = state.currentRecording;
    if (path == null) return;
    try {
      state = state.copyWith(state: VoiceState.speaking);
      await _player.play(path);
    } catch (_) {
      state = state.copyWith(state: VoiceState.error);
    }
  }

  /// Stop playback.
  Future<void> stopPlayback() async {
    try {
      await _streamPlayer.interrupt();
      await _player.stop();
      state = state.copyWith(state: VoiceState.idle, isPlaying: false);
    } catch (_) {
      state = state.copyWith(state: VoiceState.error);
    }
  }

  /// Reset to initial state.
  Future<void> reset() async {
    _stopDurationTimer();
    try {
      if (await _recorder.isRecording()) {
        await _recorder.cancelRecording();
      }
      await _streamPlayer.interrupt();
      await _player.stop();
    } catch (_) {
      // Best-effort cleanup.
    }
    _languageCode = 'en';
    state = const VoiceProviderState();
  }

  // ─── Audio streaming (called by ConversationNotifier) ───────────

  /// Queue a base64-encoded TTS audio chunk for immediate playback.
  /// ConversationNotifier delegates here so there is only one stream player.
  Future<void> queueAudioChunk(String base64Chunk) async {
    if (state.state != VoiceState.speaking) {
      state = state.copyWith(state: VoiceState.speaking, isPlaying: true);
    }
    await _streamPlayer.queueAudioChunk(base64Chunk);
  }

  /// Signal that the last TTS chunk has been received.
  void markAudioComplete() {
    _streamPlayer.markComplete();
  }

  // ─── Internal ───────────────────────────────────────────────────

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      state = state.copyWith(
        recordingDuration: state.recordingDuration + const Duration(milliseconds: 100),
      );
    });
  }

  void _stopDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = null;
  }

  void _listenToPlayback() {
    _playingSub = _player.isPlayingStream.listen((playing) {
      // Only for local playback debugger. Streaming sets speaking state manually.
      if (state.state == VoiceState.speaking && playing) return;
      if (!playing && state.state == VoiceState.speaking) {
        state = state.copyWith(state: VoiceState.idle, isPlaying: false);
      }
    });
  }

  void _listenToSocketEvents() {
    // Delay subscription to allow connection provider to initialize
    Future.microtask(() {
      final conn = ref.read(voiceConnectionProvider.notifier);
      _socketEventSub = conn.socket.eventStream.listen((event) {
        if (event.type == VoiceEventType.transcribing) {
          state = state.copyWith(state: VoiceState.processing);
        } else if (event.type == VoiceEventType.thinking) {
          state = state.copyWith(state: VoiceState.processing);
        } else if (event.type == VoiceEventType.generatingAudio) {
          state = state.copyWith(state: VoiceState.processing);
        } else if (event.type == VoiceEventType.audioChunk) {
          if (state.state != VoiceState.speaking) {
            state = state.copyWith(state: VoiceState.speaking, isPlaying: true);
          }
          final b64 = event.data;
          if (b64 != null) {
            _streamPlayer.queueAudioChunk(b64);
          }
        } else if (event.type == VoiceEventType.audioComplete) {
          _streamPlayer.markComplete();
          // We don't immediately set idle because it's still playing
        } else if (event.type == VoiceEventType.error) {
          state = state.copyWith(state: VoiceState.error);
        }
      });
    });
  }

  @override
  void dispose() {
    _stopDurationTimer();
    _playingSub?.cancel();
    _socketEventSub?.cancel();
    _recorder.dispose();
    _player.dispose();
    _streamPlayer.dispose();
    super.dispose();
  }
}

// ─── Provider ───────────────────────────────────────────────────────

final voiceProvider =
    StateNotifierProvider<VoiceNotifier, VoiceProviderState>((ref) {
  return VoiceNotifier(ref);
});
