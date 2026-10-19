import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mentora/l10n/app_localizations.dart';

import '../../language/providers/language_provider.dart';
import '../../tutor/models/conversation_state.dart';
import '../models/voice_state.dart';
import '../providers/voice_provider.dart';
import '../services/audio_recorder_service.dart';
import '../services/offline_speech_service.dart';
import '../widgets/mic_button.dart';
import '../widgets/recording_waveform.dart';
import '../widgets/tutor_avatar.dart';
import '../widgets/voice_status_chip.dart';

/// Debug screen for validating the voice pipeline.
///
/// Workflow: Press Mic → Record → Stop → Playback.
/// Validates: permission, recording, playback, no crashes.
class VoiceDebugScreen extends ConsumerStatefulWidget {
  const VoiceDebugScreen({super.key});

  @override
  ConsumerState<VoiceDebugScreen> createState() => _VoiceDebugScreenState();
}

class _VoiceDebugScreenState extends ConsumerState<VoiceDebugScreen> {
  final _recorder = AudioRecorderService();
  final _speech = OfflineSpeechService();
  bool _isTestingTts = false;

  @override
  void dispose() {
    unawaited(_speech.stopSpeaking());
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _testTts() async {
    final languageCode = LanguageProvider.shared.languageCode;
    final sample = languageCode == 'kn'
        ? 'ನಮಸ್ಕಾರ! ಇದು ಮೆಂಟೋರಾ ಆಫ್‌ಲೈನ್ ಧ್ವನಿ ಪರೀಕ್ಷೆ.'
        : 'Hello! This is Mentora speaking offline.';

    setState(() => _isTestingTts = true);
    final available = await _speech.isLanguageAvailable(languageCode);
    if (!mounted) return;
    if (!available) {
      setState(() => _isTestingTts = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Native TTS unavailable for $languageCode')),
      );
      return;
    }

    final completed = await _speech.speakText(
      sample,
      languageCode: languageCode,
    );
    if (!mounted) return;
    setState(() => _isTestingTts = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          completed
              ? 'Native TTS completed ($languageCode)'
              : 'Native TTS stopped ($languageCode)',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final voice = ref.watch(voiceProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.voiceDebugTitle),
        actions: [
          IconButton(
            icon: _isTestingTts
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.volume_up_rounded),
            onPressed: _isTestingTts ? null : _testTts,
            tooltip: 'Test native TTS',
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: () => _speech.stopSpeaking(),
            tooltip: 'Stop native TTS',
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(voiceProvider.notifier).reset(),
            tooltip: l10n.reset,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 24),

              // ─ Avatar ─
              TutorAvatar(
                state: voice.state == VoiceState.listening
                    ? ConversationState.listening
                    : voice.state == VoiceState.speaking
                    ? ConversationState.speaking
                    : voice.state == VoiceState.processing
                    ? ConversationState.uploading
                    : ConversationState.idle,
                size: 140,
              ),
              const SizedBox(height: 24),

              // ─ Status ─
              VoiceStatusChip(state: voice.state),
              const SizedBox(height: 16),

              // ─ Waveform ─
              RecordingWaveform(
                recorder: _recorder,
                isRecording: voice.state == VoiceState.listening,
              ),
              const SizedBox(height: 24),

              // ─ Info cards ─
              _InfoTile(
                label: l10n.permissionLabel,
                value: voice.hasPermission ? l10n.granted : l10n.notGranted,
                icon: voice.hasPermission ? Icons.check_circle : Icons.block,
                color: voice.hasPermission ? Colors.green : Colors.red,
              ),
              _InfoTile(
                label: l10n.recordingLabel,
                value: voice.currentRecording ?? '—',
                icon: Icons.audio_file_rounded,
                color: theme.colorScheme.primary,
              ),
              _InfoTile(
                label: l10n.durationLabel,
                value: _formatDuration(voice.recordingDuration),
                icon: Icons.timer_rounded,
                color: theme.colorScheme.secondary,
              ),
              _InfoTile(
                label: l10n.playingLabel,
                value: voice.isPlaying ? l10n.yes : l10n.no,
                icon: Icons.play_arrow_rounded,
                color: voice.isPlaying ? Colors.green : Colors.grey,
              ),

              const Spacer(),

              // ─ Playback button ─
              if (voice.currentRecording != null &&
                  voice.state == VoiceState.idle)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(l10n.playRecording),
                    onPressed: () =>
                        ref.read(voiceProvider.notifier).playRecording(),
                  ),
                ),

              // ─ Mic ─
              const MicButton(languageCode: 'en'),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final tenths = (d.inMilliseconds.remainder(1000) ~/ 100).toString();
    return '$mins:$secs.$tenths';
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
