// Ed25519 primitive used by OfflineTokenVerifier, checked against the
// RFC 8032 test vectors. Runs on the VM, dart2js and dart2wasm:
//   dart test test/ed25519_test.dart
//   dart test -p chrome test/ed25519_test.dart
//   dart test -p chrome -c dart2wasm test/ed25519_test.dart
import 'dart:typed_data';

import 'package:awesome_flutter_auth/src/offline_tokens/ed25519.dart';
import 'package:test/test.dart';

import 'vectors/rfc8032_ed25519.dart';

Uint8List _hex(String h) => Uint8List.fromList([
      for (var i = 0; i < h.length; i += 2)
        int.parse(h.substring(i, i + 2), radix: 16),
    ]);

Uint8List _flip(Uint8List bytes, int index) =>
    Uint8List.fromList(bytes)..[index] ^= 0x01;

void main() {
  group('RFC 8032 section 7.1 vectors', () {
    for (var i = 0; i < rfc8032Vectors.length; i++) {
      final v = rfc8032Vectors[i];
      final pk = _hex(v['pk']!);
      final msg = _hex(v['msg']!);
      final sig = _hex(v['sig']!);
      // The public key of the next vector, used as a wrong key.
      final otherPk =
          _hex(rfc8032Vectors[(i + 1) % rfc8032Vectors.length]['pk']!);

      group(v['name']!, () {
        test('valid signature verifies', () {
          expect(ed25519Verify(pk, msg, sig), isTrue);
        });

        test('flipped bit in R is rejected', () {
          expect(ed25519Verify(pk, msg, _flip(sig, 0)), isFalse);
        });

        test('flipped bit in S is rejected', () {
          expect(ed25519Verify(pk, msg, _flip(sig, 32)), isFalse);
        });

        test('modified message is rejected', () {
          final tampered = msg.isEmpty
              ? Uint8List.fromList([0])
              : _flip(msg, msg.length - 1);
          expect(ed25519Verify(pk, tampered, sig), isFalse);
        });

        test('wrong public key is rejected', () {
          expect(ed25519Verify(otherPk, msg, sig), isFalse);
        });
      });
    }
  });

  group('input lengths', () {
    final v = rfc8032Vectors[1];
    final pk = _hex(v['pk']!);
    final msg = _hex(v['msg']!);
    final sig = _hex(v['sig']!);

    test('public key that is not 32 bytes is rejected', () {
      expect(ed25519Verify(pk.sublist(0, 31), msg, sig), isFalse);
      expect(ed25519Verify(Uint8List.fromList([...pk, 0]), msg, sig), isFalse);
    });

    test('signature that is not 64 bytes is rejected', () {
      expect(ed25519Verify(pk, msg, sig.sublist(0, 63)), isFalse);
      expect(ed25519Verify(pk, msg, Uint8List.fromList([...sig, 0])), isFalse);
    });
  });
}
