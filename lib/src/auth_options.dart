import 'http/token_storage.dart';

/// Configuration options for [AuthClient].
class AuthOptions {
  /// Base path or URL for all auth endpoints.
  ///
  /// Can be relative (`/api/auth`) or absolute (`https://auth.example.com/auth`).
  /// Defaults to `/auth`.
  final String apiPrefix;

  /// URL to redirect to after a successful login. Defaults to `/`.
  final String homeUrl;

  /// URL of the login page. Defaults to `$apiPrefix/ui/login`.
  final String? loginUrl;

  /// When `true`, automatic redirects on session expiry are disabled.
  /// The app should react to [AuthEvent]s instead.
  ///
  /// Defaults to `false`.
  final bool headless;

  /// Whether to call [AuthClient.checkSession] automatically on construction.
  ///
  /// Defaults to `true`.
  final bool initializeOnStartup;

  /// Custom token storage for native platforms.
  ///
  /// Defaults to [InMemoryTokenStorage] when not provided.
  final TokenStorage? tokenStorage;

  /// Custom path or endpoint for deleting accounts.
  ///
  /// Defaults to `null`, which falls back to `'/account'` (relative to [apiPrefix]).
  /// When set to an absolute or root-relative path (e.g. `'/api/account'`),
  /// it overrides [apiPrefix].
  final String? deleteAccountPath;

  const AuthOptions({
    this.apiPrefix = '/auth',
    this.homeUrl = '/',
    this.loginUrl,
    this.headless = false,
    this.initializeOnStartup = true,
    this.tokenStorage,
    this.deleteAccountPath,
  });

  /// Returns the effective login URL (defaults to `$apiPrefix/ui/login`).
  String get effectiveLoginUrl => loginUrl ?? '$apiPrefix/ui/login';
}
