import 'dart:typed_data';

import 'package:pinenacl/tweetnacl.dart' show TweetNaCl;

/// Verifies an Ed25519 (RFC 8032, pure EdDSA) [signature] of [message] made
/// with [publicKey].
///
/// Returns `false` when the signature does not verify, when [publicKey] is not
/// 32 bytes or not a valid curve point, or when [signature] is not 64 bytes.
///
/// The arithmetic is TweetNaCl's (via `package:pinenacl`): 16-bit limbs held
/// in [Int32List]s, with no native code, no platform-specific imports and no
/// 64-bit-only integer operations. It gives the same results on the Dart VM,
/// dart2js and dart2wasm, and it is synchronous on all three.
///
/// This function does not check that the scalar `S` is below the group order
/// `L`; `OfflineTokenVerifier` checks that before calling it.
bool ed25519Verify(
  Uint8List publicKey,
  Uint8List message,
  Uint8List signature,
) {
  if (publicKey.length != 32 || signature.length != 64) return false;

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
