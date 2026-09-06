import 'dart:io';
import 'dart:ui'; // For ImageFilter

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:video_player/video_player.dart';
import 'package:offline_tutor_app/core/theme/idp_theme.dart';
import 'package:offline_tutor_app/core/theme/idp_colors.dart';
import 'package:offline_tutor_app/core/theme/idp_typography.dart';

/// Screen to play educational videos with playback controls
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({
    required this.videoUrl,
    required this.title,
    this.subtitle,
    this.description,
    super.key,
  });

  final String videoUrl;
  final String title;
  final String? subtitle;
  final String? description;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  double _playbackSpeed = 1.0;
  String? _initError;

  bool get _isYouTube =>
      widget.videoUrl.contains('youtube.com') ||
      widget.videoUrl.contains('youtu.be') ||
      RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(widget.videoUrl.trim());

  String get _youtubeEmbedUrl {
    final uri = Uri.tryParse(widget.videoUrl);
    String? videoId;
    if (uri != null) {
      if (uri.queryParameters.containsKey('v')) {
        videoId = uri.queryParameters['v'];
      } else if (uri.host.contains('youtu.be') && uri.pathSegments.isNotEmpty) {
        videoId = uri.pathSegments.first;
      } else if (uri.pathSegments.contains('embed') && uri.pathSegments.isNotEmpty) {
        videoId = uri.pathSegments.last;
      }
    }

    if (videoId == null || videoId.isEmpty) {
      final trimmed = widget.videoUrl.trim();
      if (RegExp(r'^[a-zA-Z0-9_-]{11}$').hasMatch(trimmed)) {
        videoId = trimmed;
      }
    }

    if (videoId != null && videoId.isNotEmpty) {
      final String embedUrl = 'https://www.youtube.com/embed/$videoId?autoplay=1&playsinline=1&rel=0&modestbranding=1&enablejsapi=1&origin=https://www.youtube.com';
      print('[VIDEO_DEBUG] Raw URL/ID: "${widget.videoUrl}" -> Formatted YouTube Embed URL: "$embedUrl"');
      return embedUrl;
    }

    print('[VIDEO_DEBUG] Raw URL: "${widget.videoUrl}" -> Using direct URL');
    return widget.videoUrl;
  }

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    print('[VIDEO_DEBUG] Initializing VideoPlayerScreen for title: "${widget.title}", URL: "${widget.videoUrl}", isYouTube: $_isYouTube');
    try {
      if (_isYouTube) {
        print('[VIDEO_DEBUG] Configured YouTube embed target: $_youtubeEmbedUrl');
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
        }
        return;
      }

      if (widget.videoUrl.startsWith('http')) {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.videoUrl),
        );
      } else {
        final file = File(widget.videoUrl);
        if (!await file.exists()) {
          print('[VIDEO_DEBUG] Local video file not found at ${widget.videoUrl}');
          if (mounted) {
            setState(() {
              _initError =
                  'Local video file not found at ${widget.videoUrl}. Please download or import the video file.';
            });
          }
          return;
        }
        _controller = VideoPlayerController.file(file);
      }

      await _controller!.initialize();
      print('[VIDEO_DEBUG] Non-YouTube VideoPlayerController initialized successfully.');

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }

      _controller!.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
    } catch (e) {
      print('[VIDEO_DEBUG] Exception initializing video player: $e');
      if (mounted) {
        setState(() {
          _initError = 'Error loading video: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _changePlaybackSpeed(double speed) {
    _controller?.setPlaybackSpeed(speed);
    setState(() {
      _playbackSpeed = speed;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Speed: ${speed}x', style: IDPTypography.bodyMd.copyWith(color: IDPColors.onPrimary)),
        backgroundColor: IDPColors.primary,
        duration: const Duration(milliseconds: 500),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: IDPColors.background,
      extendBodyBehindAppBar: true, // For glassmorphic app bar
      body: Stack(
        children: [
          // Main Scrollable Content
          SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top padding for the fixed app bar
                SizedBox(height: MediaQuery.of(context).padding.top + 72),
                if (_initError != null)
                  _buildErrorState()
                else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.containerMargin),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeroHeader(),
                        const SizedBox(height: IDPSpacing.xl),
                        _buildVideoSection(),
                        const SizedBox(height: IDPSpacing.xxl),
                        _buildDetailsSection(),
                        const SizedBox(height: 120), // Bottom padding for FAB
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          // Fixed App Bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildAppBar(context),
          ),
          
          // Fixed FAB
          Positioned(
            bottom: IDPSpacing.xl,
            right: IDPSpacing.containerMargin,
            child: _buildAskAIFab(),
          ),
        ],
      ),
    );
  }

  Widget _buildAskAIFab() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: IDPColors.primary.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ]
      ),
      child: Material(
        color: IDPColors.primary,
        borderRadius: BorderRadius.circular(IDPRadius.pill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: const Text('AI Tutor: Coming soon'), backgroundColor: IDPColors.secondary),
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: IDPSpacing.lg, vertical: IDPSpacing.md),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.psychology_outlined, color: IDPColors.onPrimary),
                const SizedBox(width: IDPSpacing.md),
                Text('Ask AI about this video', style: IDPTypography.labelMd.copyWith(color: IDPColors.onPrimary)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: IDPTypography.displayLarge.copyWith(
            color: IDPColors.onBackground,
            letterSpacing: -0.02,
          ),
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: IDPSpacing.md),
          Text(
            widget.subtitle!,
            style: IDPTypography.bodyLarge.copyWith(color: IDPColors.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + IDPSpacing.md,
            bottom: IDPSpacing.md,
            left: IDPSpacing.containerMargin,
            right: IDPSpacing.containerMargin,
          ),
          decoration: BoxDecoration(
            color: IDPColors.surface.withValues(alpha: 0.8),
            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(IDPRadius.pill),
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(IDPSpacing.xs),
                        child: Icon(Icons.arrow_back, color: IDPColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(width: IDPSpacing.md),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OfflineTutor',
                        style: IDPTypography.headlineLgMobile.copyWith(color: IDPColors.primary),
                      ),
                      Row(
                        children: [
                          Text('Video Lesson', style: IDPTypography.caption.copyWith(color: IDPColors.onSurfaceVariant)),
                          const SizedBox(width: IDPSpacing.xs),
                          const Icon(Icons.chevron_right, size: 12, color: IDPColors.onSurfaceVariant),
                          const SizedBox(width: IDPSpacing.xs),
                          Text('Playing', style: IDPTypography.caption.copyWith(color: IDPColors.primary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.settings_outlined, color: IDPColors.onSurfaceVariant),
                  const SizedBox(width: IDPSpacing.md),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: IDPColors.primaryContainer, width: 2),
                    ),
                    child: const CircleAvatar(
                      backgroundColor: IDPColors.surfaceContainerHigh,
                      child: Icon(Icons.person, color: IDPColors.primary),
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: IDPColors.errorLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: IDPColors.error.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: IDPColors.error),
            const SizedBox(height: 16),
            Text(
              _initError!,
              style: IDPTypography.bodyLarge.copyWith(color: IDPColors.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: IDPColors.error,
                foregroundColor: IDPColors.onError,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Go Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSection() {
    return Container(
      decoration: BoxDecoration(
        color: IDPColors.surfaceContainer,
        borderRadius: BorderRadius.circular(IDPRadius.defaultRadius), // rounded-lg
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04), // shadow-sm
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
        border: Border.all(color: IDPColors.outlineVariant), // border-outline-variant
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          if (_isYouTube)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: InAppWebView(
                initialUrlRequest: URLRequest(
                  url: WebUri(_youtubeEmbedUrl),
                ),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  useWideViewPort: true,
                  loadWithOverviewMode: true,
                  supportZoom: false,
                  transparentBackground: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                  userAgent: 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
                ),
                onWebViewCreated: (controller) {
                  print('[VIDEO_DEBUG] WebView created for URL: ${widget.videoUrl}');
                },
                onLoadStart: (controller, url) {
                  print('[VIDEO_DEBUG] WebView load started: $url');
                },
                onLoadStop: (controller, url) {
                  print('[VIDEO_DEBUG] WebView load stopped: $url');
                },
                onReceivedError: (controller, request, error) {
                  print('[VIDEO_DEBUG] WebView error on ${request.url}: ${error.description} (code: ${error.type})');
                },
                onReceivedHttpError: (controller, request, errorResponse) {
                  print('[VIDEO_DEBUG] WebView HTTP error on ${request.url}: statusCode=${errorResponse.statusCode}');
                },
                onConsoleMessage: (controller, consoleMessage) {
                  print('[VIDEO_DEBUG] WebView JS Console [${consoleMessage.messageLevel}]: ${consoleMessage.message}');
                },
              ),
            )
          else if (_isInitialized && _controller != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _VideoPlayerWidget(controller: _controller!),
            )
          else
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: IDPColors.backgroundDark,
                child: const Center(
                  child: CircularProgressIndicator(color: IDPColors.primary),
                ),
              ),
            ),
          if (!_isYouTube && _isInitialized && _controller != null)
            Container(
              padding: const EdgeInsets.all(IDPSpacing.md),
              color: IDPColors.surfaceContainerHighest,
              child: Column(
                children: [
                  _buildProgressBar(),
                  const SizedBox(height: IDPSpacing.md),
                  _buildPlaybackControls(),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: IDPColors.primary,
            inactiveTrackColor: IDPColors.primaryContainer.withOpacity(0.5),
            thumbColor: IDPColors.primary,
            overlayColor: IDPColors.primary.withOpacity(0.1),
          ),
          child: Slider(
            min: 0,
            max: _controller!.value.duration.inMilliseconds.toDouble(),
            value: _controller!.value.position.inMilliseconds
                .toDouble()
                .clamp(0, _controller!.value.duration.inMilliseconds.toDouble()),
            onChanged: (value) {
              _controller!.seekTo(Duration(milliseconds: value.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_controller!.value.position),
                style: IDPTypography.labelMd.copyWith(color: IDPColors.onSurfaceVariant),
              ),
              Text(
                _formatDuration(_controller!.value.duration),
                style: IDPTypography.labelMd.copyWith(color: IDPColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPlaybackControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        PopupMenuButton<double>(
          onSelected: _changePlaybackSpeed,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 0.5, child: Text('0.5x')),
            PopupMenuItem(value: 0.75, child: Text('0.75x')),
            PopupMenuItem(value: 1.0, child: Text('1.0x (Normal)')),
            PopupMenuItem(value: 1.25, child: Text('1.25x')),
            PopupMenuItem(value: 1.5, child: Text('1.5x')),
            PopupMenuItem(value: 2.0, child: Text('2.0x')),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: IDPColors.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: IDPColors.primary.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.speed_rounded, size: 18, color: IDPColors.primary),
                const SizedBox(width: 6),
                Text(
                  '${_playbackSpeed}x',
                  style: IDPTypography.labelLarge.copyWith(
                    color: IDPColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        _ControlButton(
          icon: Icons.closed_caption_rounded,
          label: 'CC',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: const Text('Subtitles: Coming soon'), backgroundColor: IDPColors.secondary),
            );
          },
        ),
        _ControlButton(
          icon: Icons.share_rounded,
          label: 'Share',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: const Text('Share: Coming soon'), backgroundColor: IDPColors.secondary),
            );
          },
        ),
      ],
    );
  }

  Widget _buildDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.description != null && widget.description!.isNotEmpty) ...[
          Text(
            'About this video',
            style: IDPTypography.headlineLarge.copyWith(color: IDPColors.primary),
          ),
          const SizedBox(height: IDPSpacing.lg),
          Text(
            widget.description!,
            style: IDPTypography.bodyLarge.copyWith(color: IDPColors.onSurface, height: 1.6),
          ),
          const SizedBox(height: IDPSpacing.xxl),
        ],
        if (_isInitialized && _controller != null)
          Row(
            children: [
              Expanded(child: _buildInfoCard('Duration', _formatDuration(_controller!.value.duration), Icons.timer_rounded)),
              const SizedBox(width: IDPSpacing.lg),
              Expanded(child: _buildInfoCard('Resolution', '${_controller!.value.size.width.toInt()}x${_controller!.value.size.height.toInt()}', Icons.aspect_ratio_rounded)),
            ],
          ),
      ],
    );
  }

  Widget _buildInfoCard(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: IDPColors.secondaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: IDPColors.secondary.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: IDPColors.secondary),
              const SizedBox(width: 6),
                Text(
                  label,
                  style: IDPTypography.labelLarge.copyWith(color: IDPColors.onPrimary),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: IDPTypography.titleMedium.copyWith(
              color: IDPColors.onSecondaryContainer,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: IDPColors.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: IDPColors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: IDPTypography.labelLarge.copyWith(color: IDPColors.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoPlayerWidget extends StatefulWidget {
  const _VideoPlayerWidget({required this.controller});
  final VideoPlayerController controller;

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  bool _showControls = true;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _showControls = !_showControls;
        });
      },
      child: AspectRatio(
        aspectRatio: widget.controller.value.aspectRatio > 0 ? widget.controller.value.aspectRatio : 16/9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(color: Colors.black),
            VideoPlayer(widget.controller),
            if (_showControls)
              Container(
                color: Colors.black.withOpacity(0.4),
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          if (widget.controller.value.isPlaying) {
                            widget.controller.pause();
                          } else {
                            widget.controller.play();
                          }
                        });
                      },
                      customBorder: const CircleBorder(),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: IDPColors.primary.withOpacity(0.9),
                          boxShadow: [
                            BoxShadow(
                              color: IDPColors.primary.withOpacity(0.4),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.controller.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: IDPColors.onPrimary,
                          size: 48,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
