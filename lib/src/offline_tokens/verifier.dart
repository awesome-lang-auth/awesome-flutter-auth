import 'dart:convert';
import 'dart:typed_data';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

import 'models.dart';

/// The group order L of Ed25519 in little-endian 32 bytes (RFC 8032).
/// L = 2^252 + 27742317777372353535851937790883648493
const _ed25519OrderL = <int>[
  0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58,
  0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
];

/// Offline token verifier for JWS compact tokens signed with EdDSA (Ed25519).
class OfflineTokenVerifier {
  /// The set of trusted public keys indexed by `kid`.
  final OkpKeySet keys;

  /// The expected token type in the `typ` header (e.g. `ita-license+jwt`).
  final String expectedTyp;

  /// The expected issuer in the `iss` claim (e.g. `https://ita.example`).
  final String issuer;

  /// The expected audience in the `aud` claim (e.g. `ita-pwa`).
  final String audience;

  /// Optional injectable clock returning UTC [DateTime].
  final DateTime Function()? clock;

  OfflineTokenVerifier({
    required this.keys,
    required this.expectedTyp,
    required this.issuer,
    required this.audience,
    this.clock,
  });

  /// Verifies [token] and returns [OfflineTokenResult] containing `header` and `claims`.
  ///
  /// Throws an [OfflineTokenException] if verification fails for any reason.
  /// No internal [Error] (such as [TypeError], [RangeError], [AssertionError]) escapes.
  OfflineTokenResult verify(String token, {DateTime? now}) {
    final result = tryVerify(token, now: now);
    return result.unwrap();
  }

