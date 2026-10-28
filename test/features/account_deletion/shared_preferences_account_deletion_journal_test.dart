import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/data/local/shared_preferences_account_deletion_journal.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';

import '../../support/fake_owner_write_coordinator.dart';

void main() {
  const key = 'delete:00000000-0000-4000-8000-000000000001';
  final now = DateTime.utc(2026, 10, 24, 12);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'reloads durable journal changes instead of trusting a stale cache',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final journal = _journal(preferences, now);
      final cloud = _cloudReceipt(now, key).durableMarker();
      SharedPreferences.setMockInitialValues({
        SharedPreferencesAccountDeletionJournal.storageKey: jsonEncode({
          'ownerId': cloud.ownerId,
          'firebaseUid': cloud.firebaseUid,
          'idempotencyKey': cloud.idempotencyKey,
          'cloudReceipt': {
            'receiptId': cloud.receiptId,
            'ownerId': cloud.ownerId,
            'firebaseUid': cloud.firebaseUid,
            'idempotencyKey': cloud.idempotencyKey,
            'completedAtUtc': cloud.completedAtUtc.toIso8601String(),
          },
        }),
      });
      expect(
        preferences.containsKey(
          SharedPreferencesAccountDeletionJournal.storageKey,
        ),
        isFalse,
      );
      expect((await journal.load())?.cloudReceipt?.receiptId, cloud.receiptId);
    },
  );

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
    expect(_operationKeys(preferences), isEmpty);
  });

  test(
    'a late clear from a completed operation cannot erase its successor',
    () async {
      final backing = <String, Object>{};
      final firstPreferences = _IndependentPreferences(backing);
      final secondPreferences = _IndependentPreferences(backing);
      final ownerWrites = FakeOwnerWriteCoordinator();
      final first = _journal(firstPreferences, now, ownerWrites: ownerWrites);
      final second = _journal(secondPreferences, now, ownerWrites: ownerWrites);
      final cloud = _cloudReceipt(now, key).durableMarker();
      final local = _localReceipt(now);
      final firstToken = await ownerWrites.beginDeletion(
        ownerId: cloud.ownerId,
        firebaseUid: cloud.firebaseUid,
        idempotencyKey: key,
      );
      await ownerWrites.markPending(firstToken);
      await ownerWrites.markCloud(firstToken, cloud);
      await first.saveCloudReceipt(cloud);
      await ownerWrites.markLocal(firstToken, cloud, local);
      final committed = Completer<void>();
      final acknowledge = Completer<void>();
      firstPreferences.afterCommittedWrite = (storedKey, value) async {
        if ((jsonDecode(value) as Map<String, Object?>)['localReceipt'] !=
            null) {
          committed.complete();
          await acknowledge.future;
        }
      };
      final delayedClear = first.saveLocalReceipt(
        cloudReceipt: cloud,
        localReceipt: local,
      );
      final cleared = expectLater(delayedClear, completes);
      await committed.future;
      try {
        // Another engine observes the committed receipt before its ACK arrives.
        await second.saveLocalReceipt(cloudReceipt: cloud, localReceipt: local);
        await ownerWrites.clearCompleted(firstToken);
        const nextKey = 'delete:synthetic-successor-operation';
        final nextToken = await ownerWrites.beginDeletion(
          ownerId: 'owner-b',
          firebaseUid: 'firebase-user-b',
          idempotencyKey: nextKey,
        );
        await ownerWrites.markPending(nextToken);
        await second.savePendingOperation(
          ownerId: 'owner-b',
          firebaseUid: 'firebase-user-b',
          idempotencyKey: nextKey,
          exportReceipt: FullAccountExportReceipt(
            ownerId: 'owner-b',
            artifactId: 'synthetic-b.json',
            artifactSha256: 'b' * 64,
            bytesWritten: 128,
            schemaVersion: 11,
            coveredScopes: requiredFullAccountExportScopes,
            completedAtUtc: now,
          ),
          authenticationReceipt: RecentAuthenticationReceipt(
            firebaseUid: 'firebase-user-b',
            authenticatedAtUtc: now,
          ),
        );
      } finally {
        acknowledge.complete();
        await cleared;
      }
      final successor = await second.load();
      expect(successor?.ownerId, 'owner-b');
      expect(successor?.firebaseUid, 'firebase-user-b');
      expect(successor?.idempotencyKey, 'delete:synthetic-successor-operation');
      expect(successor?.exportReceipt?.artifactSha256, 'b' * 64);
      expect(successor?.authenticationReceipt?.firebaseUid, 'firebase-user-b');
      expect(ownerWrites.state?.phase, DeletionIntentPhase.pendingCloud);
      expect(backing.keys, hasLength(1));
    },
  );

  test(
    'reloads a namespaced operation from another preference cache',
    () async {
      final backing = <String, Object>{};
      final firstPreferences = _IndependentPreferences(backing);
      final secondPreferences = _IndependentPreferences(backing);
      await firstPreferences.reload();
      await _journal(
        secondPreferences,
        now,
      ).saveCloudReceipt(_cloudReceipt(now, key));
      expect(firstPreferences.getKeys(), isEmpty);
      final restored = await _journal(firstPreferences, now).load();
      expect(restored?.cloudReceipt?.receiptId, 'cloud-receipt-1');
      expect(
        firstPreferences.getKeys().single,
        startsWith(
          SharedPreferencesAccountDeletionJournal.operationStoragePrefix,
        ),
      );
      expect(firstPreferences.getKeys().single, isNot(contains('owner-a')));
      expect(firstPreferences.getKeys().single, isNot(contains(key)));
    },
  );

  test(
    'a legacy global receipt migrates to an isolated operation record',
    () async {
      final preferences = await SharedPreferences.getInstance();
      final cloud = _cloudReceipt(now, key).durableMarker();
      await preferences.setString(
        SharedPreferencesAccountDeletionJournal.storageKey,
        jsonEncode(_legacyCloud(cloud)),
      );
      final journal = _journal(preferences, now);
      expect((await journal.load())?.cloudReceipt?.receiptId, cloud.receiptId);
      await journal.saveCloudReceipt(cloud);
      expect(
        preferences.containsKey(
          SharedPreferencesAccountDeletionJournal.storageKey,
        ),
        isFalse,
      );
      expect(_operationKeys(preferences), hasLength(1));
      expect((await journal.load())?.cloudReceipt?.receiptId, cloud.receiptId);
      await journal.saveLocalReceipt(
        cloudReceipt: cloud,
        localReceipt: _localReceipt(now),
      );
      expect(preferences.getKeys(), isEmpty);
    },
  );

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
    expect(_operationKeys(preferences), isEmpty);
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

      final stored = preferences.getString(_operationKeys(preferences).single)!;
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
    'keeps different operations separate and rejects ambiguous unscoped recovery',
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

      await journal.saveCloudReceipt(different);
      expect(_operationKeys(preferences), hasLength(2));
      await expectLater(journal.load(), throwsA(_unavailable()));
      final current = FakeOwnerWriteCoordinator();
      await current.beginDeletion(
        ownerId: pending.ownerId,
        firebaseUid: pending.firebaseUid,
        idempotencyKey: pending.idempotencyKey,
      );
      expect(
        (await _journal(
          preferences,
          now,
          ownerWrites: current,
        ).load())?.cloudReceipt?.receiptId,
        pending.receiptId,
      );
      final next = FakeOwnerWriteCoordinator();
      await next.beginDeletion(
        ownerId: different.ownerId,
        firebaseUid: different.firebaseUid,
        idempotencyKey: different.idempotencyKey,
      );
      expect(
        (await _journal(
          preferences,
          now,
          ownerWrites: next,
        ).load())?.cloudReceipt?.receiptId,
        different.receiptId,
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

  test('concurrent operations preserve independent durable records', () async {
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

    expect(outcomes.whereType<CloudDeletionReceipt>(), hasLength(2));
    expect(outcomes.whereType<Exception>(), isEmpty);
    expect(_operationKeys(preferences), hasLength(2));
    final stored = _operationKeys(
      preferences,
    ).map(preferences.getString).join();
    expect(stored, contains(first.receiptId));
    expect(stored, contains(second.receiptId));
    await expectLater(journal.load(), throwsA(_unavailable()));
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
  DateTime now, {
  OwnerWriteCoordinator? ownerWrites,
}) => SharedPreferencesAccountDeletionJournal(
  preferences,
  nowUtc: () => now,
  recoveryRetention: const Duration(days: 7),
  ownerWrites: ownerWrites,
);

Set<String> _operationKeys(SharedPreferences preferences) => preferences
    .getKeys()
    .where(
      (key) => key.startsWith(
        SharedPreferencesAccountDeletionJournal.operationStoragePrefix,
      ),
    )
    .toSet();

Matcher _unavailable() => isA<AccountDeletionException>().having(
  (error) => error.code,
  'code',
  AccountDeletionFailureCode.unavailable,
);

Map<String, Object?> _legacyCloud(CloudDeletionReceipt cloud) => {
  'ownerId': cloud.ownerId,
  'firebaseUid': cloud.firebaseUid,
  'idempotencyKey': cloud.idempotencyKey,
  'cloudReceipt': {
    'receiptId': cloud.receiptId,
    'ownerId': cloud.ownerId,
    'firebaseUid': cloud.firebaseUid,
    'idempotencyKey': cloud.idempotencyKey,
    'completedAtUtc': cloud.completedAtUtc.toIso8601String(),
  },
};

final class _IndependentPreferences implements SharedPreferences {
  _IndependentPreferences(this.backing);

  final Map<String, Object> backing;
  final Map<String, Object> _cache = {};
  Future<void> Function(String key, String value)? afterCommittedWrite;

  @override
  Future<void> reload() async {
    _cache
      ..clear()
      ..addAll(backing);
  }

  @override
  Set<String> getKeys() => _cache.keys.toSet();

  @override
  bool containsKey(String key) => _cache.containsKey(key);

  @override
  String? getString(String key) => _cache[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    _cache[key] = value;
    backing[key] = value;
    await afterCommittedWrite?.call(key, value);
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _cache.remove(key);
    backing.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
