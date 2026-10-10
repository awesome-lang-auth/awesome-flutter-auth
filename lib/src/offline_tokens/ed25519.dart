import 'dart:typed_data';

import 'package:pinenacl/tweetnacl.dart' show TweetNaCl;

/// The Ed25519 group order L = 2^252 + 27742317777372353535851937790883648493,
/// little-endian.
const _orderL = <int>[
  0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58,
  0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
];

/// Whether [s] is a canonical Ed25519 scalar: 32 bytes, little-endian, and
/// strictly below the group order L (RFC 8032 section 5.1.7).
bool isCanonicalEd25519Scalar(List<int> s) {
  if (s.length != 32) return false;
  for (var i = 31; i >= 0; i--) {
    if (s[i] < _orderL[i]) return true;
    if (s[i] > _orderL[i]) return false;
  }
  return false; // s == L
}

/// Verifies an Ed25519 (RFC 8032, pure EdDSA) [signature] of [message] made
/// with [publicKey].
///
/// Returns `false` when the signature does not verify, when [publicKey] is not
/// 32 bytes or not a valid curve point, when [signature] is not 64 bytes, or
/// when its scalar `S` is not below the group order `L` (RFC 8032 section
/// 5.1.7, which rules out the `S + L` malleability).
///
/// The arithmetic is TweetNaCl's (via `package:pinenacl`): 16-bit limbs held
/// in [Int32List]s, with no native code, no platform-specific imports and no
/// 64-bit-only integer operations. It gives the same results on the Dart VM,
/// dart2js and dart2wasm, and it is synchronous on all three.
///
/// The check is cofactorless (`[S]B = R + [k]A`). Apart from `S < L`, it is not
/// a strict RFC 8032 / ZIP-215 check: like `ed25519_edwards`, which it
/// replaced, it does not reject small-order or mixed-order points, nor
/// non-canonical encodings of `A` or `R` that decode to a valid point. It is
/// meant for public keys from a trusted key set.
bool ed25519Verify(
  Uint8List publicKey,
  Uint8List message,
  Uint8List signature,
) {
  if (publicKey.length != 32 || signature.length != 64) return false;
  // TweetNaCl does not check S < L, and S + L passes its equation.
  if (!isCanonicalEd25519Scalar(signature.sublist(32))) return false;

  // crypto_sign_open works on the NaCl "signed message" layout:
  // signature (64 bytes) followed by the message.
  final signedMessage = Uint8List(64 + message.length)
    ..setRange(0, 64, signature)
    ..setRange(64, 64 + message.length, message);
  final scratch = Uint8List(signedMessage.length);
  return TweetNaCl.crypto_sign_open(
        scratch,
        -1,
        signedMessage,
        0,
        signedMessage.length,
        publicKey,
      ) ==
      0;
}
