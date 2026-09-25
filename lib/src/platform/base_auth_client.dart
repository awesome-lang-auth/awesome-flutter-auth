import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth_client.dart';
import '../auth_events.dart';
import '../auth_options.dart';
import '../auth_state.dart';
import '../auth_user.dart';
import '../http/auth_http_client.dart';
import '../models/auth_result.dart';
import '../models/session_info.dart';
import '../models/ui_config.dart';

/// Shared implementation of [AuthClient] used by both web and native platform
/// clients. Sub-classes supply a platform-configured [AuthHttpClient] and may
/// override [redirectToLogin] for platform-specific redirect behaviour.
///
/// Note: [options] and [handleLogout] are intentionally non-private so they
/// can be accessed by sub-classes located in other libraries.
abstract class BaseAuthClient implements AuthClient {
  // Non-private so sub-classes in sibling libraries can read them.
  final AuthOptions options;
  @override
  final AuthHttpClient httpClient;

  final AuthState _state = AuthState();
  final StreamController<AuthEvent> _eventsController =
      StreamController<AuthEvent>.broadcast();

  BaseAuthClient(this.options, this.httpClient) {
    httpClient.setRefreshHandler(doRefresh);
    httpClient.setLogoutHandler(
        ({bool revoked = false}) => handleLogout(revoked: revoked));

    if (options.initializeOnStartup) {
      _initialize();
    }
  }

  void _initialize() {
    // Note: `initialized` is emitted regardless of whether checkSession()
    // succeeds or fails. It signals that the first session check has completed,
    // not that the user is authenticated. Check `state.isAuthenticated` separately.
    checkSession().then((_) {
      _state.setInitialized();
      _eventsController.add(const AuthEvent(type: AuthEventType.initialized));
    }).catchError((_) {
      _state.setInitialized();
      _eventsController.add(const AuthEvent(type: AuthEventType.initialized));
    });
  }

  @override
  AuthState get state => _state;

  @override
  Stream<AuthEvent> get events => _eventsController.stream;

  // -------------------------------------------------------------------------
  // Refresh handler
  // -------------------------------------------------------------------------

  Future<bool> doRefresh() => httpClient.callRefreshEndpoint();

  // -------------------------------------------------------------------------
  // Logout handler (accessible from sibling libraries)
  // -------------------------------------------------------------------------

  Future<void> handleLogout({bool revoked = false}) async {
    _state.setUser(null);
    _eventsController.add(AuthEvent(
      type: revoked ? AuthEventType.sessionRevoked : AuthEventType.loggedOut,
    ));

    if (!options.headless) {
      redirectToLogin();
    }
  }

  /// Override in sub-classes to perform a platform-specific redirect.
  void redirectToLogin() {}

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Map<String, dynamic>? _parseBody(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  String _errorMessage(http.Response response) {
    final body = _parseBody(response);
    if (body != null) {
      return (body['message'] as String?) ??
          (body['error'] as String?) ??
          'Request failed (${response.statusCode})';
    }
    return 'Request failed (${response.statusCode})';
  }

  // -------------------------------------------------------------------------
  // Session
  // -------------------------------------------------------------------------

  @override
  Future<AuthUser?> checkSession() async {
    try {
      final response = await httpClient.apiGet('/me');
      if (response.statusCode == 200) {
        final data = _parseBody(response);
        if (data != null) {
          final user = AuthUser.fromJson(data);
          _state.setUser(user);
          return user;
        }
      } else {
        _state.setUser(null);
      }
    } catch (_) {
      _state.setUser(null);
    }
    return null;
  }

  Future<void> _emitLoggedInEvent() async {
    final user = await checkSession();
    if (user != null) {
      _eventsController.add(AuthEvent(type: AuthEventType.loggedIn, user: user));
    }
  }

  @override
  Future<List<SessionInfo>> getActiveSessions() async {
    final response = await httpClient.apiGet('/sessions');
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final list = (data is Map<String, dynamic>) ? data['sessions'] : data;
      if (list is List) {
        final sessions = <SessionInfo>[];
        for (final entry in list.whereType<Map<String, dynamic>>()) {
          try {
            sessions.add(SessionInfo.fromJson(entry));
          } on FormatException {
            // No handle means nothing to show or revoke: skip the entry
            // instead of failing the whole list.
          }
        }
        return sessions;
      }
    }
    return [];
  }

