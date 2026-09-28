# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 1.10.4

### Fixed

- **Token clearing on Native platforms** ([#29](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/29)):
  - `clearLocalSession()` and successful `deleteAccount()` on `NativeAuthClient` now explicitly clear `TokenStorage` and reset `AuthHttpClient._refreshToken`. Subsequent requests do not leak stale `Authorization: Bearer` headers.
- **Robust error message extraction** ([#29](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/29)):
  - `login()` and `register()` now safely inspect non-string `error` values (such as nested objects `{"error": {"message": "..."}}` or numbers `{"error": 500}`) without throwing `_TypeError`. Nested error messages and codes are extracted when present.
- **`deleteAccount(path:)` URL resolution** ([#29](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/29)):
  - Paths without a leading slash (e.g. `deleteAccount(path: 'account')`) are resolved to `{apiPrefix}/account` rather than concatenating without a separator.
  - Paths containing query parameters (e.g. `deleteAccount(path: '/api/account?hard=1')`) preserve the query string instead of percent-encoding `?` into the path (`%3F`).

### Documentation

- Updated README to document `deleteAccountPath`, `clearLocalSession()`, and `AuthResult.statusCode`.
- Added clock synchronization note for `verify()` and `tryVerify()` fallback to `DateTime.now().toUtc()`.

## 1.10.3

### Added

- `AuthResult.statusCode` / `LoginResult.statusCode`: carries the HTTP status code of the failed response ([#27](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/27)).
- `clearLocalSession()` on `AuthClient`: resets local session state (user, tokens) and emits `AuthEventType.loggedOut` without sending network requests or triggering redirects ([#27](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/27)).
- `AuthOptions.deleteAccountPath` and optional `path` parameter on `deleteAccount({String? path})`: enables consumers mounting account deletion at custom endpoints (e.g. root-relative `/api/account`) to use `deleteAccount` with full CSRF protection and automatic local state reset ([#27](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/27)).

### Fixed

- `login()` and `register()` now preserve server error codes and status codes: `errorCode` is extracted from `code` (falling back to `error`), and `error` falls back to `data['error']` when `message` is absent ([#27](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/27)).
- All client operation failures through `BaseAuthClient` consistently populate `statusCode` and `errorCode`.

## 1.10.2

### Added

- **Offline token verification (`package:awesome_flutter_auth/offline_tokens.dart`)** ([#25](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/25)):
  - Offline verification for JWS compact tokens signed with `alg: EdDSA` (Ed25519, RFC 8037 / RFC 8725) against pre-provisioned JWK OKP public keys.
  - Implemented in pure Dart: runs in Flutter (mobile, desktop, web including WASM) as well as standalone Dart applications without Flutter SDK dependencies.
  - Evaluates 10 sequential security checks: malformed structure, algorithm allow-list (`EdDSA` only, rejecting `none`, `HS256`, `Ed25519`), expected `typ`, rejection of `crit` headers, `kid` lookup in key set, canonical Ed25519 signature verification (`S < L`, high bit clear), claim type validation, `aud` check, `iss` check, and expiration check (`exp <= now`) with an injectable clock.
  - Typed failure reasons with `OfflineTokenReason` and `OfflineTokenException` (no `Error` leaks for arbitrary input).
  - Supports JWK OKP key sets via `OkpKeySet.fromJwks()` and SubjectPublicKeyInfo (SPKI) PEM keys via `OkpKey.fromPem()`.
  - Re-exported from root `package:awesome_flutter_auth/awesome_flutter_auth.dart`.

### Changed

- Dropped the `environment.flutter` constraint in `pubspec.yaml`, enabling the package to be resolved and tested in pure Dart environments (`dart pub get` + `dart test`).

## 1.10.1

### Changed

- **Renamed to `awesome_flutter_auth`** (formerly `awesome_node_auth_flutter`, whose last standalone release is 1.10.0). To migrate, replace the dependency in `pubspec.yaml` and the `package:` imports: `package:awesome_node_auth_flutter/awesome_node_auth_flutter.dart` becomes `package:awesome_flutter_auth/awesome_flutter_auth.dart`. The library file is now `lib/awesome_flutter_auth.dart`; the rename changes no behaviour.
- The repository moved to the `awesome-lang-auth` organisation: <https://github.com/awesome-lang-auth/awesome-flutter-auth>. `homepage`, `repository`, `issue_tracker` and `documentation` in `pubspec.yaml` follow it.

### Fixed

- `getActiveSessions()` no longer throws against a conforming server ([#21](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/21)). `SessionInfo.fromJson` reads `sessionHandle`, the key the servers send, with a fallback to `handle`; optional fields of an unexpected type become `null` instead of throwing, an entry with no handle is skipped, and a 200 whose body is not JSON (an HTML fallback page, an empty body) gives an empty list, as `getLinkedAccounts()` already does. `SessionInfo.toJson()` now writes `sessionHandle`. The `GET /sessions` and `DELETE /sessions/<handle>` requests are unchanged.
- `setup2fa()` no longer throws when the server sends no `qrCode`, as awesome-go-auth and awesome-lambda-auth do ([#22](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/22)). A response without a `secret` string now comes back as `AuthResult.failure` instead of an exception. The `POST /2fa/setup` request is unchanged.

### Added

- `TotpSetupData.otpauthUrl`: the `otpauth://` provisioning URI that awesome-node-auth, awesome-go-auth and awesome-lambda-auth send, so an app can draw the QR code itself.

### Documentation

- README, "Forced 2FA enrolment": says what `login()` does today when the servers answer `403 {"requires2FASetup": true, "code": "2FA_SETUP_REQUIRED"}`. It returns a plain failure with `requires2FASetup == false`, `errorCode == null` and no `tempToken`, so enrol a second factor before 2FA becomes mandatory for the account.

### Migration

- `TotpSetupData.qrCode` is now `String?` (it was `String`). Code that passes it where a `String` is expected, such as `Image.network(setup.data!.qrCode)`, needs a null check, with `otpauthUrl` as the fallback.
- `SessionInfo.toJson()` writes the handle under `sessionHandle` (it was `handle`); `SessionInfo.fromJson` still reads either.

## 1.10.0

### Added

- `cleanupSessions()` — calls `POST /auth/sessions/cleanup` to prune expired/invalid sessions from the server store (closes section 7 of the v1.10 parity audit).
- `getOAuthUrl(String provider)` — returns the full OAuth redirect URL for a given provider (e.g. `'github'`, `'google'`). Use this to initiate a redirect-based OAuth flow on web or open the URL in a webview/system browser on native.
- `handleOAuthCallback()` — picks up the authenticated session after a successful OAuth callback. Internally calls `checkSession()` and, on success, emits an `AuthEventType.loggedIn` event.

### Changed

- Version bumped to **1.10.0** to align with `awesome-node-auth` backend v1.10.

### Notes

- **Section 15 (UI widgets)**: this library is intentionally **headless** — no pre-built Flutter widgets are provided. Build your own UI against the `AuthClient` API and `auth.state.userStream`.
- **Background token refresh on app resume**: the library does not hook into the Flutter app lifecycle automatically. Add a call to `auth.checkSession()` inside your `AppLifecycleListener.onResume` (or `WidgetsBindingObserver.didChangeAppLifecycleState`) to restore the session after the app returns to the foreground.
- **Deep-link handling (native)**: wire your platform deep-link handler (Android `intent-filter` / iOS `CFBundleURLTypes`) to call `auth.verifyMagicLink(token)`, `auth.resetPassword(password, token)`, or `auth.verifyEmail(token)` as appropriate. For OAuth callbacks, call `auth.handleOAuthCallback()` once the redirect is complete.

## 1.9.4

- Doc fix: clarify that `requestConflictLinkingEmail` is a semantic alias of `requestLinkingEmail` with identical payload, and that the backend infers the context from the presence or absence of a valid auth token in the request. The `isConflict` field is no longer sent in the request body, but if your backend version supports it, it is safely ignored if unused.

## 1.9.3

- Fixed auth/httpClient wrapper

## 1.9.2

- Added example project with a simple Node.js backend and Flutter frontend demonstrating usage of the package.

## 1.9.1

- README updated to give comprehensive usage instructions.

## 1.9.0

- version bump to 1.9.0, aligned with awesome-node-auth backend v1.9.0

## 1.8.5

- Initial public release, aligned with awesome-node-auth backend v1.8.5.
- Web (WASM-compatible) cookie + CSRF authentication via HttpOnly cookies and `X-CSRF-Token` header, same-origin only.
- Native (iOS, Android, Desktop) Bearer token authentication with pluggable `TokenStorage`.
- Automatic token refresh with concurrent-request deduplication.
- Full API coverage: login, register, logout, 2FA (TOTP / SMS / magic-link), email verification and change, password reset and change, account linking, session management, account deletion.
- `AuthState.userStream` replays the current user to new subscribers immediately upon subscription.
- WASM-compatible: no `dart:html`, no `dart:io`, no native plugins.

## 0.1.0

- Initial release.
- Web (WASM-compatible) cookie + CSRF authentication.
- Native Bearer token authentication with pluggable `TokenStorage`.
- Full API coverage: login, register, 2FA (TOTP/SMS/magic-link), email
  verification, account linking, session management.
