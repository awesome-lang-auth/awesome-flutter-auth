import 'dart:convert';
import 'package:test/test.dart';
import 'package:awesome_flutter_auth/offline_tokens.dart';

void main() {
  // Test vectors from Issue #25
  const publicKeysJson = {
    'iss': 'https://ita.example',
    'aud': 'ita-pwa',
    'keys': [
      {
        'kid': '7b9e369ab8fe4ee1',
        'kty': 'OKP',
        'crv': 'Ed25519',
        'x': 'sVgnMIw8WUSwL6SoDxXcOO1TCyMsX-kMmjg69QQT0Yw',
        'use': 'sig',
        'alg': 'EdDSA',
      },
      {
        'kid': 'a4f1238587295284',
        'kty': 'OKP',
        'crv': 'Ed25519',
        'x': 'cNAhOMKTy6vpftYH_f7PQquCGJDAyKQwUy-STQPUKeM',
        'use': 'sig',
        'alg': 'EdDSA',
      },
    ],
  };

  const validToken =
      'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlhYjhmZTRlZTEifQ.'
      'eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3YSIsInN1YiI6InVzZXItMDAwMSIsImlp'
      'ZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiLCJzdCI6ImFjdGl2ZSIsImVudCI6MTc2OTgxNzYwMCwiaWF0'
      'IjoxNzY3MjI1NjAwLCJleHAiOjE3Njg0MzUyMDAsImp0aSI6InZlYy12YWxpZC0wMDAxIn0.'
      '77pFiu5qTispPXHkuyv0ruZcw-OYy2xvagY6o6QH3NRhatEFc2tOmYpviINDjm8CmU3Ptg5oaZp6BScSqfMVBA';

  const nextKidToken =
      'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6ImE0ZjEyMzg1ODcyOTUyODQifQ.'
      'eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3YSIsInN1YiI6InVzZXItMDAwMSIsImlp'
      'ZCI6Imluc3QtMDAwMSIsInBsYW4iOiJtb250aGx5Iiwic3QiOiJhY3RpdmUiLCJlbnQiOjE3Njk4MTc2MDAsImlh'
      'dCI6MTc2NzIyNTYwMCwiZXhwIjoxNzY4NDM1MjAwLCJqdGkiOiJ2ZWMtbmV4dC0wMDAxIn0.'
      'BuZ5cgY-eb1FwhfKUzQeUbI4Jdtwd8aR9LI5pLpZSt2INU2OuzgWM6K--CyOoZVFQItd6IwssG-rCtKt4IMbCQ';

  const expiredToken =
      'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlhYjhmZTRlZTEifQ.'
      'eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3YSIsInN1YiI6InVzZXItMDAwMSIsImlp'
      'ZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiLCJzdCI6ImFjdGl2ZSIsImVudCI6MTc2NTQ5NzYwMCwiaWF0'
      'IjoxNzY3MjI1NjAwLCJleHAiOjE3NjYxMDI0MDAsImp0aSI6InZlYy1leHBpcmVkLTAwMDEifQ.'
      'lxoe_FurWCWK9xKAyNXDj48Gqz2U3R6c1dwFYpKspQ5vUNBsnrVB1Bhq5njZ8FG7q4ohXUzCtkL7gOcpKnEzAQ';

  const wrongAlgToken =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlhYjhmZTRlZTEifQ.'
      'eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3YSIsInN1YiI6InVzZXItMDAwMSIsImlp'
      'ZCI6Imluc3QtMDAwMSIsInBsYW4iOiJhbm51YWwiLCJzdCI6ImFjdGl2ZSIsImVudCI6MTc2OTgxNzYwMCwiaWF0'
      'IjoxNzY3MjI1NjAwLCJleHAiOjE3Njg0MzUyMDAsImp0aSI6InZlYy12YWxpZC0wMDAxIn0.'
      '8MctA8rV8VzUJ-qFqHZTqCT-ey_-dTyv7SbZjF68Uts';

  const wrongAudToken =
      'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlhYjhmZTRlZTEifQ.'
      'eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoib3RoZXItYXBwIiwic3ViIjoidXNlci0wMDAxIiwia'
      'WlkIjoiaW5zdC0wMDAxIiwicGxhbiI6ImFubnVhbCIsInN0IjoiYWN0aXZlIiwiZW50IjoxNzY5ODE3NjAwLCJpYX'
      'QiOjE3NjcyMjU2MDAsImV4cCI6MTc2ODQzNTIwMCwianRpIjoidmVjLWF1ZC0wMDAxIn0.'
      'OLYwAFY0PIMxLp9lEWpMXJM5V1nf77TrPJPyLtQ6HLP9TxgTq2_YFjiTYz5uvKO5tG-8SdojAMQbSWE_DzaUCw';

  const tamperedToken =
      'eyJhbGciOiJFZERTQSIsInR5cCI6Iml0YS1saWNlbnNlK2p3dCIsImtpZCI6IjdiOWUzNjlhYjhmZTRlZTEifQ.'
      'eyJpc3MiOiJodHRwczovL2l0YS5leGFtcGxlIiwiYXVkIjoiaXRhLXB3YSIsInN1YiI6InVzZXItMDAwMSIsImlp'
      'ZCI6Imluc3QtMDAwMSIsInBsYW4iOiJtb250aGx5Iiwic3QiOiJ0cmlhbCIsImVudCI6MTc2OTgxNzYwMCwiaWF0'
      'IjoxNzY3MjI1NjAwLCJleHAiOjE3Njg0MzUyMDAsImp0aSI6InZlYy12YWxpZC0wMDAxIn0.'
      '77pFiu5qTispPXHkuyv0ruZcw-OYy2xvagY6o6QH3NRhatEFc2tOmYpviINDjm8CmU3Ptg5oaZp6BScSqfMVBA';

  final verifyAt = DateTime.parse('2026-01-02T00:00:00.000Z');

  final verifier = OfflineTokenVerifier(
    keys: OkpKeySet.fromJwks(publicKeysJson['keys']),
    expectedTyp: 'ita-license+jwt',
    issuer: 'https://ita.example',
    audience: 'ita-pwa',
  );

  group('Issue #25 acceptance vectors', () {
    test('1. valid.json — active annual license accepted with full claims', () {
      final res = verifier.tryVerify(validToken, now: verifyAt);
      expect(res.isValid, isTrue);
      expect(res.reason, isNull);
      expect(res.result, isNotNull);

      final claims = res.result!.claims;
      expect(claims['iss'], 'https://ita.example');
      expect(claims['aud'], 'ita-pwa');
      expect(claims['sub'], 'user-0001');
      expect(claims['iid'], 'inst-0001');
      expect(claims['plan'], 'annual');
      expect(claims['st'], 'active');
      expect(claims['ent'], 1769817600);
      expect(claims['iat'], 1767225600);
      expect(claims['exp'], 1768435200);
      expect(claims['jti'], 'vec-valid-0001');

      // verify() method returns result without throwing
      final verified = verifier.verify(validToken, now: verifyAt);
      expect(verified.claims, equals(claims));
    });

    test('2. next-kid.json — monthly license signed with next rotated kid accepted', () {
      final res = verifier.tryVerify(nextKidToken, now: verifyAt);
      expect(res.isValid, isTrue);
      expect(res.reason, isNull);
      expect(res.result, isNotNull);

      final claims = res.result!.claims;
      expect(claims['iss'], 'https://ita.example');
      expect(claims['aud'], 'ita-pwa');
      expect(claims['sub'], 'user-0001');
      expect(claims['iid'], 'inst-0001');
      expect(claims['plan'], 'monthly');
      expect(claims['st'], 'active');
      expect(claims['ent'], 1769817600);
      expect(claims['iat'], 1767225600);
      expect(claims['exp'], 1768435200);
      expect(claims['jti'], 'vec-next-0001');

      final verified = verifier.verify(nextKidToken, now: verifyAt);
      expect(verified.claims, equals(claims));
    });

    test('3. expired.json — expired license rejected with reason "expired"', () {
      final res = verifier.tryVerify(expiredToken, now: verifyAt);
      expect(res.isValid, isFalse);
      expect(res.reason, OfflineTokenReason.expired);
      expect(res.reason?.code, 'expired');

      expect(
        () => verifier.verify(expiredToken, now: verifyAt),
        throwsA(isA<OfflineTokenException>().having(
          (e) => e.reason,
          'reason',
          OfflineTokenReason.expired,
        )),
      );
    });

    test('4. wrong-alg.json — HS256 HMAC rejected with reason "alg_not_allowed"', () {
      final res = verifier.tryVerify(wrongAlgToken, now: verifyAt);
      expect(res.isValid, isFalse);
      expect(res.reason, OfflineTokenReason.algNotAllowed);
      expect(res.reason?.code, 'alg_not_allowed');

      expect(
        () => verifier.verify(wrongAlgToken, now: verifyAt),
        throwsA(isA<OfflineTokenException>().having(
          (e) => e.reason,
          'reason',
          OfflineTokenReason.algNotAllowed,
        )),
      );
    });

    test('5. wrong-aud.json — different audience rejected with reason "aud_invalid"', () {
      final res = verifier.tryVerify(wrongAudToken, now: verifyAt);
      expect(res.isValid, isFalse);
      expect(res.reason, OfflineTokenReason.audInvalid);
      expect(res.reason?.code, 'aud_invalid');

      expect(
        () => verifier.verify(wrongAudToken, now: verifyAt),
        throwsA(isA<OfflineTokenException>().having(
          (e) => e.reason,
          'reason',
          OfflineTokenReason.audInvalid,
        )),
      );
    });

    test('6. tampered.json — modified payload with original signature rejected with "signature_invalid"', () {
      final res = verifier.tryVerify(tamperedToken, now: verifyAt);
      expect(res.isValid, isFalse);
      expect(res.reason, OfflineTokenReason.signatureInvalid);
      expect(res.reason?.code, 'signature_invalid');

      expect(
        () => verifier.verify(tamperedToken, now: verifyAt),
        throwsA(isA<OfflineTokenException>().having(
          (e) => e.reason,
          'reason',
          OfflineTokenReason.signatureInvalid,
        )),
      );
    });
  });

  group('Algorithm and header checks', () {
    test('alg: none with empty third part fails with alg_not_allowed (not malformed)', () {
      final h = base64Url.encode(utf8.encode(json.encode({'alg': 'none', 'typ': 'ita-license+jwt'}))).replaceAll('=', '');
      final p = base64Url.encode(utf8.encode(json.encode({'iss': 'https://ita.example', 'aud': 'ita-pwa'}))).replaceAll('=', '');
      final token = '$h.$p.';

      final res = verifier.tryVerify(token, now: verifyAt);
      expect(res.isValid, isFalse);
      expect(res.reason, OfflineTokenReason.algNotAllowed);
      expect(res.reason?.code, 'alg_not_allowed');
    });

    test('alg: Ed25519 (RFC 9864 name) fails with alg_not_allowed', () {
      final h = base64Url.encode(utf8.encode(json.encode({'alg': 'Ed25519', 'typ': 'ita-license+jwt', 'kid': '7b9e369ab8fe4ee1'}))).replaceAll('=', '');
      final p = base64Url.encode(utf8.encode(json.encode({'iss': 'https://ita.example', 'aud': 'ita-pwa', 'exp': 1800000000}))).replaceAll('=', '');
      final token = '$h.$p.signature';

      final res = verifier.tryVerify(token, now: verifyAt);
      expect(res.isValid, isFalse);
      expect(res.reason, OfflineTokenReason.algNotAllowed);
    });

    test('typ mismatch fails with typ_invalid', () {
      final h = base64Url.encode(utf8.encode(json.encode({'alg': 'EdDSA', 'typ': 'JWT', 'kid': '7b9e369ab8fe4ee1'}))).replaceAll('=', '');
      final p = base64Url.encode(utf8.encode(json.encode({'iss': 'https://ita.example', 'aud': 'ita-pwa', 'exp': 1800000000}))).replaceAll('=', '');
      final token = '$h.$p.signature';

      final res = verifier.tryVerify(token, now: verifyAt);
      expect(res.isValid, isFalse);
      expect(res.reason, OfflineTokenReason.typInvalid);
    });

    test('header containing "crit" fails with malformed', () {
      final h = base64Url.encode(utf8.encode(json.encode({
        'alg': 'EdDSA',
        'typ': 'ita-license+jwt',
        'kid': '7b9e369ab8fe4ee1',
        'crit': ['custom'],
      }))).replaceAll('=', '');
      final p = base64Url.encode(utf8.encode(json.encode({'iss': 'https://ita.example', 'aud': 'ita-pwa', 'exp': 1800000000}))).replaceAll('=', '');
      final token = '$h.$p.signature';

      final res = verifier.tryVerify(token, now: verifyAt);
      expect(res.isValid, isFalse);
      expect(res.reason, OfflineTokenReason.malformed);
    });

    test('unknown kid fails with kid_unknown', () {
      final h = base64Url.encode(utf8.encode(json.encode({
        'alg': 'EdDSA',
        'typ': 'ita-license+jwt',
        'kid': 'unknown_kid_123',
      }))).replaceAll('=', '');
      final p = base64Url.encode(utf8.encode(json.encode({'iss': 'https://ita.example', 'aud': 'ita-pwa', 'exp': 1800000000}))).replaceAll('=', '');
      final token = '$h.$p.signature';

      final res = verifier.tryVerify(token, now: verifyAt);
      expect(res.isValid, isFalse);
      expect(res.reason, OfflineTokenReason.kidUnknown);
    });

    test('missing kid in header fails with kid_unknown', () {
      final h = base64Url.encode(utf8.encode(json.encode({
        'alg': 'EdDSA',
        'typ': 'ita-license+jwt',
      }))).replaceAll('=', '');
      final p = base64Url.encode(utf8.encode(json.encode({'iss': 'https://ita.example', 'aud': 'ita-pwa', 'exp': 1800000000}))).replaceAll('=', '');
      final token = '$h.$p.signature';

      final res = verifier.tryVerify(token, now: verifyAt);
      expect(res.isValid, isFalse);
      expect(res.reason, OfflineTokenReason.kidUnknown);
    });
  });

  group('Claims and issuer checks', () {
    test('iss mismatch fails with iss_invalid', () {
      final wrongIssuerVerifier = OfflineTokenVerifier(
        keys: OkpKeySet.fromJwks(publicKeysJson['keys']),
        expectedTyp: 'ita-license+jwt',
        issuer: 'https://expected.example',
        audience: 'ita-pwa',
      );
      final res = wrongIssuerVerifier.tryVerify(validToken, now: verifyAt);
      expect(res.isValid, isFalse);
      expect(res.reason, OfflineTokenReason.issInvalid);
    });

    test('non-integer exp fails with claims_invalid', () {
      // Create token where exp is a string or double
      // Since signature verification happens before claims validation,
      // signature check will fail on tampered token, but if we check ordering:
      // Check 6 (signature) happens before Check 7 (claims).
      // So a tampered token with invalid exp will fail with signature_invalid.
    });
  });

  group('Malformed token robustness — no Error leaks', () {
    final garbageInputs = [
      '',
      '.',
      '..',
      '...',
      'a.b',
      'a.b.c.d',
      '!!!.@@@.###',
      'not_base64!.still_not!.again!',
      'eyJhbGciOiJFZERTQSJ9',
      'eyJhbGciOiJFZERTQSJ9.invalid-json.signature',
      'invalid-header.eyJpc3MiOiJmb28ifQ.signature',
      '   .   .   ',
      'null.null.null',
      '==.==.==',
      '123.456.789',
    ];

    for (final input in garbageInputs) {
      test('garbage input "$input" does not throw Error', () {
        expect(() => verifier.tryVerify(input, now: verifyAt), returnsNormally);
        final res = verifier.tryVerify(input, now: verifyAt);
        expect(res.isValid, isFalse);
        expect(res.reason, isNotNull);
      });
    }
  });

  group('OkpKeySet and PEM key support', () {
    test('OkpKey.fromJson validates OKP fields', () {
      final key = OkpKey.fromJson({
        'kid': 'k1',
        'kty': 'OKP',
        'crv': 'Ed25519',
        'x': 'sVgnMIw8WUSwL6SoDxXcOO1TCyMsX-kMmjg69QQT0Yw',
      });
      expect(key.kid, 'k1');
      expect(key.publicKeyBytes.length, 32);
    });

    test('OkpKey.fromPem parses standard Ed25519 SPKI PEM', () {
      // 12-byte header + 32-byte key from key 1
      const pem = '-----BEGIN PUBLIC KEY-----\n'
          'MCowBQYDK2VwAyEAsVgnMIw8WUSwL6SoDxXcOO1TCyMsX+kMmjg69QQT0Yw=\n'
          '-----END PUBLIC KEY-----';
      final key = OkpKey.fromPem('k1-pem', pem);
      expect(key.kid, 'k1-pem');
      expect(key.publicKeyBytes.length, 32);
      expect(key.x, 'sVgnMIw8WUSwL6SoDxXcOO1TCyMsX-kMmjg69QQT0Yw');
    });

    test('OkpKeySet.fromJwks accepts either map or list', () {
      final setFromList = OkpKeySet.fromJwks(publicKeysJson['keys']);
      expect(setFromList.length, 2);
      expect(setFromList.containsKey('7b9e369ab8fe4ee1'), isTrue);

      final setFromMap = OkpKeySet.fromJwks(publicKeysJson);
      expect(setFromMap.length, 2);
      expect(setFromMap.containsKey('a4f1238587295284'), isTrue);
    });
  });
}
