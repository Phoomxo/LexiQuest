import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/application/account_deletion_use_cases.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';

void main() {
  final now = DateTime.utc(2026, 10, 24, 12);
  const key = 'delete:00000000-0000-4000-8000-000000000001';
  late _Owners owners;
  late _Exporter exporter;
  late _Reauthenticator reauthenticator;
  late _CloudDeleter cloud;
  late _LocalDeleter local;
  late _Journal journal;
  late AccountSession? session;

  AccountDeletionUseCases useCases({bool enabled = true}) =>
      AccountDeletionUseCases(
        enabled: enabled,
        owners: owners,
        currentSession: () => session,
        exporter: exporter,
        reauthenticator: reauthenticator,
        cloud: cloud,
        local: local,
        journal: journal,
        nowUtc: () => now,
      );

  setUp(() {
    owners = _Owners(_owner());
    session = _session();
    exporter = _Exporter(_exportReceipt(now));
    reauthenticator = _Reauthenticator(
      RecentAuthenticationReceipt(
        firebaseUid: 'firebase-user',
        authenticatedAtUtc: now.subtract(const Duration(minutes: 1)),
      ),
    );
    cloud = _CloudDeleter(_cloudReceipt(now, key));
    local = _LocalDeleter(
      LocalDeletionReceipt(
        deletedOwnerId: 'owner-a',
        newGuestOwnerId: 'local:new-guest',
        completedAtUtc: now,
      ),
    );
    journal = _Journal();
  });

  test('production path is disabled unless explicitly configured', () async {
    await expectLater(
      useCases(enabled: false).deleteAccount(idempotencyKey: key),
      throwsA(_failure(AccountDeletionFailureCode.disabled)),
    );

    expect(exporter.calls, 0);
    expect(reauthenticator.calls, 0);
    expect(cloud.calls, 0);
    expect(local.calls, 0);
  });

  test('deletes cloud before local and returns an auditable receipt', () async {
    final order = <String>[];
    exporter.onCall = () => order.add('export');
    reauthenticator.onCall = () => order.add('reauth');
    cloud.onCall = () => order.add('cloud');
    local.onCall = () => order.add('local');
    journal.onSaveCloud = () => order.add('journal-cloud');
    journal.onSaveLocal = () => order.add('journal-local');

    final receipt = await useCases().deleteAccount(idempotencyKey: key);

    expect(order, [
      'export',
      'reauth',
      'cloud',
      'journal-cloud',
      'local',
      'journal-local',
    ]);
    expect(receipt.ownerId, 'owner-a');
    expect(receipt.firebaseUid, 'firebase-user');
    expect(receipt.idempotencyKey, key);
    expect(receipt.exportReceipt.artifactSha256, 'a' * 64);
    expect(receipt.cloudReceipt.receiptId, 'cloud-receipt-1');
    expect(receipt.localReceipt.newGuestOwnerId, 'local:new-guest');
  });

  test(
    'requires a complete export before reauthentication or deletion',
    () async {
      exporter.receipt = _exportReceipt(
        now,
        scopes: requiredFullAccountExportScopes.difference({'events_v2'}),
      );

      await expectLater(
        useCases().deleteAccount(idempotencyKey: key),
        throwsA(_failure(AccountDeletionFailureCode.fullExportRequired)),
      );

      expect(reauthenticator.calls, 0);
      expect(cloud.calls, 0);
      expect(local.calls, 0);
    },
  );

  test('rejects an export with an extra unrecognized scope', () async {
    exporter.receipt = _exportReceipt(
      now,
      scopes: {...requiredFullAccountExportScopes, 'unknown_scope'},
    );

    await expectLater(
      useCases().deleteAccount(idempotencyKey: key),
      throwsA(_failure(AccountDeletionFailureCode.fullExportRequired)),
    );

    expect(reauthenticator.calls, 0);
    expect(cloud.calls, 0);
    expect(local.calls, 0);
  });

  test(
    'rejects owner changes after export without touching cloud data',
    () async {
      exporter.onCall = () => owners.current = _owner(id: 'owner-b');

      await expectLater(
        useCases().deleteAccount(idempotencyKey: key),
        throwsA(_failure(AccountDeletionFailureCode.ownerChanged)),
      );

      expect(reauthenticator.calls, 0);
      expect(cloud.calls, 0);
      expect(local.calls, 0);
    },
  );

  test('requires recent reauthentication for the same Firebase user', () async {
    for (final receipt in <RecentAuthenticationReceipt>[
      RecentAuthenticationReceipt(
        firebaseUid: 'firebase-user',
        authenticatedAtUtc: now.subtract(const Duration(minutes: 6)),
      ),
      RecentAuthenticationReceipt(
        firebaseUid: 'other-user',
        authenticatedAtUtc: now,
      ),
    ]) {
      reauthenticator.receipt = receipt;

      await expectLater(
        useCases().deleteAccount(idempotencyKey: key),
        throwsA(_failure(AccountDeletionFailureCode.reauthenticationRequired)),
      );
    }

    expect(cloud.calls, 0);
    expect(local.calls, 0);
  });

  test('does not delete local data when cloud deletion fails', () async {
    cloud.failure = StateError('synthetic backend timeout');

    await expectLater(
      useCases().deleteAccount(idempotencyKey: key),
      throwsA(
        isA<AccountDeletionException>()
            .having(
              (error) => error.code,
              'code',
              AccountDeletionFailureCode.cloudDeleteFailed,
            )
            .having((error) => error.retryable, 'retryable', isTrue),
      ),
    );

    expect(local.calls, 0);
  });

  test('rejects a cloud receipt outside the bound owner operation', () async {
    cloud.receipt = _cloudReceipt(now, 'delete:other-operation');

    await expectLater(
      useCases().deleteAccount(idempotencyKey: key),
      throwsA(_failure(AccountDeletionFailureCode.invalidCloudReceipt)),
    );

    expect(local.calls, 0);
  });

  test(
    'crash after cloud receipt reopens and resumes from durable journal',
    () async {
      local.failure = StateError('synthetic disk lock');

      try {
        await useCases().deleteAccount(idempotencyKey: key);
        fail('expected local deletion to fail');
      } on AccountDeletionException catch (error) {
        expect(error.code, AccountDeletionFailureCode.localDeleteFailed);
        expect(error.retryable, isTrue);
        expect(error.cloudReceipt, same(cloud.receipt));
      }
      expect(journal.entry?.cloudReceipt, same(cloud.receipt));
      expect(journal.entry?.localReceipt, isNull);
      local.failure = null;

      final reopened = useCases();
      final receipt = await reopened.resumePendingDeletion();

      expect(receipt?.deletedOwnerId, 'owner-a');
      expect(cloud.keys, [key]);
      expect(exporter.calls, 1);
      expect(reauthenticator.calls, 1);
      expect(local.calls, 2);
      expect(journal.entry?.localReceipt, same(local.receipt));
    },
  );

  test('repeated acknowledgement loss returns saved local receipt', () async {
    journal.loseNextLocalAcknowledgement = true;

    await expectLater(
      useCases().deleteAccount(idempotencyKey: key),
      throwsA(_failure(AccountDeletionFailureCode.localDeleteFailed)),
    );
    expect(journal.entry?.localReceipt, same(local.receipt));

    final resumed = await useCases().resumePendingDeletion();

    expect(resumed, same(local.receipt));
    expect(local.calls, 1);
    expect(cloud.calls, 1);
  });

  void setUpFreshOperation() {
    owners = _Owners(_owner());
    session = _session();
    exporter = _Exporter(_exportReceipt(now));
    reauthenticator = _Reauthenticator(
      RecentAuthenticationReceipt(
        firebaseUid: 'firebase-user',
        authenticatedAtUtc: now,
      ),
    );
    cloud = _CloudDeleter(_cloudReceipt(now, key));
    local = _LocalDeleter(
      LocalDeletionReceipt(
        deletedOwnerId: 'owner-a',
        newGuestOwnerId: 'local:new-guest',
        completedAtUtc: now,
      ),
    );
    journal = _Journal();
  }

  test('accepts only bounded future server clock skew', () async {
    reauthenticator.receipt = RecentAuthenticationReceipt(
      firebaseUid: 'firebase-user',
      authenticatedAtUtc: now.add(AccountDeletionUseCases.serverClockSkew),
    );
    cloud.receipt = _cloudReceipt(
      now.add(AccountDeletionUseCases.serverClockSkew),
      key,
    );

    final accepted = await useCases().deleteAccount(idempotencyKey: key);
    expect(accepted.cloudReceipt.completedAtUtc, cloud.receipt.completedAtUtc);

    setUpFreshOperation();
    cloud.receipt = _cloudReceipt(
      now
          .add(AccountDeletionUseCases.serverClockSkew)
          .add(const Duration(microseconds: 1)),
      key,
    );
    await expectLater(
      useCases().deleteAccount(idempotencyKey: key),
      throwsA(_failure(AccountDeletionFailureCode.invalidCloudReceipt)),
    );
  });

  test('resume still enforces the cloud receipt owner boundary', () async {
    owners.current = _owner(id: 'owner-b');

    await expectLater(
      useCases().resumeLocalDeletion(_cloudReceipt(now, key)),
      throwsA(_failure(AccountDeletionFailureCode.ownerChanged)),
    );

    expect(local.calls, 0);
  });

  test('rejects anonymous, signed-out, and cross-owner sessions', () async {
    for (final candidate in <AccountSession?>[
      null,
      _session(anonymous: true),
      _session(uid: 'other-user'),
    ]) {
      session = candidate;
      await expectLater(
        useCases().deleteAccount(idempotencyKey: key),
        throwsA(_failure(AccountDeletionFailureCode.invalidIdentity)),
      );
    }

    expect(exporter.calls, 0);
  });
}

