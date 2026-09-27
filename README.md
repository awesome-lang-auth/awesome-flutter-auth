# awesome_flutter_auth

[![pub.dev](https://img.shields.io/pub/v/awesome_flutter_auth.svg)](https://pub.dev/packages/awesome_flutter_auth)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![WASM ready](https://img.shields.io/badge/WASM-ready-green.svg)]()

Flutter/Dart authentication client for [awesome-lang-auth](https://github.com/awesome-lang-auth) servers: [awesome-node-auth](https://github.com/awesome-lang-auth/awesome-node-auth) and the ports that speak its wire contract, such as [awesome-go-auth](https://github.com/awesome-lang-auth/awesome-go-auth) and [awesome-lambda-auth](https://github.com/awesome-lang-auth/awesome-lambda-auth).

Supports **web** (including WASM) via HttpOnly cookies + CSRF, and **native** (iOS, Android, Desktop) via Bearer token.

---

## Table of Contents

1. [Installation](#installation)
2. [Quick start](#quick-start)
3. [Examples](#examples)
4. [Platform behaviour](#platform-behaviour)
5. [AuthOptions](#authoptions)
6. [AuthState & userStream](#authstate--userstream)
7. [Events stream](#events-stream)
8. [Registration](#registration)
9. [Login & 2FA](#login--2fa)
10. [Two-factor authentication (2FA)](#two-factor-authentication-2fa)
11. [Password management](#password-management)
12. [Email management](#email-management)
13. [Active sessions](#active-sessions)
14. [OAuth (redirect-based)](#oauth-redirect-based)
15. [Account linking](#account-linking)
16. [AuthUser model](#authuser-model)
17. [AuthResult\<T\>](#authresultt)
18. [Custom TokenStorage](#custom-tokenstorage)
19. [Internal behaviour — automatic refresh](#internal-behaviour--automatic-refresh)
20. [Headless mode](#headless-mode)
21. [Authenticated HTTP client (interceptor)](#authenticated-http-client-interceptor)
22. [SSE stream](#sse-stream)
23. [UI config](#ui-config)
24. [WASM compatibility](#wasm-compatibility)
25. [Offline token verification](#offline-token-verification)
26. [License](#license)

---

## Installation

```bash
flutter pub add awesome_flutter_auth
```

or add it to `pubspec.yaml` yourself:

```yaml
dependencies:
  awesome_flutter_auth: ^1.10.1
```

> **Formerly `awesome_node_auth_flutter`:** replace the dependency and the `package:` imports: `package:awesome_node_auth_flutter/awesome_node_auth_flutter.dart` becomes `package:awesome_flutter_auth/awesome_flutter_auth.dart`. `TotpSetupData.qrCode` is now `String?` (awesome-go-auth and awesome-lambda-auth do not send it); fall back to `otpauthUrl`. The [CHANGELOG](CHANGELOG.md) lists the other 1.10.1 changes.

---

## Quick start

```dart
import 'package:awesome_flutter_auth/awesome_flutter_auth.dart';

// 1. Create the client (checkSession is called automatically)
final auth = AuthClient(AuthOptions(apiPrefix: '/api/auth'));

// 2. React to state changes
auth.state.userStream.listen((user) {
  if (user != null) {
    print('Logged in: ${user.email}');
  } else {
    print('Not authenticated');
  }
});

// 3. Login
final result = await auth.login('user@example.com', 'password');
if (result.success && !result.requires2fa) {
  print('Welcome, ${result.data?.firstName}');
} else if (result.requires2fa) {
  // Proceed to the 2FA step — see the Login & 2FA section
}
```

---

## Examples

A complete **working example** with Flutter app + Node.js backend is available in the [`example/`](example/) directory.

### Run the Example

**1. Start the Node.js server** (in-memory user store):
```bash
cd example/server
npm install
npm start
# Runs on http://localhost:3000
```

**2. Run the Flutter app**:
```bash
cd example
flutter pub get
flutter run
```

**Test with demo credentials:**
- Email: `demo@example.com`
- Password: `demo123`

See [example/README.md](example/README.md) for full setup guide, architecture diagram, API endpoints, and customization options.

---

## Platform behaviour

| Platform | Auth mode | Token management | CSRF |
|---|---|---|---|
| Web / WASM | Cookie (HttpOnly) | Browser automatic | `X-CSRF-Token` same-origin only |
| iOS / Android / Desktop | Bearer token | `TokenStorage` (in-memory default) | N/A |

On **web** the browser handles cookie storage. The client reads the CSRF token from `document.cookie` and attaches the `X-CSRF-Token` header to every same-origin mutating request.

On **native** platforms the access token is stored in `TokenStorage` (default: `InMemoryTokenStorage`). Provide a custom implementation backed by `flutter_secure_storage` for persistence across app restarts.

---

## AuthOptions

All constructor parameters are optional; sensible defaults are provided.

```dart
final auth = AuthClient(
  AuthOptions(
    apiPrefix: '/api/auth',          // Relative or absolute base URL for auth endpoints (default: '/auth')
    homeUrl: '/',                    // Redirect destination after successful login (default: '/')
    loginUrl: '/login',              // Redirect destination when session expires (web, headless: false only)
                                     // Defaults to '$apiPrefix/ui/login' when omitted
    headless: false,                 // true = disable automatic redirects; listen to events instead
    initializeOnStartup: true,       // Calls checkSession() automatically on construction (default: true)
    tokenStorage: MySecureStorage(), // Native only: custom persistent storage for Bearer tokens
  ),
);

// If initializeOnStartup is false, call checkSession() explicitly:
await auth.checkSession();
```

> **⚠️ Race condition with `initializeOnStartup: true`**
>
> `initializeOnStartup: true` (the default) calls `checkSession()` as a fire-and-forget
> task in the constructor — Dart constructors cannot `await` it. If you make authenticated
> calls immediately after constructing `AuthClient`, the session may not be loaded yet and
> you could receive unexpected 401 responses.
>
> **Option 1 — wait for the `initialized` event before making authenticated calls:**
> ```dart
> await auth.events.firstWhere((e) => e.type == AuthEventType.initialized);
> // Now safe to make authenticated calls
> ```
>
> **Option 2 — disable `initializeOnStartup` and `await` explicitly:**
> ```dart
> final auth = AuthClient(AuthOptions(
>   apiPrefix: '/api/auth',
>   initializeOnStartup: false,
> ));
> await auth.checkSession(); // explicit await before use
> ```

---

## AuthState & userStream

`auth.state` is the reactive authentication state object. It exposes:

| Member | Type | Description |
|---|---|---|
| `userStream` | `Stream<AuthUser?>` | Emits the current user on every change. **Replays the current value** to new subscribers immediately. |
| `currentUser` | `AuthUser?` | Synchronous access to the current user. |
| `isAuthenticated` | `bool` | `true` when a user is signed in. |
| `isInitialized` | `bool` | `true` after the first `checkSession()` call completes. |

### StreamBuilder (Flutter)

```dart
StreamBuilder<AuthUser?>(
  stream: auth.state.userStream,
  builder: (context, snapshot) {
    final user = snapshot.data;
    if (!auth.state.isInitialized) {
      return const CircularProgressIndicator();
    }
    if (user == null) {
      return const LoginPage();
    }
    return HomePage(user: user);
  },
);
```

### Synchronous access

```dart
if (auth.state.isAuthenticated) {
  final user = auth.state.currentUser!;
  print(user.email);
}
```

> **Note:** `userStream` is implemented with `async*` + `yield` so it always replays the latest value to new subscribers before emitting future changes.

---

## Events stream

`auth.events` is a broadcast stream of `AuthEvent` objects. Subscribe to it to react to lifecycle changes outside the UI tree (e.g. in a GoRouter redirect, background service, or logging layer).

```dart
auth.events.listen((event) {
  switch (event.type) {
    case AuthEventType.initialized:
      // First checkSession() completed (success or failure)
      print('Auth ready. User: ${event.user?.email}');
    case AuthEventType.loggedIn:
      // User authenticated successfully
      print('Logged in as ${event.user?.email}');
    case AuthEventType.loggedOut:
      // User logged out (manually or after a failed refresh)
      print('Logged out');
    case AuthEventType.sessionExpired:
      // Access token refresh failed — session is gone
      print('Session expired');
    case AuthEventType.sessionRevoked:
      // Backend returned SESSION_REVOKED — forced logout
      print('Session was revoked server-side');
    case AuthEventType.emailChanged:
      // User confirmed an email address change
      print('Email changed — new address: ${auth.state.currentUser?.email}');
  }
});
```

| Event type | Trigger |
|---|---|
| `initialized` | First `checkSession()` completed (regardless of outcome) |
| `loggedIn` | Successful login, magic-link / SMS / TOTP verification, OAuth callback, or conflict-linking resolution |
| `loggedOut` | Explicit `logout()` or failed token refresh |
| `sessionExpired` | Token refresh call returned a non-2xx response |
| `sessionRevoked` | Backend returned `{ "code": "SESSION_REVOKED" }` |
| `emailChanged` | User successfully confirmed an email address change via `confirmEmailChange()` |

> **Note:** The `initialized` event is emitted whether `checkSession()` succeeds **or** fails
> (e.g. network error, 401 on startup). It only signals that the first session check has
> completed — not that the user is authenticated. Always check `auth.state.isAuthenticated`
> or the `event.user` value before treating the session as valid.

---

## Registration

```dart
final result = await auth.register(
  'user@example.com', // email
  'strongPassword1!', // password
  'Jane',             // firstName
  'Doe',              // lastName
);

if (result.success) {
  print('New user ID: ${result.data}');
} else {
  print('Registration failed: ${result.error}');
}
```

---

## Login & 2FA

### Simple login (no 2FA)

```dart
final result = await auth.login('user@example.com', 'password');

if (result.success && !result.requires2fa) {
  // Authenticated — state is already updated
  print('Welcome ${result.data?.firstName}');
} else if (!result.success) {
  print('Login failed: ${result.error}');
}
```

### Login with 2FA required

```dart
final result = await auth.login('user@example.com', 'password');

if (result.success && !result.requires2fa) {
  // Direct login — no 2FA needed
} else if (result.requires2fa) {
  // User has 2FA enabled — verify with one of the available methods
  print('Available 2FA methods: ${result.availableMethods}');
  // Use result.tempToken for the chosen 2FA call
  await _handle2fa(result.tempToken!, result.availableMethods);
} else {
  // Wrong credentials, or a forced 2FA enrolment: see below
  print('Login failed: ${result.error}');
}
```

`LoginResult` extends `AuthResult<AuthUser>` with additional fields:

| Field | Type | Description |
|---|---|---|
| `requires2fa` | `bool` | `true` when a 2FA step is needed before authentication completes |
| `requires2FASetup` | `bool` | `true` only when a 200/201 login answer carries both `requiresTwoFactor: true` and `requires2FASetup: true`; see [Forced 2FA enrolment](#forced-2fa-enrolment) |
| `tempToken` | `String?` | Temporary session token to pass to the 2FA verification calls |
| `availableMethods` | `List<String>` | Methods the user can use (e.g. `['totp', 'sms', 'magic-link']`) |

### Forced 2FA enrolment

When 2FA is required for an account that has no second factor it can use, awesome-node-auth answers `POST /login` with a 403, and awesome-go-auth and awesome-lambda-auth send the same answer:

```json
{ "requires2FASetup": true, "tempToken": "…", "code": "2FA_SETUP_REQUIRED" }
```

`login()` does not surface this answer today. It reads `requiresTwoFactor` and `requires2FASetup` only from a 200 or 201, so on this 403 it returns a plain failure:

- `success` is `false` and `error` is the generic `'Login failed'`;
- `requires2FASetup` is `false`, `errorCode` is `null` and `tempToken` is `null`.

The app cannot tell this case from a wrong password, and `requires2FASetup` is never `true` against these servers. Enrol a second factor while the account can still sign in (for example `setup2fa()` and `verify2faSetup()` from an authenticated session) before 2FA becomes mandatory for it.

---

## Two-factor authentication (2FA)

### TOTP

```dart
// 1. Start setup — returns the secret, the otpauth:// URI and, from some servers, a QR code
final setup = await auth.setup2fa();
if (setup.success) {
  final secret = setup.data!.secret;         // show as fallback text entry
  final otpauthUrl = setup.data!.otpauthUrl; // otpauth://totp/… — render your own QR code from it
  final qrCode = setup.data!.qrCode;         // PNG data URL, or null — see below
}

// 2. Confirm setup with the code from the authenticator app
final verify = await auth.verify2faSetup(totpCode, secret);
if (verify.success) {
  print('TOTP enabled');
}

// 3. During login, validate the code using the temp token
final validate = await auth.validate2fa(tempToken, totpCode);
if (validate.success) {
  // User is now fully authenticated — state updated automatically
}

// 4. Disable TOTP (requires active session)
await auth.disable2fa();
```

`qrCode` is a PNG data URL that awesome-node-auth renders on the server; awesome-go-auth and awesome-lambda-auth do not send it, so it is `null` there. When it is `null`, draw a QR code from `otpauthUrl` with a QR package of your choice, or show `secret` for manual entry. A setup response without a `secret` comes back as a failed `AuthResult`, not as an exception.

### SMS one-time password

```dart
// ── Passwordless login via SMS OTP ───────────────────────────────────────────

// 1. Send an OTP to the user's registered phone
await auth.sendSmsLogin('user@example.com');

// 2. Verify the OTP (userId is returned by the backend in the send response)
final result = await auth.verifySmsLogin(userId, otpCode);
if (result.success) {
  // Authenticated — state updated automatically
}

// ── 2FA step via SMS ─────────────────────────────────────────────────────────

// 1. Request an SMS OTP during the 2FA step of a password login
await auth.send2faSms(tempToken);

// 2. Verify the code
final result2fa = await auth.validateSms(tempToken, otpCode);
if (result2fa.success) {
  // Fully authenticated — state updated automatically
}

// ── Register a phone number ───────────────────────────────────────────────────
await auth.addPhone('+1234567890');
```

### Magic link

```dart
// ── Passwordless login via magic link ────────────────────────────────────────

// 1. Send a magic link to the user's email
await auth.sendMagicLink('user@example.com');

// 2. When the user clicks the link, the app receives the token (e.g. via deep link)
final result = await auth.verifyMagicLink(token);
if (result.success) {
  // Authenticated — state updated automatically
}

// ── 2FA step via magic link ───────────────────────────────────────────────────

// 1. Send the magic link using the temp token from the login flow
await auth.send2faMagicLink(tempToken);

// 2. Verify the token when the user clicks the link
final result2fa = await auth.verifyMagicLink(token);
```

---

## Password management

```dart
// Initiate password recovery — sends a reset email
final forgot = await auth.forgotPassword('user@example.com');

// Reset password using the token from the recovery email
final reset = await auth.resetPassword('newPassword1!', resetToken);

// Change password for an authenticated user
final change = await auth.changePassword('currentPassword', 'newPassword1!');

// Set a password for an OAuth-only account (no existing password)
final set = await auth.setPassword('newPassword1!');

// Check result
if (reset.success) {
  print('Password updated');
} else {
  print('Error: ${reset.error}');
}
```

---

## Email management

```dart
// Resend the verification email for the current user
await auth.resendVerificationEmail();

// Verify the email using the token from the verification email
final verify = await auth.verifyEmail(emailToken);

// Request an email address change (sends a confirmation to newEmail)
await auth.requestEmailChange('new@example.com');

// Confirm the email change using the token from the confirmation email
final confirm = await auth.confirmEmailChange(confirmToken);
```

---

## Active sessions

```dart
// List all active sessions for the current user
final sessions = await auth.getActiveSessions();

for (final session in sessions) {
  print('Handle:      ${session.handle}');
  print('User-agent:  ${session.userAgent}');
  print('IP address:  ${session.ipAddress}');
  print('Created at:  ${session.createdAt}');
  print('Last active: ${session.lastActiveAt}');
  print('Current:     ${session.isCurrent}');
  print('---');
}

// Revoke a specific session (e.g. from a "sign out everywhere" screen)
final result = await auth.revokeSession(session.handle);
if (result.success) {
  print('Session revoked');
}

// Remove expired / invalid sessions from the server store
final cleanup = await auth.cleanupSessions();
if (cleanup.success) {
  print('Session store cleaned up');
}
```

`SessionInfo` fields:

| Field | Type | Description |
|---|---|---|
| `handle` | `String` | Unique session identifier, read from the server's `sessionHandle` — pass to `revokeSession()` |
| `userAgent` | `String?` | User-agent string of the client (not sent by awesome-go-auth / awesome-lambda-auth) |
| `ipAddress` | `String?` | IP address of the client (not sent by awesome-go-auth / awesome-lambda-auth) |
| `createdAt` | `DateTime?` | When the session was created |
| `lastActiveAt` | `DateTime?` | Timestamp of the last activity (not sent by awesome-go-auth / awesome-lambda-auth) |
| `isCurrent` | `bool` | `true` only when the server marks the session; awesome-node-auth, awesome-go-auth and awesome-lambda-auth do not send it, so it is `false` against them |

---

## OAuth (redirect-based)

The library provides helpers to initiate OAuth provider flows. The actual redirect
is always browser-driven (web) or opened in a webview / system browser (native);
the library does not embed a browser itself.

```dart
// 1. Get the redirect URL for the chosen provider
final url = auth.getOAuthUrl('github');
// → 'https://api.example.com/auth/oauth/github'

// ── Web ───────────────────────────────────────────────────────────────────────
// Redirect the browser — the callback is handled server-side and the session
// cookie is set automatically.
// (In headless / SPA mode you may use window.location.href or your router)

// ── Native (iOS / Android / Desktop) ─────────────────────────────────────────
// Open the URL in a webview or system browser, e.g. with url_launcher:
//   await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
//
// Configure your deep-link scheme in Android's AndroidManifest.xml (intent-filter)
// and iOS's Info.plist (CFBundleURLTypes) so the OAuth callback redirects back
// to your app.

// 2. After the callback, pick up the session
final user = await auth.handleOAuthCallback();
if (user != null) {
  print('OAuth login successful: ${user.email}');
  // AuthEventType.loggedIn is emitted automatically
}
```

### Background token refresh on app resume

The client does not hook into the Flutter app lifecycle automatically. Add a
`checkSession()` call in your `AppLifecycleListener.onResume` (Flutter ≥ 3.13)
or `WidgetsBindingObserver.didChangeAppLifecycleState` handler to restore the
session after the app returns to the foreground:

```dart
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      auth.checkSession(); // silently restores or expires the session
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
```

### Deep-link handling for email flows (native)

Wire your platform deep-link handler to call the appropriate client method:

| Deep-link token type | Client method |
|---|---|
| Email verification | `auth.verifyEmail(token)` |
| Password reset | `auth.resetPassword(newPassword, token)` |
| Magic link | `auth.verifyMagicLink(token)` |
| OAuth callback | `auth.handleOAuthCallback()` |

---

## Account linking

Link a second OAuth provider to an existing account.

```dart
// 1. Request a linking email for the given provider
await auth.requestLinkingEmail('user@example.com', 'github');

// 2. Verify the token from the linking email
await auth.verifyLinkingToken(linkingToken, 'github');

// ── Conflict resolution ───────────────────────────────────────────────────────
// When the provider account already belongs to another user, a conflict occurs.

// 1. Request a conflict-resolution linking email
await auth.requestConflictLinkingEmail('user@example.com', 'github');

// 2. Verify the conflict token (merges accounts and logs the user in)
await auth.verifyConflictLinkingToken(conflictToken);

// ── Manage linked accounts ────────────────────────────────────────────────────

// List all linked OAuth providers for the current user
final accounts = await auth.getLinkedAccounts();
// Returns a List<dynamic> where each item has 'provider' and 'providerAccountId'

// Remove a linked provider
await auth.unlinkAccount('github', providerAccountId);
```

---

## AuthUser model

Every field returned by the backend `/me` endpoint is mapped to this model.

| Field | Type | Description |
|---|---|---|
| `sub` | `String` | Stable unique user identifier |
| `email` | `String` | Email address |
| `isEmailVerified` | `bool` | Whether the email has been verified |
| `id` | `String?` | Optional database ID (may differ from `sub`) |
| `firstName` | `String?` | First name |
| `lastName` | `String?` | Last name |
| `name` | `String?` | Display name |
| `phoneNumber` | `String?` | Registered phone number |
| `role` | `String?` | Primary role string |
| `roles` | `List<String>?` | All roles assigned to the user |
| `permissions` | `List<String>?` | Permissions granted to the user |
| `isAdmin` | `bool?` | Whether the user has administrator privileges |
| `loginProvider` | `String?` | OAuth provider used for the last login (e.g. `'github'`) |
| `isTotpEnabled` | `bool?` | Whether TOTP 2FA is active |
| `hasPassword` | `bool?` | `false` for OAuth-only accounts that have never set a password |
| `lastLogin` | `DateTime?` | Timestamp of the most recent login |
| `metadata` | `Map<String, dynamic>?` | Arbitrary key-value data attached by the backend |

```dart
final user = auth.state.currentUser!;

print(user.sub);              // '64a1f...'
print(user.email);            // 'jane@example.com'
print(user.isEmailVerified);  // true
print(user.firstName);        // 'Jane'
print(user.roles);            // ['user', 'editor']
print(user.isAdmin);          // false
print(user.isTotpEnabled);    // true
print(user.hasPassword);      // true
print(user.loginProvider);    // null (password login)
```

---

## AuthResult\<T\>

Most `AuthClient` methods return `AuthResult<T>`. `LoginResult` is a subtype returned only by `login()`.

### `AuthResult<T>`

| Field | Type | Description |
|---|---|---|
| `success` | `bool` | `true` when the operation succeeded |
| `data` | `T?` | Payload on success (`null` on failure) |
| `error` | `String?` | Human-readable error message on failure |
| `errorCode` | `String?` | Machine-readable error code (e.g. `"SESSION_REVOKED"`) |

```dart
final result = await auth.changePassword('old', 'new');
if (result.success) {
  print('Done');
} else {
  print('${result.errorCode}: ${result.error}');
}
```

### `LoginResult` (extends `AuthResult<AuthUser>`)

| Field | Type | Description |
|---|---|---|
| `requires2fa` | `bool` | `true` when a 2FA verification step is required |
| `requires2FASetup` | `bool` | `true` only when a 200/201 login answer asks for 2FA enrolment; see [Forced 2FA enrolment](#forced-2fa-enrolment) |
| `tempToken` | `String?` | Temporary token for the 2FA verification calls |
| `availableMethods` | `List<String>` | 2FA methods available to this user |

---

## Custom TokenStorage

On native platforms, provide a custom `TokenStorage` implementation to persist tokens across app restarts. `flutter_secure_storage` is **not** a dependency of this package — add it to your own `pubspec.yaml`.

```yaml
# In your app's pubspec.yaml
dependencies:
  flutter_secure_storage: ^9.0.0
```

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:awesome_flutter_auth/awesome_flutter_auth.dart';

class SecureTokenStorage implements TokenStorage {
  final _storage = const FlutterSecureStorage();

  static const _accessKey  = 'auth_access_token';
  static const _refreshKey = 'auth_refresh_token';

  @override
  Future<String?> readAccessToken() => _storage.read(key: _accessKey);

  @override
  Future<void> writeAccessToken(String token) =>
      _storage.write(key: _accessKey, value: token);

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _refreshKey);

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _refreshKey, value: token);

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

// Pass it to AuthOptions
final auth = AuthClient(
  AuthOptions(
    apiPrefix: '/api/auth',
    tokenStorage: SecureTokenStorage(),
  ),
);
```

`TokenStorage` interface:

| Method | Description |
|---|---|
| `readAccessToken()` | Returns the stored access token, or `null` |
| `writeAccessToken(token)` | Persists a new access token |
| `readRefreshToken()` | Returns the stored refresh token, or `null` |
| `writeRefreshToken(token)` | Persists a new refresh token |
| `clear()` | Deletes all stored tokens (called on logout) |

---

## Internal behaviour — automatic refresh

The client transparently handles token expiry so individual API calls do not need to manage refresh logic.

### Flow

1. Every request that receives a `401` or `403` response checks whether the endpoint is in the **no-retry list** (see below).
2. If eligible for retry, the client calls `POST $apiPrefix/refresh`.
3. On success (native) the new `accessToken` from the response body is written back to `TokenStorage`. On web the browser updates the cookie automatically.
4. The original request is retried with the new token.
5. If the refresh also fails, the session is considered expired and `handleLogout()` is called.

### Concurrent refresh deduplication

If multiple requests fail at the same time, only **one** refresh call is made. All concurrent requests wait for that single call to complete before retrying. This prevents the `POST /refresh` endpoint from being hammered.

### Session revoked

When the backend responds with `{ "code": "SESSION_REVOKED" }`, the client skips the refresh attempt and immediately calls `handleLogout(revoked: true)`, which emits `AuthEventType.sessionRevoked`.

### Endpoints excluded from auto-retry

The following endpoints always receive the raw response — they are never retried after a 401/403:

| Endpoint segment | Reason |
|---|---|
| `login` | Credentials failure, not a token issue |
| `logout` | Already logging out |
| `refresh` | Avoid infinite loop |
| `register` | No session expected |
| `forgot-password` | Unauthenticated flow |
| `reset-password` | Token-based, not session-based |
| `verify-email` | Token-based |
| `confirm` | One-time confirmation token flow |
| `2fa/verify` | Uses a temp token, not a session token |

### Web vs native refresh

| | Web | Native |
|---|---|---|
| Token location | HttpOnly cookie | `TokenStorage` |
| Refresh request body | Empty (browser sends the HttpOnly cookie automatically) | Empty body; `Authorization: Bearer <accessToken>` header is sent so the backend can identify the session |
| New token delivery | Cookie set by server | `accessToken` field in JSON response body |

---

## Headless mode

Set `headless: true` to disable all automatic browser redirects. In this mode the client never calls `window.location.href` — your code is responsible for reacting to events and navigating appropriately.

```dart
final auth = AuthClient(
  AuthOptions(
    apiPrefix: '/api/auth',
    headless: true,           // No automatic redirects
  ),
);

auth.events.listen((event) {
  if (event.type == AuthEventType.loggedOut ||
      event.type == AuthEventType.sessionExpired ||
      event.type == AuthEventType.sessionRevoked) {
    // Navigate to login using your router
    GoRouter.of(context).go('/login');
  }
});
```

**When to use headless mode:**

- Apps using **GoRouter** or **AutoRoute** for programmatic navigation.
- **Web iframes** where redirecting the frame would break the embedding page.
- Any scenario where the auth client must not touch `window.location`.

---

## Authenticated HTTP client (interceptor)

`auth.httpClient` is a standard [`http.Client`](https://pub.dev/documentation/http/latest/http/Client-class.html) with authentication baked in — analogous to an Angular `HttpInterceptor` or the `auth.js` middleware for Express.

Use it for **all** calls to your own backend. There is nothing extra to configure: the library automatically injects the correct credentials for the running platform.

| Platform | What is injected |
|---|---|
| Web / WASM | `X-CSRF-Token` for same-origin requests; the browser sends the HttpOnly cookie automatically |
| Native | `Authorization: Bearer <token>` + `X-Auth-Strategy: bearer`; token is refreshed silently on 401 / 403 |

```dart
// auth.httpClient is a drop-in http.Client — use it anywhere
final client = auth.httpClient;

// GET a protected resource — no manual token handling
final response = await client.get(Uri.parse('https://api.example.com/todos'));

// POST with a JSON body
final res = await client.post(
  Uri.parse('https://api.example.com/todos'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'title': 'Buy milk'}),
);
```

Because `httpClient` is an `http.Client`, it is compatible with any package that accepts one (e.g. `dio` adapters, `chopper`, `retrofit`, GraphQL clients):

```dart
// Example: pass the authenticated client to a third-party package
final graphql = GraphQLClient(
  link: HttpLink(apiUrl, httpClient: auth.httpClient),
  cache: GraphQLCache(),
);
```

---

## SSE stream

The client exposes a server-sent events stream from `$apiPrefix/tools/stream`. This is only available on **web**; on native platforms `getToolsStream()` returns `Stream.empty()`.

```dart
// Web: live event stream from the backend
auth.getToolsStream().listen(
  (event) => print('SSE event: $event'),
  onDone: () => print('Stream closed'),
);
```

The stream automatically closes when the `EventSource` emits an error (e.g. server disconnect). To reconnect, call `getToolsStream()` again.

---

## UI config

Load feature flags and enabled providers from the backend to drive conditional UI rendering.

```dart
final config = await auth.loadUiConfig();
if (config != null) {
  print('Registration enabled: ${config.registrationEnabled}');
  print('Magic link enabled:   ${config.magicLinkEnabled}');
  print('SMS enabled:          ${config.smsEnabled}');
  print('TOTP enabled:         ${config.totpEnabled}');
  print('GitHub OAuth:         ${config.githubEnabled}');
  print('Google OAuth:         ${config.googleEnabled}');
  print('Providers:            ${config.availableProviders}');
}
```

`UiConfig` fields:

| Field | Type | Description |
|---|---|---|
| `registrationEnabled` | `bool` | Whether new user registration is allowed |
| `magicLinkEnabled` | `bool` | Whether magic-link (passwordless) login is enabled |
| `smsEnabled` | `bool` | Whether SMS OTP login is enabled |
| `totpEnabled` | `bool` | Whether TOTP 2FA is enabled |
| `githubEnabled` | `bool` | Whether GitHub OAuth login is enabled |
| `googleEnabled` | `bool` | Whether Google OAuth login is enabled |
| `availableProviders` | `List<String>` | All enabled OAuth provider names |
| `extra` | `Map<String, dynamic>?` | Backend-specific extra configuration |

---

## WASM compatibility

This package is WASM-ready. The following design decisions ensure compatibility:

- **`package:web`** is used instead of `dart:html` for all DOM/browser APIs (e.g. `window.location`, `EventSource`, cookie reading).
- **`package:http`** is used for all HTTP calls instead of `dart:io`'s `HttpClient`.
- Platform-specific code is gated with **conditional imports** using `dart.library.js_interop`:

```dart
import 'platform/native_auth_client.dart'
    if (dart.library.js_interop) 'platform/web_auth_client.dart' as platform;
```

### Verify WASM build

```bash
flutter build web --wasm
```

---

## Offline token verification

Verify JWS compact tokens signed with `alg: EdDSA` (Ed25519) offline without contacting the server, such as for standalone licence validation, desktop apps, or PWAs.

Implemented in **pure Dart** without dependencies on Flutter SDK, `dart:io` or `dart:html`: works on Flutter mobile/desktop/web (including WASM) as well as standalone Dart CLI, servers, and tests.

```dart
import 'package:awesome_flutter_auth/offline_tokens.dart';

// 1. Configure the verifier with public keys (JWK OKP) and expectations
final verifier = OfflineTokenVerifier(
  keys: OkpKeySet.fromJwks(publicKeysJson['keys']), // or OkpKeySet.fromKeys(...)
  expectedTyp: 'ita-license+jwt',
  issuer: 'https://ita.example',
  audience: 'ita-pwa',
);

// 2. Verify with throwing API
try {
  final result = verifier.verify(token, now: DateTime.now().toUtc());
  print('Token valid for: ${result.claims['sub']}');
  print('Plan: ${result.claims['plan']}');
} on OfflineTokenException catch (e) {
  print('Verification failed: ${e.reason.code} - ${e.message}');
}

// Or verify with non-throwing API:
final check = verifier.tryVerify(token, now: DateTime.now().toUtc());
if (check.isValid) {
  final claims = check.result!.claims;
  // Use claims...
} else {
  // Map typed reason to UI state:
  switch (check.reason!) {
    case OfflineTokenReason.expired:
      // Licence expired
      break;
    case OfflineTokenReason.signatureInvalid:
      // Tampered token
      break;
    case OfflineTokenReason.audInvalid:
    case OfflineTokenReason.issInvalid:
    case OfflineTokenReason.typInvalid:
    case OfflineTokenReason.algNotAllowed:
    case OfflineTokenReason.kidUnknown:
    case OfflineTokenReason.claimsInvalid:
    case OfflineTokenReason.malformed:
      // Invalid licence
      break;
  }
}
```

### Verification checks & security guarantees

Checks are performed strictly in order:

| # | Check | Reason Code |
|---|---|---|
| 1 | Exactly 3 parts, non-empty header/payload, canonical base64url, valid JSON | `malformed` |
| 2 | `alg == "EdDSA"` exactly (rejects `none`, `HS256`, `Ed25519`, ...) | `alg_not_allowed` |
| 3 | `typ` matches `expectedTyp` | `typ_invalid` |
| 4 | Header contains no `crit` extensions | `malformed` |
| 5 | `kid` is a non-empty string and present in `keys` | `kid_unknown` |
| 6 | Signature is canonical base64url, 64 bytes, canonical scalar (`S < L`), and Ed25519-valid | `signature_invalid` |
| 7 | Claim types (`exp`, `iat`, `ent` integers; strings non-empty) | `claims_invalid` |
| 8 | `aud` matches expected audience | `aud_invalid` |
| 9 | `iss` matches expected issuer | `iss_invalid` |
| 10 | `exp <= now` (integer seconds comparison) | `expired` |

- **No `Error` leaks**: Any malformed input string safely evaluates to a typed failure.
- **Canonical encoding**: Strict checks against base64url malleability and non-canonical scalar encodings (`S < L`).

---

## License

MIT
