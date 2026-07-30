import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';

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
}