Matcher _failure(AccountDeletionFailureCode code) =>
    isA<AccountDeletionException>().having((error) => error.code, 'code', code);

LocalOwner _owner({String id = 'owner-a'}) => LocalOwner(
  id: id,
  firebaseUid: 'firebase-user',
  createdAtUtc: DateTime.utc(2026, 10, 20),
);

AccountSession _session({
  String uid = 'firebase-user',
  bool anonymous = false,
}) => AccountSession(
  uid: uid,
  email: anonymous ? null : 'learner@example.test',
  isAnonymous: anonymous,
  emailVerified: !anonymous,
);

FullAccountExportReceipt _exportReceipt(
  DateTime now, {
  Set<String> scopes = requiredFullAccountExportScopes,
}) => FullAccountExportReceipt(
  ownerId: 'owner-a',
  artifactId: 'export-artifact-1',
  artifactSha256: 'a' * 64,
  bytesWritten: 4096,
  schemaVersion: 10,
  coveredScopes: scopes,
  completedAtUtc: now.subtract(const Duration(minutes: 2)),
);

CloudDeletionReceipt _cloudReceipt(DateTime now, String key) =>
    CloudDeletionReceipt(
      receiptId: 'cloud-receipt-1',
      ownerId: 'owner-a',
      firebaseUid: 'firebase-user',
      idempotencyKey: key,
      completedAtUtc: now,
    );

