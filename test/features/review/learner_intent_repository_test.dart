import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/review/data/drift_learner_intent_repository.dart';
import 'package:vocab_learning_app/features/review/domain/learner_intent.dart';

void main() {
  late AppDatabase database;
  late _OwnerRepository owners;
  late DateTime nowUtc;
  late int mutationNotifications;
  late DriftLearnerIntentRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    owners = _OwnerRepository();
    nowUtc = DateTime.utc(2026, 8, 24, 8);
    mutationNotifications = 0;
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: owners.owner.id,
            createdAtUtcMs: owners.owner.createdAtUtc.millisecondsSinceEpoch,
          ),
        );
    repository = DriftLearnerIntentRepository(
      database,
      owners: owners,
      nowUtc: () => nowUtc,
      onLocalMutation: () async => mutationNotifications += 1,
    );
  });

  tearDown(() => database.close());

  test('save replay is idempotent by owner content and revision', () async {
    await repository.save(_savedItem(id: 'saved:first'));
    nowUtc = DateTime.utc(2026, 8, 24, 9);
    await repository.save(_savedItem(id: 'saved:replay'));

    final rows = await database.customSelect('''
      SELECT id, local_revision, is_deleted FROM saved_learning_items
    ''').get();
    expect(rows, hasLength(1));
    expect(rows.single.read<String>('id'), 'saved:first');
    expect(rows.single.read<int>('local_revision'), 1);
    expect(rows.single.read<int>('is_deleted'), 0);
    expect(await _outboxRows(database), hasLength(1));
    expect(mutationNotifications, 1);
  });

  test(
    'unsave is an idempotent tombstone and never mutates weakness',
    () async {
      await repository.save(_savedItem(id: 'saved:first'));
      nowUtc = DateTime.utc(2026, 8, 24, 10);
      await repository.unsave(_identity);
      await repository.unsave(_identity);

      final row = await database.customSelect('''
      SELECT local_revision, is_deleted, updated_at_utc_ms
      FROM saved_learning_items
    ''').getSingle();
      expect(row.read<int>('local_revision'), 2);
      expect(row.read<int>('is_deleted'), 1);
      expect(row.read<int>('updated_at_utc_ms'), nowUtc.millisecondsSinceEpoch);
      final operations = await _outboxRows(database);
      expect(operations.map((row) => row.read<String>('operation_kind')), [
        'upsert',
        'delete',
      ]);
      expect(operations.map((row) => row.read<int>('base_revision')), [0, 0]);
      expect(
        await database
            .customSelect('SELECT COUNT(*) AS count FROM srs_states')
            .map((row) => row.read<int>('count'))
            .getSingle(),
        0,
      );
      expect(mutationNotifications, 2);
    },
  );

  test('new intent advances past every retired local operation id', () async {
    await database.customInsert('''
      INSERT INTO saved_learning_items(
        id, owner_id, content_type, content_id, content_revision,
        saved_at_utc_ms, updated_at_utc_ms, local_revision, cloud_revision,
        is_deleted
      ) VALUES (
        'saved:first', 'owner:learner', 'lexicalMetadata', 'word:station', 3,
        1000, 2000, 1, 1, 1
      )
    ''');
    await database.customInsert('''
      INSERT INTO outbox_operations(
        operation_id, owner_id, entity_type, entity_id, operation_kind,
        payload_version, base_revision, state, attempt_count,
        created_at_utc_ms
      ) VALUES (
        'savedLearningItem:saved:first:2', 'owner:learner',
        'savedLearningItem', 'saved:first', 'delete', 1, 1,
        'conflictResolved', 1, 2000
      )
    ''');

    await repository.save(_savedItem(id: 'saved:replay'));

    final row = await database.customSelect('''
      SELECT local_revision, cloud_revision, is_deleted
      FROM saved_learning_items
    ''').getSingle();
    expect(row.read<int>('local_revision'), 3);
    expect(row.read<int>('cloud_revision'), 1);
    expect(row.read<int>('is_deleted'), 0);
    final pending = await database.customSelect('''
      SELECT operation_id, base_revision, state
      FROM outbox_operations
      WHERE state = 'pending'
    ''').getSingle();
    expect(
      pending.read<String>('operation_id'),
      'savedLearningItem:saved:first:3',
    );
    expect(pending.read<int>('base_revision'), 1);
    expect(mutationNotifications, 1);
  });

  test(
    're-save keeps the original saved time and appends a new intent',
    () async {
      final firstSavedAt = DateTime.utc(2026, 8, 24, 8);
      await repository.save(
        _savedItem(id: 'saved:first', savedAtUtc: firstSavedAt),
      );
      nowUtc = DateTime.utc(2026, 8, 24, 10);
      await repository.unsave(_identity);
      final resavedAt = DateTime.utc(2026, 8, 24, 11);
      await repository.save(
        _savedItem(id: 'saved:replay', savedAtUtc: resavedAt),
      );

      final row = await database.customSelect('''
      SELECT saved_at_utc_ms, updated_at_utc_ms, local_revision, is_deleted
      FROM saved_learning_items
    ''').getSingle();
      expect(
        row.read<int>('saved_at_utc_ms'),
        firstSavedAt.millisecondsSinceEpoch,
      );
      expect(
        row.read<int>('updated_at_utc_ms'),
        resavedAt.millisecondsSinceEpoch,
      );
      expect(row.read<int>('local_revision'), 3);
      expect(row.read<int>('is_deleted'), 0);
      expect(
        (await _outboxRows(
          database,
        )).map((row) => row.read<String>('operation_kind')),
        ['upsert', 'delete', 'upsert'],
      );
    },
  );

  test(
    'save resolves the active owner atomically after an interleaved upgrade',
    () async {
      await _seedAccountOwner(database);
      owners.interleaveNextEnsure(() => _upgradeGuest(database));

      await repository.save(_savedItem(id: 'saved:interleaved-save'));

      await _expectTargetLifecycleOwnership(
        database,
        expectedSaved: true,
        expectedOutboxCount: 1,
      );
    },
  );

  test(
    'unsave resolves the moved row atomically after an interleaved upgrade',
    () async {
      await repository.save(_savedItem(id: 'saved:interleaved-unsave'));
      await _seedAccountOwner(database);
      owners.interleaveNextEnsure(() => _upgradeGuest(database));
      nowUtc = DateTime.utc(2026, 8, 24, 10);

      await repository.unsave(_identity);

      await _expectTargetLifecycleOwnership(
        database,
        expectedSaved: false,
        expectedOutboxCount: 2,
      );
    },
  );
}

