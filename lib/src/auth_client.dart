import 'dart:async';

import 'package:http/http.dart' as http;

import 'auth_events.dart';
import 'auth_options.dart';
import 'auth_state.dart';
import 'auth_user.dart';
import 'models/auth_result.dart';
import 'models/session_info.dart';
import 'models/ui_config.dart';
import 'platform/native_auth_client.dart'
    if (dart.library.js_interop) 'platform/web_auth_client.dart' as platform;

/// Abstract authentication client.
///
/// Use the factory constructor to obtain a platform-appropriate implementation:
///
/// ```dart
/// final auth = AuthClient(AuthOptions(apiPrefix: '/api/auth'));
/// await auth.checkSession();
/// ```
abstract class AuthClient {
  /// Creates a platform-appropriate [AuthClient].
  ///
  /// - On **web** (including WASM): uses cookie-based auth with CSRF protection.
  /// - On **native** (iOS, Android, Desktop): uses Bearer token with
  ///   [InMemoryTokenStorage] (or a custom [TokenStorage]).
  factory AuthClient(
    AuthOptions options, {
    http.Client? httpClient,
  }) {
    return platform.createAuthClient(options, httpClient: httpClient);
  }

  // ---------------------------------------------------------------------------
  // State & events
  // ---------------------------------------------------------------------------

  /// Reactive authentication state (current user, initialization flag).
  AuthState get state;

  /// Stream of lifecycle events (login, logout, session expiry, etc.).
  Stream<AuthEvent> get events;

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  /// Checks the current session with the backend and updates [state].
  ///
  /// Returns the authenticated [AuthUser] or `null` when not authenticated.
  Future<AuthUser?> checkSession();

  /// Returns a list of all active sessions for the current user.
  ///
  /// Calls `GET $apiPrefix/sessions`. Returns an empty list when the server
  /// answers anything but 200, and skips any entry that carries no
  /// `sessionHandle`: see [SessionInfo.fromJson].
  Future<List<SessionInfo>> getActiveSessions();

  /// Revokes the session identified by [sessionHandle].
  Future<AuthResult<void>> revokeSession(String sessionHandle);

  /// Removes all expired and invalid sessions from the server store.
  ///
  /// Calls `POST $apiPrefix/sessions/cleanup`. Useful to call periodically
  /// or from a session-management UI to prune stale entries.
  Future<AuthResult<void>> cleanupSessions();

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// Authenticates the user with [email] and [password].
  ///
  /// On success, updates [state] with the authenticated user.
  /// When two-factor authentication is required, [LoginResult.requires2fa] is
  /// `true` and [LoginResult.tempToken] contains the temporary token.
  Future<LoginResult> login(String email, String password);

  /// Registers a new account and returns the new user's ID.
  Future<AuthResult<String>> register(
    String email,
    String password,
    String firstName,
    String lastName,
  );

  /// Logs the current user out and clears [state].
  Future<void> logout();

  /// Updates the current user's profile.
  Future<AuthResult<void>> updateProfile(String firstName, String lastName);

  // ---------------------------------------------------------------------------
  // Password
  // ---------------------------------------------------------------------------

  /// Initiates the password-recovery flow for [email].
  Future<AuthResult<void>> forgotPassword(String email);

  /// Resets the password using a one-time [token] obtained from the recovery email.
  Future<AuthResult<void>> resetPassword(String password, String token);

  /// Changes the authenticated user's password.
  Future<AuthResult<void>> changePassword(
      String currentPassword, String newPassword);

  /// Sets a password for an account that currently has none.
  ///
  /// Calls [changePassword] with an empty string as the current password.
  Future<AuthResult<void>> setPassword(String password);

  // ---------------------------------------------------------------------------
  // Magic link
  // ---------------------------------------------------------------------------

  Future<AuthResult<void>> sendMagicLink(String email);
  Future<AuthResult<void>> verifyMagicLink(String token);
  Future<AuthResult<void>> send2faMagicLink(String tempToken);

  // ---------------------------------------------------------------------------
  // SMS / OTP
  // ---------------------------------------------------------------------------

  Future<AuthResult<void>> sendSmsLogin(String email);
  Future<AuthResult<void>> verifySmsLogin(String userId, String code);
  Future<AuthResult<void>> send2faSms(String tempToken);
  Future<AuthResult<void>> validateSms(String tempToken, String code);
  Future<AuthResult<void>> addPhone(String phoneNumber);