final class _Owners implements LocalOwnerRepository {
  _Owners(this.current);

  LocalOwner current;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => current;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _Exporter implements FullAccountExporter {
  _Exporter(this.receipt);

  FullAccountExportReceipt receipt;
  int calls = 0;
  void Function()? onCall;

  @override
  Future<FullAccountExportReceipt> export({required String ownerId}) async {
    calls++;
    onCall?.call();
    return receipt;
  }
}

final class _Reauthenticator implements AccountDeletionReauthenticator {
  _Reauthenticator(this.receipt);

  RecentAuthenticationReceipt receipt;
  int calls = 0;
  void Function()? onCall;

  @override
  Future<RecentAuthenticationReceipt> reauthenticate({
    required String firebaseUid,
  }) async {
    calls++;
    onCall?.call();
    return receipt;
  }
}

final class _CloudDeleter implements PrivilegedAccountDeletionGateway {
  _CloudDeleter(this.receipt);

  CloudDeletionReceipt receipt;
  Object? failure;
  int calls = 0;
  final List<String> keys = [];
  void Function()? onCall;

  @override
  Future<CloudDeletionReceipt> deleteRecursively({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  }) async {
    calls++;
    keys.add(idempotencyKey);
    onCall?.call();
    if (failure case final error?) throw error;
    return receipt;
  }
}

final class _LocalDeleter implements LocalAccountDeletionGateway {
  _LocalDeleter(this.receipt);

  LocalDeletionReceipt receipt;
  Object? failure;
  int calls = 0;
  void Function()? onCall;

  @override
  Future<LocalDeletionReceipt> deleteAfterCloud({
    required String ownerId,
    required CloudDeletionReceipt cloudReceipt,
  }) async {
    calls++;
    onCall?.call();
    if (failure case final error?) throw error;
    return receipt;
  }
}

final class _Journal implements AccountDeletionJournal {
  AccountDeletionJournalEntry? entry;
  bool loseNextLocalAcknowledgement = false;
  void Function()? onSaveCloud;
  void Function()? onSaveLocal;

  @override
  Future<AccountDeletionJournalEntry?> load() async => entry;

  @override
  Future<void> saveCloudReceipt(CloudDeletionReceipt receipt) async {
    onSaveCloud?.call();
    if (entry?.cloudReceipt != receipt) {
      entry = AccountDeletionJournalEntry(cloudReceipt: receipt);
    }
  }

  @override
  Future<void> saveLocalReceipt({
    required CloudDeletionReceipt cloudReceipt,
    required LocalDeletionReceipt localReceipt,
  }) async {
    onSaveLocal?.call();
    entry = AccountDeletionJournalEntry(
      cloudReceipt: cloudReceipt,
      localReceipt: localReceipt,
    );
    if (loseNextLocalAcknowledgement) {
      loseNextLocalAcknowledgement = false;
      throw StateError('synthetic acknowledgement loss');
    }
  }
}
