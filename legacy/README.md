# legacy/

Bridge packages for names this client was published under before the move to
the awesome-lang-auth organisation. They are not part of `awesome_flutter_auth`:

- `legacy/.pubignore` keeps this folder out of the archive that
  `dart pub publish` and `.github/workflows/publish.yml` build from the
  repository root;
- `.github/workflows/test.yml` analyzes `lib/` and runs `test/` of the root
  package only.

| Folder | Package | Version | What it does |
| --- | --- | --- | --- |
| [`awesome_node_auth_flutter/`](awesome_node_auth_flutter/) | [`awesome_node_auth_flutter`](https://pub.dev/packages/awesome_node_auth_flutter) | 2.0.0 | Re-exports `package:awesome_flutter_auth/awesome_flutter_auth.dart` and depends on `awesome_flutter_auth: ^1.10.1`. Last release under the old name. |

## Publishing `awesome_node_auth_flutter` 2.0.0

This is a one-off manual publish by a pub.dev uploader of `awesome_node_auth_flutter`.
There is no workflow and no tag for it: do not push a `v2.0.0` tag, because
`publish.yml` would try to publish the root package.

1. `awesome_flutter_auth` 1.10.1 must already be on pub.dev. Until then
   `dart pub get` and `dart pub publish` fail with "could not find package
   awesome_flutter_auth".
2. Export the folder to a directory outside any git checkout. Run inside this
   repository, pub applies `legacy/.pubignore` and reports "The pubspec is
   hidden". Use the `dart` of a Flutter SDK (or `flutter pub publish`), for
   example inside `ghcr.io/cirruslabs/flutter:stable`; a standalone Dart SDK
   refuses the package. Run the commands below from a clone of `main` after
   this folder has been merged there:

   ```sh
   out="$(mktemp -d)"
   git -c core.autocrlf=false archive HEAD:legacy/awesome_node_auth_flutter | tar -x -C "$out"
   cd "$out"
   dart pub publish --dry-run   # expect 5 files and no errors
   dart pub publish
   ```

3. On pub.dev, mark `awesome_node_auth_flutter` as discontinued, replaced by
   `awesome_flutter_auth`.
