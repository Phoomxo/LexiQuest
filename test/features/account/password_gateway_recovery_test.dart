import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/data/firebase_account_gateway.dart';

void main() {
  for (final replacement in ['removed', 'different', 'same-uid-new-session']) {
    test(
      'BB gateway stops update after $replacement during reauthentication',
      () async {
        final user = FakeUser();
        final auth = FakeAuth()..user = user;
        final gateway = FirebaseAccountGateway(auth);
        Object? caught;
        final result = gateway
            .changePassword(
              currentPassword: 'synthetic-old-123',
              newPassword: 'synthetic-new-456',
            )
            .catchError((Object e) {
              caught = e;
            });
        auth.user = replacement == 'removed'
            ? null
            : FakeUser(
                uid: replacement == 'different'
                    ? 'other-synthetic'
                    : 'synthetic-user',
              );
        user.reauthenticated.complete(FakeCredential());
        await result;
        expect(user.updates, 0);
        expect(caught, isNotNull);
      },
    );
  }
  test('BB gateway rejects simultaneous explicit submissions', () async {
    final user = FakeUser();
    final auth = FakeAuth()..user = user;
    final gateway = FirebaseAccountGateway(auth);
    final first = gateway.changePassword(
      currentPassword: 'synthetic-old-123',
      newPassword: 'synthetic-new-456',
    );
    Object? secondError;
    final second = gateway
        .changePassword(
          currentPassword: 'synthetic-old-123',
          newPassword: 'synthetic-new-789',
        )
        .catchError((Object e) {
          secondError = e;
        });
    user.reauthenticated.complete(FakeCredential());
    await first;
    await second;
    expect(user.updates, 1);
    expect(secondError, isNotNull);
  });
  test(
    'BB caller retirement during reauthentication prevents update',
    () async {
      final user = FakeUser();
      final auth = FakeAuth()..user = user;
      final gateway = FirebaseAccountGateway(auth);
      var active = true;
      Object? caught;
      final result = gateway
          .changePassword(
            currentPassword: 'synthetic-old-123',
            newPassword: 'synthetic-new-456',
            isCurrent: () => active,
          )
          .catchError((Object e) {
            caught = e;
          });
      active = false;
      user.reauthenticated.complete(FakeCredential());
      await result;
      expect(user.updates, 0);
      expect(caught, isNotNull);
    },
  );
  test('BB SDK fresh wrappers preserve current session operation', () async {
    final user = FakeUser();
    final auth = FakeAuth()
      ..user = user
      ..freshWrappers = true;
    final gateway = FirebaseAccountGateway(auth);
    Object? caught;
    final result = gateway
        .changePassword(
          currentPassword: 'synthetic-old-123',
          newPassword: 'synthetic-new-456',
        )
        .catchError((Object e) {
          caught = e;
        });
    user.reauthenticated.complete(FakeCredential());
    await result;
    expect(caught, isNull);
    expect(user.updates, 1);
  });
  for (final failure in [false, true]) {
    test(
      'BB sent update remains committed after caller retirement failure=$failure',
      () async {
        final user = FakeUser();
        final auth = FakeAuth()..user = user;
        final gateway = FirebaseAccountGateway(auth);
        final pending = Completer<void>();
        user.updatePending = pending.future;
        var active = true;
        Object? caught;
        final result = gateway
            .changePassword(
              currentPassword: 'synthetic-old-123',
              newPassword: 'synthetic-new-456',
              isCurrent: () => active,
            )
            .catchError((Object e) {
              caught = e;
            });
        user.reauthenticated.complete(FakeCredential());
        await user.updateEntered.future;
        active = false;
        if (failure) {
          pending.completeError(
            FirebaseAuthException(code: 'network-request-failed'),
          );
        } else {
          pending.complete();
        }
        await result;
        expect(user.updates, 1);
        expect(caught, failure ? isNotNull : isNull);
      },
    );
  }
  test(
    'BB reauthentication error never sends update and releases admission',
    () async {
      final user = FakeUser();
      final auth = FakeAuth()..user = user;
      final gateway = FirebaseAccountGateway(auth);
      Object? caught;
      final result = gateway
          .changePassword(
            currentPassword: 'synthetic-old-123',
            newPassword: 'synthetic-new-456',
          )
          .catchError((Object e) {
            caught = e;
          });
      user.reauthenticated.completeError(
        FirebaseAuthException(code: 'wrong-password'),
      );
      // Observe this synthetic Future immediately before the async initial snapshot.
      user.reauthenticated.future.ignore();
      await result;
      expect(user.updates, 0);
      expect(caught, isNotNull);
      final current = FakeUser();
      auth.user = current;
      final retry = gateway.changePassword(
        currentPassword: 'synthetic-old-123',
        newPassword: 'synthetic-new-456',
      );
      current.reauthenticated.complete(FakeCredential());
      await retry;
      expect(current.updates, 1);
    },
  );
  test('BB gateway current session updates once', () async {
    final user = FakeUser();
    final auth = FakeAuth()..user = user;
    final gateway = FirebaseAccountGateway(auth);
    final result = gateway.changePassword(
      currentPassword: 'synthetic-old-123',
      newPassword: 'synthetic-new-456',
    );
    user.reauthenticated.complete(FakeCredential());
    await result;
    expect(user.updates, 1);
  });
}

class FakeAuth implements FirebaseAuth {
  User? _user;
  final changes = StreamController<User?>.broadcast(sync: true);
  User? get user => _user;
  set user(User? value) {
    _user = value;
    changes.add(value);
  }

  @override
  Stream<User?> authStateChanges() => Stream<User?>.multi((sink) {
    sink.addSync(_user);
    final sub = changes.stream.listen(sink.addSync, onError: sink.addErrorSync);
    sink.onCancel = sub.cancel;
  });
  bool freshWrappers = false;
  @override
  User? get currentUser =>
      freshWrappers && user != null ? WrappedUser(user!) : user;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeUser implements User {
  FakeUser({this.uid = 'synthetic-user'});
  @override
  final String uid;
  @override
  String get email => 'synthetic@example.test';
  final reauthenticated = Completer<UserCredential>();
  int updates = 0;
  Future<void>? updatePending;
  final updateEntered = Completer<void>();
  @override
  Future<UserCredential> reauthenticateWithCredential(AuthCredential c) =>
      reauthenticated.future;
  @override
  Future<void> updatePassword(String value) async {
    updates++;
    if (!updateEntered.isCompleted) updateEntered.complete();
    if (updatePending != null) await updatePending;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class FakeCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class WrappedUser implements User {
  WrappedUser(this.inner);
  final User inner;
  @override
  String get uid => inner.uid;
  @override
  String? get email => inner.email;
  @override
  Future<UserCredential> reauthenticateWithCredential(AuthCredential c) =>
      inner.reauthenticateWithCredential(c);
  @override
  Future<void> updatePassword(String value) => inner.updatePassword(value);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
