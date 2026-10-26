import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/data/local/shared_preferences_account_deletion_journal.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';

void main() {
  const key = 'delete:00000000-0000-4000-8000-000000000001';
  final now = DateTime.utc(2026, 10, 24, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('clears account identifiers after local completion', () async {
    final preferences = await SharedPreferences.getInstance();
    final journal = _journal(preferences, now);
    final cloud = _cloudReceipt(now, key);
    final local = _localReceipt(now);

    await journal.saveCloudReceipt(cloud);
    expect((await journal.load())?.localReceipt, isNull);
    await journal.saveLocalReceipt(cloudReceipt: cloud, localReceipt: local);

    final reopened = _journal(await SharedPreferences.getInstance(), now);
    expect(await reopened.load(), isNull);
    expect(
      preferences.containsKey(
        SharedPreferencesAccountDeletionJournal.storageKey,
      ),
      isFalse,
    );
  });

  test('persists the recovery secret before a cloud receipt exists', () async {
    final preferences = await SharedPreferences.getInstance();
    final journal = _journal(preferences, now);
    final export = FullAccountExportReceipt(
      ownerId: 'owner-a',
      artifactId: 'account-export.json',
      artifactSha256: 'a' * 64,
      bytesWritten: 10,
      schemaVersion: 10,
      coveredScopes: requiredFullAccountExportScopes,
      completedAtUtc: now,
    );
    final authentication = RecentAuthenticationReceipt(
      firebaseUid: 'firebase-user',
      authenticatedAtUtc: now,
    );

    await journal.savePendingOperation(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-user',
      idempotencyKey: key,
      exportReceipt: export,
      authenticationReceipt: authentication,
    );
    final reopened = _journal(await SharedPreferences.getInstance(), now);
    final entry = await reopened.load();

    expect(entry?.ownerId, 'owner-a');
    expect(entry?.idempotencyKey, key);
    expect(entry?.exportReceipt?.artifactSha256, 'a' * 64);
    expect(entry?.authenticationReceipt?.firebaseUid, 'firebase-user');
    expect(entry?.cloudReceipt, isNull);
  });

  test('expires and scrubs a recovery secret after its bounded TTL', () async {
    final preferences = await SharedPreferences.getInstance();
    var clock = now;
    final journal = SharedPreferencesAccountDeletionJournal(
      preferences,
      nowUtc: () => clock,
      recoveryRetention: const Duration(hours: 1),
    );
    await journal.savePendingOperation(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-user',
      idempotencyKey: key,
      exportReceipt: FullAccountExportReceipt(
        ownerId: 'owner-a',
        artifactId: 'account-export.json',
        artifactSha256: 'a' * 64,
        bytesWritten: 10,
        schemaVersion: 10,
        coveredScopes: requiredFullAccountExportScopes,
        completedAtUtc: now,
      ),
      authenticationReceipt: RecentAuthenticationReceipt(
        firebaseUid: 'firebase-user',
        authenticatedAtUtc: now,
      ),
    );

    clock = now.add(const Duration(hours: 1, microseconds: 1));

    await expectLater(
      journal.load(),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.code,
          'code',
          AccountDeletionFailureCode.recoveryExpired,
        ),
      ),
    );
    expect(
      preferences.containsKey(
        SharedPreferencesAccountDeletionJournal.storageKey,
      ),
      isFalse,
    );
  });

  test(
    'cloud commit scrubs continuation data but keeps local purge marker past TTL',
    () async {
      final preferences = await SharedPreferences.getInstance();
      var clock = now;
      final journal = SharedPreferencesAccountDeletionJournal(
        preferences,
        nowUtc: () => clock,
        recoveryRetention: const Duration(hours: 1),
      );
      await journal.savePendingOperation(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-user',
        idempotencyKey: key,
        exportReceipt: FullAccountExportReceipt(
          ownerId: 'owner-a',
          artifactId: 'account-export.json',
          artifactSha256: 'a' * 64,
          bytesWritten: 10,
          schemaVersion: 10,
          coveredScopes: requiredFullAccountExportScopes,
          completedAtUtc: now,
        ),
        authenticationReceipt: RecentAuthenticationReceipt(
          firebaseUid: 'firebase-user',
          authenticatedAtUtc: now,
        ),
      );
      await journal.saveCloudReceipt(_cloudReceipt(now, key));

      final stored = preferences.getString(
        SharedPreferencesAccountDeletionJournal.storageKey,
      )!;
      expect(stored, isNot(contains(key)));
      expect(stored, contains('"exportReceipt":null'));
      expect(stored, contains('"authenticationReceipt":null'));

      clock = now.add(const Duration(days: 2));
      final reopened = await journal.load();

      expect(reopened?.cloudReceipt, isNotNull);
      expect(reopened?.exportReceipt, isNull);
      expect(reopened?.authenticationReceipt, isNull);
      expect(reopened?.idempotencyKey, startsWith('sha256:'));
    },
  );

  test(
    'accepts a new pending operation after completed identifiers are scrubbed',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final journal = _journal(preferences, now);
      final cloud = _cloudReceipt(now, key);
      final local = _localReceipt(now);
      await journal.saveCloudReceipt(cloud);
      await journal.saveLocalReceipt(cloudReceipt: cloud, localReceipt: local);

      await journal.saveCloudReceipt(cloud);
      expect((await journal.load())?.cloudReceipt?.receiptId, cloud.receiptId);
    },
  );

  test(
    'does not overwrite a pending operation with a different receipt',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final journal = _journal(preferences, now);
      final pending = _cloudReceipt(now, key);
      final different = CloudDeletionReceipt(
        receiptId: 'cloud-receipt-2',
        ownerId: 'owner-b',
        firebaseUid: 'firebase-user-b',
        idempotencyKey: 'delete:00000000-0000-4000-8000-000000000002',
        completedAtUtc: now.add(const Duration(minutes: 1)),
      );
      await journal.saveCloudReceipt(pending);

      await expectLater(
        journal.saveCloudReceipt(different),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.invalidCloudReceipt,
          ),
        ),
      );

      expect(
        (await journal.load())?.cloudReceipt?.receiptId,
        pending.receiptId,
      );
    },
  );

  test(
    'rejects a different cloud receipt for the same owner and key',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final journal = _journal(preferences, now);
      final saved = _cloudReceipt(now, key);
      final conflicting = CloudDeletionReceipt(
        receiptId: 'cloud-receipt-conflict',
        ownerId: saved.ownerId,
        firebaseUid: saved.firebaseUid,
        idempotencyKey: saved.idempotencyKey,
        completedAtUtc: saved.completedAtUtc.add(const Duration(seconds: 1)),
      );
      await journal.saveCloudReceipt(saved);

      await expectLater(
        journal.saveCloudReceipt(conflicting),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.invalidCloudReceipt,
          ),
        ),
      );
      expect((await journal.load())?.cloudReceipt?.receiptId, saved.receiptId);
    },
  );

  test('serializes concurrent cloud receipts so one operation wins', () async {
    final preferences = await SharedPreferences.getInstance();
    final journal = _journal(preferences, now);
    final first = _cloudReceipt(now, key);
    final second = CloudDeletionReceipt(
      receiptId: 'cloud-receipt-2',
      ownerId: 'owner-b',
      firebaseUid: 'firebase-user-b',
      idempotencyKey: 'delete:00000000-0000-4000-8000-000000000002',
      completedAtUtc: now.add(const Duration(minutes: 1)),
    );

    Future<Object> capture(
      Future<void> operation,
      CloudDeletionReceipt receipt,
    ) async {
      try {
        await operation;
        return receipt;
      } catch (error) {
        return error;
      }
    }

    final outcomes = await Future.wait([
      capture(journal.saveCloudReceipt(first), first),
      capture(journal.saveCloudReceipt(second), second),
    ]);

    expect(outcomes.whereType<CloudDeletionReceipt>(), hasLength(1));
    expect(
      outcomes.whereType<AccountDeletionException>().single.code,
      AccountDeletionFailureCode.invalidCloudReceipt,
    );
    expect(
      (await journal.load())?.cloudReceipt?.receiptId,
      outcomes.whereType<CloudDeletionReceipt>().single.receiptId,
    );
  });
}

CloudDeletionReceipt _cloudReceipt(DateTime now, String key) =>
    CloudDeletionReceipt(
      receiptId: 'cloud-receipt-1',
      ownerId: 'owner-a',
      firebaseUid: 'firebase-user',
      idempotencyKey: key,
      completedAtUtc: now,
    );

LocalDeletionReceipt _localReceipt(DateTime now) => LocalDeletionReceipt(
  deletedOwnerId: 'owner-a',
  newGuestOwnerId: 'local:new-guest',
  completedAtUtc: now,
);

SharedPreferencesAccountDeletionJournal _journal(
  SharedPreferences preferences,
  DateTime now,
) => SharedPreferencesAccountDeletionJournal(
  preferences,
  nowUtc: () => now,
  recoveryRetention: const Duration(days: 7),
);
