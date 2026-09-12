import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/idp_colors.dart';
import '../../../../core/theme/idp_typography.dart';

class GeogebraEmbeddedView extends StatefulWidget {
  final String initialApp;

  const GeogebraEmbeddedView({
    super.key,
    this.initialApp = '3d',
  });

  @override
  State<GeogebraEmbeddedView> createState() => _GeogebraEmbeddedViewState();
}

class _GeogebraEmbeddedViewState extends State<GeogebraEmbeddedView> {
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool _hasError = false;

  bool get _isWebViewSupported =>
      !kIsWeb &&
      !Platform.isLinux &&
      !Platform.isWindows &&
      InAppWebViewPlatform.instance != null;

  String get _appUrl {
    switch (widget.initialApp) {
      case 'geometry':
        return 'https://www.geogebra.org/geometry';
      case 'classic':
        return 'https://www.geogebra.org/classic';
      case '3d':
      default:
        return 'https://www.geogebra.org/3d';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isWebViewSupported) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.calculate_rounded, size: 56, color: Color(0xFF4F46E5)),
                const SizedBox(height: 16),
                Text(
                  'GeoGebra Interactive Suite (${widget.initialApp.toUpperCase()})',
                  style: IDPTypography.titleMedium.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Embedded webview is optimized for mobile devices. Open GeoGebra directly in your desktop browser for full 3D performance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: IDPColors.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open GeoGebra Suite'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F46E5),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  onPressed: () async {
                    final uri = Uri.parse(_appUrl);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(_appUrl),
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                domStorageEnabled: true,
                useHybridComposition: true,
                transparentBackground: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onLoadStart: (controller, url) {
                setState(() {
                  _isLoading = true;
                  _hasError = false;
                });
              },
              onLoadStop: (controller, url) {
                setState(() {
                  _isLoading = false;
                });
              },
              onReceivedError: (controller, request, error) {
                setState(() {
                  _isLoading = false;
                  _hasError = true;
                });
              },
            ),

            if (_isLoading)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF4F46E5)),
                    SizedBox(height: 12),
                    Text(
                      'Loading GeoGebra 3D Calculator Engine...',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),

            if (_hasError)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.orangeAccent),
                      const SizedBox(height: 12),
                      Text(
                        'GeoGebra Online Engine Unavailable',
                        style: IDPTypography.titleSmall.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Switching to Mentora Native 3D High-Performance Canvas Engine.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: IDPColors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry Connection'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F46E5),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          _webViewController?.reload();
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