  // ---------------------------------------------------------------------------
  // TOTP (2FA)
  // ---------------------------------------------------------------------------

  /// Starts TOTP enrolment: calls `POST $apiPrefix/2fa/setup`.
  ///
  /// On success the data carries the `secret`, the `otpauthUrl` and, when
  /// the server renders one, the `qrCode`. A response with no `secret`
  /// string is returned as a failure, not thrown.
  Future<AuthResult<TotpSetupData>> setup2fa();
  Future<AuthResult<void>> verify2faSetup(String code, String secret);
  Future<AuthResult<void>> validate2fa(String tempToken, String totpCode);
  Future<AuthResult<void>> disable2fa();

  // ---------------------------------------------------------------------------
  // Email verification
  // ---------------------------------------------------------------------------

  Future<AuthResult<void>> resendVerificationEmail();
  Future<AuthResult<void>> verifyEmail(String token);
  Future<AuthResult<void>> requestEmailChange(String newEmail);
  Future<AuthResult<void>> confirmEmailChange(String token);

  // ---------------------------------------------------------------------------
  // Account linking
  // ---------------------------------------------------------------------------

  Future<AuthResult<void>> requestLinkingEmail(String email, String provider);
  Future<AuthResult<void>> verifyLinkingToken(String token, String provider);
  Future<AuthResult<void>> requestConflictLinkingEmail(
      String email, String provider);
  Future<AuthResult<void>> verifyConflictLinkingToken(String token);
  Future<List<dynamic>> getLinkedAccounts();
  Future<AuthResult<void>> unlinkAccount(
      String provider, String providerAccountId);

  // ---------------------------------------------------------------------------
  // Account management
  // ---------------------------------------------------------------------------

  Future<AuthResult<void>> deleteAccount();

  // ---------------------------------------------------------------------------
  // Authenticated HTTP client (interceptor / guard)
  // ---------------------------------------------------------------------------

  /// An [http.Client] that transparently handles authentication for every
  /// request to the backend \u2014 analogous to an Angular `HttpInterceptor`.
  ///
  /// - **Web / WASM**: attaches the CSRF token for same-origin requests;
  ///   the browser manages HttpOnly cookies automatically.
  /// - **Native**: attaches `Authorization: Bearer <token>` and
  ///   `X-Auth-Strategy: bearer`; silently refreshes the token on 401 / 403.
  ///
  /// Use this client for all your own backend API calls so authentication
  /// is handled without any additional setup:
  ///
  /// ```dart
  /// final response = await auth.httpClient.get(Uri.parse('$api/todos'));
  /// ```
  http.Client get httpClient;

  // ---------------------------------------------------------------------------
  // OAuth (redirect-based)
  // ---------------------------------------------------------------------------

  /// Returns the OAuth redirect URL for the given [provider].
  ///
  /// Redirect the user (or open a webview/system browser on native) to this URL
  /// to initiate the OAuth login flow. After the callback, call
  /// [handleOAuthCallback] to pick up the new session.
  ///
  /// Example:
  /// ```dart
  /// final url = auth.getOAuthUrl('github');
  /// // Web: redirect the browser
  /// // Native: open url in a webview or system browser
  /// ```
  String getOAuthUrl(String provider);

  /// Picks up the authenticated session after a successful OAuth callback.
  ///
  /// Call this once the OAuth provider has redirected back to your app (e.g.
  /// in the deep-link or post-redirect handler). Internally calls
  /// [checkSession] and, on success, emits a [AuthEventType.loggedIn] event.
  ///
  /// Returns the authenticated [AuthUser], or `null` when the session could
  /// not be established.
  Future<AuthUser?> handleOAuthCallback();

  // ---------------------------------------------------------------------------
  // Streaming & UI config
  // ---------------------------------------------------------------------------

  /// Returns a server-sent-events stream from `$apiPrefix/tools/stream`.
  ///
  /// On native platforms this returns [Stream.empty].
  Stream<String> getToolsStream();

  /// Loads the backend UI configuration from `$apiPrefix/ui/config`.
  Future<UiConfig?> loadUiConfig();
}