const _identity = ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: 'word:station',
  revision: 3,
);

SaveLearningItemCommand _savedItem({
  required String id,
  DateTime? savedAtUtc,
}) => SaveLearningItemCommand(
  id: id,
  contentIdentity: _identity,
  savedAtUtc: savedAtUtc ?? DateTime.utc(2026, 8, 24, 8),
);

Future<List<QueryRow>> _outboxRows(AppDatabase database) =>
    database.customSelect('''
      SELECT operation_kind, base_revision FROM outbox_operations
      WHERE entity_type = 'savedLearningItem'
      ORDER BY created_at_utc_ms, operation_kind DESC
    ''').get();

Future<void> _seedAccountOwner(AppDatabase database) => database.customInsert(
  'INSERT INTO local_owners '
  '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
  "VALUES ('owner:account', 'firebase-user', 'firebaseBound', 2, 0)",
);

Future<void> _upgradeGuest(AppDatabase database) async {
  await DriftOwnerUpgradeRepository(
    database,
    nowUtc: () => DateTime.utc(2026, 8, 24, 9),
    generateConflictId: () => 'intent-upgrade-conflict',
    generateOwnerId: () => 'unused-owner',
    generateOwnerOperationToken: () => 'intent-upgrade-operation',
    deleteOwnerSecrets: (_) async {},
  ).upgrade(activeOwnerId: 'owner:learner', firebaseUid: 'firebase-user');
}

