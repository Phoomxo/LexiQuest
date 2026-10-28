import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';

import 'research_lifecycle_fixtures.dart';

void main() {
  late AppDatabase database;
  late DriftOwnerUpgradeRepository repository;
  late List<String> erasedSecrets;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    erasedSecrets = [];
    var sequence = 0;
    repository = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.utc(2026, 9, 5),
      generateConflictId: () => 'conflict:${sequence++}',
      generateOwnerId: () => 'new-owner',
      generateOwnerOperationToken: () => 'operation:${sequence++}',
      deleteOwnerSecrets: (ownerId) async => erasedSecrets.add(ownerId),
    );
    await seedLifecycleOwner(database, 'source', active: true);
    await seedLifecycleOwner(
      database,
      'target',
      firebaseUid: 'firebase-target',
    );
  });
  tearDown(() => database.close());

  for (final targetUid in ['firebase-target', 'new-firebase']) {
    for (final kind in ['permit', 'run', 'graph', 'tombstone']) {
      test(
        '$kind blocks $targetUid before any owner or credential mutation',
        () async {
          await seedLifecycleResearch(
            database,
            'source',
            run: kind != 'permit',
            response: kind == 'graph' || kind == 'tombstone',
            permit: kind != 'run',
            opportunity: kind == 'graph' || kind == 'tombstone',
            deleted: kind == 'tombstone',
            withdrawn: kind == 'tombstone',
          );
          final source = await lifecycleSnapshot(database, 'source');
          final target = await lifecycleSnapshot(database, 'target');
          for (var retry = 0; retry < 2; retry++) {
            await expectLater(
              repository.upgrade(
                activeOwnerId: 'source',
                firebaseUid: targetUid,
              ),
              throwsA(isA<ResearchOwnerUpgradeConflict>()),
            );
            expect(await lifecycleSnapshot(database, 'source'), source);
            expect(await lifecycleSnapshot(database, 'target'), target);
            expect(erasedSecrets, isEmpty);
          }
        },
      );
    }
  }

  test('owner without research still merges normally', () async {
    final result = await repository.upgrade(
      activeOwnerId: 'source',
      firebaseUid: 'firebase-target',
    );
    expect(result.mode, OwnerUpgradeMode.mergedExisting);
    expect(result.targetOwnerId, 'target');
    expect(erasedSecrets, ['source']);
  });

  test('owner without research still binds to a new account', () async {
    final result = await repository.upgrade(
      activeOwnerId: 'source',
      firebaseUid: 'new-firebase',
    );
    expect(result.mode, OwnerUpgradeMode.anonymousBound);
    expect(result.targetOwnerId, 'source');
    expect(erasedSecrets, isEmpty);
  });

  test(
    'target research is preserved when research-free source merges',
    () async {
      await seedLifecycleResearch(database, 'target');
      final before = {
        for (final table in researchLifecycleTables)
          table: await lifecycleRows(database, table, 'target'),
      };
      final result = await repository.upgrade(
        activeOwnerId: 'source',
        firebaseUid: 'firebase-target',
      );
      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      for (final table in researchLifecycleTables) {
        expect(await lifecycleRows(database, table, 'target'), before[table]);
      }
    },
  );

  test(
    'same-owner already-bound replay preserves signed research pins',
    () async {
      await database.customStatement(
        "UPDATE local_owners SET firebase_uid = 'firebase-source', account_state = 'firebaseBound' WHERE id = 'source'",
      );
      await seedLifecycleResearch(database, 'source');
      final before = {
        for (final table in researchLifecycleTables)
          table: await lifecycleRows(database, table, 'source'),
      };
      final result = await repository.upgrade(
        activeOwnerId: 'source',
        firebaseUid: 'firebase-source',
      );
      expect(result.mode, OwnerUpgradeMode.alreadyBound);
      for (final table in researchLifecycleTables) {
        expect(await lifecycleRows(database, table, 'source'), before[table]);
      }
      expect(erasedSecrets, isEmpty);
    },
  );
}
