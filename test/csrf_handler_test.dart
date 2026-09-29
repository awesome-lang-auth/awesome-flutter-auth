import 'package:test/test.dart';

import 'package:awesome_flutter_auth/src/http/csrf_cookie_parser.dart';
import 'package:awesome_flutter_auth/src/http/csrf_handler_stub.dart';

void main() {
  group('parseCsrfFromCookies', () {
    test('returns null for empty cookie string', () {
      expect(parseCsrfFromCookies(''), isNull);
    });

    test('parses plain csrf-token cookie', () {
      expect(
        parseCsrfFromCookies('csrf-token=abc123'),
        equals('abc123'),
      );
    });

    test('parses __Secure-csrf-token cookie', () {
      expect(
        parseCsrfFromCookies('__Secure-csrf-token=secureToken; other=value'),
        equals('secureToken'),
      );
    });

    test('parses __Host-csrf-token cookie', () {
      expect(
        parseCsrfFromCookies('__Host-csrf-token=hostToken'),
        equals('hostToken'),
      );
    });

    test('__Host-csrf-token has highest priority over __Secure-csrf-token', () {
      expect(
        parseCsrfFromCookies(
          '__Host-csrf-token=host; __Secure-csrf-token=secure; csrf-token=plain',
        ),
        equals('host'),
      );
    });

    test('__Secure-csrf-token has higher priority than plain csrf-token', () {
      expect(
        parseCsrfFromCookies('__Secure-csrf-token=secure; csrf-token=plain'),
        equals('secure'),
      );
    });

    test('handles whitespace around cookie pairs', () {
      expect(
        parseCsrfFromCookies('  csrf-token = myToken ; session=abc'),
        equals('myToken'),
      );
    });

    test('returns null when no csrf cookie present', () {
      expect(
        parseCsrfFromCookies('session=abc; user=xyz'),
        isNull,
      );
    });

    test('handles cookie string with only separators', () {
      expect(parseCsrfFromCookies(';;;'), isNull);
    });

    test('handles cookie value with equals sign', () {
      // Cookie value may contain '=' (e.g. base64-encoded values).
      final result =
          parseCsrfFromCookies('csrf-token=base64==; session=abc');
      expect(result, isNotNull);
    });
  });

  group('stub readCsrfToken', () {
    test('always returns null on native', () {
      expect(readCsrfToken(), isNull);
    });
  });

  group('stub isSameOrigin', () {
    test('always returns false on native', () {
      expect(isSameOrigin('https://example.com/api', '/auth'), isFalse);
      expect(isSameOrigin('/auth/me', '/auth'), isFalse);
    });
  });

  group('isSameOriginPure', () {
    test('relative URL with any prefix → true', () {
      expect(
        isSameOriginPure('/auth/me', '/auth', 'https://example.com'),
        isTrue,
      );
    });

    test('absolute same-origin URL with absolute prefix → true', () {
      expect(
        isSameOriginPure(
          'https://api.example.com/auth/me',
          'https://api.example.com/auth',
          'https://example.com',
        ),
        isTrue,
      );
    });

    test('absolute cross-origin URL with absolute prefix → false', () {
      expect(
        isSameOriginPure(
          'https://other.example.com/auth/me',
          'https://api.example.com/auth',
          'https://example.com',
        ),
        isFalse,
      );
    });

    test('absolute same-origin URL with relative prefix → true', () {
      expect(
        isSameOriginPure(
          'https://example.com/auth/me',
          '/auth',
          'https://example.com',
        ),
        isTrue,
      );
    });

    test('absolute cross-origin URL with relative prefix → false', () {
      expect(
        isSameOriginPure(
          'https://other.com/auth/me',
          '/auth',
          'https://example.com',
        ),
        isFalse,
      );
    });

    test('scheme mismatch → false', () {
      expect(
        isSameOriginPure(
          'http://api.example.com/auth/me',
          'https://api.example.com/auth',
          'https://example.com',
        ),
        isFalse,
      );
    });

    test('port mismatch → false', () {
      expect(
        isSameOriginPure(
          'https://api.example.com:8443/auth/me',
          'https://api.example.com/auth',
          'https://example.com',
        ),
        isFalse,
      );
    });

    test('scheme-relative URL with relative prefix → false (issue #31)', () {
      expect(
        isSameOriginPure('//evil.com/x', '/api/auth', 'https://ita.app'),
        isFalse,
      );
    });

    test('scheme-relative URL with absolute prefix → false (issue #31)', () {
      expect(
        isSameOriginPure(
            '//evil.com/x', 'https://ita.app/api/auth', 'https://ita.app'),
        isFalse,
      );
    });

    test('scheme-relative URL to the same host → false (issue #31)', () {
      expect(
        isSameOriginPure('//ita.app/x', '/api/auth', 'https://ita.app'),
        isFalse,
      );
    });

    test('backslash form /\\evil.com → false (issue #31)', () {
      expect(
        isSameOriginPure('/\\evil.com/x', '/api/auth', 'https://ita.app'),
        isFalse,
      );
    });
  });
}