  @override
  Future<AuthResult<void>> revokeSession(String sessionHandle) async {
    final response = await httpClient.apiDelete('/sessions/$sessionHandle');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> cleanupSessions() async {
    final response = await httpClient.apiPost('/sessions/cleanup');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  // -------------------------------------------------------------------------
  // Auth
  // -------------------------------------------------------------------------

  @override
  Future<LoginResult> login(String email, String password) async {
    final response = await httpClient.apiPost(
      '/login',
      body: {'email': email, 'password': password},
    );

    final data = _parseBody(response);

    if (response.statusCode == 200 || response.statusCode == 201) {
      if (data != null && data['requiresTwoFactor'] == true) {
        return LoginResult.requires2FA(
          tempToken: data['tempToken'] as String? ?? '',
          availableMethods:
              (data['available2faMethods'] as List<dynamic>?)?.cast<String>() ??
                  [],
          requires2FASetup: data['requires2FASetup'] as bool? ?? false,
        );
      }

      final user = await checkSession();
      if (user != null) {
        _eventsController
            .add(AuthEvent(type: AuthEventType.loggedIn, user: user));
        return LoginResult.authenticated(user);
      }
    }

    return LoginResult.failure(
      data != null
          ? (data['message'] as String?) ?? 'Login failed'
          : 'Login failed (${response.statusCode})',
    );
  }

  @override
  Future<AuthResult<String>> register(
    String email,
    String password,
    String firstName,
    String lastName,
  ) async {
    final response = await httpClient.apiPost(
      '/register',
      body: {
        'email': email,
        'password': password,
        'firstName': firstName,
        'lastName': lastName,
      },
    );

    final data = _parseBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final userId = data?['userId'] as String? ?? data?['id'] as String?;
      return AuthResult.success(userId);
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<void> logout() async {
    try {
      await httpClient.apiPost('/logout');
    } catch (_) {}
    await handleLogout();
  }

  @override
  Future<AuthResult<void>> updateProfile(
      String firstName, String lastName) async {
    final response = await httpClient.apiPatch(
      '/profile',
      body: {'firstName': firstName, 'lastName': lastName},
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await checkSession();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  // -------------------------------------------------------------------------
  // Password
  // -------------------------------------------------------------------------

  @override
  Future<AuthResult<void>> forgotPassword(String email) async {
    final response =
        await httpClient.apiPost('/forgot-password', body: {'email': email});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> resetPassword(String password, String token) async {
    final response = await httpClient.apiPost(
      '/reset-password',
      body: {'password': password, 'token': token},
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> changePassword(
      String currentPassword, String newPassword) async {
    final response = await httpClient.apiPost(
      '/change-password',
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> setPassword(String password) =>
      changePassword('', password);

  // -------------------------------------------------------------------------
  // Magic link
  // -------------------------------------------------------------------------

  @override
  Future<AuthResult<void>> sendMagicLink(String email) async {
    final response =
        await httpClient.apiPost('/magic-link/send', body: {'email': email});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> verifyMagicLink(String token) async {
    final response =
        await httpClient.apiPost('/magic-link/verify', body: {'token': token});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await _emitLoggedInEvent();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> send2faMagicLink(String tempToken) async {
    final response = await httpClient.apiPost('/magic-link/send',
        body: {'tempToken': tempToken, 'mode': '2fa'});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  // -------------------------------------------------------------------------
  // SMS / OTP
  // -------------------------------------------------------------------------

  @override
  Future<AuthResult<void>> sendSmsLogin(String email) async {
    final response = await httpClient
        .apiPost('/sms/send', body: {'email': email, 'mode': 'login'});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> verifySmsLogin(String userId, String code) async {
    final response = await httpClient.apiPost('/sms/verify',
        body: {'userId': userId, 'code': code, 'mode': 'login'});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await _emitLoggedInEvent();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> send2faSms(String tempToken) async {
    final response = await httpClient
        .apiPost('/sms/send', body: {'tempToken': tempToken, 'mode': '2fa'});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> validateSms(String tempToken, String code) async {
    final response = await httpClient.apiPost('/sms/verify',
        body: {'tempToken': tempToken, 'code': code, 'mode': '2fa'});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await _emitLoggedInEvent();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> addPhone(String phoneNumber) async {
    final response = await httpClient
        .apiPost('/add-phone', body: {'phoneNumber': phoneNumber});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await checkSession();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  // -------------------------------------------------------------------------
  // TOTP
  // -------------------------------------------------------------------------

  @override
  Future<AuthResult<TotpSetupData>> setup2fa() async {
    final response = await httpClient.apiPost('/2fa/setup');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final data = _parseBody(response);
      if (data != null) {
        try {
          return AuthResult.success(TotpSetupData.fromJson(data));
        } on FormatException catch (e) {
          return AuthResult.failure(
              'Unexpected 2FA setup response: ${e.message}');
        }
      }
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> verify2faSetup(String code, String secret) async {
    final response = await httpClient.apiPost(
      '/2fa/verify-setup',
      body: {'token': code, 'secret': secret},
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await checkSession();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> validate2fa(
      String tempToken, String totpCode) async {
    final response = await httpClient.apiPost(
      '/2fa/verify',
      body: {'tempToken': tempToken, 'totpCode': totpCode},
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await _emitLoggedInEvent();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> disable2fa() async {
    final response = await httpClient.apiPost('/2fa/disable');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await checkSession();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  // -------------------------------------------------------------------------
  // Email verification
  // -------------------------------------------------------------------------

  @override
  Future<AuthResult<void>> resendVerificationEmail() async {
    final response = await httpClient.apiPost('/send-verification-email');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> verifyEmail(String token) async {
    final response = await httpClient.apiGet(
      '/verify-email',
      queryParameters: {'token': token},
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await checkSession();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> requestEmailChange(String newEmail) async {
    final response = await httpClient
        .apiPost('/change-email/request', body: {'newEmail': newEmail});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> confirmEmailChange(String token) async {
    final response = await httpClient
        .apiPost('/change-email/confirm', body: {'token': token});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await checkSession();
      _eventsController.add(const AuthEvent(type: AuthEventType.emailChanged));
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  // -------------------------------------------------------------------------
  // Account linking
  // -------------------------------------------------------------------------

  @override
  Future<AuthResult<void>> requestLinkingEmail(
      String email, String provider) async {
    final response = await httpClient
        .apiPost('/link-request', body: {'email': email, 'provider': provider});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> verifyLinkingToken(
      String token, String provider) async {
    final response = await httpClient
        .apiPost('/link-verify', body: {'token': token, 'provider': provider});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await checkSession();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> requestConflictLinkingEmail(
      String email, String provider) async {
    // Semantic alias of requestLinkingEmail — the payload is identical.
    // The backend does not receive a discriminator in the body; it infers the
    // context (standard linking vs. conflict-linking) from the presence or
    // absence of a valid auth token in the request.
    final response = await httpClient.apiPost(
      '/link-request',
      body: {'email': email, 'provider': provider},
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<AuthResult<void>> verifyConflictLinkingToken(String token) async {
    final response = await httpClient.apiPost('/link-verify',
        body: {'token': token, 'loginAfterLinking': true});
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await _emitLoggedInEvent();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  @override
  Future<List<dynamic>> getLinkedAccounts() async {
    final response = await httpClient.apiGet('/linked-accounts');
    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        if (data is List) return data;
      } catch (_) {}
    }
    return [];
  }

  @override
  Future<AuthResult<void>> unlinkAccount(
      String provider, String providerAccountId) async {
    final response = await httpClient
        .apiDelete('/linked-accounts/$provider/$providerAccountId');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      await checkSession();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  // -------------------------------------------------------------------------
  // Account management
  // -------------------------------------------------------------------------

  @override
  Future<AuthResult<void>> deleteAccount() async {
    final response = await httpClient.apiDelete('/account');
    if (response.statusCode >= 200 && response.statusCode < 300) {
      _state.setUser(null);
      _eventsController.add(const AuthEvent(type: AuthEventType.loggedOut));
      if (!options.headless) redirectToLogin();
      return AuthResult.success();
    }
    return AuthResult.failure(_errorMessage(response));
  }

  // -------------------------------------------------------------------------
  // UI config
  // -------------------------------------------------------------------------

  @override
  Future<UiConfig?> loadUiConfig() async {
    try {
      final response = await httpClient.apiGet('/ui/config');
      if (response.statusCode == 200) {
        final data = _parseBody(response);
        if (data != null) return UiConfig.fromJson(data);
      }
    } catch (_) {}
    return null;
  }

  // -------------------------------------------------------------------------
  // OAuth (redirect-based)
  // -------------------------------------------------------------------------

  @override
  String getOAuthUrl(String provider) => '${options.apiPrefix}/oauth/$provider';

  @override
  Future<AuthUser?> handleOAuthCallback() async {
    final user = await checkSession();
    if (user != null) {
      _eventsController.add(AuthEvent(type: AuthEventType.loggedIn, user: user));
    }
    return user;
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  void dispose() {
    _state.dispose();
    _eventsController.close();
    httpClient.close();
  }
}
