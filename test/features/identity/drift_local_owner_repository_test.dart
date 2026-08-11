import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/domain/owner_operation_gate.dart';

void main() {
  late AppDatabase database;
  late DateTime nowUtc;
  late int generatedIds;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    nowUtc = DateTime.utc(2026, 7, 30, 9);
    generatedIds = 0;
  });

  tearDown(() async {
    await database.close();
  });

  DriftLocalOwnerRepository repository() {
    return DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner-${++generatedIds}',
      nowUtc: () => nowUtc,
    );
  }

  test('first access creates a stable local guest owner', () async {
    final owner = await repository().getOrCreateActiveOwner();

    expect(owner.id, 'local:owner-1');
    expect(owner.firebaseUid, isNull);
    expect(owner.createdAtUtc, nowUtc);
    expect(owner.upgradedAtUtc, isNull);
  });

  test(
    'a repository reconstruction returns the same persisted owner',
    () async {
      final first = await repository().getOrCreateActiveOwner();
      nowUtc = nowUtc.add(const Duration(days: 1));

      final restored = await repository().getOrCreateActiveOwner();

      expect(restored.id, first.id);
      expect(restored.createdAtUtc, first.createdAtUtc);
      expect(generatedIds, 1);
    },
  );

  test('concurrent first access creates exactly one active owner', () async {
    final ownerRepository = repository();

    final owners = await Future.wait([
      ownerRepository.getOrCreateActiveOwner(),
      ownerRepository.getOrCreateActiveOwner(),
      ownerRepository.getOrCreateActiveOwner(),
    ]);

    expect(owners.map((owner) => owner.id).toSet(), {'local:owner-1'});
    expect(await database.select(database.localOwners).get(), hasLength(1));
  });

  test(
    'binding a Firebase UID is idempotent and keeps the local owner id',
    () async {
      final ownerRepository = repository();
      final guest = await ownerRepository.getOrCreateActiveOwner();

      final bound = await ownerRepository.bindFirebaseUid(
        guest.id,
        'firebase-user-1',
      );
      final replayed = await ownerRepository.bindFirebaseUid(
        guest.id,
        'firebase-user-1',
      );

      expect(bound.id, guest.id);
      expect(bound.firebaseUid, 'firebase-user-1');
      expect(replayed.firebaseUid, 'firebase-user-1');
      expect(await database.select(database.localOwners).get(), hasLength(1));
    },
  );

  test(
    'direct binding rejects a different non-null UID without mutation',
    () async {
      final ownerRepository = repository();
      final guest = await ownerRepository.getOrCreateActiveOwner();
      await ownerRepository.bindFirebaseUid(guest.id, 'firebase-user-a');
      final before = await database.select(database.localOwners).get();
      nowUtc = nowUtc.add(const Duration(hours: 1));

      await expectLater(
        ownerRepository.bindFirebaseUid(guest.id, 'firebase-user-b'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('UpgradeGuestOwner'),
          ),
        ),
      );

      expect(await database.select(database.localOwners).get(), before);
    },
  );

  test(
    'binding rejects a blank Firebase UID without changing storage',
    () async {
      final ownerRepository = repository();
      final guest = await ownerRepository.getOrCreateActiveOwner();

      await expectLater(
        ownerRepository.bindFirebaseUid(guest.id, '   '),
        throwsArgumentError,
      );

      final restored = await ownerRepository.getOrCreateActiveOwner();
      expect(restored.firebaseUid, isNull);
    },
  );

  test('binding an unknown owner fails closed', () async {
    await expectLater(
      repository().bindFirebaseUid('missing-owner', 'firebase-user-1'),
      throwsStateError,
    );
  });

  test('binding waits for the persisted owner-operation gate', () async {
    final guest = await repository().getOrCreateActiveOwner();
    final gate = DriftOwnerOperationGate(database);
    expect(
      await gate.tryAcquire(
        token: 'sync-run',
        nowUtc: nowUtc,
        leaseDuration: const Duration(minutes: 10),
      ),
      isTrue,
    );
    final retryEntered = Completer<void>();
    final allowRetry = Completer<void>();
    final bindingRepository = DriftLocalOwnerRepository(
      database,
      generateId: () => 'unused',
      nowUtc: () => nowUtc,
      ownerOperationGate: gate,
      generateOwnerOperationToken: () => 'uid-bind',
      ownerGateDelay: (_) {
        if (!retryEntered.isCompleted) retryEntered.complete();
        return allowRetry.future;
      },
    );
    var completed = false;

    final binding = bindingRepository
        .bindFirebaseUid(guest.id, 'firebase-user-1')
        .whenComplete(() => completed = true);
    await retryEntered.future;

    expect(completed, isFalse);
    await gate.release(token: 'sync-run');
    allowRetry.complete();
    final bound = await binding;

    expect(bound.firebaseUid, 'firebase-user-1');
  });

  test('binding transaction rejects an unpersisted operation token', () async {
    final guest = await repository().getOrCreateActiveOwner();
    final bindingRepository = DriftLocalOwnerRepository(
      database,
      generateId: () => 'unused',
      nowUtc: () => nowUtc,
      ownerOperationGate: const _UnpersistedOwnerOperationGate(),
      generateOwnerOperationToken: () => 'uid-bind',
    );

    await expectLater(
      bindingRepository.bindFirebaseUid(guest.id, 'firebase-user-1'),
      throwsStateError,
    );
    final stored = await database.select(database.localOwners).getSingle();

    expect(stored.firebaseUid, isNull);
  });
}

final class _UnpersistedOwnerOperationGate implements OwnerOperationGate {
  const _UnpersistedOwnerOperationGate();

  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async => true;

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async => true;

  @override
  Future<bool> isOwned({
    required String token,
    required DateTime nowUtc,
  }) async => true;

  @override
  Future<void> release({required String token}) async {}
}
