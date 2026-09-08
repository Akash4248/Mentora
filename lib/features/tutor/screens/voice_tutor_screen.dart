import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:offline_tutor_app/l10n/app_localizations.dart';

import '../../language/providers/language_provider.dart';
import '../../language/widgets/language_selector.dart';
import '../../voice/providers/voice_provider.dart';
import '../../voice/widgets/mic_button.dart';
import '../../voice/widgets/tutor_avatar.dart';
import '../../voice/widgets/voice_status_chip.dart';
import '../../language/services/language_interceptor.dart';
import '../../voice/providers/voice_connection_provider.dart';
import '../providers/conversation_provider.dart';
import '../widgets/connection_status_bar.dart';
import '../widgets/conversation_bubble.dart';
import '../widgets/developer_overlay.dart';
import '../widgets/voice_quality_dashboard.dart';

/// Full-featured voice tutor screen (F5).
///
/// Layout (top to bottom):
/// 1. Language Selector
/// 2. Connection Status Bar
/// 3. Tutor Avatar
/// 4. Conversation History (ListView.builder)
/// 5. Mic Button
/// 6. Bottom Status (voice state chip)
class VoiceTutorScreen extends ConsumerStatefulWidget {
  VoiceTutorScreen({
    super.key,
    LanguageProvider? languageProvider,
  }) : languageProvider = languageProvider ?? LanguageProvider.shared;

  final LanguageProvider languageProvider;

  @override
  ConsumerState<VoiceTutorScreen> createState() => _VoiceTutorScreenState();
}

class _VoiceTutorScreenState extends ConsumerState<VoiceTutorScreen> {
  bool _devMode = false;
  final _scrollController = ScrollController();
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final voiceConn = ref.read(voiceConnectionProvider.notifier);
        voiceConn.socket.interceptor ??=
            LanguageInterceptor(widget.languageProvider);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: widget.languageProvider,
      builder: (context, _) {
        final voice = ref.watch(voiceProvider);
        final conv = ref.watch(conversationProvider);

        // Auto-scroll only when new messages arrive
        if (conv.messages.length > _lastMessageCount) {
          _lastMessageCount = conv.messages.length;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.voiceTutorTitle),
            actions: [
              IconButton(
                icon: Icon(_devMode ? Icons.code_off : Icons.code),
                onPressed: () => setState(() => _devMode = !_devMode),
                tooltip: l10n.developerMode,
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                // 1. Connection Status
                const ConnectionStatusBar(),

                // 2. Language Selector (compact)
                ExpansionTile(
                  title: Text(
                    '${l10n.languageLabel}: ${widget.languageProvider.currentLanguage.nativeName}',
                    style: const TextStyle(fontSize: 14),
                  ),
                  dense: true,
                  children: [
                    LanguageSelector(languageProvider: widget.languageProvider),
                  ],
                ),

                // 3. Developer overlay & Quality Dashboard
                DeveloperOverlay(visible: _devMode),
                if (_devMode) const VoiceQualityDashboard(),

                // 4. Tutor Avatar
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: TutorAvatar(
                    state: conv.state,
                    size: 100,
                  ),
                ),

                // 5. Partial transcript
                if (conv.partialTranscript.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      conv.partialTranscript,
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),

                // 6. Conversation History
                Expanded(
                  child: conv.messages.isEmpty
                      ? Center(
                    child: Text(
                            l10n.tapMicToStartTalking,
                            style: TextStyle(color: Colors.grey.shade400),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          itemCount: conv.messages.length,
                          itemBuilder: (context, index) {
                            return ConversationBubble(
                              message: conv.messages[index],
                            );
                          },
                        ),
                ),

                // 7. Mic + Status
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      MicButton(languageCode: widget.languageProvider.languageCode),
                      const SizedBox(height: 8),
                      VoiceStatusChip(state: voice.state),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

}
