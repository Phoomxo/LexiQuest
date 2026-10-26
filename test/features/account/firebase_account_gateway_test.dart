import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/data/firebase_account_gateway.dart';
import 'package:vocab_learning_app/features/account/data/google_sign_in_credential_source.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';

void main() {
  group('registration verification dispatch', () {
    for (final linkAnonymous in <bool>[false, true]) {
      final path = linkAnonymous ? 'link' : 'create';

      test(
        '$path returns the committed session when verification dispatch fails',
        () async {
          for (final failure in <Object>[
            FirebaseAuthException(code: 'network-request-failed'),
            StateError('synthetic provider detail'),
          ]) {
            final registeredUser = _User(
              emailVerified: false,
              verificationFailure: failure,
            );
            final anonymousUser = linkAnonymous
                ? _User(anonymous: true, linkedUser: registeredUser)
                : null;
            final auth = _Auth(anonymousUser, createdUser: registeredUser);

            final session = await FirebaseAccountGateway(
              auth,
            ).register(email: 'learner@example.test', password: 'password123');

            expect(session.uid, 'synthetic-user');
            expect(session.emailVerified, isFalse);
            expect(registeredUser.verificationCalls, 1);
            expect(auth.createCalls, linkAnonymous ? 0 : 1);
            expect(anonymousUser?.linkCalls ?? 0, linkAnonymous ? 1 : 0);
          }
        },
      );

      test('$path failure remains typed and does not dispatch', () async {
        final registeredUser = _User(emailVerified: false);
        final anonymousUser = linkAnonymous
            ? _User(
                anonymous: true,
                linkFailure: FirebaseAuthException(
                  code: 'email-already-in-use',
                ),
              )
            : null;
        final auth = _Auth(
          anonymousUser,
          createdUser: registeredUser,
          createFailure: FirebaseAuthException(code: 'email-already-in-use'),
        );

        await expectLater(
          FirebaseAccountGateway(
            auth,
          ).register(email: 'learner@example.test', password: 'password123'),
          throwsA(
            isA<AccountException>().having(
              (error) => error.code,
              'code',
              AccountFailureCode.emailInUse,
            ),
          ),
        );

        expect(registeredUser.verificationCalls, 0);
        expect(auth.createCalls, linkAnonymous ? 0 : 1);
        expect(anonymousUser?.linkCalls ?? 0, linkAnonymous ? 1 : 0);
      });
    }
  });

  test(
    'profile name is read from and saved through Firebase user metadata',
    () async {
      final user = _User();
      final gateway = FirebaseAccountGateway(_Auth(user));

      expect(gateway.currentSession?.displayName, 'Learner A');
      final updated = await gateway.updateDisplayName('Learner B');

      expect(user.updateCalls, 1);
      expect(updated.displayName, 'Learner B');
      expect(gateway.currentSession?.displayName, 'Learner B');
    },
  );

  test('profile name rejects absent and anonymous Firebase users', () async {
    for (final user in <_User?>[null, _User(anonymous: true)]) {
      await expectLater(
        FirebaseAccountGateway(_Auth(user)).updateDisplayName('Learner B'),
        throwsA(
          isA<AccountException>().having(
            (error) => error.code,
            'code',
            AccountFailureCode.invalidCredential,
          ),
        ),
      );
      expect(user?.updateCalls ?? 0, 0);
    }
  });

  test(
    'profile provider failures use safe typed errors and preserve the name',
    () async {
      for (final failure in [
        FirebaseAuthException(code: 'network-request-failed'),
        StateError('synthetic provider failure'),
      ]) {
        final user = _User()..failure = failure;
        await expectLater(
          FirebaseAccountGateway(_Auth(user)).updateDisplayName('Learner B'),
          throwsA(
            isA<AccountException>().having(
              (error) => error.code,
              'code',
              failure is FirebaseAuthException
                  ? AccountFailureCode.network
                  : AccountFailureCode.unavailable,
            ),
          ),
        );
        expect(user.displayName, 'Learner A');
      }
    },
  );

  group('Google sign in', () {
    test('is unavailable unless a credential source is configured', () {
      expect(
        FirebaseAccountGateway(_Auth(null)).googleSignInAvailable,
        isFalse,
      );
      expect(
        FirebaseAccountGateway(
          _Auth(null),
          google: _GoogleSource(),
        ).googleSignInAvailable,
        isTrue,
      );
    });

    test('links an anonymous user with one provider credential', () async {
      final linked = _User();
      final anonymous = _User(anonymous: true, linkedUser: linked);
      final auth = _Auth(anonymous);
      final google = _GoogleSource();

      final session = await FirebaseAccountGateway(
        auth,
        google: google,
      ).signInWithGoogle();

      expect(session.uid, 'synthetic-user');
      expect(google.credentialCalls, 1);
      expect(anonymous.linkCalls, 1);
      expect(auth.credentialSignInCalls, 0);
    });

    test(
      'falls back once when the Google credential already has an owner',
      () async {
        final existing = _User();
        final anonymous = _User(
          anonymous: true,
          linkFailure: FirebaseAuthException(code: 'credential-already-in-use'),
        );
        final auth = _Auth(anonymous, credentialUser: existing);
        final google = _GoogleSource();

        final session = await FirebaseAccountGateway(
          auth,
          google: google,
        ).signInWithGoogle();

        expect(session.uid, 'synthetic-user');
        expect(google.credentialCalls, 1);
        expect(anonymous.linkCalls, 1);
        expect(auth.credentialSignInCalls, 1);
      },
    );

    test('credential source failure does not call Firebase', () async {
      final auth = _Auth(null);
      final google = _GoogleSource(
        failure: const AccountException(AccountFailureCode.cancelled),
      );

      await expectLater(
        FirebaseAccountGateway(auth, google: google).signInWithGoogle(),
        throwsA(
          isA<AccountException>().having(
            (error) => error.code,
            'code',
            AccountFailureCode.cancelled,
          ),
        ),
      );
      expect(auth.credentialSignInCalls, 0);
    });
  });
}

