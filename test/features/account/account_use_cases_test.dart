import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';

void main() {
  late _FakeGateway gateway;
  late _FakeOwnerRepository owners;
  late _FakeUpgradeRepository upgrades;
  late AccountUseCases accounts;

  setUp(() {
    gateway = _FakeGateway();
    owners = _FakeOwnerRepository();
    upgrades = _FakeUpgradeRepository();
    accounts = AccountUseCases(
      gateway: gateway,
      owners: owners,
      upgradeGuestOwner: UpgradeGuestOwner(upgrades),
    );
  });

  test(
    'registration links the local guest owner without dropping data',
    () async {
      final session = await accounts.register(
        email: ' Student@Example.com ',
        password: 'password123',
      );

      expect(session.uid, 'firebase-user');
      expect(gateway.registerEmail, 'student@example.com');
      expect(upgrades.upgradeOwnerId, 'local-owner');
      expect(upgrades.upgradeUid, 'firebase-user');
    },
  );

  test(
    'sign in merges the active local owner into the existing account',
    () async {
      await accounts.signIn(
        email: 'student@example.com',
        password: 'password123',
      );

      expect(upgrades.upgradeCalls, 1);
      expect(upgrades.upgradeUid, 'firebase-user');
    },
  );

  test('Google sign in binds through the same owner upgrade path', () async {
    gateway.googleAvailable = true;

    final session = await accounts.signInWithGoogle();

    expect(session.uid, 'google-user');
    expect(gateway.googleCalls, 1);
    expect(upgrades.upgradeOwnerId, 'local-owner');
    expect(upgrades.upgradeUid, 'google-user');
  });

  test('Google sign in is safely unavailable when not configured', () async {
    expect(accounts.googleSignInAvailable, isFalse);
    await expectLater(
      accounts.signInWithGoogle(),
      throwsA(
        isA<AccountException>().having(
          (error) => error.code,
          'code',
          AccountFailureCode.unavailable,
        ),
      ),
    );
    expect(gateway.googleCalls, 0);
  });

  test('Google owner binding failure signs the provider session out', () async {
    gateway.googleAvailable = true;
    upgrades.upgradeFailure = StateError('synthetic bind failure');

    await expectLater(accounts.signInWithGoogle(), throwsStateError);

    expect(gateway.googleCalls, 1);
    expect(gateway.signOutCalls, 1);
  });

  test('logout creates a fresh local guest after provider sign-out', () async {
    final result = await accounts.signOutToLocalGuest();

    expect(gateway.signOutCalls, 1);
    expect(upgrades.logoutCalls, 1);
    expect(upgrades.transitionLog, ['createGuest', 'signOut']);
    expect(result.mode, OwnerUpgradeMode.localGuestCreated);
  });

  test('sign in signs out provider when local owner binding fails', () async {
    upgrades.upgradeFailure = StateError('disk write failed');

    await expectLater(
      accounts.signIn(email: 'student@example.com', password: 'password123'),
      throwsStateError,
    );

    expect(gateway.signOutCalls, 1);
  });

  test(
    'startup binds an authenticated provider session to local data',
    () async {
      gateway.currentSession = const AccountSession(
        uid: 'firebase-user',
        email: 'student@example.com',
        isAnonymous: false,
        emailVerified: true,
      );

      await accounts.reconcileLocalOwner();

      expect(upgrades.upgradeCalls, 1);
      expect(upgrades.upgradeUid, 'firebase-user');
    },
  );

  test('startup creates a guest when provider session is absent', () async {
    owners.activeOwner = LocalOwner(
      id: 'account-owner',
      firebaseUid: 'firebase-user',
      createdAtUtc: DateTime.utc(2026, 7, 30),
      upgradedAtUtc: DateTime.utc(2026, 7, 30),
    );

    await accounts.reconcileLocalOwner();

    expect(upgrades.logoutCalls, 1);
  });

  test('logout rolls local owner back when provider sign-out fails', () async {
    gateway.signOutFailure = StateError('provider failure');

    await expectLater(accounts.signOutToLocalGuest(), throwsStateError);

    expect(upgrades.rollbackCalls, 1);
    expect(upgrades.rollbackPreviousOwnerId, 'local-owner');
    expect(upgrades.rollbackGuestOwnerId, 'new-local-owner');
  });

  test('validates email and password before provider calls', () async {
    await expectLater(
      accounts.register(email: 'bad', password: 'password123'),
      throwsA(
        isA<AccountException>().having(
          (error) => error.code,
          'code',
          AccountFailureCode.invalidEmail,
        ),
      ),
    );
    await expectLater(
      accounts.register(email: 'a@example.com', password: 'short'),
      throwsA(
        isA<AccountException>().having(
          (error) => error.code,
          'code',
          AccountFailureCode.weakPassword,
        ),
      ),
    );
    expect(gateway.registerCalls, 0);
  });

  test(
    'profile update trims the display name before the provider call',
    () async {
      gateway.currentSession = const AccountSession(
        uid: 'firebase-user',
        email: 'learner@example.test',
        isAnonymous: false,
        emailVerified: true,
      );
      owners.activeOwner = LocalOwner(
        id: 'local-owner',
        firebaseUid: 'firebase-user',
        createdAtUtc: DateTime.utc(2026, 10, 20),
      );
      final session = await accounts.updateDisplayName('  ผู้เรียน A  ');

      expect(gateway.updateDisplayNameCalls, 1);
      expect(gateway.updatedDisplayName, 'ผู้เรียน A');
      expect(session.displayName, 'ผู้เรียน A');
    },
  );

  test(
    'profile update rejects unsafe display names before provider calls',
    () async {
      for (final value in ['', '   ', 'name\nwith control', 'a' * 51]) {
        await expectLater(
          accounts.updateDisplayName(value),
          throwsA(
            isA<AccountException>().having(
              (error) => error.code,
              'code',
              AccountFailureCode.invalidDisplayName,
            ),
          ),
        );
      }

      expect(gateway.updateDisplayNameCalls, 0);
    },
  );

  test(
    'profile update rejects absent, anonymous, or mismatched sessions',
    () async {
      for (final session in <AccountSession?>[
        null,
        const AccountSession(
          uid: 'anonymous',
          email: null,
          isAnonymous: true,
          emailVerified: false,
        ),
        const AccountSession(
          uid: 'other-user',
          email: 'other@example.test',
          isAnonymous: false,
          emailVerified: true,
        ),
      ]) {
        gateway.currentSession = session;
        await expectLater(
          accounts.updateDisplayName('ผู้เรียน A'),
          throwsA(
            isA<AccountException>().having(
              (error) => error.code,
              'code',
              AccountFailureCode.invalidCredential,
            ),
          ),
        );
      }
      expect(gateway.updateDisplayNameCalls, 0);
      expect(upgrades.upgradeCalls, 0);
    },
  );

  test('email action parser follows the deterministic App Link contract', () {
    final fixture =
        jsonDecode(
              File('test/fixtures/email_action_links.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(fixture['schemaVersion'], 1);

    for (final entry
        in (fixture['accepted'] as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      final action = EmailAction.parse(Uri.parse(entry['url'] as String));
      final expectedMode = switch (entry['mode']) {
        'verifyEmail' => EmailActionMode.verifyEmail,
        'resetPassword' => EmailActionMode.resetPassword,
        _ => EmailActionMode.unknown,
      };
      expect(action?.mode, expectedMode, reason: entry['id'] as String);
      expect(action?.code, entry['code'], reason: entry['id'] as String);
    }

    for (final entry
        in (fixture['rejected'] as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      expect(
        EmailAction.parse(Uri.parse(entry['url'] as String)),
        isNull,
        reason: entry['id'] as String,
      );
    }
  });
}

final class _FakeGateway implements AccountGateway, GoogleAccountGateway {
  int registerCalls = 0;
  int signOutCalls = 0;
  int updateDisplayNameCalls = 0;
  String? registerEmail;
  String? updatedDisplayName;
  Object? signOutFailure;
  bool googleAvailable = false;
  int googleCalls = 0;

  @override
  bool get googleSignInAvailable => googleAvailable;

  @override
  AccountSession? currentSession;

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) async {
    registerCalls += 1;
    registerEmail = email;
    return const AccountSession(
      uid: 'firebase-user',
      email: 'student@example.com',
      isAnonymous: false,
      emailVerified: false,
    );
  }

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => register(email: email, password: password);

  @override
  Future<AccountSession> signInWithGoogle() async {
    googleCalls += 1;
    return const AccountSession(
      uid: 'google-user',
      email: 'google@example.test',
      isAnonymous: false,
      emailVerified: true,
    );
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    _activeUpgradeRepository?.transitionLog.add('signOut');
    if (signOutFailure case final failure?) throw failure;
  }

  @override
  Future<void> applyEmailVerificationCode(String code) async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {}

  @override
  Future<AccountSession> reload() async => currentSession!;

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> sendVerification() async {}

  @override
  Future<AccountSession> updateDisplayName(String displayName) async {
    updateDisplayNameCalls += 1;
    updatedDisplayName = displayName;
    return AccountSession(
      uid: 'firebase-user',
      email: 'student@example.com',
      displayName: displayName,
      isAnonymous: false,
      emailVerified: true,
    );
  }
}

final class _FakeOwnerRepository implements LocalOwnerRepository {
  LocalOwner activeOwner = LocalOwner(
    id: 'local-owner',
    firebaseUid: null,
    createdAtUtc: DateTime.utc(2026, 7, 30),
    upgradedAtUtc: null,
  );

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => activeOwner;

  @override
  Future<LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async => getOrCreateActiveOwner();
}

final class _FakeUpgradeRepository implements OwnerUpgradeRepository {
  _FakeUpgradeRepository() {
    _activeUpgradeRepository = this;
  }

  int upgradeCalls = 0;
  int logoutCalls = 0;
  int rollbackCalls = 0;
  String? upgradeOwnerId;
  String? upgradeUid;
  String? rollbackPreviousOwnerId;
  String? rollbackGuestOwnerId;
  Object? upgradeFailure;
  final List<String> transitionLog = [];

  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) async {
    upgradeCalls += 1;
    if (upgradeFailure case final failure?) throw failure;
    upgradeOwnerId = activeOwnerId;
    upgradeUid = firebaseUid;
    return const OwnerUpgradeResult(
      targetOwnerId: 'local-owner',
      mode: OwnerUpgradeMode.anonymousBound,
      conflictCount: 0,
    );
  }

  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() async {
    logoutCalls += 1;
    transitionLog.add('createGuest');
    return const OwnerUpgradeResult(
      targetOwnerId: 'new-local-owner',
      mode: OwnerUpgradeMode.localGuestCreated,
      conflictCount: 0,
    );
  }

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) async {
    rollbackCalls += 1;
    rollbackPreviousOwnerId = previousOwnerId;
    rollbackGuestOwnerId = guestOwnerId;
    transitionLog.add('rollbackGuest');
  }
}

_FakeUpgradeRepository? _activeUpgradeRepository;