  /// Attempts to verify [token] without throwing, returning an [OfflineTokenVerificationResult].
  OfflineTokenVerificationResult tryVerify(String token, {DateTime? now}) {
    try {
      return _verifyInternal(token, now: now);
    } catch (e) {
      // Guarantee that no Error or unhandled exception leaks for any arbitrary input string
      return OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.malformed,
        'Unexpected parsing failure: $e',
      );
    }
  }

  OfflineTokenVerificationResult _verifyInternal(String token, {DateTime? now}) {
    // -------------------------------------------------------------------------
    // 1. Check: exactly 3 parts, header and payload non-empty, base64url, JSON
    // Failure reason: malformed
    // -------------------------------------------------------------------------
    final parts = token.split('.');
    if (parts.length != 3) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.malformed,
        'Token must contain exactly 3 dot-separated parts',
      );
    }

    final headerPart = parts[0];
    final payloadPart = parts[1];
    final signaturePart = parts[2];

    if (headerPart.isEmpty || payloadPart.isEmpty) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.malformed,
        'Token header and payload parts must be non-empty',
      );
    }

    final base64UrlRegex = RegExp(r'^[A-Za-z0-9_-]+$');
    if (!base64UrlRegex.hasMatch(headerPart) || !base64UrlRegex.hasMatch(payloadPart)) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.malformed,
        'Header or payload contains non-base64url characters',
      );
    }

    final headerBytes = _decodeBase64Url(headerPart);
    final payloadBytes = _decodeBase64Url(payloadPart);

    if (headerBytes == null || payloadBytes == null) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.malformed,
        'Base64url decoding failed for header or payload',
      );
    }

    // Canonical base64url check: re-encoding must match the original string
    if (_encodeBase64UrlUnpadded(headerBytes) != headerPart ||
        _encodeBase64UrlUnpadded(payloadBytes) != payloadPart) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.malformed,
        'Header or payload is not canonically base64url encoded',
      );
    }

    final Map<String, dynamic> header;
    final Map<String, dynamic> payload;

    try {
      final headerStr = utf8.decode(headerBytes, allowMalformed: false);
      final decoded = json.decode(headerStr);
      if (decoded is! Map<String, dynamic>) {
        return const OfflineTokenVerificationResult.invalid(
          OfflineTokenReason.malformed,
          'Decoded header is not a JSON object',
        );
      }
      header = decoded;
    } catch (_) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.malformed,
        'Header is not valid UTF-8 JSON',
      );
    }

    try {
      final payloadStr = utf8.decode(payloadBytes, allowMalformed: false);
      final decoded = json.decode(payloadStr);
      if (decoded is! Map<String, dynamic>) {
        return const OfflineTokenVerificationResult.invalid(
          OfflineTokenReason.malformed,
          'Decoded payload is not a JSON object',
        );
      }
      payload = decoded;
    } catch (_) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.malformed,
        'Payload is not valid UTF-8 JSON',
      );
    }

    // -------------------------------------------------------------------------
    // 2. Check: alg == "EdDSA" exactly (reject none, HS256, Ed25519, ...)
    // Must be verified before any key is used.
    // Failure reason: alg_not_allowed
    // -------------------------------------------------------------------------
    final alg = header['alg'];
    if (alg != 'EdDSA') {
      return OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.algNotAllowed,
        'Algorithm "$alg" is not allowed (only "EdDSA" is accepted)',
      );
    }

    // -------------------------------------------------------------------------
    // 3. Check: typ equals expectedTyp
    // Failure reason: typ_invalid
    // -------------------------------------------------------------------------
    final typ = header['typ'];
    if (typ != expectedTyp) {
      return OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.typInvalid,
        'Token type "$typ" does not match expected "$expectedTyp"',
      );
    }

    // -------------------------------------------------------------------------
    // 4. Check: header has no crit
    // Failure reason: malformed
    // -------------------------------------------------------------------------
    if (header.containsKey('crit')) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.malformed,
        'Header contains unsupported "crit" parameter',
      );
    }

    // -------------------------------------------------------------------------
    // 5. Check: kid is a string and matches one of the provided keys
    // Failure reason: kid_unknown
    // -------------------------------------------------------------------------
    final kid = header['kid'];
    if (kid is! String || kid.isEmpty) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.kidUnknown,
        'Header "kid" is missing or not a non-empty string',
      );
    }

    final key = keys.getKey(kid);
    if (key == null) {
      return OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.kidUnknown,
        'Key id "$kid" is not in the trusted key set',
      );
    }

    // -------------------------------------------------------------------------
    // 6. Check: signature is canonical base64url, exactly 64 bytes, and
    //           Ed25519-valid over the ASCII header.payload
    // Failure reason: signature_invalid
    // -------------------------------------------------------------------------
    if (signaturePart.isEmpty || !base64UrlRegex.hasMatch(signaturePart)) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.signatureInvalid,
        'Signature is empty or contains non-base64url characters',
      );
    }

    final sigBytes = _decodeBase64Url(signaturePart);
    if (sigBytes == null) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.signatureInvalid,
        'Signature base64url decoding failed',
      );
    }

    // Canonical base64url check: re-encoding must produce the exact same string
    if (_encodeBase64UrlUnpadded(sigBytes) != signaturePart) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.signatureInvalid,
        'Signature is not canonically base64url encoded',
      );
    }

    // Must be exactly 64 bytes
    if (sigBytes.length != 64) {
      return OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.signatureInvalid,
        'Signature length is ${sigBytes.length} bytes (expected 64 bytes)',
      );
    }

    // Canonical encoding: S < L, high bit of last byte clear
    if (!_isScalarCanonical(sigBytes.sublist(32, 64))) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.signatureInvalid,
        'Signature S scalar is non-canonical (must be < L with high bit clear)',
      );
    }

    // Verify Ed25519 signature over ASCII header.payload
    final signedMessage = ascii.encode('$headerPart.$payloadPart');
    final bool isSigValid;
    try {
      isSigValid = ed.verify(
        ed.PublicKey(key.publicKeyBytes),
        Uint8List.fromList(signedMessage),
        sigBytes,
      );
    } catch (_) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.signatureInvalid,
        'Ed25519 verification internal error',
      );
    }

    if (!isSigValid) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.signatureInvalid,
        'Ed25519 signature verification failed',
      );
    }

    // -------------------------------------------------------------------------
    // 7. Check: claim types (strings non-empty, ent/iat/exp integers)
    // Failure reason: claims_invalid
    // -------------------------------------------------------------------------
    final exp = payload['exp'];
    if (exp is! int) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.claimsInvalid,
        'Claim "exp" must be an integer',
      );
    }

    final iss = payload['iss'];
    if (iss is! String || iss.isEmpty) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.claimsInvalid,
        'Claim "iss" must be a non-empty string',
      );
    }

    final aud = payload['aud'];
    if (aud is! String || aud.isEmpty) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.claimsInvalid,
        'Claim "aud" must be a non-empty string',
      );
    }

    if (payload.containsKey('iat') && payload['iat'] is! int) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.claimsInvalid,
        'Claim "iat" must be an integer',
      );
    }

    if (payload.containsKey('ent') && payload['ent'] is! int) {
      return const OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.claimsInvalid,
        'Claim "ent" must be an integer',
      );
    }

    // Ensure all string claims present are non-empty
    for (final entry in payload.entries) {
      final value = entry.value;
      if (value is String && value.isEmpty) {
        return OfflineTokenVerificationResult.invalid(
          OfflineTokenReason.claimsInvalid,
          'Claim "${entry.key}" must not be empty string',
        );
      }
    }

    // -------------------------------------------------------------------------
    // 8. Check: aud equals expected audience
    // Failure reason: aud_invalid
    // -------------------------------------------------------------------------
    if (aud != audience) {
      return OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.audInvalid,
        'Audience "$aud" does not match expected "$audience"',
      );
    }

    // -------------------------------------------------------------------------
    // 9. Check: iss equals expected issuer
    // Failure reason: iss_invalid
    // -------------------------------------------------------------------------
    if (iss != issuer) {
      return OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.issInvalid,
        'Issuer "$iss" does not match expected "$issuer"',
      );
    }

    // -------------------------------------------------------------------------
    // 10. Check: exp <= now (integer seconds)
    // Failure reason: expired
    // Note: falls back to DateTime.now().toUtc() when neither now nor clock is
    // provided. Consumers requiring a monotonic or server-synchronized clock
    // should pass `now` explicitly.
    final effectiveNow = now ?? (clock?.call() ?? DateTime.now().toUtc());
    final nowSeconds = effectiveNow.millisecondsSinceEpoch ~/ 1000;
    if (exp <= nowSeconds) {
      return OfflineTokenVerificationResult.invalid(
        OfflineTokenReason.expired,
        'Token has expired (exp: $exp <= now: $nowSeconds)',
      );
    }

    // Verification succeeded
    return OfflineTokenVerificationResult.valid(
      OfflineTokenResult(header: header, claims: payload),
    );
  }
}

/// Checks that a 32-byte scalar [s] is in canonical form: S < L and high bit is clear.
bool _isScalarCanonical(Uint8List s) {
  if (s.length != 32) return false;
  // High bit of last byte (s[31]) must be clear
  if ((s[31] & 0x80) != 0) return false;

  // Compare s with L from most significant byte down to least significant
  for (var i = 31; i >= 0; i--) {
    final sByte = s[i];
    final lByte = _ed25519OrderL[i];
    if (sByte < lByte) return true;
    if (sByte > lByte) return false;
  }
  // If equal to L, it is not strictly less than L
  return false;
}

Uint8List? _decodeBase64Url(String input) {
  try {
    var s = input.replaceAll('-', '+').replaceAll('_', '/');
    while (s.length % 4 != 0) {
      s += '=';
    }
    return Uint8List.fromList(base64Decode(s));
  } catch (_) {
    return null;
  }
}

String _encodeBase64UrlUnpadded(Uint8List bytes) {
  return base64UrlEncode(bytes).replaceAll('=', '');
}
