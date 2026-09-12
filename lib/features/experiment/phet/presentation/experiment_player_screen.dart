import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../simulation_context/providers/simulation_context_provider.dart';
import '../models/experiment_descriptor.dart';

class ExperimentPlayerScreen extends ConsumerStatefulWidget {
  const ExperimentPlayerScreen({required this.experiment, super.key});

  final ExperimentDescriptor experiment;

  @override
  ConsumerState<ExperimentPlayerScreen> createState() =>
      _ExperimentPlayerScreenState();
}

class _ExperimentPlayerScreenState
    extends ConsumerState<ExperimentPlayerScreen> {
  InAppWebViewController? _controller;
  double _progress = 0;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(simulationContextProvider.notifier)
          .update(
            experimentId: widget.experiment.id,
            experimentName: widget.experiment.title,
            subject: widget.experiment.subject,
            provider: widget.experiment.provider,
            currentState: 'Running',
          );
    });
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(simulationContextProvider.notifier).clear();
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWebViewSupported = !kIsWeb && !Platform.isLinux && !Platform.isWindows && InAppWebViewPlatform.instance != null;
    final experiment = widget.experiment;
    final localFile = experiment.isInstalled
        ? File(experiment.launchLocation)
        : null;
    final missingLocalFile = localFile != null && !localFile.existsSync();

    if (!isWebViewSupported) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        appBar: AppBar(
          title: Text(experiment.title),
          backgroundColor: const Color(0xFF1E293B),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.science_outlined, color: Color(0xFF38BDF8), size: 64),
                const SizedBox(height: 16),
                Text(
                  experiment.title,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Interactive PhET simulations are optimized for mobile devices and web browsers.',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                if (experiment.publicUrl != null)
                  ElevatedButton.icon(
                    onPressed: () {
                      final uri = Uri.tryParse(experiment.publicUrl!);
                      if (uri != null) launchUrl(uri);
                    },
                    icon: const Icon(Icons.open_in_browser),
                    label: const Text('Open PhET Lab in Web Browser'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (!missingLocalFile)
            InAppWebView(
              initialFile: experiment.usesBundledAsset
                  ? experiment.launchLocation
                  : null,
              initialUrlRequest: experiment.usesBundledAsset
                  ? null
                  : URLRequest(
                      url: WebUri(
                        experiment.isInstalled
                            ? Uri.file(experiment.launchLocation).toString()
                            : experiment.launchLocation,
                      ),
                    ),
              initialSettings: InAppWebViewSettings(
                allowFileAccessFromFileURLs: true,
                allowUniversalAccessFromFileURLs: true,
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                useHybridComposition: true,
                transparentBackground: false,
              ),
              onWebViewCreated: (controller) => _controller = controller,
              onProgressChanged: (_, progress) {
                if (mounted) {
                  setState(() => _progress = progress / 100);
                }
              },
              onLoadStart: (_, _) {
                if (mounted) setState(() => _loadError = null);
              },
              onReceivedError: (_, request, error) {
                if (request.isForMainFrame != true || !mounted) return;
                setState(() {
                  _loadError = error.description;
                });
              },
              onReceivedHttpError: (_, request, response) {
                if (request.isForMainFrame != true || !mounted) return;
                setState(() {
                  _loadError =
                      'Simulation server returned HTTP ${response.statusCode}.';
                });
              },
            ),
          if (missingLocalFile || _loadError != null)
            _SimulationError(
              message: missingLocalFile
                  ? 'The installed simulation file is missing. Reinstall the '
                        'PhET pack from the catalog.'
                  : _loadError!,
              onRetry: missingLocalFile
                  ? null
                  : () {
                      setState(() => _loadError = null);
                      _controller?.reload();
                    },
            ),
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: Material(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close simulation',
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Text(
                        experiment.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_progress < 1 && _loadError == null && !missingLocalFile)
            LinearProgressIndicator(value: _progress),
        ],
      ),
    );
  }
}

class _SimulationError extends StatelessWidget {
  const _SimulationError({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Colors.white,
              size: 36,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
