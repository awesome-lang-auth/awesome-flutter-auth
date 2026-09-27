import 'dart:convert';
import 'dart:typed_data';

/// Reasons for token verification failure.
///
/// Evaluated in a fixed order where the first failure determines the reason:
/// 1. [malformed]
/// 2. [algNotAllowed]
/// 3. [typInvalid]
/// 4. [malformed] (if critical headers present)
/// 5. [kidUnknown]
/// 6. [signatureInvalid]
/// 7. [claimsInvalid]
/// 8. [audInvalid]
/// 9. [issInvalid]
/// 10. [expired]
enum OfflineTokenReason {
  malformed('malformed'),
  algNotAllowed('alg_not_allowed'),
  typInvalid('typ_invalid'),
  kidUnknown('kid_unknown'),
  signatureInvalid('signature_invalid'),
  claimsInvalid('claims_invalid'),
  audInvalid('aud_invalid'),
  issInvalid('iss_invalid'),
  expired('expired');

  const OfflineTokenReason(this.code);

  /// String code corresponding to the acceptance test vectors.
  final String code;

  /// Looks up a reason by its string [code].
  static OfflineTokenReason? fromCode(String code) {
    for (final reason in values) {
      if (reason.code == code) return reason;
    }
    return null;
  }

  @override
  String toString() => code;
}

/// Exception thrown when an offline token fails verification.
class OfflineTokenException implements Exception {
  final OfflineTokenReason reason;
  final String message;

  const OfflineTokenException({
    required this.reason,
    required this.message,
  });

  @override
  String toString() => 'OfflineTokenException($reason): $message';
}

/// The decoded and verified header and claims of an offline token.
class OfflineTokenResult {
  final Map<String, dynamic> header;
  final Map<String, dynamic> claims;

  const OfflineTokenResult({
    required this.header,
    required this.claims,
  });

  @override
  String toString() => 'OfflineTokenResult(header: $header, claims: $claims)';
}

/// Non-throwing result of an offline token verification attempt.
class OfflineTokenVerificationResult {
  final bool isValid;
  final OfflineTokenReason? reason;
  final String? errorMessage;
  final OfflineTokenResult? result;

  const OfflineTokenVerificationResult.valid(OfflineTokenResult this.result)
      : isValid = true,
        reason = null,
        errorMessage = null;

  const OfflineTokenVerificationResult.invalid(
    OfflineTokenReason this.reason,
    String this.errorMessage,
  )   : isValid = false,
        result = null;

  /// Returns [result] if valid, or throws [OfflineTokenException] if invalid.
  OfflineTokenResult unwrap() {
    if (isValid && result != null) {
      return result!;
    }
    throw OfflineTokenException(
      reason: reason ?? OfflineTokenReason.malformed,
      message: errorMessage ?? 'Token verification failed',
    );
  }

  @override
  String toString() {
    if (isValid) {
      return 'OfflineTokenVerificationResult.valid($result)';
    }
    return 'OfflineTokenVerificationResult.invalid($reason: $errorMessage)';
  }
}

/// Represents an Ed25519 public key in JWK OKP format (RFC 8037).
class OkpKey {
  final String kid;
  final String x;
  final Uint8List publicKeyBytes;
  final String? kty;
  final String? crv;
  final String? use;
  final String? alg;

  const OkpKey({
    required this.kid,
    required this.x,
    required this.publicKeyBytes,
    this.kty = 'OKP',
    this.crv = 'Ed25519',
    this.use = 'sig',
    this.alg = 'EdDSA',
  });

  /// Parses a JWK OKP map containing `kid`, `kty: "OKP"`, `crv: "Ed25519"`, and `x`.
  factory OkpKey.fromJson(Map<String, dynamic> json) {
    final kid = json['kid']?.toString();
    if (kid == null || kid.isEmpty) {
      throw const FormatException('JWK OKP key missing or empty "kid"');
    }

    final kty = json['kty']?.toString();
    if (kty != null && kty != 'OKP') {
      throw FormatException('JWK key "kty" must be "OKP", got: $kty');
    }

    final crv = json['crv']?.toString();
    if (crv != null && crv != 'Ed25519') {
      throw FormatException('JWK key "crv" must be "Ed25519", got: $crv');
    }

    final x = json['x']?.toString();
    if (x == null || x.isEmpty) {
      throw const FormatException('JWK OKP key missing or empty "x" coordinate');
    }

    final bytes = _decodeBase64Url(x);
    if (bytes == null || bytes.length != 32) {
      throw const FormatException('JWK OKP "x" coordinate must decode to exactly 32 bytes');
    }

    return OkpKey(
      kid: kid,
      x: x,
      publicKeyBytes: bytes,
      kty: kty ?? 'OKP',
      crv: crv ?? 'Ed25519',
      use: json['use']?.toString() ?? 'sig',
      alg: json['alg']?.toString() ?? 'EdDSA',
    );
  }

