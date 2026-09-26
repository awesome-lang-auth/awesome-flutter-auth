# Changelog

## 2.0.0

### Discontinued

- **Renamed to [`awesome_flutter_auth`](https://pub.dev/packages/awesome_flutter_auth).** This is the last release of `awesome_node_auth_flutter`. It has no code of its own: `lib/awesome_node_auth_flutter.dart` re-exports `package:awesome_flutter_auth/awesome_flutter_auth.dart`, and the package depends on `awesome_flutter_auth: ^1.10.1`. Migrate by replacing the dependency with `awesome_flutter_auth` and the `package:` imports with `package:awesome_flutter_auth/awesome_flutter_auth.dart`.

### Breaking

- Through `awesome_flutter_auth` 1.10.1, `TotpSetupData.qrCode` is now `String?` (it was `String`). Code that passes it where a `String` is expected, such as `Image.network(setup.data!.qrCode)`, needs a null check, with `TotpSetupData.otpauthUrl` as the fallback. This is why the bridge is a major release: a `^1.x` constraint stays on 1.10.0.

### Changed

- Everything else `awesome_flutter_auth` 1.10.1 brings: `getActiveSessions()` reads `sessionHandle` ([#21](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/21)), `setup2fa()` accepts a response without `qrCode` ([#22](https://github.com/awesome-lang-auth/awesome-flutter-auth/issues/22)), the new `TotpSetupData.otpauthUrl`, and `SessionInfo.toJson()` writing `sessionHandle`. See the [awesome_flutter_auth changelog](https://github.com/awesome-lang-auth/awesome-flutter-auth/blob/main/CHANGELOG.md#1101).
- `homepage`, `repository` and `issue_tracker` point at <https://github.com/awesome-lang-auth/awesome-flutter-auth>.

## 1.10.0 and earlier

Released as the standalone `awesome_node_auth_flutter` package. Their entries are in the [awesome_flutter_auth changelog](https://github.com/awesome-lang-auth/awesome-flutter-auth/blob/main/CHANGELOG.md).
