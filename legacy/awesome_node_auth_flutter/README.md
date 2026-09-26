# awesome_node_auth_flutter (discontinued)

**This package has been renamed to [`awesome_flutter_auth`](https://pub.dev/packages/awesome_flutter_auth).** It is the same Flutter/Dart client, now maintained under the [awesome-lang-auth](https://github.com/awesome-lang-auth) organisation at <https://github.com/awesome-lang-auth/awesome-flutter-auth>, and it works with every awesome-lang-auth server (awesome-node-auth, awesome-go-auth, awesome-lambda-auth).

`awesome_node_auth_flutter` 2.0.0 is the last release under the old name. It contains no code of its own: its library re-exports `package:awesome_flutter_auth/awesome_flutter_auth.dart`, and it depends on `awesome_flutter_auth: ^1.10.1`. It exists so that the old name points at the new package. New features and fixes land in `awesome_flutter_auth` only.

## Migrate

1. Replace the dependency:

   ```sh
   flutter pub remove awesome_node_auth_flutter
   flutter pub add awesome_flutter_auth
   ```

   or, in `pubspec.yaml`:

   ```yaml
   dependencies:
     awesome_flutter_auth: ^1.10.1
   ```

2. Replace the imports:

   ```dart
   // before
   import 'package:awesome_node_auth_flutter/awesome_node_auth_flutter.dart';
   // after
   import 'package:awesome_flutter_auth/awesome_flutter_auth.dart';
   ```

   The class names are the same; the two changes below are the only ones that can need code changes.

3. `TotpSetupData.qrCode` is now `String?` (it was `String`), because awesome-go-auth and awesome-lambda-auth do not send it. Add a null check and fall back to `TotpSetupData.otpauthUrl` (draw the QR code yourself) or `secret`.

4. `SessionInfo.toJson()` now writes the handle under `sessionHandle` (it was `handle`). `SessionInfo.fromJson` still reads either key.

## Why 2.0.0

`awesome_flutter_auth` 1.10.1 changed `TotpSetupData.qrCode` from `String` to `String?`, which can break code that compiled against `awesome_node_auth_flutter` 1.10.0. A re-export of 1.10.1 under the old name is therefore a major release. A `^1.x` constraint keeps resolving to 1.10.0, the last standalone release, so nobody is moved onto the new package by a routine `pub upgrade`.

If you bump to `awesome_node_auth_flutter: ^2.0.0` instead of migrating, your existing imports keep compiling (apart from the `qrCode` and `toJson()` changes above) and you get `awesome_flutter_auth` 1.x through this package. Migrating is still recommended: this package will not get further releases.

## Links

- New package: <https://pub.dev/packages/awesome_flutter_auth>
- Repository: <https://github.com/awesome-lang-auth/awesome-flutter-auth>
- Full changelog, including every `awesome_node_auth_flutter` release up to 1.10.0: <https://github.com/awesome-lang-auth/awesome-flutter-auth/blob/main/CHANGELOG.md>

## License

MIT. See [LICENSE](https://github.com/awesome-lang-auth/awesome-flutter-auth/blob/main/legacy/awesome_node_auth_flutter/LICENSE).
