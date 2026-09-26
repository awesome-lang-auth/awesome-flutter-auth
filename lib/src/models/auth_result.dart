import '../auth_user.dart';

/// Generic result type for auth operations.
///
/// [T] is the type of the success data payload.
class AuthResult<T> {
  /// Whether the operation succeeded.
  final bool success;

  /// The data payload on success, or `null` on failure.
  final T? data;

  /// A human-readable error message on failure, or `null` on success.
  final String? error;

  /// An optional machine-readable error code (e.g. `"SESSION_REVOKED"`).
  final String? errorCode;

  const AuthResult._({
    required this.success,
    this.data,
    this.error,
    this.errorCode,
  });

  /// Creates a successful result with optional [data].
  factory AuthResult.success([T? data]) =>
      AuthResult._(success: true, data: data);

  /// Creates a failed result with the given [error] message and optional [errorCode].
  factory AuthResult.failure(String error, {String? errorCode}) =>
      AuthResult._(success: false, error: error, errorCode: errorCode);

  @override
  String toString() =>
      'AuthResult(success: $success, data: $data, error: $error)';
}

/// Result returned by [AuthClient.login].
class LoginResult extends AuthResult<AuthUser> {
  /// Whether the login requires a two-factor authentication step.
  final bool requires2fa;

  /// Whether the user needs to set up 2FA before proceeding.
  ///
  /// Set only from a 200/201 login answer that carries both
  /// `requiresTwoFactor: true` and `requires2FASetup: true`. The
  /// awesome-lang-auth servers answer a forced enrolment with
  /// `403 {"requires2FASetup": true, "code": "2FA_SETUP_REQUIRED"}` instead,
  /// which `AuthClient.login()` returns as a plain failure with this flag
  /// `false`.
  final bool requires2FASetup;

  /// Temporary token used to complete the 2FA flow.
  final String? tempToken;

  /// The 2FA methods available to the user (e.g. `['totp', 'sms', 'magic-link']`).
  final List<String> availableMethods;

  const LoginResult._({
    required super.success,
    super.data,
    super.error,
    super.errorCode,
    this.requires2fa = false,
    this.requires2FASetup = false,
    this.tempToken,
    this.availableMethods = const [],
  }) : super._();

  factory LoginResult.authenticated(AuthUser user) => LoginResult._(
        success: true,
        data: user,
      );

  factory LoginResult.requires2FA({
    required String tempToken,
    required List<String> availableMethods,
    bool requires2FASetup = false,
  }) =>
      LoginResult._(
        success: true,
        requires2fa: true,
        requires2FASetup: requires2FASetup,
        tempToken: tempToken,
        availableMethods: availableMethods,
      );

  factory LoginResult.failure(String error, {String? errorCode}) =>
      LoginResult._(success: false, error: error, errorCode: errorCode);
}

/// Data returned when setting up TOTP two-factor authentication.
class TotpSetupData {
  /// The TOTP secret key, for manual entry in an authenticator app.
  final String secret;

  /// The `otpauth://totp/...` provisioning URI.
  ///
  /// Render your own QR code from it when [qrCode] is `null`. The
  /// awesome-lang-auth servers send it; it is `null` only when a server
  /// leaves it out.
  final String? otpauthUrl;

  /// A PNG data URL of the QR code, when the server renders one.
  ///
  /// awesome-node-auth sends it; awesome-go-auth and awesome-lambda-auth do
  /// not, so fall back to [otpauthUrl] or [secret].
  final String? qrCode;

  const TotpSetupData({required this.secret, this.otpauthUrl, this.qrCode});

  /// Builds a [TotpSetupData] from the `POST /2fa/setup` response.
  ///
  /// Throws a [FormatException] when `secret` is missing or not a string;
  /// `otpauthUrl` and `qrCode` are `null` when missing or not strings.
  factory TotpSetupData.fromJson(Map<String, dynamic> json) {
    final secret = json['secret'];
    if (secret is! String) {
      throw const FormatException(
          'TotpSetupData: the response has no "secret" string');
    }
    final otpauthUrl = json['otpauthUrl'];
    final qrCode = json['qrCode'];
    return TotpSetupData(
      secret: secret,
      otpauthUrl: otpauthUrl is String ? otpauthUrl : null,
      qrCode: qrCode is String ? qrCode : null,
    );
  }
}
