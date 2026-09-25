/// Represents an active user session.
class SessionInfo {
  /// Unique session handle used to identify and revoke this session.
  ///
  /// The server sends it as `sessionHandle`: see [SessionInfo.fromJson].
  final String handle;

  /// User-agent string of the browser or client that created this session.
  final String? userAgent;

  /// IP address from which this session was created.
  final String? ipAddress;

  /// Timestamp when this session was created.
  final DateTime? createdAt;

  /// Timestamp of the last activity for this session.
  final DateTime? lastActiveAt;

  /// Whether this is the currently active session for the authenticated user.
  final bool isCurrent;

  const SessionInfo({
    required this.handle,
    this.userAgent,
    this.ipAddress,
    this.createdAt,
    this.lastActiveAt,
    this.isCurrent = false,
  });

  /// Builds a [SessionInfo] from one entry of the `GET /sessions` response.
  ///
  /// The handle is read from `sessionHandle`, the key the awesome-lang-auth
  /// servers send, with a fallback to `handle` for JSON written by [toJson]
  /// before 1.10.1. Optional fields that are missing or of an unexpected type
  /// are left `null`, and [isCurrent] is `true` only for a JSON `true`.
  ///
  /// Throws a [FormatException] when neither key holds a string, because a
  /// session without a handle cannot be revoked.
  factory SessionInfo.fromJson(Map<String, dynamic> json) {
    final sessionHandle = json['sessionHandle'];
    final handle = sessionHandle is String ? sessionHandle : json['handle'];
    if (handle is! String) {
      throw const FormatException(
          'SessionInfo: the session has no "sessionHandle" string');
    }
    return SessionInfo(
      handle: handle,
      userAgent: _string(json['userAgent']),
      ipAddress: _string(json['ipAddress']),
      createdAt: _date(json['createdAt']),
      lastActiveAt: _date(json['lastActiveAt']),
      isCurrent: json['isCurrent'] == true,
    );
  }

  /// Serialises this session with the keys the server uses, so
  /// `SessionInfo.fromJson(session.toJson())` gives the session back.
  Map<String, dynamic> toJson() => {
        'sessionHandle': handle,
        if (userAgent != null) 'userAgent': userAgent,
        if (ipAddress != null) 'ipAddress': ipAddress,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (lastActiveAt != null)
          'lastActiveAt': lastActiveAt!.toIso8601String(),
        'isCurrent': isCurrent,
      };

  static String? _string(Object? value) => value is String ? value : null;

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;
}
