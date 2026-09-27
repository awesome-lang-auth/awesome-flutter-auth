/// Flutter/Dart authentication client for awesome-lang-auth servers
/// (awesome-node-auth and the ports that speak its wire contract).
///
/// Formerly published as `awesome_node_auth_flutter`.
///
/// Supports:
/// - Web (including WASM): cookie-based auth with CSRF protection
/// - Native (iOS, Android, Desktop): Bearer token with in-memory storage
library;

export 'src/auth_client.dart';
export 'src/auth_events.dart';
export 'src/auth_options.dart';
export 'src/auth_state.dart';
export 'src/auth_user.dart';
export 'src/http/token_storage.dart';
export 'src/models/auth_result.dart';
export 'src/models/session_info.dart';
export 'src/models/ui_config.dart';
export 'offline_tokens.dart';
