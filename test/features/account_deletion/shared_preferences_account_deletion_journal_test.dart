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
    final journal = SharedPreferencesAccountDeletionJournal(preferences);
    final cloud = _cloudReceipt(now, key);
    final local = _localReceipt(now);

    await journal.saveCloudReceipt(cloud);
    expect((await journal.load())?.localReceipt, isNull);
    await journal.saveLocalReceipt(cloudReceipt: cloud, localReceipt: local);

    final reopened = SharedPreferencesAccountDeletionJournal(
      await SharedPreferences.getInstance(),
    );
    expect(await reopened.load(), isNull);
    expect(
      preferences.containsKey(
        SharedPreferencesAccountDeletionJournal.storageKey,
      ),
      isFalse,
    );
  });

  test(
    'accepts a new pending operation after completed identifiers are scrubbed',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final journal = SharedPreferencesAccountDeletionJournal(preferences);
      final cloud = _cloudReceipt(now, key);
      final local = _localReceipt(now);
      await journal.saveCloudReceipt(cloud);
      await journal.saveLocalReceipt(cloudReceipt: cloud, localReceipt: local);

      await journal.saveCloudReceipt(cloud);
      expect((await journal.load())?.cloudReceipt.receiptId, cloud.receiptId);
    },
  );

  test(
    'does not overwrite a pending operation with a different receipt',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final journal = SharedPreferencesAccountDeletionJournal(preferences);
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

      expect((await journal.load())?.cloudReceipt.receiptId, pending.receiptId);
    },
  );

  test('serializes concurrent cloud receipts so one operation wins', () async {
    final preferences = await SharedPreferences.getInstance();
    final journal = SharedPreferencesAccountDeletionJournal(preferences);
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
      (await journal.load())?.cloudReceipt.receiptId,
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
