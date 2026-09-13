import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tutor_app/features/p2p/application/p2p_secret_bootstrap_service.dart';

void main() {
  group('P2PSecretBootstrapService Hardened Crypto Tests', () {
    late P2PSecretBootstrapService service;

    setUp(() {
      service = P2PSecretBootstrapService();
    });

    test('Create and import valid bootstrap token with PBKDF2-HMAC-SHA256', () {
      const secret = 'super-secret-p2p-key-12345';
      const passcode = 'mentora88';
      const ttl = Duration(minutes: 10);

      final token = service.createBootstrapToken(
        sharedSecret: secret,
        passcode: passcode,
        ttl: ttl,
      );

      expect(token, isNotEmpty);

      final payload = service.importBootstrapToken(
        token: token,
        passcode: passcode,
      );

      expect(payload.secret, equals(secret));
      expect(payload.nonce, isNotEmpty);
      expect(payload.expiresAt, greaterThan(payload.createdAt));
    });

    test('Fails on invalid passcode / PIN', () {
      const secret = 'super-secret-p2p-key-12345';
      const passcode = 'mentora88';
      const wrongPasscode = 'wrongpin1';
      const ttl = Duration(minutes: 10);

      final token = service.createBootstrapToken(
        sharedSecret: secret,
        passcode: passcode,
        ttl: ttl,
      );

      expect(
        () => service.importBootstrapToken(
          token: token,
          passcode: wrongPasscode,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('Fails on tampered cipher text', () {
      const secret = 'super-secret-p2p-key-12345';
      const passcode = 'mentora88';
      const ttl = Duration(minutes: 10);

      final token = service.createBootstrapToken(
        sharedSecret: secret,
        passcode: passcode,
        ttl: ttl,
      );

      // Decode token and tamper cipher payload
      final decodedJson = utf8.decode(base64Url.decode(base64Url.normalize(token)));
      final Map<String, dynamic> decoded = jsonDecode(decodedJson);
      final metadata = decoded['metadata'] as Map<String, dynamic>;
      metadata['cipher'] = base64UrlEncode(utf8.encode('tampered-cipher-text'));

      final tamperedToken = base64UrlEncode(utf8.encode(jsonEncode(decoded)));

      expect(
        () => service.importBootstrapToken(
          token: tamperedToken,
          passcode: passcode,
        ),
        throwsA(predicate((e) => e.toString().contains('verification failed'))),
      );
    });

    test('Fails on expired token', () async {
      const secret = 'super-secret-p2p-key-12345';
      const passcode = 'mentora88';
      const ttl = Duration(milliseconds: 1);

      final token = service.createBootstrapToken(
        sharedSecret: secret,
        passcode: passcode,
        ttl: ttl,
      );

      await Future.delayed(const Duration(milliseconds: 10));

      expect(
        () => service.importBootstrapToken(
          token: token,
          passcode: passcode,
        ),
        throwsA(predicate((e) => e.toString().contains('expired'))),
      );
    });

    test('Generates unique nonces per token (Nonce Reuse Prevention)', () {
      const secret = 'super-secret-p2p-key-12345';
      const passcode = 'mentora88';
      const ttl = Duration(minutes: 10);

      final token1 = service.createBootstrapToken(
        sharedSecret: secret,
        passcode: passcode,
        ttl: ttl,
      );

      final token2 = service.createBootstrapToken(
        sharedSecret: secret,
        passcode: passcode,
        ttl: ttl,
      );

      final payload1 = service.importBootstrapToken(token: token1, passcode: passcode);
      final payload2 = service.importBootstrapToken(token: token2, passcode: passcode);

      expect(payload1.nonce, isNot(equals(payload2.nonce)));
    });
  });
}
