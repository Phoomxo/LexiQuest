import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/billing/billing_runtime.dart';
import 'package:vocab_learning_app/features/billing/domain/billing_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';

void main() {
  late AppDatabase database;
  late StreamController<void> authEvents;
  late DriftBillingAccountBinding binding;
  BillingAuthIdentity? identity;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement(
      "INSERT INTO local_owners (id,firebase_uid,account_state,created_at_utc_ms,is_active) VALUES ('synthetic-a','synthetic-uid-a','firebaseBound',1,1),('synthetic-b','synthetic-uid-b','firebaseBound',1,0)",
    );
    authEvents = StreamController<void>.broadcast(sync: true);
    identity = const BillingAuthIdentity(
      uid: 'synthetic-uid-a',
      isAnonymous: false,
    );
    binding = DriftBillingAccountBinding(
      database: database,
      currentIdentity: () => identity,
      authInvalidations: authEvents.stream,
    );
  });
  tearDown(() async {
    await binding.dispose();
    await authEvents.close();
    await database.close();
  });

  test(
    'observing the registered current owner creates no owner or billing rows',
    () async {
      final before = await _rows(database);
      await binding.refresh();
      expect(binding.currentAccount?.ownerId, 'synthetic-a');
      await binding.requireCurrent(binding.currentAccount!);
      expect(await _rows(database), before);
    },
  );

  test(
    'auth A-B-A retires the observed account before a coalesced reread',
    () async {
      await binding.refresh();
      final original = binding.currentAccount!;
      final observed = <BillingAccount?>[];
      final subscription = binding.changes.listen(observed.add);
      addTearDown(subscription.cancel);
      identity = const BillingAuthIdentity(
        uid: 'synthetic-uid-b',
        isAnonymous: false,
      );
      authEvents.add(null);
      expect(binding.currentAccount, isNull);
      expect(observed.first, isNull);
      identity = const BillingAuthIdentity(
        uid: 'synthetic-uid-a',
        isAnonymous: false,
      );
      authEvents.add(null);
      expect(binding.currentAccount, isNull);
      await binding.refresh();
      expect(binding.currentAccount, original);
      expect(
        observed.where((value) => value == null).length,
        greaterThanOrEqualTo(2),
      );
    },
  );

  test(
    'a real deletion intent fences paid identity without modifying any data',
    () async {
      await binding.refresh();
      final account = binding.currentAccount!;
      final coordinator = DriftOwnerWriteCoordinator(
        database,
        nowUtc: () => DateTime.utc(2026, 11, 1),
        nonceGenerator: () => 'synthetic-nonce',
      );
      await coordinator.beginDeletion(
        ownerId: 'synthetic-a',
        firebaseUid: 'synthetic-uid-a',
        idempotencyKey: 'synthetic-deletion',
      );
      final before = await _rows(database);
      await expectLater(
        () => binding.requireCurrent(account),
        throwsA(isA<BillingException>()),
      );
      await binding.refresh();
      expect(binding.currentAccount, isNull);
      expect(await _rows(database), before);
    },
  );

  test('two active owners and anonymous auth both fail closed', () async {
    await database.customStatement('UPDATE local_owners SET is_active=1');
    await binding.refresh();
    expect(binding.currentAccount, isNull);
    await database.customStatement(
      "UPDATE local_owners SET is_active=0 WHERE id='synthetic-b'",
    );
    identity = const BillingAuthIdentity(
      uid: 'synthetic-uid-a',
      isAnonymous: true,
    );
    await binding.refresh();
    expect(binding.currentAccount, isNull);
  });

  for (final failure in ['closed', 'failed']) {
    test('a $failure identity observer cannot be revived by refresh', () async {
      await binding.refresh();
      expect(binding.currentAccount, isNotNull);
      if (failure == 'closed') {
        await authEvents.close();
      } else {
        authEvents.addError(StateError('Synthetic observer failure'));
      }
      expect(binding.currentAccount, isNull);
      final before = await _rows(database);
      await binding.refresh();
      expect(binding.currentAccount, isNull);
      expect(await _rows(database), before);
    });
  }

  test('a local guest row cannot act as a registered identity', () async {
    await database.customStatement(
      "UPDATE local_owners SET account_state='localGuest' WHERE id='synthetic-a'",
    );
    final before = await _rows(database);
    await binding.refresh();
    expect(binding.currentAccount, isNull);
    expect(await _rows(database), before);
  });
}

Future<Map<String, List<Map<String, Object?>>>> _rows(
  AppDatabase database,
) async => {
  for (final table in database.allTables)
    table.actualTableName: [
      for (final row
          in await database
              .customSelect(
                'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
              )
              .get())
        Map<String, Object?>.from(row.data),
    ],
};
