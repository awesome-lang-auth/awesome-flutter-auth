import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Identifier used to signal that the session was revoked on the server.
const _kSessionRevoked = 'SESSION_REVOKED';

/// Auth endpoints that should NOT trigger a refresh + retry on 401/403.
const _kNoRetryEndpoints = {
  'login',
  'logout',
  'refresh',
  'register',
  'forgot-password',
  'reset-password',
  'verify-email',
  'confirm',
};

/// Two-segment endpoint that must be excluded separately.
const _kNoRetryTwoSegment = '2fa/verify';

/// Provides CSRF token for web given the full request URL.
///
/// The [url] parameter allows the provider to perform a same-origin check
/// and return `null` for cross-origin requests so the header is omitted.
typedef CsrfTokenProvider = String? Function(String url);

/// Provides the current Bearer access token (native only).
typedef BearerTokenProvider = Future<String?> Function();

/// Persists a new Bearer access token received after a refresh (native only).
typedef BearerTokenSetter = Future<void> Function(String token);

/// Called when the session ends (expired, revoked, or user logout).
typedef LogoutCallback = Future<void> Function({bool revoked});

/// Authenticated HTTP client that wraps [http.Client] and adds:
///
/// - CSRF header injection (web, same-origin)
/// - Bearer token injection (native)
/// - Automatic refresh + retry on 401/403 with deduplication
/// - Session-revoked detection
///
/// Extends [http.BaseClient] so it can be used as a drop-in [http.Client]
/// for any backend request — authentication is handled transparently, similar
/// to an Angular `HttpInterceptor`.
class AuthHttpClient extends http.BaseClient {
  final http.Client _inner;
  final String _apiPrefix;

  final CsrfTokenProvider? _csrfProvider;
  final BearerTokenProvider? _bearerProvider;
  final BearerTokenSetter? _bearerSetter;
  String? _refreshToken;

  LogoutCallback? _onLogout;
  Future<bool> Function()? _refreshHandler;

  /// In-flight refresh deduplicator.
  Completer<bool>? _refreshCompleter;

  /// Session generation the in-flight refresh was started under. Only a
  /// request of the same generation joins it.
  int _refreshGeneration = 0;

  /// In-flight token-storage clear (see [waitForTokenClear]).
  Future<void>? _pendingTokenClear;

  /// Incremented by [markSessionEnded]. Each request records the value when
  /// it starts, so a 401/403 that arrives after the session ended is
  /// recognised as late (issue #33).
  int _sessionGeneration = 0;

  /// Set by [markSessionEnded], cleared by the next successful `GET /me`
  /// (every login flow ends with one). While set, a 401/403 is returned
  /// unchanged: there is no session to refresh.
  bool _sessionEnded = false;

  AuthHttpClient({
    required http.Client inner,
    required String apiPrefix,
    CsrfTokenProvider? csrfProvider,
    BearerTokenProvider? bearerProvider,
    BearerTokenSetter? bearerSetter,
  })  : _inner = inner,
        _apiPrefix = apiPrefix,
        _csrfProvider = csrfProvider,
        _bearerProvider = bearerProvider,
        _bearerSetter = bearerSetter;

  /// Registers the callback invoked when the session ends.
  void setLogoutHandler(LogoutCallback handler) => _onLogout = handler;

  /// Registers the function that performs the token refresh.
  void setRefreshHandler(Future<bool> Function() handler) =>
      _refreshHandler = handler;

  /// Clears stored in-memory tokens (such as the refresh token on native).
  void clearTokens() {
    _refreshToken = null;
  }

