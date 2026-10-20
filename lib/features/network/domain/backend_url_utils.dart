import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

/// Utilities for backend URL normalization, validation, and connectivity probing.
class BackendUrlUtils {
  BackendUrlUtils._();

  /// Default port for Mentora backend servers (gateway / FastAPI).
  static const int defaultPort = 8000;

  /// Normalizes a raw URL or host input string into a complete, well-formed URL.
  ///
  /// Examples:
  ///   - "10.35.98.193"          -> "http://10.35.98.193:8000"
  ///   - "10.35.98.193:8000"     -> "http://10.35.98.193:8000"
  ///   - "10.35.98.193:8040"     -> "http://10.35.98.193:8040"
  ///   - "akash-Ubuntu"          -> "http://akash-Ubuntu:8000"
  ///   - "akash-Ubuntu.local"    -> "http://akash-Ubuntu.local:8000"
  ///   - "akash-ubuntu:8000"     -> "http://akash-ubuntu:8000"
  ///   - "http://10.35.98.193"   -> "http://10.35.98.193:8000"
  ///   - "https://api.mentora.app" -> "https://api.mentora.app"
  static String normalizeUrl(String input) {
    var trimmed = input.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isEmpty) return 'http://127.0.0.1:$defaultPort';

    // Prepend http:// if missing scheme
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      trimmed = 'http://$trimmed';
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.host.isNotEmpty && !uri.hasPort) {
      final host = uri.host.toLowerCase();
      // If it's an IP, localhost, .local domain, or standard dev laptop host, default to port 8000 for http
      final isLocalOrIp = RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host) ||
          host == 'localhost' ||
          host.endsWith('.local') ||
          host.contains('ubuntu') ||
          host.contains('pihub');
      if (isLocalOrIp && uri.scheme == 'http') {
        final path = uri.path.isNotEmpty ? uri.path : '';
        trimmed = '${uri.scheme}://${uri.host}:$defaultPort$path';
      }
    }
    return trimmed;
  }

  /// Checks if a string can be parsed into a valid URL with scheme and host.
  static bool isValidUrl(String raw) {
    if (raw.trim().isEmpty) return false;
    final normalized = normalizeUrl(raw);
    final uri = Uri.tryParse(normalized);
    return uri != null && uri.hasAuthority && uri.host.isNotEmpty;
  }

  /// Probes a backend URL at GET /health to check connectivity and response time.
  static Future<Map<String, dynamic>> probeUrl(
    String rawUrl, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final targetUrl = normalizeUrl(rawUrl);
    final healthUrl = '$targetUrl/health';
    final stopwatch = Stopwatch()..start();

    try {
      final client = HttpClient();
      client.connectionTimeout = timeout;
      final uri = Uri.parse(healthUrl);
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(timeout);
      stopwatch.stop();

      final isSuccess = response.statusCode == 200;
      client.close(force: true);

      return {
        'success': isSuccess,
        'url': targetUrl,
        'statusCode': response.statusCode,
        'latencyMs': stopwatch.elapsedMilliseconds,
      };
    } catch (e) {
      stopwatch.stop();
      return {
        'success': false,
        'url': targetUrl,
        'error': e.toString(),
        'latencyMs': stopwatch.elapsedMilliseconds,
      };
    }
  }

  /// Tries to infer candidate gateway IPs from the device's active Wi-Fi interface.
  static Future<List<String>> inferWifiGatewayCandidates() async {
    final candidates = <String>[];
    try {
      final wifiIP = await NetworkInfo().getWifiIP();
      if (wifiIP != null && wifiIP.isNotEmpty) {
        final parts = wifiIP.split('.');
        if (parts.length == 4) {
          final subnetBase = '${parts[0]}.${parts[1]}.${parts[2]}';
          // Add standard gateway .1 and current host IP
          candidates.add('http://$subnetBase.1:$defaultPort');
          candidates.add('http://$wifiIP:$defaultPort');
        }
      }
    } catch (_) {}
    return candidates;
  }
}
