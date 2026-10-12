import 'dart:async';

import 'auth_user.dart';

/// Reactive authentication state that notifies listeners of user changes.
class AuthState {
  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();

  AuthUser? _currentUser;
  bool _isInitialized = false;

  /// Stream that emits the current user whenever authentication state changes.
  ///
  /// Emits `null` when the user is not authenticated.
  ///
  /// New subscribers always receive the current value immediately upon
  /// subscription, followed by future state changes.
  ///
  /// The current value is read, and the subscription to state changes is
  /// made, synchronously inside `listen`, so no [setUser] call made after
  /// `listen` returns is lost (issue #36).
  Stream<AuthUser?> get userStream => Stream<AuthUser?>.multi((listener) {
        // Delivered asynchronously, so `listen` returns before the first event.
        listener.add(_currentUser);
        final changes = _controller.stream.listen(
          // The broadcast controller already delivers in a later microtask;
          // forwarding synchronously avoids a second hop. While the initial
          // value is still pending, addSync queues behind it, so the order
          // is kept.
          listener.addSync,
          onError: listener.addErrorSync,
          onDone: listener.closeSync,
        );
        listener
          ..onPause = changes.pause
          ..onResume = changes.resume
          ..onCancel = changes.cancel;
      });

  /// The currently authenticated user, or `null` if not authenticated.
  AuthUser? get currentUser => _currentUser;

  /// Whether the user is currently authenticated.
  bool get isAuthenticated => _currentUser != null;

  /// Whether [AuthClient] has completed its initial session check.
  bool get isInitialized => _isInitialized;

  /// Updates the current user and notifies all listeners.
  void setUser(AuthUser? user) {
    _currentUser = user;
    if (!_controller.isClosed) {
      _controller.add(user);
    }
  }

  /// Marks the auth client as initialized (first session check complete).
  void setInitialized() {
    _isInitialized = true;
  }

  /// Releases resources held by this state object.
  void dispose() {
    _controller.close();
  }
}
