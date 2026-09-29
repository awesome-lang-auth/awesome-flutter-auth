import 'dart:convert';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:mocktail/mocktail.dart';

import 'package:awesome_flutter_auth/src/http/auth_http_client.dart';
import 'package:awesome_flutter_auth/src/http/csrf_cookie_parser.dart';
import 'package:awesome_flutter_auth/src/http/token_storage.dart';
import 'package:awesome_flutter_auth/src/auth_events.dart';
import 'package:awesome_flutter_auth/src/auth_options.dart';
import 'package:awesome_flutter_auth/src/auth_user.dart';
import 'package:awesome_flutter_auth/src/models/auth_result.dart';
import 'package:awesome_flutter_auth/src/models/session_info.dart';
import 'package:awesome_flutter_auth/src/platform/native_auth_client.dart';

class MockHttpClient extends Mock implements http.Client {}

/// [TokenStorage] whose [clear] completes after a delay, like a secure
/// storage plugin (issue #31).
class SlowTokenStorage implements TokenStorage {
  String? accessToken;
  String? refreshToken;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<void> writeAccessToken(String token) async => accessToken = token;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeRefreshToken(String token) async => refreshToken = token;

  @override
  Future<void> clear() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    accessToken = null;
    refreshToken = null;
  }
}

http.Response jsonResponse(int statusCode, [Map<String, dynamic>? body]) {
  return http.Response(
    body != null ? jsonEncode(body) : '',
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

final _testUser = {
  'sub': 'user-123',
  'email': 'test@example.com',
  'isEmailVerified': true,
  'firstName': 'Test',
  'lastName': 'User',
};

void main() {
  late MockHttpClient mockClient;
  late NativeAuthClient authClient;
  late InMemoryTokenStorage storage;

  setUp(() {
    registerFallbackValue(Uri());
    mockClient = MockHttpClient();
    storage = InMemoryTokenStorage();

    final options = const AuthOptions(
      apiPrefix: 'https://api.example.com/auth',
      headless: true,
      initializeOnStartup: false,
    );

    final authHttp = AuthHttpClient(
      inner: mockClient,
      apiPrefix: options.apiPrefix,
      bearerProvider: storage.readAccessToken,
      bearerSetter: storage.writeAccessToken,
    );

    authClient = NativeAuthClient(options, authHttp, storage);
  });

  group('AuthClient — login', () {
    test('successful login updates state', () async {
      // First call: /login succeeds.
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200, {'success': true}));

      // Second call: /me returns the user.
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      final result = await authClient.login('test@example.com', 'password');

      expect(result.success, isTrue);
      expect(result.requires2fa, isFalse);
      expect(result.data, isA<AuthUser>());
      expect(authClient.state.isAuthenticated, isTrue);
      expect(authClient.state.currentUser?.email, equals('test@example.com'));
    });

    test('login with 2FA returns requires2fa=true', () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200, {
            'requiresTwoFactor': true,
            'tempToken': 'tmp-token-xyz',
            'available2faMethods': ['totp', 'sms'],
          }));

      final result = await authClient.login('test@example.com', 'password');

      expect(result.success, isTrue);
      expect(result.requires2fa, isTrue);
      expect(result.tempToken, equals('tmp-token-xyz'));
      expect(result.availableMethods, containsAll(['totp', 'sms']));
    });

    test('failed login returns success=false', () async {
      when(() => mockClient.post(
                Uri.parse('https://api.example.com/auth/login'),
                headers: any(named: 'headers'),
                body: any(named: 'body'),
              ))
          .thenAnswer((_) async =>
              jsonResponse(401, {'message': 'Invalid credentials'}));

      final result = await authClient.login('bad@example.com', 'wrong');

      expect(result.success, isFalse);
      expect(result.error, contains('Invalid credentials'));
    });

    test('native login stores bearer token and uses it for /me', () async {
      // awesome-node-auth bearer strategy returns tokens in the login body.
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200, {
            'success': true,
            'accessToken': 'native-access-token',
            'refreshToken': 'native-refresh-token',
          }));

      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      final result = await authClient.login('test@example.com', 'password');

      expect(result.success, isTrue);

      final captured = verify(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: captureAny(named: 'headers'),
          )).captured;
      final headers = captured.first as Map<String, String>;
      expect(headers['Authorization'], equals('Bearer native-access-token'));
      expect(headers['X-Auth-Strategy'], equals('bearer'));
    });
  });

  group('AuthClient — checkSession', () {
    test('returns user when session is valid', () async {
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      final user = await authClient.checkSession();

      expect(user, isNotNull);
      expect(user!.email, equals('test@example.com'));
      expect(user.sub, equals('user-123'));
      expect(authClient.state.isAuthenticated, isTrue);
    });

    test('returns null when session is invalid', () async {
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(401));

      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/refresh'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(401));

      final user = await authClient.checkSession();

      expect(user, isNull);
      expect(authClient.state.isAuthenticated, isFalse);
    });
  });

  group('AuthClient — register', () {
    test('successful registration returns userId', () async {
      when(() => mockClient.post(
                Uri.parse('https://api.example.com/auth/register'),
                headers: any(named: 'headers'),
                body: any(named: 'body'),
              ))
          .thenAnswer(
              (_) async => jsonResponse(201, {'userId': 'new-user-id'}));

      final result =
          await authClient.register('new@example.com', 'pass', 'First', 'Last');

      expect(result.success, isTrue);
      expect(result.data, equals('new-user-id'));
    });
  });

  group('AuthClient — password', () {
    test('forgotPassword succeeds', () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/forgot-password'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));

      final result = await authClient.forgotPassword('user@example.com');
      expect(result.success, isTrue);
    });

    test('setPassword calls changePassword with empty current password',
        () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/change-password'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));

      final result = await authClient.setPassword('newPassword');
      expect(result.success, isTrue);

      // Verify the body included an empty currentPassword.
      final captured = verify(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/change-password'),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured;
      final body = jsonDecode(captured.first as String) as Map<String, dynamic>;
      expect(body['currentPassword'], equals(''));
      expect(body['newPassword'], equals('newPassword'));
    });
  });

  group('AuthClient — 2FA TOTP', () {
    final setupUri = Uri.parse('https://api.example.com/auth/2fa/setup');
    const otpauthUrl =
        'otpauth://totp/awesome-node-auth:test%40example.com?secret=TOTP_SECRET&issuer=awesome-node-auth';

    void stubSetup(int status, Map<String, dynamic> body) {
      when(() => mockClient.post(
            setupUri,
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(status, body));
    }

    test('setup2fa returns secret, otpauthUrl and qrCode (node shape)',
        () async {
      stubSetup(200, {
        'secret': 'TOTP_SECRET',
        'otpauthUrl': otpauthUrl,
        'qrCode': 'data:image/png;base64,abc==',
      });

      final result = await authClient.setup2fa();

      expect(result.success, isTrue);
      expect(result.data?.secret, equals('TOTP_SECRET'));
      expect(result.data?.otpauthUrl, equals(otpauthUrl));
      expect(result.data?.qrCode, equals('data:image/png;base64,abc=='));
    });

    // Issue #22: awesome-go-auth and awesome-lambda-auth send no qrCode.
    test('setup2fa succeeds without qrCode and exposes otpauthUrl', () async {
      stubSetup(200, {'secret': 'TOTP_SECRET', 'otpauthUrl': otpauthUrl});

      final result = await authClient.setup2fa();

      expect(result.success, isTrue);
      expect(result.data?.secret, equals('TOTP_SECRET'));
      expect(result.data?.otpauthUrl, equals(otpauthUrl));
      expect(result.data?.qrCode, isNull);
      verify(() => mockClient.post(
            setupUri,
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).called(1);
    });

    test('setup2fa turns a response without secret into a failure', () async {
      stubSetup(200, {'otpauthUrl': otpauthUrl});

      final result = await authClient.setup2fa();

      expect(result.success, isFalse);
      expect(result.data, isNull);
      expect(result.error, contains('secret'));
    });

    test('setup2fa turns fields of the wrong type into a failure', () async {
      stubSetup(200, {'secret': 42, 'otpauthUrl': otpauthUrl});

      final result = await authClient.setup2fa();

      expect(result.success, isFalse);
      expect(result.error, contains('secret'));
    });

    test('TotpSetupData.fromJson ignores optional fields of the wrong type', () {
      final data = TotpSetupData.fromJson(
          {'secret': 'TOTP_SECRET', 'otpauthUrl': 1, 'qrCode': false});

      expect(data.secret, equals('TOTP_SECRET'));
      expect(data.otpauthUrl, isNull);
      expect(data.qrCode, isNull);
    });
  });

  group('AuthClient — Bearer token injection', () {
    test('Bearer token is sent in Authorization header', () async {
      await storage.writeAccessToken('my-access-token');

      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      await authClient.checkSession();

      final captured = verify(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: captureAny(named: 'headers'),
          )).captured;
      final headers = captured.first as Map<String, String>;
      expect(headers['Authorization'], equals('Bearer my-access-token'));
    });
  });

  group('AuthClient — state stream', () {
    test('userStream emits user on login and null on logout', () async {
      final events = <AuthUser?>[];
      final sub = authClient.state.userStream.listen(events.add);

      // Setup login.
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      await authClient.login('test@example.com', 'password');

      // Logout.
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/logout'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));

      await authClient.logout();

      await sub.cancel();

      // userStream yields the current value on subscription (null before login),
      // then the user after login, then null after logout.
      expect(events, hasLength(greaterThanOrEqualTo(2)));
      expect(events.any((e) => e is AuthUser), isTrue);
      expect(events.last, isNull);
    });

    test('userStream replays current value to late subscribers', () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      await authClient.login('test@example.com', 'password');

      // Subscribe *after* login — should receive the current user immediately.
      final received = <AuthUser?>[];
      final sub = authClient.state.userStream.listen(received.add);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(received, isNotEmpty);
      expect(received.first, isA<AuthUser>());
    });
  });

  group('AuthClient — auth events', () {
    Future<void> expectLoggedInEvent(
      Future<dynamic> Function() action,
    ) async {
      final eventFuture = expectLater(
        authClient.events,
        emits(predicate<AuthEvent>((event) {
          return event.type == AuthEventType.loggedIn &&
              event.user?.email == _testUser['email'];
        })),
      );

      await action();
      await eventFuture;
      expect(authClient.state.currentUser?.email, equals(_testUser['email']));
    }

    test('verifyMagicLink emits loggedIn event', () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/magic-link/verify'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      await expectLoggedInEvent(() => authClient.verifyMagicLink('magic-token'));
    });

    test('verifySmsLogin emits loggedIn event', () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/sms/verify'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      await expectLoggedInEvent(
          () => authClient.verifySmsLogin('user-123', '123456'));
    });

    test('validateSms emits loggedIn event', () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/sms/verify'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      await expectLoggedInEvent(
          () => authClient.validateSms('temp-token', '123456'));
    });

    test('validate2fa emits loggedIn event', () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/2fa/verify'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      await expectLoggedInEvent(
          () => authClient.validate2fa('temp-token', '123456'));
    });

    test('confirmEmailChange refreshes session and emits emailChanged', () async {
      final updatedUser = {..._testUser, 'email': 'updated@example.com'};
      final eventFuture = expectLater(
        authClient.events,
        emits(predicate<AuthEvent>((event) {
          return event.type == AuthEventType.emailChanged && event.user == null;
        })),
      );

      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/change-email/confirm'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, updatedUser));

      final result = await authClient.confirmEmailChange('confirm-token');

      expect(result.success, isTrue);
      await eventFuture;
      expect(authClient.state.currentUser?.email, equals('updated@example.com'));
    });

    test('verifyConflictLinkingToken emits loggedIn event', () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/link-verify'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      await expectLoggedInEvent(
          () => authClient.verifyConflictLinkingToken('conflict-token'));

      final captured = verify(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/link-verify'),
            headers: any(named: 'headers'),
            body: captureAny(named: 'body'),
          )).captured;
      final body = jsonDecode(captured.first as String) as Map<String, dynamic>;
      expect(body['token'], equals('conflict-token'));
      expect(body['loginAfterLinking'], isTrue);
    });
  });

  // Issue #21: the server sends `sessionHandle`, not `handle`.
  group('AuthClient — active sessions', () {
    final sessionsUri = Uri.parse('https://api.example.com/auth/sessions');

    void stubSessions(String body) {
      when(() => mockClient.get(sessionsUri, headers: any(named: 'headers')))
          .thenAnswer((_) async => http.Response(body, 200,
              headers: {'content-type': 'application/json'}));
    }

    test('getActiveSessions reads the sessionHandle the server sends',
        () async {
      // The shape GET /sessions answers with: the reference's SessionInfo
      // (src/models/session.model.ts), dates serialised by JSON.stringify.
      stubSessions(r'''
{"sessions":[{"sessionHandle":"ses_ae852735043ae641f308b16b03b6a12d",
"userId":"user-123","createdAt":"2026-08-15T18:00:00.000Z",
"expiresAt":"2026-08-22T18:00:00.000Z",
"lastActiveAt":"2026-08-15T18:29:31.000Z",
"userAgent":"Mozilla/5.0","ipAddress":"203.0.113.7"}]}''');

      final sessions = await authClient.getActiveSessions();

      expect(sessions, hasLength(1));
      final session = sessions.single;
      expect(session.handle, equals('ses_ae852735043ae641f308b16b03b6a12d'));
      expect(session.userAgent, equals('Mozilla/5.0'));
      expect(session.ipAddress, equals('203.0.113.7'));
      expect(session.createdAt, equals(DateTime.utc(2026, 8, 15, 18)));
      expect(session.lastActiveAt, equals(DateTime.utc(2026, 8, 15, 18, 29, 31)));
      expect(session.isCurrent, isFalse);
    });

    test('getActiveSessions falls back to handle', () async {
      stubSessions('{"sessions":[{"handle":"legacy-handle"}]}');

      final sessions = await authClient.getActiveSessions();

      expect(sessions.single.handle, equals('legacy-handle'));
    });

    test('getActiveSessions skips an entry with no handle instead of throwing',
        () async {
      stubSessions('{"sessions":[{"userId":"user-123"},'
          '{"sessionHandle":"ses_ok","createdAt":42,"isCurrent":"yes"}]}');

      final sessions = await authClient.getActiveSessions();

      expect(sessions, hasLength(1));
      expect(sessions.single.handle, equals('ses_ok'));
      expect(sessions.single.createdAt, isNull);
      expect(sessions.single.isCurrent, isFalse);
    });

    test('getActiveSessions returns an empty list for a body that is not JSON',
        () async {
      // What a proxy or SPA fallback answers when apiPrefix is wrong.
      stubSessions('<html><body>app</body></html>');
      expect(await authClient.getActiveSessions(), isEmpty);

      stubSessions('');
      expect(await authClient.getActiveSessions(), isEmpty);
    });

    test('revokeSession sends the handle read from sessionHandle', () async {
      stubSessions(
          '{"sessions":[{"sessionHandle":"ses_ae852735043ae641f308b16b03b6a12d"}]}');
      final revokeUri = Uri.parse(
          'https://api.example.com/auth/sessions/ses_ae852735043ae641f308b16b03b6a12d');
      when(() => mockClient.delete(revokeUri, headers: any(named: 'headers')))
          .thenAnswer((_) async => jsonResponse(200, {'success': true}));

      final sessions = await authClient.getActiveSessions();
      final result = await authClient.revokeSession(sessions.single.handle);

      expect(result.success, isTrue);
      verify(() => mockClient.delete(revokeUri, headers: any(named: 'headers')))
          .called(1);
    });

    test('SessionInfo.toJson writes sessionHandle and round-trips', () {
      final session = SessionInfo(
        handle: 'ses_1',
        createdAt: DateTime.utc(2026, 8, 15, 18),
        isCurrent: true,
      );

      final json = session.toJson();
      final back = SessionInfo.fromJson(json);

      expect(json['sessionHandle'], equals('ses_1'));
      expect(json.containsKey('handle'), isFalse);
      expect(back.handle, equals('ses_1'));
      expect(back.createdAt, equals(DateTime.utc(2026, 8, 15, 18)));
      expect(back.isCurrent, isTrue);
    });

    test('SessionInfo.fromJson throws FormatException without a handle', () {
      expect(() => SessionInfo.fromJson({'userId': 'user-123'}),
          throwsFormatException);
      expect(() => SessionInfo.fromJson({'sessionHandle': 7}),
          throwsFormatException);
    });
  });

  group('AuthClient — sessions cleanup', () {
    test('cleanupSessions succeeds on 200', () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/sessions/cleanup'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200));

      final result = await authClient.cleanupSessions();
      expect(result.success, isTrue);
    });

    test('cleanupSessions returns failure on 500', () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/sessions/cleanup'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer(
              (_) async => jsonResponse(500, {'message': 'Server error'}));

      final result = await authClient.cleanupSessions();
      expect(result.success, isFalse);
      expect(result.error, contains('Server error'));
    });
  });

  group('AuthClient — OAuth helpers', () {
    test('getOAuthUrl returns correct URL for a provider', () {
      final url = authClient.getOAuthUrl('github');
      expect(url, equals('https://api.example.com/auth/oauth/github'));
    });

    test('getOAuthUrl returns correct URL for google provider', () {
      final url = authClient.getOAuthUrl('google');
      expect(url, equals('https://api.example.com/auth/oauth/google'));
    });

    test('handleOAuthCallback returns user and emits loggedIn on success',
        () async {
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));

      final eventFuture = expectLater(
        authClient.events,
        emits(predicate<AuthEvent>((event) =>
            event.type == AuthEventType.loggedIn &&
            event.user?.email == _testUser['email'])),
      );

      final user = await authClient.handleOAuthCallback();

      expect(user, isNotNull);
      expect(user?.email, equals('test@example.com'));
      await eventFuture;
    });

    test('handleOAuthCallback returns null when session check fails', () async {
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(401));

      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/refresh'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(401));

      final user = await authClient.handleOAuthCallback();
      expect(user, isNull);
    });
  });

  // Issue #27: Login/register failures lose status and error code; deleteAccount() path is hardcoded.
  group('AuthClient — Issue #27: login and register error details', () {
    test('401 login carries server errorCode, statusCode 401, and falls back to error',
        () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(
            401,
            {
              'error': 'Invalid credentials',
              'code': 'INVALID_CREDENTIALS',
            },
          ));

      final result = await authClient.login('test@example.com', 'badpass');

      expect(result.success, isFalse);
      expect(result.statusCode, equals(401));
      expect(result.errorCode, equals('INVALID_CREDENTIALS'));
      expect(result.error, equals('Invalid credentials'));
    });

    test('403 login with EMAIL_VERIFICATION_REQUIRED preserves code and status',
        () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(
            403,
            {
              'error': 'Email not verified',
              'code': 'EMAIL_VERIFICATION_REQUIRED',
            },
          ));

      final result = await authClient.login('test@example.com', 'pass');

      expect(result.success, isFalse);
      expect(result.statusCode, equals(403));
      expect(result.errorCode, equals('EMAIL_VERIFICATION_REQUIRED'));
      expect(result.error, equals('Email not verified'));
    });

    test('429 rate limit login carries statusCode 429 and error string as code fallback',
        () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(
            429,
            {'error': 'Too many attempts'},
          ));

      final result = await authClient.login('test@example.com', 'pass');

      expect(result.success, isFalse);
      expect(result.statusCode, equals(429));
      expect(result.errorCode, equals('Too many attempts'));
      expect(result.error, equals('Too many attempts'));
    });

    test('error prefers message over error when both are present', () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(
            400,
            {
              'message': 'Custom user message',
              'error': 'BAD_REQUEST',
              'code': 'VALIDATION_FAILED',
            },
          ));

      final result = await authClient.login('test@example.com', 'pass');

      expect(result.error, equals('Custom user message'));
      expect(result.errorCode, equals('VALIDATION_FAILED'));
      expect(result.statusCode, equals(400));
    });

    test('409 register carries errorCode USER_EXISTS and statusCode 409',
        () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/register'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(
            409,
            {
              'error': 'User already exists',
              'code': 'USER_EXISTS',
            },
          ));

      final result = await authClient.register(
        'existing@example.com',
        'password',
        'First',
        'Last',
      );

      expect(result.success, isFalse);
      expect(result.statusCode, equals(409));
      expect(result.errorCode, equals('USER_EXISTS'));
      expect(result.error, equals('User already exists'));
    });
  });

  group('AuthClient — Issue #27: deleteAccount and clearLocalSession', () {
    test('clearLocalSession emits loggedOut, clears state and makes no request',
        () async {
      // Simulate authenticated state.
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));
      await authClient.checkSession();
      expect(authClient.state.isAuthenticated, isTrue);

      final events = <AuthEvent>[];
      final sub = authClient.events.listen(events.add);

      // Call clearLocalSession.
      authClient.clearLocalSession();

      expect(authClient.state.isAuthenticated, isFalse);
      expect(authClient.state.currentUser, isNull);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(events, hasLength(1));
      expect(events.first.type, equals(AuthEventType.loggedOut));
      // No DELETE or POST request made.
      verifyNever(() => mockClient.delete(any(), headers: any(named: 'headers')));
      verifyNever(() => mockClient.post(any(),
          headers: any(named: 'headers'), body: any(named: 'body')));
    });

    test('deleteAccount() default calls {apiPrefix}/account and resets state on 200',
        () async {
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(200, _testUser));
      await authClient.checkSession();

      final deleteUri = Uri.parse('https://api.example.com/auth/account');
      when(() => mockClient.delete(deleteUri, headers: any(named: 'headers')))
          .thenAnswer((_) async => jsonResponse(200, {'success': true}));

      final result = await authClient.deleteAccount();

      expect(result.success, isTrue);
      expect(authClient.state.isAuthenticated, isFalse);
      verify(() => mockClient.delete(deleteUri, headers: any(named: 'headers')))
          .called(1);
    });

    test('deleteAccount(path: "/api/account") calls root-relative path with CSRF',
        () async {
      final customClient = MockHttpClient();
      final webStorage = InMemoryTokenStorage();
      final options = const AuthOptions(
        apiPrefix: 'https://api.example.com/auth',
        headless: true,
        initializeOnStartup: false,
      );

      final authHttp = AuthHttpClient(
        inner: customClient,
        apiPrefix: options.apiPrefix,
        csrfProvider: (_) => 'csrf-secret-token',
        bearerProvider: webStorage.readAccessToken,
      );
      final client = NativeAuthClient(options, authHttp, webStorage);

      final targetUri = Uri.parse('https://api.example.com/api/account');
      when(() => customClient.delete(targetUri, headers: any(named: 'headers')))
          .thenAnswer((_) async => jsonResponse(200, {'success': true}));

      final result = await client.deleteAccount(path: '/api/account');

      expect(result.success, isTrue);
      final captured = verify(() =>
              customClient.delete(targetUri, headers: captureAny(named: 'headers')))
          .captured;
      final headers = captured.first as Map<String, String>;
      expect(headers['X-CSRF-Token'], equals('csrf-secret-token'));
    });

    test('deleteAccount respects AuthOptions.deleteAccountPath option',
        () async {
      final customClient = MockHttpClient();
      final options = const AuthOptions(
        apiPrefix: 'https://api.example.com/auth',
        deleteAccountPath: '/api/account',
        headless: true,
        initializeOnStartup: false,
      );

      final authHttp = AuthHttpClient(
        inner: customClient,
        apiPrefix: options.apiPrefix,
      );
      final client = NativeAuthClient(options, authHttp, InMemoryTokenStorage());

      final targetUri = Uri.parse('https://api.example.com/api/account');
      when(() => customClient.delete(targetUri, headers: any(named: 'headers')))
          .thenAnswer((_) async => jsonResponse(200, {'success': true}));

      final result = await client.deleteAccount();

      expect(result.success, isTrue);
      verify(() => customClient.delete(targetUri, headers: any(named: 'headers')))
          .called(1);
    });

    test('deleteAccount failure carries server statusCode and errorCode',
        () async {
      final deleteUri = Uri.parse('https://api.example.com/auth/account');
      when(() => mockClient.delete(deleteUri, headers: any(named: 'headers')))
          .thenAnswer((_) async => jsonResponse(
                403,
                {
                  'error': 'Account cannot be deleted',
                  'code': 'DELETE_BLOCKED',
                },
              ));

      final result = await authClient.deleteAccount();

      expect(result.success, isFalse);
      expect(result.statusCode, equals(403));
      expect(result.errorCode, equals('DELETE_BLOCKED'));
      expect(result.error, equals('Account cannot be deleted'));
    });
  });

  group('AuthClient — Issue #29 fixes', () {
    test(
        'clearLocalSession clears token storage on native and subsequent request has no Authorization header',
        () async {
      await storage.writeAccessToken('native-access-token');
      await storage.writeRefreshToken('native-refresh-token');

      authClient.clearLocalSession();

      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readRefreshToken(), isNull);

      // Subsequent /me request must NOT carry Authorization header
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(401, {'error': 'Unauthorized'}));

      await authClient.checkSession();

      final captured = verify(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: captureAny(named: 'headers'),
          )).captured;
      final headers = captured.first as Map<String, String>;
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test(
        'deleteAccount on 2xx clears token storage on native and subsequent request has no Authorization header',
        () async {
      await storage.writeAccessToken('native-access-token');
      await storage.writeRefreshToken('native-refresh-token');

      final deleteUri = Uri.parse('https://api.example.com/auth/account');
      when(() => mockClient.delete(deleteUri, headers: any(named: 'headers')))
          .thenAnswer((_) async => jsonResponse(200, {'success': true}));

      final result = await authClient.deleteAccount();
      expect(result.success, isTrue);

      expect(await storage.readAccessToken(), isNull);
      expect(await storage.readRefreshToken(), isNull);

      // Subsequent /me request must NOT carry Authorization header
      when(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: any(named: 'headers'),
          )).thenAnswer((_) async => jsonResponse(401, {'error': 'Unauthorized'}));

      await authClient.checkSession();

      final captured = verify(() => mockClient.get(
            Uri.parse('https://api.example.com/auth/me'),
            headers: captureAny(named: 'headers'),
          )).captured;
      final headers = captured.first as Map<String, String>;
      expect(headers.containsKey('Authorization'), isFalse);
    });

    test(
        'login() handles non-string error payloads gracefully without throwing',
        () async {
      // Object error: {"error": {"message": "Invalid password", "code": "WRONG_PASSWORD"}}
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(400, {
            'error': {'message': 'Invalid password', 'code': 'WRONG_PASSWORD'},
          }));

      final result = await authClient.login('test@example.com', 'badpass');
      expect(result.success, isFalse);
      expect(result.error, equals('Invalid password'));
      expect(result.errorCode, equals('WRONG_PASSWORD'));
      expect(result.statusCode, equals(400));

      // Number error: {"error": 500}
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(500, {'error': 500}));

      final result2 = await authClient.login('test@example.com', 'badpass');
      expect(result2.success, isFalse);
      expect(result2.statusCode, equals(500));
      expect(result2.error, equals('Login failed'));
    });

    test(
        'register() handles non-string error payloads gracefully without throwing',
        () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/register'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(400, {
            'error': {'message': 'Email in use', 'code': 'EMAIL_EXISTS'},
          }));

      final result =
          await authClient.register('test@example.com', 'pass', 'A', 'B');
      expect(result.success, isFalse);
      expect(result.error, equals('Email in use'));
      expect(result.errorCode, equals('EMAIL_EXISTS'));
      expect(result.statusCode, equals(400));

      // Number error
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/register'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(400, {'error': 422}));

      final result2 =
          await authClient.register('test@example.com', 'pass', 'A', 'B');
      expect(result2.success, isFalse);
      expect(result2.error, equals('Request failed (400)'));
    });

    test(
        'deleteAccount(path: "account") without leading slash resolves to {prefix}/account',
        () async {
      final targetUri = Uri.parse('https://api.example.com/auth/account');
      when(() => mockClient.delete(targetUri, headers: any(named: 'headers')))
          .thenAnswer((_) async => jsonResponse(200, {'success': true}));

      final result = await authClient.deleteAccount(path: 'account');
      expect(result.success, isTrue);
      verify(() => mockClient.delete(targetUri, headers: any(named: 'headers')))
          .called(1);
    });

    test(
        'deleteAccount(path: "/api/account?hard=1") preserves query string without encoding ? as %3F',
        () async {
      final targetUri = Uri.parse('https://api.example.com/api/account?hard=1');
      when(() => mockClient.delete(targetUri, headers: any(named: 'headers')))
          .thenAnswer((_) async => jsonResponse(200, {'success': true}));

      final result = await authClient.deleteAccount(path: '/api/account?hard=1');
      expect(result.success, isTrue);
      verify(() => mockClient.delete(targetUri, headers: any(named: 'headers')))
          .called(1);
    });
  });

  group('AuthClient — Issue #31 fixes', () {
    const windowOrigin = 'https://ita.app';
    late List<http.Request> sent;

    /// Builds a NativeAuthClient over a recording MockClient, with the same
    /// CSRF wiring as the web factory (same-origin check on the URL).
    NativeAuthClient build(
      String prefix, {
      TokenStorage? tokenStorage,
      int status = 200,
      String? deleteAccountPath,
    }) {
      sent = [];
      final inner = http_testing.MockClient((r) async {
        sent.add(r);
        return http.Response('{}', status,
            headers: {'content-type': 'application/json'});
      });
      final st = tokenStorage ?? InMemoryTokenStorage();
      final authHttp = AuthHttpClient(
        inner: inner,
        apiPrefix: prefix,
        csrfProvider: (url) =>
            isSameOriginPure(url, prefix, windowOrigin) ? 'CSRF1' : null,
        bearerProvider: st.readAccessToken,
        bearerSetter: st.writeAccessToken,
      );
      return NativeAuthClient(
        AuthOptions(
          apiPrefix: prefix,
          headless: true,
          initializeOnStartup: false,
          deleteAccountPath: deleteAccountPath,
        ),
        authHttp,
        st,
      );
    }

    for (final prefix in ['/api/auth', 'https://ita.app/api/auth']) {
      for (final path in ['//evil.com/x', '/\\evil.com/x', 'javascript:x']) {
        test(
            'deleteAccount(path: "$path") with prefix $prefix is rejected '
            'without any request', () async {
          final client = build(prefix);
          final events = <AuthEventType>[];
          final sub = client.events.listen((e) => events.add(e.type));

          final result = await client.deleteAccount(path: path);
          await Future<void>.delayed(Duration.zero);
          await sub.cancel();

          expect(result.success, isFalse);
          expect(result.errorCode, equals('INVALID_PATH'));
          expect(sent, isEmpty);
          expect(events, isEmpty);
        });
      }

      test(
          'deleteAccountPath option "//evil.com/x" with prefix $prefix is '
          'rejected', () async {
        final client = build(prefix, deleteAccountPath: '//evil.com/x');
        final result = await client.deleteAccount();
        expect(result.errorCode, equals('INVALID_PATH'));
        expect(sent, isEmpty);
      });

      test(
          'httpClient.send() to scheme-relative //evil.com/x with prefix '
          '$prefix carries no CSRF token', () async {
        final client = build(prefix);
        await client.httpClient.delete(Uri.parse('//evil.com/x'));
        expect(sent.single.url.host, equals('evil.com'));
        expect(sent.single.headers.containsKey('X-CSRF-Token'), isFalse);
      });

      test(
          'httpClient.send() to a foreign absolute URL with prefix $prefix '
          'carries no CSRF token, same-origin requests still do', () async {
        final client = build(prefix);
        await client.httpClient.delete(Uri.parse('https://evil.com/x'));
        await client.httpClient.delete(Uri.parse('https://ita.app/api/x'));
        await client.httpClient.delete(Uri.parse('/api/x'));
        expect(sent[0].headers.containsKey('X-CSRF-Token'), isFalse);
        expect(sent[1].headers['X-CSRF-Token'], equals('CSRF1'));
        expect(sent[2].headers['X-CSRF-Token'], equals('CSRF1'));
      });

      test('AuthHttpClient.apiDelete("//evil.com/x") throws with prefix $prefix',
          () async {
        final client = build(prefix);
        await expectLater(
          client.httpClient.apiDelete('//evil.com/x', isAbsolute: true),
          throwsArgumentError,
        );
        await expectLater(
          client.httpClient.apiDelete('//evil.com/x'),
          throwsArgumentError,
        );
        expect(sent, isEmpty);
      });

      test('revokeSession keeps ?, # and / inside the segment ($prefix)',
          () async {
        final client = build(prefix);
        await client.revokeSession('a?b#c');
        await client.revokeSession('a/b');

        final first = sent[0].url;
        expect(first.pathSegments, equals(['api', 'auth', 'sessions', 'a?b#c']));
        expect(first.hasQuery, isFalse);
        expect(first.hasFragment, isFalse);
        expect(first.path, equals('/api/auth/sessions/a%3Fb%23c'));

        final second = sent[1].url;
        expect(second.pathSegments, equals(['api', 'auth', 'sessions', 'a/b']));
        expect(second.path, equals('/api/auth/sessions/a%2Fb'));
      });

      test('unlinkAccount encodes provider and providerAccountId ($prefix)',
          () async {
        final client = build(prefix);
        await client.unlinkAccount('goo/gle', 'id?x=1#f');
        // sent[1] is the /me refresh that follows a successful unlink.
        expect(sent.first.method, equals('DELETE'));
        final url = sent.first.url;
        expect(url.pathSegments,
            equals(['api', 'auth', 'linked-accounts', 'goo/gle', 'id?x=1#f']));
        expect(url.hasQuery, isFalse);
        expect(url.hasFragment, isFalse);
      });
    }

    group('prefix and endpoint are joined by path segments', () {
      final cases = <String, String>{
        'https://ita.app/s': 'https://ita.app/s/sessions',
        'https://ita.app/s/': 'https://ita.app/s/sessions',
        '/s': '/s/sessions',
        '/s/': '/s/sessions',
        'https://ita.app': 'https://ita.app/sessions',
        'https://ita.app/': 'https://ita.app/sessions',
        'https://ita.app:8443/api/auth': 'https://ita.app:8443/api/auth/sessions',
        '/api/auth': '/api/auth/sessions',
      };
      cases.forEach((prefix, expected) {
        test('$prefix + /sessions -> $expected', () async {
          final client = build(prefix);
          await client.getActiveSessions();
          expect(sent.single.url.toString(), equals(expected));
        });
      });

      test(
          'an endpoint that merely starts with the prefix path as a string '
          'is still joined (https://ita.app/a + /about)', () async {
        final client = build('https://ita.app/a');
        await client.httpClient.apiGet('/about');
        expect(sent.single.url.toString(), equals('https://ita.app/a/about'));
      });

      test('absolute and relative prefixes give the same path', () async {
        final abs = build('https://ita.app/api/auth');
        await abs.httpClient.apiGet('/api/auth/me');
        await abs.httpClient.apiGet('/x', queryParameters: {'q': '1'});
        final absPaths = sent.map((r) => '${r.url.path}?${r.url.query}').toList();

        final rel = build('/api/auth');
        await rel.httpClient.apiGet('/api/auth/me');
        await rel.httpClient.apiGet('/x', queryParameters: {'q': '1'});
        final relPaths = sent.map((r) => '${r.url.path}?${r.url.query}').toList();

        expect(absPaths, equals(relPaths));
        expect(relPaths,
            equals(['/api/auth/api/auth/me?', '/api/auth/x?q=1']));
      });
    });

    test(
        'clearLocalSession() with an async storage: awaited, the next request '
        'has no Authorization', () async {
      final slow = SlowTokenStorage()..accessToken = 'OLD';
      final client = build('/api/auth', tokenStorage: slow);

      await client.clearLocalSession();
      expect(slow.accessToken, isNull);

      await client.checkSession();
      expect(sent.first.headers.containsKey('Authorization'), isFalse);
    });

    test(
        'clearLocalSession() with an async storage: not awaited, the next '
        'request still waits for the clear and has no Authorization', () async {
      final slow = SlowTokenStorage()..accessToken = 'OLD';
      final client = build('/api/auth', tokenStorage: slow);
      final events = <AuthEventType>[];
      final sub = client.events.listen((e) => events.add(e.type));

      // ignore: unawaited_futures
      client.clearLocalSession();
      // State is reset synchronously.
      expect(client.state.isAuthenticated, isFalse);

      await client.checkSession();
      await sub.cancel();

      expect(sent.first.headers.containsKey('Authorization'), isFalse);
      expect(events, contains(AuthEventType.loggedOut));
    });

    for (final path in ['', '   ']) {
      test('deleteAccount(path: "$path") falls back to {prefix}/account',
          () async {
        final client = build('https://ita.app/api/auth');
        final result = await client.deleteAccount(path: path);
        expect(result.success, isTrue);
        expect(sent.single.method, equals('DELETE'));
        expect(sent.single.url.toString(),
            equals('https://ita.app/api/auth/account'));
      });
    }

    test('deleteAccount(path: "") uses a non-empty deleteAccountPath option',
        () async {
      final client =
          build('https://ita.app/api/auth', deleteAccountPath: '/api/account');
      await client.deleteAccount(path: '');
      expect(sent.single.url.toString(), equals('https://ita.app/api/account'));
    });

    test('deleteAccountPath option "" falls back to {prefix}/account',
        () async {
      final client = build('/api/auth', deleteAccountPath: '');
      await client.deleteAccount();
      expect(sent.single.url.toString(), equals('/api/auth/account'));
    });

    test('available2faMethods is validated eagerly: non-strings are dropped',
        () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200, {
            'requiresTwoFactor': true,
            'tempToken': 't',
            'available2faMethods': [1, 'totp', null, 'sms', {'x': 1}],
            'requires2FASetup': 'yes',
          }));

      final result = await authClient.login('a@b.c', 'p');
      expect(result.requires2fa, isTrue);
      expect(result.availableMethods, equals(['totp', 'sms']));
      expect(result.requires2FASetup, isFalse);
    });

    test('available2faMethods of the wrong type yields an empty list',
        () async {
      when(() => mockClient.post(
            Uri.parse('https://api.example.com/auth/login'),
            headers: any(named: 'headers'),
            body: any(named: 'body'),
          )).thenAnswer((_) async => jsonResponse(200, {
            'requiresTwoFactor': true,
            'tempToken': 't',
            'available2faMethods': 'totp',
          }));

      final result = await authClient.login('a@b.c', 'p');
      expect(result.requires2fa, isTrue);
      expect(result.availableMethods, isEmpty);
    });

    test('getOAuthUrl encodes the provider segment', () {
      expect(authClient.getOAuthUrl('a/b?c'),
          equals('https://api.example.com/auth/oauth/a%2Fb%3Fc'));
    });
  });
}
