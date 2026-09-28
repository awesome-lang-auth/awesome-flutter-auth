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

  // -------------------------------------------------------------------------
  // URL helpers
  // -------------------------------------------------------------------------

  Uri _buildUri(String path, {bool isAbsolute = false}) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return Uri.parse(path);
    }
    if (isAbsolute) {
      if (_apiPrefix.startsWith('http://') || _apiPrefix.startsWith('https://')) {
        final base = Uri.parse(_apiPrefix);
        return base.replace(path: path);
      }
      return Uri(path: path);
    }
    if (_apiPrefix.startsWith('http://') || _apiPrefix.startsWith('https://')) {
      return Uri.parse('$_apiPrefix$path');
    }
    return Uri(path: '$_apiPrefix$path');
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

  // -------------------------------------------------------------------------
  // Header helpers
  // -------------------------------------------------------------------------

  Future<Map<String, String>> _buildHeaders(
    String path,
    Map<String, String>? extra, {
    bool includeAuthHeaders = true,
    bool isAbsolute = false,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...?extra,
    };

    if (includeAuthHeaders) {
      final url = _buildUri(path, isAbsolute: isAbsolute).toString();
      final csrf = _csrfProvider?.call(url);
      if (csrf != null) headers['X-CSRF-Token'] = csrf;

      if (_bearerProvider != null) {
        // Interop contract with awesome-node-auth: native clients opt into
        // token-in-body delivery via X-Auth-Strategy=bearer.
        headers['X-Auth-Strategy'] = 'bearer';
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
    final allHeaders =
        await _buildHeaders(path, headers, isAbsolute: isAbsolute);
    final response = await _rawSend(
      method,
      path,
      allHeaders,
      body,
      queryParameters,
      isAbsolute: isAbsolute,
    );

    await _captureBearerTokens(response);

    if ((response.statusCode == 401 || response.statusCode == 403) &&
        !_isExcludedEndpoint(path)) {
      return _handleUnauthorized(method, path, response,
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

  Future<http.Response> _handleUnauthorized(
    String method,
    String path,
    http.Response response, {
    Map<String, String>? headers,
    Object? body,
    Map<String, String>? queryParameters,
    bool isAbsolute = false,
  }) async {
    if (_isSessionRevoked(response)) {
      await _onLogout?.call(revoked: true);
      return response;
    }

    final refreshed = await _doRefresh();
    if (refreshed) {
      final retryHeaders =
          await _buildHeaders(path, headers, isAbsolute: isAbsolute);
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
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();
    try {
      final success = await (_refreshHandler?.call() ?? Future.value(false));
      _refreshCompleter!.complete(success);
      return success;
    } catch (_) {
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
  }

  // -------------------------------------------------------------------------
  // Internal refresh endpoint call
  // -------------------------------------------------------------------------

  /// Calls `POST $apiPrefix/refresh` directly, bypassing retry logic.
  Future<bool> callRefreshEndpoint() async {
    try {
      final headers = await _buildHeaders('/refresh', null);
      // On web: _bearerProvider is null — the refresh token is an HttpOnly cookie
      // managed by the browser. No body is sent; the cookie is included automatically.
      // On native: _bearerProvider is set, _refreshToken is populated from the login
      // response body. If null (e.g. before first login), the refresh will fail gracefully.
      final body = (_bearerProvider != null && _refreshToken != null)
          ? {'refreshToken': _refreshToken}
          : null;
      final response = await _rawSend('POST', '/refresh', headers, body, null);

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
    // Inject auth headers before the request is finalised inside _inner.send().
    final authHeaders = await _buildHeaders(request.url.toString(), null);
    request.headers.addAll(authHeaders);

    // Materialise the response so we can inspect the status code and body.
    final streamed = await _inner.send(request);
    final response = await http.Response.fromStream(streamed);

    await _captureBearerTokens(response);

    if ((response.statusCode == 401 || response.statusCode == 403) &&
        !_isExcludedEndpoint(request.url.path)) {
      if (_isSessionRevoked(response)) {
        await _onLogout?.call(revoked: true);
        return _toStreamedResponse(response);
      }

      final refreshed = await _doRefresh();
      if (refreshed) {
        final retry = _cloneRequest(request);
        final retryHeaders = await _buildHeaders(request.url.toString(), null);
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
