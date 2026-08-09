import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';

void main() {
  late _FakeGateway gateway;
  late _FakeOwnerRepository owners;
  late _FakeUpgradeRepository upgrades;
  late _MemoryAppEntryStateStore entryState;
  late AccountUseCases accounts;

  setUp(() {
    gateway = _FakeGateway();
    owners = _FakeOwnerRepository();
    upgrades = _FakeUpgradeRepository();
    entryState = _MemoryAppEntryStateStore(AppEntryMode.guest);
    accounts = AccountUseCases(
      gateway: gateway,
      owners: owners,
      upgradeGuestOwner: UpgradeGuestOwner(upgrades),
      entryState: entryState,
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
      expect(entryState.mode, AppEntryMode.signedOut);
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
      expect(entryState.mode, AppEntryMode.signedOut);
    },
  );

  test('logout creates a fresh local guest after provider sign-out', () async {
    final result = await accounts.signOutToLocalGuest();

    expect(gateway.signOutCalls, 1);
    expect(upgrades.logoutCalls, 1);
    expect(upgrades.transitionLog, ['createGuest', 'signOut']);
    expect(result.mode, OwnerUpgradeMode.localGuestCreated);
    expect(entryState.mode, AppEntryMode.signedOut);
  });

  test('sign in signs out provider when local owner binding fails', () async {
    upgrades.upgradeFailure = StateError('disk write failed');

    await expectLater(
      accounts.signIn(email: 'student@example.com', password: 'password123'),
      throwsStateError,
    );

    expect(gateway.signOutCalls, 1);
    expect(entryState.clearCalls, 1);
    expect(entryState.markGuestCalls, 1);
    expect(entryState.mode, AppEntryMode.guest);
  });

  test('registration signs out provider when entry clear fails', () async {
    entryState.clearFailure = StateError('preferences unavailable');

    await expectLater(
      accounts.register(email: 'student@example.com', password: 'password123'),
      throwsStateError,
    );

    expect(upgrades.upgradeCalls, 0);
    expect(gateway.signOutCalls, 1);
    expect(entryState.mode, AppEntryMode.guest);
  });

  test('sign in signs out provider when entry clear fails', () async {
    entryState.clearFailure = StateError('preferences unavailable');

    await expectLater(
      accounts.signIn(email: 'student@example.com', password: 'password123'),
      throwsStateError,
    );

    expect(upgrades.upgradeCalls, 0);
    expect(gateway.signOutCalls, 1);
    expect(entryState.mode, AppEntryMode.guest);
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
    expect(entryState.clearCalls, 1);
    expect(entryState.markGuestCalls, 1);
    expect(entryState.mode, AppEntryMode.guest);
  });

  test(
    'logout clear failure leaves provider and local owner unchanged',
    () async {
      entryState.clearFailure = StateError('preferences unavailable');

      await expectLater(accounts.signOutToLocalGuest(), throwsStateError);

      expect(gateway.signOutCalls, 0);
      expect(upgrades.logoutCalls, 0);
      expect(upgrades.rollbackCalls, 0);
      expect(entryState.mode, AppEntryMode.guest);
    },
  );

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

  test('email action parser accepts only action links with a code', () {
    final action = EmailAction.parse(
      Uri.parse(
        'https://vocab-learning-app-219ef.firebaseapp.com/auth/action'
        '?mode=resetPassword&oobCode=abc123',
      ),
    );
    expect(action?.mode, EmailActionMode.resetPassword);
    expect(action?.code, 'abc123');
    expect(EmailAction.parse(Uri.parse('https://example.com')), isNull);
  });
}

final class _MemoryAppEntryStateStore implements AppEntryStateStore {
  _MemoryAppEntryStateStore(this.mode);

  AppEntryMode mode;
  int clearCalls = 0;
  int markGuestCalls = 0;
  Object? clearFailure;

  @override
  Future<void> clear() async {
    clearCalls += 1;
    if (clearFailure case final failure?) throw failure;
    mode = AppEntryMode.signedOut;
  }

  @override
  Future<void> markGuest() async {
    markGuestCalls += 1;
    mode = AppEntryMode.guest;
  }

  @override
  Future<AppEntryMode> read() async => mode;
}

final class _FakeGateway implements AccountGateway {
  int registerCalls = 0;
  int signOutCalls = 0;
  String? registerEmail;
  Object? signOutFailure;

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