final class _Auth implements FirebaseAuth {
  _Auth(
    this.currentUser, {
    this.createdUser,
    this.createFailure,
    this.credentialUser,
  });
  @override
  final User? currentUser;
  final User? createdUser;
  final Object? createFailure;
  final User? credentialUser;
  int createCalls = 0;
  int credentialSignInCalls = 0;

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    createCalls++;
    if (createFailure case final error?) throw error;
    return _UserCredential(createdUser);
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    credentialSignInCalls++;
    return _UserCredential(credentialUser);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _GoogleSource implements GoogleCredentialSource {
  _GoogleSource({this.failure});

  final Object? failure;
  int credentialCalls = 0;

  @override
  Future<AuthCredential> credential() async {
    credentialCalls++;
    if (failure case final error?) throw error;
    return EmailAuthProvider.credential(
      email: 'synthetic@example.test',
      password: 'synthetic-password',
    );
  }

  @override
  Future<void> signOut() async {}
}

final class _User implements User {
  _User({
    this.anonymous = false,
    this.emailVerified = true,
    this.linkedUser,
    this.linkFailure,
    this.verificationFailure,
  });
  final bool anonymous;
  @override
  final bool emailVerified;
  final User? linkedUser;
  final Object? linkFailure;
  final Object? verificationFailure;
  Object? failure;
  int updateCalls = 0;
  int linkCalls = 0;
  int verificationCalls = 0;
  @override
  String? displayName = 'Learner A';
  @override
  String get uid => 'synthetic-user';
  @override
  String? get email => 'learner@example.test';
  @override
  bool get isAnonymous => anonymous;
  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    linkCalls++;
    if (linkFailure case final error?) throw error;
    return _UserCredential(linkedUser ?? this);
  }

  @override
  Future<void> sendEmailVerification([
    ActionCodeSettings? actionCodeSettings,
  ]) async {
    verificationCalls++;
    if (verificationFailure case final error?) throw error;
  }

  @override
  Future<void> updateDisplayName(String? value) async {
    updateCalls++;
    if (failure case final error?) throw error;
    displayName = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _UserCredential implements UserCredential {
  const _UserCredential(this.user);

  @override
  final User? user;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
