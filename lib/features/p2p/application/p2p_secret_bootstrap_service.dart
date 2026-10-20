import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

class BootstrapTokenPayload {
  const BootstrapTokenPayload({
    required this.secret,
    required this.createdAt,
    required this.expiresAt,
    required this.nonce,
  });

  final String secret;
  final int createdAt;
  final int expiresAt;
  final String nonce;
}

Uint8List _pbkdf2IsolateEntryPoint(Map<String, dynamic> params) {
  final passcode = params['passcode'] as String;
  final nonce = params['nonce'] as String;
  final passwordBytes = utf8.encode(passcode);
  final saltBytes = utf8.encode(nonce);

  final hmac = Hmac(sha256, passwordBytes);
  const iterations = P2PSecretBootstrapService.pbkdf2Iterations;
  const keyLength = P2PSecretBootstrapService.derivedKeyLength;

  final blocksNeeded = (keyLength / 32).ceil();
  final out = Uint8List(keyLength);
  var outOffset = 0;

  for (var i = 1; i <= blocksNeeded; i++) {
    final blockInput = Uint8List(saltBytes.length + 4);
    blockInput.setAll(0, saltBytes);
    ByteData.view(blockInput.buffer).setUint32(saltBytes.length, i, Endian.big);

    var u = Uint8List.fromList(hmac.convert(blockInput).bytes);
    final t = Uint8List.fromList(u);

    for (var iter = 1; iter < iterations; iter++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var k = 0; k < t.length; k++) {
        t[k] ^= u[k];
      }
    }

    final bytesToCopy = (outOffset + t.length > keyLength)
        ? keyLength - outOffset
        : t.length;
    out.setRange(outOffset, outOffset + bytesToCopy, t);
    outOffset += bytesToCopy;
  }

  return out;
}

class P2PSecretBootstrapService {
  static const int pbkdf2Iterations = 100000;
  static const int derivedKeyLength = 32;

