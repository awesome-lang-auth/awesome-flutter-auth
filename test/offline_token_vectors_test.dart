// Licence token vectors for OfflineTokenVerifier (issues #25 and #34). Every
// vector must give the same outcome on the VM, dart2js and dart2wasm:
//   dart test test/offline_token_vectors_test.dart
//   dart test -p chrome test/offline_token_vectors_test.dart
//   dart test -p chrome -c dart2wasm test/offline_token_vectors_test.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:awesome_flutter_auth/offline_tokens.dart';
import 'package:test/test.dart';

import 'vectors/licence_vectors.dart';

const _kid = '7b9e369ab8fe4ee1';
const _x = 'sVgnMIw8WUSwL6SoDxXcOO1TCyMsX-kMmjg69QQT0Yw';
const _nextKid = 'a4f1238587295284';
const _nextX = 'cNAhOMKTy6vpftYH_f7PQquCGJDAyKQwUy-STQPUKeM';

/// Ed25519 group order L, as an integer.
final _orderL = BigInt.two.pow(252) +
    BigInt.parse('27742317777372353535851937790883648493');

Map<String, Object> _jwk(String kid, String x) => {
      'kid': kid,
      'kty': 'OKP',
      'crv': 'Ed25519',
      'x': x,
      'use': 'sig',
      'alg': 'EdDSA',
    };

OfflineTokenVerifier _verifier(List<Map<String, Object>> jwks) =>
    OfflineTokenVerifier(
      keys: OkpKeySet.fromJwks(jwks),
      expectedTyp: 'ita-license+jwt',
      issuer: 'https://ita.example',
      audience: 'ita-pwa',
    );

Uint8List _b64d(String s) =>
    Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));

String _b64e(List<int> bytes) => base64UrlEncode(bytes).replaceAll('=', '');

BigInt _leToBigInt(List<int> bytes) {
  var n = BigInt.zero;
  for (var i = bytes.length - 1; i >= 0; i--) {
    n = (n << 8) | BigInt.from(bytes[i]);
  }
  return n;
}

List<int> _bigIntToLe(BigInt n, int length) => [
      for (var i = 0; i < length; i++)
        ((n >> (8 * i)) & BigInt.from(0xff)).toInt(),
    ];

/// Replaces the signature of [token] with [mutate] applied to its bytes.
String _withSignature(String token, Uint8List Function(Uint8List) mutate) {
  final parts = token.split('.');
  return '${parts[0]}.${parts[1]}.${_b64e(mutate(_b64d(parts[2])))}';
}

void main() {
  final verifier = _verifier([_jwk(_kid, _x), _jwk(_nextKid, _nextX)]);

  group('licence vectors give the recorded outcome', () {
    for (final v in licenceVectors) {
      test(v.name, () {
        final res =
            verifier.tryVerify(v.token, now: DateTime.parse(v.verifyAt));
        expect(
          (valid: res.isValid, reason: res.reason?.code),
          (valid: v.valid, reason: v.reason),
          reason: 'errorMessage: ${res.errorMessage}',
        );
      });
    }
  });

  group('negative vectors built from the valid token', () {
    final valid = licenceVectors.singleWhere((v) => v.name == 'valid');
    final now = DateTime.parse(valid.verifyAt);

    void expectSignatureInvalid(OfflineTokenVerificationResult res) {
      expect(res.isValid, isFalse, reason: 'token was accepted');
      expect(res.reason, OfflineTokenReason.signatureInvalid,
          reason: 'errorMessage: ${res.errorMessage}');
    }

    test('baseline: the valid token verifies', () {
      final res = verifier.tryVerify(valid.token, now: now);
      expect(res.isValid, isTrue, reason: 'errorMessage: ${res.errorMessage}');
      expect(res.result!.claims['jti'], 'vec-valid-0001');
    });

    test('wrong key: kid mapped to another public key', () {
      final wrongKey = _verifier([_jwk(_kid, _nextX)]);
      final res = wrongKey.tryVerify(valid.token, now: now);
      expectSignatureInvalid(res);
      expect(res.errorMessage, 'Ed25519 signature verification failed');
    });

    test('tampered payload, original signature', () {
      final parts = valid.token.split('.');
      final claims =
          json.decode(utf8.decode(_b64d(parts[1]))) as Map<String, dynamic>;
      claims['plan'] = 'lifetime';
      final token = '${parts[0]}.${_b64e(utf8.encode(json.encode(claims)))}'
          '.${parts[2]}';
      final res = verifier.tryVerify(token, now: now);
      expectSignatureInvalid(res);
      expect(res.errorMessage, 'Ed25519 signature verification failed');
    });

    test('flipped bit in R', () {
      final token =
          _withSignature(valid.token, (s) => Uint8List.fromList(s)..[0] ^= 1);
      final res = verifier.tryVerify(token, now: now);
      expectSignatureInvalid(res);
      expect(res.errorMessage, 'Ed25519 signature verification failed');
    });

    test('flipped bit in S', () {
      final token =
          _withSignature(valid.token, (s) => Uint8List.fromList(s)..[32] ^= 1);
      final res = verifier.tryVerify(token, now: now);
      expectSignatureInvalid(res);
      expect(res.errorMessage, 'Ed25519 signature verification failed');
    });

    test('non-canonical S (S + L) is rejected before verification', () {
      final token = _withSignature(valid.token, (s) {
        final sPlusL = _leToBigInt(s.sublist(32)) + _orderL;
        // S + L still fits in 253 bits, so only the S < L check rejects it.
        expect(sPlusL.bitLength, lessThanOrEqualTo(255));
        return Uint8List.fromList(
            [...s.sublist(0, 32), ..._bigIntToLe(sPlusL, 32)]);
      });
      final res = verifier.tryVerify(token, now: now);
      expectSignatureInvalid(res);
      expect(res.errorMessage, contains('non-canonical'));
    });
  });
}
