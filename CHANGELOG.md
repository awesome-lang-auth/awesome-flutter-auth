# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Fixed

- **`AuthState.userStream` no longer loses or delays state changes** ([#36](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/36)):
  - `userStream` was an `async*` generator. It read the current user and subscribed to the changes only once the generator body had run, some microtasks after `listen`. A `setUser` in that window was lost, and the first value could already be the newer user instead of the one at `listen` time. This happened on every platform; the window differs between the VM, dart2js and dart2wasm.
  - Each change also went through extra asynchronous hops. Under dart2js the `null` from `logout()` had not arrived yet when `logout()` completed, so a subscription cancelled right after it missed the logout.
  - Apps that listen to `userStream` right after creating the client (for example a `StreamBuilder` in the first frame while the startup session check runs) could miss the initial login or logout.
  - `userStream` now reads the current user and subscribes to the changes synchronously in `listen`, and forwards each change as soon as the state delivers it. The first event is still delivered asynchronously, and every event arrives in order. Pause, resume and cancel are forwarded, and `dispose()` still closes the stream.
- **No refresh for a late 401/403 after the session ended** ([#33](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/33)):
  - A request still in flight when `logout()`, `clearLocalSession()` or a successful `deleteAccount()` ended the session could get 401/403 (for example 403 `No access token provided`) after the server had cleared the cookies. The client then sent `POST /refresh`, on web without `X-CSRF-Token` because the csrf cookie was gone, and emitted a second `loggedOut` event when that refresh failed.
  - Once the session has ended locally (`logout()`, `clearLocalSession()`, a successful `deleteAccount()`, a failed refresh), a 401/403 is returned to the caller unchanged until the next successful `GET /me`: no refresh, no retry, no `loggedOut` or `sessionRevoked` event. This covers requests in flight when the session ended and requests started afterwards, such as route guards, polling or `checkSession()`. Every login flow ends with `GET /me`, so the next login restores the usual refresh. This applies to the `api*` methods and to `httpClient.send()`, on web and native.
  - `logout()` marks the session as ended before it sends `POST /logout`, because the server can clear the cookies before its response arrives.
  - A refresh in flight when the session ends has its result dropped: on native its tokens are no longer written back to the cleared `TokenStorage` or kept in memory, so a logged-out app no longer sends a fresh `Authorization` header or resumes the session on the next start. The original request is not retried, and the logout callback is not called again. A request of a new session no longer joins a refresh started for the ended one.
  - `logout()` waits for a refresh in flight before it sends `POST /logout`, so the server revokes the refreshed session. On web the browser stores the refresh response's cookies itself and the client cannot undo that; `clearLocalSession()`, which is local, does not wait, so on web those cookies can still be stored after it.
  - A retry is not sent when the session ended while its headers were being read.
  - A refresh with no csrf cookie is still sent when the session was not ended locally. The csrf cookie expires with the access token while the refresh cookie lives on, and `/refresh` is CSRF-exempt on the servers, so this refresh is how an idle web session resumes.
- **`logout()` sends the refresh token on native** ([#33](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/33)): in bearer mode `POST /logout` carries `{"refreshToken": "..."}`, read before the local tokens are cleared, so the server can revoke the session even when the access token has expired. Both servers accept it. Cookie mode sends no body, as before.

### Changed

- When several requests get 401/403 and share one refresh that fails, `loggedOut` is emitted once instead of once per request.
- When a refresh fails while `logout()` waits for it, `logout()` sends `POST /logout` but emits no second `loggedOut`.
- A request of an ended session whose 401/403 arrives after a new login is returned unchanged instead of being refreshed with the new session.
- The wire protocol is unchanged apart from the optional `refreshToken` in the native `POST /logout` body.

### Tests

- Added `test/auth_state_test.dart`: no change is lost when made right after `listen`, changes are delivered one microtask after `setUser`, late and multiple subscribers, pause, and `dispose()`.
- The test "userStream emits user on login and null on logout" now checks the exact sequence (null, user, null).
- CI runs the whole suite on Chrome with dart2js again, not only the offline token tests.
- A request in flight across `logout()`, `clearLocalSession()` and `deleteAccount()`, in cookie mode and native, through `apiGet` and `httpClient.get`, resolved with 403 `No access token provided`: no `POST /refresh`, the original error is returned, one `loggedOut` event. The mock server fails `/refresh` once the session is gone, as the real servers do, so the event count is checked.
- Cookie mode with the csrf cookie cleared by logout: no `POST /refresh` (and no other unsafe request) without `X-CSRF-Token` is sent.
- A refresh in flight across `clearLocalSession()` and `logout()`: no token written back (native), `logout()` sends `POST /logout` only after the refresh, with the refreshed token in the body (native).
- A request of a new session does not join the ended session's refresh; a retry is not sent when the session ends while its headers are read.
- Two 401s sharing one failed refresh: one refresh, one `loggedOut`.
- After logout with no new login, a 401/403 and `checkSession()` do not refresh and emit no second `loggedOut`; after a new login a 401 refreshes as before.
- `logout()` sends the refresh token in the body on native and no body in cookie mode.
- Regression guard: with no logout and an expired csrf cookie the client still refreshes and retries.

## 1.10.6

### Fixed

- **`OfflineTokenVerifier` works under dart2wasm** ([#34](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/34)):
  - Under `flutter build web --wasm` every token was rejected with `signature_invalid: Ed25519 verification internal error`.
  - The cause was `ed25519_edwards`. It does its arithmetic through `adaptive_number`, whose conditional import has no dart2wasm branch, so every operation threw `UnsupportedError`.
  - Ed25519 verification now uses the TweetNaCl arithmetic of `pinenacl`. It is pure Dart and synchronous, and it gives the same result on the VM, dart2js and dart2wasm.
  - The public API and the order of the checks are unchanged.

### Changed

- **New direct dependency: `pinenacl` ^0.6.0**, which replaces `ed25519_edwards`. `pinenacl` has no dependencies, so this drops five packages from the dependency graph: `ed25519_edwards`, `adaptive_number`, `fixnum`, `convert` and `crypto`.
  - An app or package that already depends on `pinenacl` below 0.6 gets a version-solving conflict with this release.

### Tests

- Added the RFC 8032 section 7.1 Ed25519 vectors.
- Added the licence token vectors, with the outcome recorded on the VM before the change: valid, next-kid, expired, wrong-alg, wrong-aud, tampered, tier-*, next-tier-* and trial-premium.
- Added negative cases: wrong key, tampered payload, a flipped bit in R or S, and non-canonical S (S + L on the tokens; S + L and S = L on the Ed25519 check itself).
- All of these run on the VM, on Chrome with dart2js and on Chrome with dart2wasm.
- CI has a `web` job that runs the suite on Chrome with dart2wasm, and the offline token tests with dart2js (the rest of the suite has a known dart2js-only test failure in `test/auth_client_test.dart`, unrelated to this change).

## 1.10.5

### Security

- **CSRF token never sent to a scheme-relative or foreign URI** ([#31](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/31)):
  - `isSameOriginPure` treats a scheme-relative URL (`//host/...`) as cross-origin, including one pointing at the same host.
  - `AuthHttpClient` takes the CSRF decision on the URI that is actually sent. `httpClient.send()` used to rebuild `request.url` under the API prefix, so `//evil.com/x` passed the same-origin check as `/x`. It never calls the CSRF provider for a scheme-relative target.
  - `deleteAccount(path:)` and `AuthOptions.deleteAccountPath` reject scheme-relative paths (`//evil.com/x`, and `/\evil.com/x`, which `Uri.parse` normalises to `//evil.com/x`) and non-http(s) schemes. They return `AuthResult.failure` with `errorCode: 'INVALID_PATH'` and send no request.
  - `apiGet`/`apiPost`/`apiPatch`/`apiDelete` throw `ArgumentError` for a scheme-relative path.

### Fixed

- **Path segments encoded again** ([#31](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/31)): `revokeSession()` and `unlinkAccount()` encode the interpolated segments (session handle, provider, providerAccountId) with `Uri.encodeComponent`. A `?`, `#` or `/` in an id now stays inside its segment instead of becoming a query, fragment or extra segment; this was a regression since 1.10.2. `getOAuthUrl()` encodes the provider segment too.
- **Prefix and endpoint joined by path segments** ([#31](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/31)): the prefix path segments and the endpoint path segments are joined, with the same result for absolute and relative prefixes. Before, with an absolute prefix, the prefix was skipped when the endpoint merely started with the prefix path as a string: `https://ita.app/s` + `/sessions` resolved to `https://ita.app/sessions` and now resolves to `https://ita.app/s/sessions`.
- **`NativeAuthClient.clearLocalSession()` awaits the token storage** ([#31](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/31)):
  - It awaits `TokenStorage.clear()` and returns a `Future` that completes once the storage is cleared.
  - Requests issued before then wait for the clear even if the call is not awaited, so they never carry the old `Authorization: Bearer` header with an asynchronous storage.
  - User state and the `loggedOut` event are still updated synchronously.
- **`deleteAccount(path: '')` falls back to `/account`** ([#31](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/31)): an empty or blank `path` (or `AuthOptions.deleteAccountPath`) is treated as unset. It falls back to `deleteAccountPath` if that is set, otherwise to `{apiPrefix}/account`.
- **`available2faMethods` validated eagerly** ([#31](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/31)): non-string entries are dropped and a non-list value yields an empty list. Reading `LoginResult.availableMethods` no longer throws. A non-boolean `requires2FASetup` reads as `false` instead of throwing.

### Changed

- **`AuthClient.clearLocalSession()` returns `Future<void>`** (was `void`). Existing calls such as `auth.clearLocalSession();` still compile. Classes that implement or override `clearLocalSession()` with a `void` return type must change it to `Future<void>`.
- **Endpoint paths are no longer de-duplicated against an absolute prefix.** With an absolute prefix, `httpClient.apiGet('/api/auth/me')` used to resolve to `https://host/api/auth/me` when the prefix was `https://host/api/auth`. It now resolves to `https://host/api/auth/api/auth/me`, the same as with a relative prefix. Pass paths relative to the prefix (`/me`), or use a full URL.

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
