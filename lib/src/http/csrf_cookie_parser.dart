/// Parses CSRF token cookies in priority order:
/// `__Host-csrf-token` > `__Secure-csrf-token` > `csrf-token`.
///
/// [cookieString] is the raw `document.cookie` string (or any semicolon-separated
/// cookie string). Returns `null` when no CSRF cookie is found.
String? parseCsrfFromCookies(String cookieString) {
  final cookies = <String, String>{};
  for (final part in cookieString.split(';')) {
    final idx = part.indexOf('=');
    if (idx == -1) continue;
    final name = part.substring(0, idx).trim();
    final value = part.substring(idx + 1).trim();
    cookies[name] = value;
  }
  return cookies['__Host-csrf-token'] ??
      cookies['__Secure-csrf-token'] ??
      cookies['csrf-token'];
}

/// Pure, platform-independent same-origin check.
///
/// Returns `true` when [url] is considered same-origin with the backend
/// determined by [apiPrefix] and [windowOrigin]:
///
/// - Relative [url] (no scheme, no authority) — always same-origin.
/// - Scheme-relative [url] (`//host/...`) — always cross-origin: the host is
///   chosen by whoever built the URL, so the CSRF token is never attached
///   (issue #31).
/// - Absolute [url] + absolute [apiPrefix] — compare scheme, host and port.
/// - Absolute [url] + relative [apiPrefix] — compare against [windowOrigin].
///
/// [windowOrigin] is the `window.location.origin` value on web, or an empty
/// string / any placeholder on native (where this function is not used in
/// practice).
bool isSameOriginPure(String url, String apiPrefix, String windowOrigin) {
  try {
    final parsedUrl = Uri.tryParse(url);
    if (parsedUrl == null) return false;

    if (!parsedUrl.hasScheme) {
      // Scheme-relative URL (`//host/path`): the browser would send it to
      // `host`, so treat it as cross-origin (issue #31).
      if (parsedUrl.hasAuthority) return false;
      // Relative URL (path only) — same origin by definition.
      return true;
    }

    if (apiPrefix.startsWith('http://') || apiPrefix.startsWith('https://')) {
      final parsedPrefix = Uri.tryParse(apiPrefix);
      if (parsedPrefix == null) return false;
      return parsedUrl.scheme == parsedPrefix.scheme &&
          parsedUrl.host == parsedPrefix.host &&
          parsedUrl.port == parsedPrefix.port;
    }

    // Relative apiPrefix — compare against the provided window origin.
    final windowUri = Uri.tryParse(windowOrigin);
    if (windowUri == null) return false;
    return parsedUrl.scheme == windowUri.scheme &&
        parsedUrl.host == windowUri.host &&
        parsedUrl.port == windowUri.port;
  } catch (_) {
    return false;
  }
}
