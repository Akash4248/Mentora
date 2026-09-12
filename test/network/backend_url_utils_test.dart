import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tutor_app/features/network/domain/backend_url_utils.dart';
import 'package:offline_tutor_app/features/network/services/mentora_backend_client.dart';

void main() {
  group('BackendUrlUtils Normalization Tests', () {
    test('normalizes raw IP address without scheme or port', () {
      expect(BackendUrlUtils.normalizeUrl('10.35.98.193'), 'http://10.35.98.193:8000');
    });

    test('normalizes IP address with port', () {
      expect(BackendUrlUtils.normalizeUrl('10.35.98.193:8000'), 'http://10.35.98.193:8000');
      expect(BackendUrlUtils.normalizeUrl('10.35.98.193:8040'), 'http://10.35.98.193:8040');
    });

    test('normalizes hostname with .local', () {
      expect(BackendUrlUtils.normalizeUrl('akash-Ubuntu.local'), 'http://akash-ubuntu.local:8000');
      expect(BackendUrlUtils.normalizeUrl('akash-ubuntu:8000'), 'http://akash-ubuntu:8000');
    });

    test('normalizes URL with trailing slashes', () {
      expect(BackendUrlUtils.normalizeUrl('http://10.35.98.193:8000///'), 'http://10.35.98.193:8000');
    });

    test('validates valid URLs', () {
      expect(BackendUrlUtils.isValidUrl('10.35.98.193'), isTrue);
      expect(BackendUrlUtils.isValidUrl('akash-Ubuntu:8000'), isTrue);
      expect(BackendUrlUtils.isValidUrl(''), isFalse);
    });
  });

  group('MentoraBackendClient Probe List Tests', () {
    test('getCandidateGatewayUrls contains laptop hostnames and normalized URLs', () {
      final candidates = MentoraBackendClient.getCandidateGatewayUrls();
      expect(candidates, contains('http://akash-ubuntu.local:8000'));
      expect(candidates, contains('http://akash-ubuntu:8000'));
      expect(candidates, contains('http://10.0.2.2:8000'));
      expect(candidates, contains('http://127.0.0.1:8000'));
    });
  });
}