  /// Creates an [OkpKey] from raw 32-byte public key bytes.
  factory OkpKey.fromRawBytes(String kid, Uint8List bytes) {
    if (bytes.length != 32) {
      throw ArgumentError.value(bytes.length, 'bytes.length', 'Ed25519 public key must be 32 bytes');
    }
    final x = _encodeBase64UrlUnpadded(bytes);
    return OkpKey(
      kid: kid,
      x: x,
      publicKeyBytes: bytes,
    );
  }

  /// Creates an [OkpKey] from a SubjectPublicKeyInfo (SPKI) PEM string.
  factory OkpKey.fromPem(String kid, String pem) {
    final cleaned = pem
        .replaceAll('-----BEGIN PUBLIC KEY-----', '')
        .replaceAll('-----END PUBLIC KEY-----', '')
        .replaceAll(RegExp(r'\s+'), '');
    final der = base64.decode(cleaned);

    // Ed25519 SPKI DER is 44 bytes: 12-byte header + 32-byte raw public key
    // Header: 30 2a 30 05 06 03 2b 65 70 03 21 00
    const spkiHeader = [
      0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00
    ];

    if (der.length == 44) {
      for (var i = 0; i < 12; i++) {
        if (der[i] != spkiHeader[i]) {
          throw const FormatException('Invalid Ed25519 SPKI header');
        }
      }
      final rawKey = Uint8List.fromList(der.sublist(12));
      return OkpKey.fromRawBytes(kid, rawKey);
    } else if (der.length == 32) {
      return OkpKey.fromRawBytes(kid, Uint8List.fromList(der));
    } else {
      throw FormatException('Unexpected public key DER length: ${der.length} (expected 44 or 32)');
    }
  }

  @override
  String toString() => 'OkpKey(kid: $kid, crv: $crv, alg: $alg)';
}

/// A set of [OkpKey] public keys indexed by `kid`.
class OkpKeySet {
  final Map<String, OkpKey> _keys;

  OkpKeySet(Map<String, OkpKey> keys) : _keys = Map.unmodifiable(keys);

  factory OkpKeySet.fromKeys(Iterable<OkpKey> keys) {
    final map = <String, OkpKey>{};
    for (final key in keys) {
      map[key.kid] = key;
    }
    return OkpKeySet(map);
  }

  /// Parses JWK OKP keys from a JSON list of key maps or a JWK Set map with a `"keys"` entry.
  factory OkpKeySet.fromJwks(dynamic jwks) {
    final List<dynamic> keyList;
    if (jwks is List) {
      keyList = jwks;
    } else if (jwks is Map && jwks['keys'] is List) {
      keyList = jwks['keys'] as List;
    } else {
      throw const FormatException('Invalid JWKS format: expected a List or a Map containing a "keys" list');
    }

    final map = <String, OkpKey>{};
    for (final item in keyList) {
      if (item is Map<String, dynamic>) {
        final key = OkpKey.fromJson(item);
        map[key.kid] = key;
      } else if (item is Map) {
        final key = OkpKey.fromJson(Map<String, dynamic>.from(item));
        map[key.kid] = key;
      }
    }
    return OkpKeySet(map);
  }

  OkpKey? getKey(String kid) => _keys[kid];
  bool containsKey(String kid) => _keys.containsKey(kid);
  Iterable<OkpKey> get keys => _keys.values;
  int get length => _keys.length;
  bool get isEmpty => _keys.isEmpty;
  bool get isNotEmpty => _keys.isNotEmpty;

  @override
  String toString() => 'OkpKeySet(${_keys.keys.toList()})';
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
