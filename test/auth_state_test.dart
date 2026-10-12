import 'dart:async';

import 'package:test/test.dart';

import 'package:awesome_flutter_auth/src/auth_state.dart';
import 'package:awesome_flutter_auth/src/auth_user.dart';

/// [AuthState.userStream] must not lose state changes made right after
/// `listen`, nor deliver them too late (issue #36). These run on the VM, on
/// Chrome with dart2js and on Chrome with dart2wasm.
void main() {
  const user = AuthUser(
    sub: 'user-123',
    email: 'test@example.com',
    isEmailVerified: true,
  );

  late AuthState state;

  setUp(() => state = AuthState());
  tearDown(() => state.dispose());

  Future<void> microtasks(int n) async {
    for (var i = 0; i < n; i++) {
      await Future<void>.value();
    }
  }

  test('emits the value current at listen time, then each change', () async {
    final events = <AuthUser?>[];
    final sub = state.userStream.listen(events.add);

    // Synchronously after listen: neither the initial value nor the change
    // may be lost, and the initial value is the one from before the change.
    state.setUser(user);
    state.setUser(null);
    await microtasks(10);
    await sub.cancel();

    expect(events, [isNull, same(user), isNull]);
  });

  for (final delay in [0, 1, 2, 3, 5]) {
    test('no change is lost when made $delay microtasks after listen',
        () async {
      final events = <AuthUser?>[];
      final sub = state.userStream.listen(events.add);

      await microtasks(delay);
      state.setUser(user);
      await microtasks(1);
      state.setUser(null);
      await microtasks(10);
      await sub.cancel();

      expect(events, [isNull, same(user), isNull]);
    });
  }

  test('a change is delivered one microtask after setUser', () async {
    final events = <AuthUser?>[];
    final sub = state.userStream.listen(events.add);
    await microtasks(5);

    state.setUser(user);
    await microtasks(1);
    state.setUser(null);
    await microtasks(1);
    await sub.cancel();

    expect(events, [isNull, same(user), isNull]);
  });

  test('a late subscriber gets the current value first', () async {
    state.setUser(user);
    final events = <AuthUser?>[];
    final sub = state.userStream.listen(events.add);
    state.setUser(null);
    await microtasks(10);
    await sub.cancel();

    expect(events, [same(user), isNull]);
  });

  test('listen does not deliver synchronously', () {
    final events = <AuthUser?>[];
    state.userStream.listen(events.add);
    state.setUser(user);
    expect(events, isEmpty);
  });

  test('each subscriber gets its own events', () async {
    final a = <AuthUser?>[];
    final b = <AuthUser?>[];
    final stream = state.userStream;
    final subA = stream.listen(a.add);
    state.setUser(user);
    await microtasks(10);
    final subB = stream.listen(b.add);
    state.setUser(null);
    await microtasks(10);
    await subA.cancel();
    await subB.cancel();

    expect(a, [isNull, same(user), isNull]);
    expect(b, [same(user), isNull]);
  });

  test('a paused subscription buffers changes in order', () async {
    final events = <AuthUser?>[];
    final sub = state.userStream.listen(events.add);
    sub.pause();
    state.setUser(user);
    state.setUser(null);
    await microtasks(10);
    expect(events, isEmpty);

    sub.resume();
    await microtasks(10);
    await sub.cancel();

    expect(events, [isNull, same(user), isNull]);
  });

  test('dispose closes the stream', () async {
    final done = Completer<void>();
    final events = <AuthUser?>[];
    state.userStream.listen(events.add, onDone: done.complete);
    await microtasks(5);
    state.setUser(user);
    state.dispose();

    await done.future.timeout(const Duration(seconds: 5));
    expect(events, [isNull, same(user)]);
  });

  test('a subscription made after dispose gets the value and closes', () async {
    state.setUser(user);
    state.dispose();

    final events = await state.userStream.toList();
    expect(events, [same(user)]);
  });
}
