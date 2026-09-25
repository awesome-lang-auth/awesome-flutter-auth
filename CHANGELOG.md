# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 1.10.1

### Changed

- **Renamed to `awesome_flutter_auth`** (formerly `awesome_node_auth_flutter`, whose last version is 1.10.0). To migrate, replace the dependency in `pubspec.yaml` and the `package:` imports: `package:awesome_node_auth_flutter/awesome_node_auth_flutter.dart` becomes `package:awesome_flutter_auth/awesome_flutter_auth.dart`. The library file is now `lib/awesome_flutter_auth.dart`; the rename changes no behaviour.
- The repository moved to the `awesome-lang-auth` organisation: <https://github.com/awesome-lang-auth/awesome-flutter-auth>. `homepage`, `repository`, `issue_tracker` and `documentation` in `pubspec.yaml` follow it.

### Fixed

- `getActiveSessions()` no longer throws against a conforming server ([#21](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/21)). `SessionInfo.fromJson` reads `sessionHandle`, the key the servers send, with a fallback to `handle`; optional fields of an unexpected type become `null` instead of throwing, and an entry with no handle is skipped. `SessionInfo.toJson()` now writes `sessionHandle`. The `GET /sessions` and `DELETE /sessions/<handle>` requests are unchanged.

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
