import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/idp_colors.dart';
import '../../../../core/theme/idp_typography.dart';
import '../../../../core/theme/idp_theme.dart';
import '../../domain/tutor_message.dart';
import '../formatted_text_widget.dart';

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    this.isGenerating = false,
  });

  final List<TutorMessage> messages;
  final ScrollController scrollController;
  final bool isGenerating;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 48,
              color: IDPColors.onSurfaceVariant,
            ),
            const SizedBox(height: IDPSpacing.sm),
            Text(
              'Start asking your Mentora Socratic AI Tutor!',
              style: IDPTypography.bodyMedium.copyWith(
                color: IDPColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.all(IDPSpacing.md),
      itemCount: messages.length + (isGenerating ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: IDPSpacing.sm),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: IDPColors.primary,
                  ),
                ),
                const SizedBox(width: IDPSpacing.xs),
                Text(
                  'Mentora is thinking & reasoning...',
                  style: IDPTypography.caption.copyWith(
                    color: IDPColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        final message = messages[index];
        return _buildMessageBubble(context, message);
      },
    );
  }

  Widget _buildMessageBubble(BuildContext context, TutorMessage message) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: IDPSpacing.xs),
        padding: const EdgeInsets.all(IDPSpacing.md),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        decoration: BoxDecoration(
          color: isUser ? IDPColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(IDPRadius.lg),
          border: isUser
              ? null
              : Border.all(
                  color: IDPColors.outlineVariant.withValues(alpha: 0.5),
                ),
          boxShadow: isUser
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ],
        ),
        child: Column(
          crossAxisAlignment:
              isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            FormattedTextWidget(
              text: message.text,
              style: IDPTypography.bodyMd.copyWith(
                color: isUser ? Colors.white : IDPColors.onSurface,
              ),
            ),
            const SizedBox(height: IDPSpacing.xs / 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(message.timestamp),
                  style: IDPTypography.caption.copyWith(
                    color: isUser
                        ? Colors.white.withValues(alpha: 0.7)
                        : IDPColors.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
                if (!isUser) ...[
                  const SizedBox(width: IDPSpacing.xs),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: message.text));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Message copied to clipboard.'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.copy_rounded,
                      size: 14,
                      color: IDPColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$hour:$min';
  }
}
