import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';

import 'package:awesome_flutter_auth/src/http/auth_http_client.dart';
import 'package:awesome_flutter_auth/src/http/token_storage.dart';
import 'package:awesome_flutter_auth/src/auth_events.dart';
import 'package:awesome_flutter_auth/src/auth_options.dart';
import 'package:awesome_flutter_auth/src/auth_user.dart';
import 'package:awesome_flutter_auth/src/models/auth_result.dart';
import 'package:awesome_flutter_auth/src/models/session_info.dart';
import 'package:awesome_flutter_auth/src/platform/native_auth_client.dart';

class MockHttpClient extends Mock implements http.Client {}

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
}
