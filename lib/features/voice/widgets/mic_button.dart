import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../simulation_context/providers/simulation_context_provider.dart';
import '../models/voice_state.dart';
import '../providers/voice_provider.dart';

/// Large circular microphone button with animated state feedback.
///
/// - **idle**: static mic icon
/// - **listening**: pulsing red ring
/// - **processing**: spinning indicator
/// - **speaking**: equalizer-style animation
class MicButton extends ConsumerWidget {
  const MicButton({
    super.key,
    this.languageCode = 'en',
  });

  final String languageCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final voice = ref.watch(voiceProvider);
    final notifier = ref.read(voiceProvider.notifier);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _handleTap(voice.state, notifier, ref, languageCode),
      child: _AnimatedMic(state: voice.state, theme: theme),
    );
  }

  void _handleTap(VoiceState state, VoiceNotifier notifier, WidgetRef ref, String languageCode) {
    switch (state) {
      case VoiceState.idle:
        notifier.startRecording(languageCode: languageCode);
        break;
      case VoiceState.listening:
        final ctx = ref.read(simulationContextProvider);
        notifier.stopRecording(context: ctx.hasContext ? ctx.toJson() : null);
        break;
      case VoiceState.speaking:
        notifier.stopPlayback();
        break;
      case VoiceState.processing:
      case VoiceState.error:
        break;
    }
  }
}

class _AnimatedMic extends StatefulWidget {
  const _AnimatedMic({required this.state, required this.theme});

  final VoiceState state;
  final ThemeData theme;

  @override
  State<_AnimatedMic> createState() => _AnimatedMicState();
}

class _AnimatedMicState extends State<_AnimatedMic>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulse = Tween(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(_AnimatedMic old) {
    super.didUpdateWidget(old);
    if (widget.state == VoiceState.listening) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isRecording = widget.state == VoiceState.listening;
    final isProcessing = widget.state == VoiceState.processing;
    final color = isRecording
        ? Colors.red
        : widget.state == VoiceState.error
            ? Colors.orange
            : widget.theme.colorScheme.primary;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        return Transform.scale(
          scale: isRecording ? _pulse.value : 1.0,
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                if (isRecording)
                  BoxShadow(
                    color: Colors.red.withAlpha(80),
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
              ],
            ),
            child: isProcessing
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  )
                : Icon(
                    isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    color: Colors.white,
                    size: 36,
                  ),
          ),
        );
      },
    );
  }
}