  /// Async token creation using compute isolate to prevent main thread jank.
  Future<String> createBootstrapTokenAsync({
    required String sharedSecret,
    required String passcode,
    required Duration ttl,
  }) async {
    final secret = sharedSecret.trim();
    final pin = passcode.trim();
    if (secret.isEmpty || pin.isEmpty) {
      throw Exception('Secret and passcode are required for bootstrap token.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = now + ttl.inMilliseconds;
    final nonceBytes = _randomBytes(16);
    final nonce = base64UrlEncode(nonceBytes);

    final key = await _deriveKeyAsync(passcode: pin, nonce: nonce);
    final cipherBytes = _xorBytes(utf8.encode(secret), key);
    final cipherText = base64UrlEncode(cipherBytes);

    final metadata = <String, dynamic>{
      'version': 2,
      'createdAt': now,
      'expiresAt': expiresAt,
      'nonce': nonce,
      'cipher': cipherText,
      'algo': 'pbkdf2-100k+hmac-sha256',
    };

    final canonical = jsonEncode(metadata);
    final macDigest = Hmac(sha256, key).convert(utf8.encode(canonical));
    final mac = base64UrlEncode(macDigest.bytes);

    final token = <String, dynamic>{
      'metadata': metadata,
      'mac': mac,
    };

    final tokenJson = jsonEncode(token);
    return base64UrlEncode(utf8.encode(tokenJson));
  }

  /// Synchronous token creation for testing and direct execution.
  String createBootstrapToken({
    required String sharedSecret,
    required String passcode,
    required Duration ttl,
  }) {
    final secret = sharedSecret.trim();
    final pin = passcode.trim();
    if (secret.isEmpty || pin.isEmpty) {
      throw Exception('Secret and passcode are required for bootstrap token.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final expiresAt = now + ttl.inMilliseconds;
    final nonceBytes = _randomBytes(16);
    final nonce = base64UrlEncode(nonceBytes);

    final key = _deriveKey(passcode: pin, nonce: nonce);
    final cipherBytes = _xorBytes(utf8.encode(secret), key);
    final cipherText = base64UrlEncode(cipherBytes);

    final metadata = <String, dynamic>{
      'version': 2,
      'createdAt': now,
      'expiresAt': expiresAt,
      'nonce': nonce,
      'cipher': cipherText,
      'algo': 'pbkdf2-100k+hmac-sha256',
    };

    final canonical = jsonEncode(metadata);
    final macDigest = Hmac(sha256, key).convert(utf8.encode(canonical));
    final mac = base64UrlEncode(macDigest.bytes);

    final token = <String, dynamic>{
      'metadata': metadata,
      'mac': mac,
    };

    final tokenJson = jsonEncode(token);
    return base64UrlEncode(utf8.encode(tokenJson));
  }

  /// Async token import using compute isolate.
  Future<BootstrapTokenPayload> importBootstrapTokenAsync({
    required String token,
    required String passcode,
  }) async {
    final rawToken = token.trim();
    final pin = passcode.trim();
    if (rawToken.isEmpty || pin.isEmpty) {
      throw Exception('Token and passcode are required.');
    }

    final decodedJson = utf8.decode(base64Url.decode(base64Url.normalize(rawToken)));
    final decoded = jsonDecode(decodedJson) as Map<String, dynamic>;
    final metadata = decoded['metadata'] as Map<String, dynamic>?;
    final mac = decoded['mac'] as String? ?? '';
    if (metadata == null || mac.isEmpty) {
      throw Exception('Invalid bootstrap token format.');
    }

    final nonce = metadata['nonce'] as String? ?? '';
    final cipher = metadata['cipher'] as String? ?? '';
    final createdAt = metadata['createdAt'] as int? ?? 0;
    final expiresAt = metadata['expiresAt'] as int? ?? 0;
    final version = metadata['version'] as int? ?? 1;

    if (nonce.isEmpty || cipher.isEmpty || createdAt <= 0 || expiresAt <= 0) {
      throw Exception('Bootstrap token payload is incomplete.');
    }

    if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
      throw Exception('Bootstrap token has expired.');
    }

    final key = version >= 2
        ? await _deriveKeyAsync(passcode: pin, nonce: nonce)
        : _deriveKeyV1(passcode: pin, nonce: nonce);

    final canonical = jsonEncode(metadata);
    final expectedMacDigest = version >= 2
        ? Hmac(sha256, key).convert(utf8.encode(canonical))
        : Hmac(sha256, utf8.encode(pin)).convert(utf8.encode(canonical));

    List<int> macBytes;
    try {
      macBytes = base64Url.decode(base64Url.normalize(mac));
    } catch (_) {
      macBytes = _hexToBytes(mac);
    }

    if (!_constantTimeCompare(expectedMacDigest.bytes, macBytes)) {
      throw Exception('Bootstrap token verification failed. Wrong passcode or tampered token.');
    }

    final cipherBytes = base64Url.decode(base64Url.normalize(cipher));
    final plainBytes = _xorBytes(cipherBytes, key);
    final secret = utf8.decode(plainBytes).trim();
    if (secret.isEmpty) {
      throw Exception('Bootstrap token does not contain a valid secret.');
    }

    return BootstrapTokenPayload(
      secret: secret,
      createdAt: createdAt,
      expiresAt: expiresAt,
      nonce: nonce,
    );
  }

  /// Synchronous token import for testing.
  BootstrapTokenPayload importBootstrapToken({
    required String token,
    required String passcode,
  }) {
    final rawToken = token.trim();
    final pin = passcode.trim();
    if (rawToken.isEmpty || pin.isEmpty) {
      throw Exception('Token and passcode are required.');
    }

    final decodedJson = utf8.decode(base64Url.decode(base64Url.normalize(rawToken)));
    final decoded = jsonDecode(decodedJson) as Map<String, dynamic>;
    final metadata = decoded['metadata'] as Map<String, dynamic>?;
    final mac = decoded['mac'] as String? ?? '';
    if (metadata == null || mac.isEmpty) {
      throw Exception('Invalid bootstrap token format.');
    }

    final nonce = metadata['nonce'] as String? ?? '';
    final cipher = metadata['cipher'] as String? ?? '';
    final createdAt = metadata['createdAt'] as int? ?? 0;
    final expiresAt = metadata['expiresAt'] as int? ?? 0;
    final version = metadata['version'] as int? ?? 1;

    if (nonce.isEmpty || cipher.isEmpty || createdAt <= 0 || expiresAt <= 0) {
      throw Exception('Bootstrap token payload is incomplete.');
    }

    if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
      throw Exception('Bootstrap token has expired.');
    }

    final key = version >= 2
        ? _deriveKey(passcode: pin, nonce: nonce)
        : _deriveKeyV1(passcode: pin, nonce: nonce);

    final canonical = jsonEncode(metadata);
    final expectedMacDigest = version >= 2
        ? Hmac(sha256, key).convert(utf8.encode(canonical))
        : Hmac(sha256, utf8.encode(pin)).convert(utf8.encode(canonical));

    List<int> macBytes;
    try {
      macBytes = base64Url.decode(base64Url.normalize(mac));
    } catch (_) {
      macBytes = _hexToBytes(mac);
    }

    if (!_constantTimeCompare(expectedMacDigest.bytes, macBytes)) {
      throw Exception('Bootstrap token verification failed. Wrong passcode or tampered token.');
    }

    final cipherBytes = base64Url.decode(base64Url.normalize(cipher));
    final plainBytes = _xorBytes(cipherBytes, key);
    final secret = utf8.decode(plainBytes).trim();
    if (secret.isEmpty) {
      throw Exception('Bootstrap token does not contain a valid secret.');
    }

    return BootstrapTokenPayload(
      secret: secret,
      createdAt: createdAt,
      expiresAt: expiresAt,
      nonce: nonce,
    );
  }

  Future<Uint8List> _deriveKeyAsync({required String passcode, required String nonce}) {
    return compute(_pbkdf2IsolateEntryPoint, {'passcode': passcode, 'nonce': nonce});
  }

  Uint8List _deriveKey({required String passcode, required String nonce}) {
    final passwordBytes = utf8.encode(passcode);
    final saltBytes = utf8.encode(nonce);
    return _pbkdf2HmacSha256(
      password: passwordBytes,
      salt: saltBytes,
      iterations: pbkdf2Iterations,
      keyLength: derivedKeyLength,
    );
  }

  Uint8List _deriveKeyV1({required String passcode, required String nonce}) {
    final material = utf8.encode('$passcode::$nonce');
    final digest = sha256.convert(material).bytes;
    return Uint8List.fromList(digest);
  }

  Uint8List _pbkdf2HmacSha256({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int keyLength,
  }) {
    final hmac = Hmac(sha256, password);
    final blocksNeeded = (keyLength / 32).ceil();
    final out = Uint8List(keyLength);
    var outOffset = 0;

    for (var i = 1; i <= blocksNeeded; i++) {
      final blockInput = Uint8List(salt.length + 4);
      blockInput.setAll(0, salt);
      ByteData.view(blockInput.buffer).setUint32(salt.length, i, Endian.big);

      var u = Uint8List.fromList(hmac.convert(blockInput).bytes);
      final t = Uint8List.fromList(u);

      for (var iter = 1; iter < iterations; iter++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }

      final bytesToCopy = (outOffset + t.length > keyLength)
          ? keyLength - outOffset
          : t.length;
      out.setRange(outOffset, outOffset + bytesToCopy, t);
      outOffset += bytesToCopy;
    }

    return out;
  }

  bool _constantTimeCompare(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  Uint8List _xorBytes(List<int> source, List<int> key) {
    final out = Uint8List(source.length);
    for (var i = 0; i < source.length; i++) {
      out[i] = source[i] ^ key[i % key.length];
    }
    return out;
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return result;
  }
}
