import 'package:flutter/material.dart';
import '../../../../core/theme/idp_colors.dart';
import '../../../../core/theme/idp_theme.dart';
import '../../../tutor/screens/voice_tutor_screen.dart';

class ChatInputBar extends StatelessWidget {
  const ChatInputBar({
    super.key,
    required this.controller,
    required this.onSend,
    this.isGenerating = false,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool isGenerating;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(IDPSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(
            color: IDPColors.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.mic_rounded, color: IDPColors.primary),
              tooltip: 'Voice Tutor Mode',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VoiceTutorScreen(),
                  ),
                );
              },
            ),
            const SizedBox(width: IDPSpacing.xs),
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !isGenerating,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Ask your Socratic AI Tutor a question...',
                  filled: true,
                  fillColor: IDPColors.surfaceVariant.withValues(alpha: 0.4),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: IDPSpacing.md,
                    vertical: IDPSpacing.sm,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(IDPRadius.full),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: IDPSpacing.xs),
            IconButton(
              icon: isGenerating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: IDPColors.primary,
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: IDPColors.primary),
              tooltip: 'Send Question',
              onPressed: isGenerating ? null : onSend,
            ),
          ],
        ),
      ),
    );
  }
}