  /// Registers an in-flight clear of the persisted tokens.
  ///
  /// Every request built after this call waits for [clearing] to complete
  /// before reading the Bearer token, so a request issued right after an
  /// un-awaited `clearLocalSession()` never carries the old
  /// `Authorization` header, even with an asynchronous [TokenStorage]
  /// (issue #31).
  void waitForTokenClear(Future<void> clearing) {
    _pendingTokenClear = clearing;
    clearing.then((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_pendingTokenClear, clearing)) _pendingTokenClear = null;
    });
  }

  /// Marks the current session as ended locally (logout, account deletion,
  /// `clearLocalSession()`, a failed refresh).
  ///
  /// Until the next successful `GET /me`, a 401/403 is returned unchanged: no
  /// refresh, no retry and no logout callback, because the caller of this
  /// method already handles the logout. Without this, a late 401/403 sent
  /// `POST /refresh` after the server had cleared the cookies, without
  /// `X-CSRF-Token` on web, and emitted a second logout (issue #33).
  ///
  /// A refresh in flight across this call has its result dropped: no token
  /// is written to storage or kept in memory, and the original request is
  /// not retried.
  void markSessionEnded() {
    _sessionGeneration++;
    _sessionEnded = true;
  }

  /// Current session generation, incremented by [markSessionEnded].
  int get sessionGeneration => _sessionGeneration;

  /// Completes when the refresh in flight, if any, has completed (never
  /// throws). `logout()` waits for it so that `POST /logout` revokes the
  /// refreshed session: on web the browser has already stored the refresh
  /// response's cookies, which the client cannot undo.
  Future<void> waitForRefresh() async {
    final inFlight = _refreshCompleter;
    if (inFlight == null) return;
    try {
      await inFlight.future;
    } catch (_) {}
  }

  /// Body of `POST /logout`: in bearer mode (native) the current refresh
  /// token, so the server can revoke the session even when the access token
  /// has expired; `null` in cookie mode, where the browser sends the cookie.
  Map<String, String>? get logoutBody {
    final refreshToken = _refreshToken;
    if (_bearerProvider == null || refreshToken == null) return null;
    return {'refreshToken': refreshToken};
  }

  // -------------------------------------------------------------------------
  // URL helpers
  // -------------------------------------------------------------------------

  static bool _isHttpUrl(Uri uri) =>
      uri.scheme == 'http' || uri.scheme == 'https';

  /// Returns `true` for a scheme-relative URI (`//host/path`): no scheme but
  /// an authority, so the host is chosen by the URI itself.
  static bool isSchemeRelative(Uri uri) => !uri.hasScheme && uri.hasAuthority;

  /// Resolves [path] against the API prefix.
  ///
  /// - `http(s)://...` URLs are used as-is.
  /// - Scheme-relative paths (`//host/...`, including `/\host`, which
  ///   `Uri.parse` normalises to `//host`) are rejected with an
  ///   [ArgumentError]: they would leave the prefix origin (issue #31).
  /// - [isAbsolute] (root-relative `/x`): the path replaces the prefix path,
  ///   keeping the prefix origin when the prefix is absolute.
  /// - Otherwise the prefix path segments and the endpoint path segments are
  ///   joined, with the same result for absolute and relative prefixes.
  ///
  /// Segments are decoded by [Uri.pathSegments] and re-encoded by the [Uri]
  /// constructor, so an interpolated segment encoded with
  /// [Uri.encodeComponent] (containing `?`, `#` or `/`) stays one segment.
  Uri _buildUri(String path, {bool isAbsolute = false}) {
    final parsed = Uri.parse(path);
    if (parsed.hasScheme) {
      if (_isHttpUrl(parsed)) return parsed;
      throw ArgumentError.value(
          path, 'path', 'Only http and https absolute URLs are supported');
    }
    if (parsed.hasAuthority) {
      throw ArgumentError.value(
          path, 'path', 'Scheme-relative paths (//host/...) are not allowed');
    }

    final prefix = Uri.parse(_apiPrefix);
    final query = parsed.hasQuery ? parsed.query : null;

    final List<String> segments;
    if (isAbsolute) {
      segments = parsed.pathSegments;
    } else {
      final prefixSegments = [...prefix.pathSegments];
      while (prefixSegments.isNotEmpty && prefixSegments.last.isEmpty) {
        prefixSegments.removeLast();
      }
      segments = [...prefixSegments, ...parsed.pathSegments];
    }

    if (_isHttpUrl(prefix)) {
      return prefix.replace(pathSegments: segments, query: query);
    }
    final rooted = isAbsolute || prefix.path.isEmpty || prefix.path.startsWith('/');
    return Uri(
      pathSegments: rooted ? ['', ...segments] : segments,
      query: query,
    );
  }

  // -------------------------------------------------------------------------
  // Endpoint exclusion
  // -------------------------------------------------------------------------

  bool _isExcludedEndpoint(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return false;

    final last = segments.last;
    if (_kNoRetryEndpoints.contains(last)) return true;

    if (segments.length >= 2) {
      final twoSeg = '${segments[segments.length - 2]}/$last';
      if (twoSeg == _kNoRetryTwoSegment) return true;
    }

    return false;
  }

  bool _isMeEndpoint(String path) {
    final segments = Uri.parse(path).pathSegments.where((s) => s.isNotEmpty);
    return segments.isNotEmpty && segments.last == 'me';
  }

  // -------------------------------------------------------------------------
  // Header helpers
  // -------------------------------------------------------------------------

  /// Builds the request headers for a request that will be sent to exactly
  /// [target]. The CSRF decision is taken on [target] itself, never on a
  /// rebuilt URI, and is skipped for scheme-relative targets (issue #31).
  Future<Map<String, String>> _buildHeaders(
    Uri target,
    Map<String, String>? extra, {
    bool includeAuthHeaders = true,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?extra,
    };

    if (includeAuthHeaders) {
      if (!isSchemeRelative(target)) {
        final csrf = _csrfProvider?.call(target.toString());
        if (csrf != null) headers['X-CSRF-Token'] = csrf;
      }

      if (_bearerProvider != null) {
        // Interop contract with awesome-node-auth: native clients opt into
        // token-in-body delivery via X-Auth-Strategy=bearer.
        headers['X-Auth-Strategy'] = 'bearer';
        final pending = _pendingTokenClear;
        if (pending != null) {
          try {
            await pending;
          } catch (_) {
            // The error is reported to the caller of clearLocalSession().
          }
        }
        final bearer = await _bearerProvider();
        if (bearer != null) headers['Authorization'] = 'Bearer $bearer';
      }
    }

    return headers;
  }

  // -------------------------------------------------------------------------
  // Path-based HTTP verbs (internal use by BaseAuthClient)
  //
  // These use String paths relative to apiPrefix and return buffered
  // http.Response objects. They are intentionally distinct from the
  // http.BaseClient URI-based methods (get/post/patch/delete) which are
  // inherited and used by consumers via [AuthClient.httpClient].
  // -------------------------------------------------------------------------

  Future<http.Response> apiGet(
    String path, {
    Map<String, String>? headers,
    Map<String, String>? queryParameters,
  }) =>
      _send('GET', path, headers: headers, queryParameters: queryParameters);

  Future<http.Response> apiPost(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _send('POST', path, headers: headers, body: body);

  Future<http.Response> apiPatch(
    String path, {
    Map<String, String>? headers,
    Object? body,
  }) =>
      _send('PATCH', path, headers: headers, body: body);

  Future<http.Response> apiDelete(
    String path, {
    Map<String, String>? headers,
    bool isAbsolute = false,
  }) =>
      _send('DELETE', path, headers: headers, isAbsolute: isAbsolute);

  // -------------------------------------------------------------------------
  // Core send logic
  // -------------------------------------------------------------------------

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? headers,
    Object? body,
    Map<String, String>? queryParameters,
    bool isAbsolute = false,
  }) async {
    final generation = _sessionGeneration;
    final allHeaders =
        await _buildHeaders(_buildUri(path, isAbsolute: isAbsolute), headers);
    final response = await _rawSend(
      method,
      path,
      allHeaders,
      body,
      queryParameters,
      isAbsolute: isAbsolute,
    );

    // Tokens in a response to a request of an ended session are dropped.
    if (_sessionEndedSince(generation)) return response;

    await _captureBearerTokens(response);

    // A successful GET /me proves a live session again (issue #33).
    if (_sessionEnded &&
        method == 'GET' &&
        _isMeEndpoint(path) &&
        response.statusCode >= 200 &&
        response.statusCode < 300 &&
        !_sessionEndedSince(generation)) {
      _sessionEnded = false;
    }

    if ((response.statusCode == 401 || response.statusCode == 403) &&
        !_isExcludedEndpoint(path)) {
      return _handleUnauthorized(method, path, response, generation,
          headers: headers,
          body: body,
          queryParameters: queryParameters,
          isAbsolute: isAbsolute);
    }

    return response;
  }

  Future<void> _captureBearerTokens(http.Response response) async {
    if (_bearerSetter == null) return;
    if (response.body.isEmpty) return;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return;

      final accessToken = decoded['accessToken'] as String?;
      final refreshToken = decoded['refreshToken'] as String?;

      if (accessToken != null) {
        // Persist before subsequent requests (e.g. immediate /me after /login).
        await _bearerSetter(accessToken);
      }
      if (refreshToken != null) {
        _refreshToken = refreshToken;
      }
    } catch (_) {
      // Non-JSON or body without tokens: ignore.
    }
  }

  Future<http.Response> _rawSend(
    String method,
    String path,
    Map<String, String> headers,
    Object? body,
    Map<String, String>? queryParameters, {
    bool isAbsolute = false,
  }) async {
    var uri = _buildUri(path, isAbsolute: isAbsolute);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      uri = uri.replace(queryParameters: {
        ...uri.queryParameters,
        ...queryParameters,
      });
    }

    switch (method) {
      case 'GET':
        return _inner.get(uri, headers: headers);
      case 'DELETE':
        return _inner.delete(uri, headers: headers);
      case 'POST':
        final encoded =
            body is String ? body : (body != null ? jsonEncode(body) : null);
        return _inner.post(uri, headers: headers, body: encoded);
      case 'PATCH':
        final encoded =
            body is String ? body : (body != null ? jsonEncode(body) : null);
        return _inner.patch(uri, headers: headers, body: encoded);
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
  }

  // -------------------------------------------------------------------------
  // 401 / 403 interception
  // -------------------------------------------------------------------------

  /// Returns `true` when the response body contains a JSON object with
  /// `"code": "SESSION_REVOKED"`, matching the backend contract.
  bool _isSessionRevoked(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded['code'] == _kSessionRevoked;
      }
    } catch (_) {}
    return false;
  }

  /// Returns `true` when the session ended (see [markSessionEnded]) after the
  /// request that recorded [generation] started.
  bool _sessionEndedSince(int generation) => generation != _sessionGeneration;

  /// Returns `true` when a 401/403 must be returned unchanged: the request
  /// belongs to a session that has ended since it started, or the session is
  /// known to be ended (issue #33).
  bool _noSessionToRefresh(int generation) =>
      _sessionEnded || _sessionEndedSince(generation);

  Future<http.Response> _handleUnauthorized(
    String method,
    String path,
    http.Response response,
    int generation, {
    Map<String, String>? headers,
    Object? body,
    Map<String, String>? queryParameters,
    bool isAbsolute = false,
  }) async {
    // Late 401/403 after logout, or no session at all: nothing to refresh,
    // and the logout is already handled (issue #33).
    if (_noSessionToRefresh(generation)) return response;

    if (_isSessionRevoked(response)) {
      await _onLogout?.call(revoked: true);
      return response;
    }

    final refreshed = await _doRefresh();
    // The session ended while the refresh was in flight: no retry, and the
    // logout is already handled by whoever ended it.
    if (_sessionEndedSince(generation)) return response;
    if (refreshed) {
      final retryHeaders =
          await _buildHeaders(_buildUri(path, isAbsolute: isAbsolute), headers);
      // The session may have ended while the headers were read.
      if (_sessionEndedSince(generation)) return response;
      return _rawSend(method, path, retryHeaders, body, queryParameters,
          isAbsolute: isAbsolute);
    } else {
      await _onLogout?.call(revoked: false);
      return response;
    }
  }

  // -------------------------------------------------------------------------
  // Refresh with deduplication
  // -------------------------------------------------------------------------

  Future<bool> _doRefresh() async {
    final inFlight = _refreshCompleter;
    // A refresh started under an older session generation is not joined: its
    // result belongs to the ended session.
    if (inFlight != null && _refreshGeneration == _sessionGeneration) {
      return inFlight.future;
    }

    final mine = Completer<bool>();
    _refreshCompleter = mine;
    _refreshGeneration = _sessionGeneration;
    try {
      final success = await (_refreshHandler?.call() ?? Future.value(false));
      mine.complete(success);
      return success;
    } catch (_) {
      mine.complete(false);
      return false;
    } finally {
      if (identical(_refreshCompleter, mine)) _refreshCompleter = null;
    }
  }

  // -------------------------------------------------------------------------
  // Internal refresh endpoint call
  // -------------------------------------------------------------------------

  /// Calls `POST $apiPrefix/refresh` directly, bypassing retry logic.
  Future<bool> callRefreshEndpoint() async {
    final generation = _sessionGeneration;
    try {
      // On web, X-CSRF-Token is absent when the csrf cookie is gone. The
      // refresh is still sent: /refresh is CSRF-exempt on the servers (node
      // runs no check on it, go lists it in csrfExemptRoutes) and the refresh
      // cookie is HttpOnly and SameSite. The csrf cookie expires with the
      // access token, so after an idle period this header-less refresh is
      // the normal way to resume the session. The header-less refresh
      // reported in issue #33 came from a late 401/403 after logout, which
      // no longer refreshes (see [markSessionEnded]).
      final headers = await _buildHeaders(_buildUri('/refresh'), null);
      // On web: _bearerProvider is null — the refresh token is an HttpOnly cookie
      // managed by the browser. No body is sent; the cookie is included automatically.
      // On native: _bearerProvider is set, _refreshToken is populated from the login
      // response body. If null (e.g. before first login), the refresh will fail gracefully.
      final body = (_bearerProvider != null && _refreshToken != null)
          ? {'refreshToken': _refreshToken}
          : null;
      final response = await _rawSend('POST', '/refresh', headers, body, null);

      // The session ended while the refresh was in flight: its tokens must
      // not be written back to the cleared storage or kept in memory.
      if (_sessionEndedSince(generation)) return false;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _captureBearerTokens(response);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // http.BaseClient implementation
  // -------------------------------------------------------------------------

  /// Sends [request] with auth headers injected, retrying once after a
  /// transparent token refresh on 401 / 403.
  ///
  /// This allows [AuthHttpClient] to be used as a generic [http.Client]
  /// for any call to the backend — no manual token handling required.
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final generation = _sessionGeneration;

    // Inject auth headers before the request is finalised inside _inner.send().
    // The CSRF decision uses request.url exactly as it will be sent.
    final authHeaders = await _buildHeaders(request.url, null);
    request.headers.addAll(authHeaders);

    // Materialise the response so we can inspect the status code and body.
    final streamed = await _inner.send(request);
    final response = await http.Response.fromStream(streamed);

    // Tokens in a response to a request of an ended session are dropped.
    if (_sessionEndedSince(generation)) return _toStreamedResponse(response);

    await _captureBearerTokens(response);

    if ((response.statusCode == 401 || response.statusCode == 403) &&
        !_isExcludedEndpoint(request.url.path)) {
      // Late 401/403 after logout, or no session at all: nothing to refresh,
      // and the logout is already handled (issue #33).
      if (_noSessionToRefresh(generation)) return _toStreamedResponse(response);

      if (_isSessionRevoked(response)) {
        await _onLogout?.call(revoked: true);
        return _toStreamedResponse(response);
      }

      final refreshed = await _doRefresh();
      // The session ended while the refresh was in flight: no retry, and the
      // logout is already handled by whoever ended it.
      if (_sessionEndedSince(generation)) return _toStreamedResponse(response);
      if (refreshed) {
        final retry = _cloneRequest(request);
        final retryHeaders = await _buildHeaders(request.url, null);
        // The session may have ended while the headers were read.
        if (_sessionEndedSince(generation)) return _toStreamedResponse(response);
        retry.headers.addAll(retryHeaders);
        final retryStreamed = await _inner.send(retry);
        final retryResponse = await http.Response.fromStream(retryStreamed);
        return _toStreamedResponse(retryResponse);
      } else {
        await _onLogout?.call(revoked: false);
      }
    }

    return _toStreamedResponse(response);
  }

  @override
  void close() => _inner.close();

  /// Converts a buffered [http.Response] back to [http.StreamedResponse].
  http.StreamedResponse _toStreamedResponse(http.Response r) =>
      http.StreamedResponse(
        Stream.value(r.bodyBytes),
        r.statusCode,
        contentLength: r.contentLength,
        headers: r.headers,
        reasonPhrase: r.reasonPhrase,
      );

  /// Clones an [http.Request] so it can be resent after a token refresh.
  ///
  /// Only [http.Request] (the standard in-memory request) is supported;
  /// multipart and other streaming subtypes cannot be reliably cloned.
  http.Request _cloneRequest(http.BaseRequest original) {
    if (original is http.Request) {
      return http.Request(original.method, original.url)
        ..encoding = original.encoding
        ..bodyBytes = original.bodyBytes;
    }
    throw UnsupportedError(
      'AuthHttpClient cannot retry ${original.runtimeType}. '
      'Use http.Request for authenticated calls through this client.',
    );
  }
}