Future<void> _expectTargetLifecycleOwnership(
  AppDatabase database, {
  required bool expectedSaved,
  required int expectedOutboxCount,
}) async {
  final activeOwner = await database
      .customSelect(
        'SELECT id FROM local_owners WHERE is_active = 1',
        readsFrom: {database.localOwners},
      )
      .map((row) => row.read<String>('id'))
      .getSingle();
  expect(activeOwner, 'owner:account');

  final savedRows = await database.customSelect('''
    SELECT owner_id, is_deleted FROM saved_learning_items
  ''').get();
  expect(savedRows, hasLength(1));
  expect(savedRows.single.read<String>('owner_id'), activeOwner);
  expect(savedRows.single.read<int>('is_deleted'), expectedSaved ? 0 : 1);
  expect(
    await database
        .customSelect('''
          SELECT COUNT(*) AS count FROM saved_learning_items
          WHERE owner_id = 'owner:learner'
        ''')
        .map((row) => row.read<int>('count'))
        .getSingle(),
    0,
  );

  final outboxOwners = await database
      .customSelect('''
        SELECT owner_id FROM outbox_operations
        WHERE entity_type = 'savedLearningItem'
      ''')
      .map((row) => row.read<String>('owner_id'))
      .get();
  expect(outboxOwners, hasLength(expectedOutboxCount));
  expect(outboxOwners, everyElement(activeOwner));

  final archive = await OwnerLifecycleArchiveExporter(
    database: database,
    nowUtc: () => DateTime.utc(2026, 8, 24, 11),
  ).prepareActive();
  final envelope =
      jsonDecode(utf8.decode(archive.bytes)) as Map<String, Object?>;
  final content = envelope['content']! as Map<String, Object?>;
  final tables = content['tables']! as List<Object?>;
  final savedTable = tables.cast<Map<String, Object?>>().singleWhere(
    (table) => table['alias'] == 'savedLearningItems',
  );
  final records = savedTable['records']! as List<Object?>;
  expect(records.first, {'recordCount': 1});
  expect((records.last as Map<String, Object?>)['isSaved'], expectedSaved);

  final deleted = await LocalDataDeletion(
    database,
    deleteOwnerSecrets: (_) async {},
  ).eraseAll(ownerId: activeOwner);
  expect(deleted, greaterThan(0));
  expect(
    await database
        .customSelect('SELECT COUNT(*) AS count FROM saved_learning_items')
        .map((row) => row.read<int>('count'))
        .getSingle(),
    0,
  );
  expect(
    await database
        .customSelect('''
          SELECT COUNT(*) AS count FROM outbox_operations
          WHERE entity_type = 'savedLearningItem'
        ''')
        .map((row) => row.read<int>('count'))
        .getSingle(),
    0,
  );
  expect(
    await database
        .customSelect(
          "SELECT COUNT(*) AS count FROM local_owners WHERE id = 'owner:account'",
        )
        .map((row) => row.read<int>('count'))
        .getSingle(),
    0,
  );
  final sourceOwner = await database.customSelect('''
    SELECT is_active FROM local_owners WHERE id = 'owner:learner'
  ''').getSingle();
  expect(sourceOwner.read<int>('is_active'), 0);
}

final class _OwnerRepository implements LocalOwnerRepository {
  Future<void> Function()? _interleave;

  final owner = identity.LocalOwner(
    id: 'owner:learner',
    createdAtUtc: DateTime.utc(2026, 8, 24),
  );

  void interleaveNextEnsure(Future<void> Function() operation) {
    _interleave = operation;
  }

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    final staleOwner = owner;
    final operation = _interleave;
    _interleave = null;
    if (operation != null) await operation();
    return staleOwner;
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => throw UnimplementedError();
}
