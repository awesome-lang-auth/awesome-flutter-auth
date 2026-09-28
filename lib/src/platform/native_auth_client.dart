import 'dart:async';

import 'package:http/http.dart' as http;

import '../auth_client.dart';
import '../auth_options.dart';
import '../http/auth_http_client.dart';
import '../http/token_storage.dart';
import 'base_auth_client.dart';

/// Factory function called by the conditional import in [AuthClient].
///
/// On native platforms (`dart.library.io` available) this function is used.
AuthClient createAuthClient(AuthOptions options, {http.Client? httpClient}) {
  final inner = httpClient ?? http.Client();
  final storage = options.tokenStorage ?? InMemoryTokenStorage();

  final authHttp = AuthHttpClient(
    inner: inner,
    apiPrefix: options.apiPrefix,
    bearerProvider: storage.readAccessToken,
    bearerSetter: storage.writeAccessToken,
  );

  return NativeAuthClient(options, authHttp, storage);
}

/// Native-platform implementation of [AuthClient].
///
/// Uses Bearer token authentication:
/// - Reads/writes the access token from [TokenStorage].
/// - Attaches `Authorization: Bearer <token>` to all requests.
/// - On token refresh the backend returns a new `accessToken` in the response
///   body, which is persisted back to [TokenStorage].
class NativeAuthClient extends BaseAuthClient {
  final TokenStorage _storage;

  NativeAuthClient(super.options, super.httpClient, this._storage);

  @override
  Future<void> handleLogout({bool revoked = false}) async {
    httpClient.clearTokens();
    await _storage.clear();
    return super.handleLogout(revoked: revoked);
  }

  @override
  void clearLocalSession() {
    httpClient.clearTokens();
    unawaited(_storage.clear());
    super.clearLocalSession();
  }

  // On native there is no SSE / EventSource — return an empty stream.
  @override
  Stream<String> getToolsStream() => const Stream.empty();
}
