import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/sync/application/sync_backoff.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_mutex.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  test(
    'lost acknowledgement replays vocabulary and learning work once after reopen',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-file-backed-sync-',
      );
      final path = '${directory.path}${Platform.pathSeparator}sync.sqlite';
      final gateway = _RestartCloud();
      var nowUtc = DateTime.utc(2026, 8, 9, 9);
      var leaseSequence = 0;

      AppDatabase openDatabase() => AppDatabase(NativeDatabase(File(path)));
      SyncEngine buildEngine(AppDatabase database) {
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner',
          nowUtc: () => nowUtc,
        );
        return SyncEngine(
          owners: owners,
          store: DriftSyncStore(database),
          gateway: gateway,
          policyProvider: () async => CloudSyncPolicy(
            enabled: true,
            source: CloudSyncPolicySource.cache,
            fetchedAtUtc: nowUtc,
            expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
          ),
          ownerGate: DriftOwnerOperationGate(database),
          mutex: SyncMutex(),
          backoff: const SyncBackoff(jitterFraction: 0),
          nowUtc: () => nowUtc,
          generateLeaseToken: () => 'restart-lease-${leaseSequence++}',
        );
      }

      try {
        var database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        await _seedRestartInventory(database);

        final lostAcknowledgement = await buildEngine(database).run();
        final reserved =
            await (database.select(database.outboxOperations)
                  ..where((row) => row.operationId.equals(_lostAckOperationId)))
                .getSingle();

        expect(lostAcknowledgement.status, SyncRunStatus.partialFailure);
        expect(reserved.state, 'retryWaiting');
        expect(reserved.attemptCount, 1);
        expect(gateway.requestCounts[_lostAckNamespaceKey], 1);
        expect(gateway.applyCounts[_lostAckNamespaceKey], 1);
        expect(
          await DriftSyncStore(
            database,
          ).readCheckpoint('owner-a', SyncCollection.categories),
          isNull,
        );
        nowUtc = DateTime.fromMillisecondsSinceEpoch(
          reserved.nextAttemptAtUtcMs!,
          isUtc: true,
        );
        await database.close();

        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        final replayed = await buildEngine(database).run();
        final afterReplay = await _restartSnapshot(database);
        final checkpoint = await DriftSyncStore(
          database,
        ).readCheckpoint('owner-a', SyncCollection.categories);
        final pushesAfterReplay = gateway.pushCalls;

        expect(replayed.status, SyncRunStatus.completed);
        expect(gateway.requestCounts[_lostAckNamespaceKey], 2);
        expect(gateway.applyCounts[_lostAckNamespaceKey], 1);
        expect(gateway.applyCounts, hasLength(4));
        expect(gateway.applyCounts.values, everyElement(1));
        expect(checkpoint, gateway.categoryCursor);
        expect(afterReplay['categoryIds'], {
          'category:local',
          'category:remote',
        });
        expect(afterReplay['wordIds'], {'word:local'});
        expect(afterReplay['attemptIds'], {'attempt:local'});
        expect(afterReplay['srsIds'], {'srs:local'});
        expect(
          afterReplay['operationRows'],
          everyElement(contains('|acknowledged|')),
        );
        await database.close();

        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        nowUtc = nowUtc.add(const Duration(minutes: 1));
        final secondReopen = await buildEngine(database).run();
        final stable = await _restartSnapshot(database);
        final stableCheckpoint = await DriftSyncStore(
          database,
        ).readCheckpoint('owner-a', SyncCollection.categories);

        expect(secondReopen.status, SyncRunStatus.completed);
        expect(secondReopen.pushed, 0);
        expect(gateway.pushCalls, pushesAfterReplay);
        expect(gateway.requestCounts[_lostAckNamespaceKey], 2);
        expect(gateway.applyCounts.values, everyElement(1));
        expect(stable, afterReplay);
        expect(stableCheckpoint, checkpoint);
        await database.close();
      } finally {
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );
}

const String _lostAckOperationId = 'category:local:1';
const String _lostAckNamespaceKey = 'firebase-a|category:local:1';

final class _RestartCloud implements SyncGateway {
  int pushCalls = 0;
  final Map<String, int> requestCounts = <String, int>{};
  final Map<String, int> applyCounts = <String, int>{};
  final Map<String, PushAcknowledged> durableAcknowledgements =
      <String, PushAcknowledged>{};
  final SyncCursor categoryCursor = SyncCursor(
    serverUpdatedAtUtc: DateTime.utc(2026, 8, 9, 9, 1),
    documentId: 'category:remote',
  );

  @override
  Future<PushResult> push(PushMutation mutation) async {
    pushCalls += 1;
    final namespaceKey = '${mutation.firebaseUid}|${mutation.operationId}';
    final requestCount = requestCounts.update(
      namespaceKey,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    final existing = durableAcknowledgements[namespaceKey];
    if (existing != null) return existing;

    applyCounts.update(namespaceKey, (count) => count + 1, ifAbsent: () => 1);
    final acknowledgement = PushAcknowledged(
      operationId: mutation.operationId,
      resultingRevision: mutation.localRevision,
      acknowledgedAtUtc: categoryCursor.serverUpdatedAtUtc,
    );
    durableAcknowledgements[namespaceKey] = acknowledgement;
    if (namespaceKey == _lostAckNamespaceKey && requestCount == 1) {
      throw const ProviderUnavailableSyncFailure();
    }
    return acknowledgement;
  }

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async {
    if (collection != SyncCollection.categories || after != null) {
      return PullPage(
        changes: const <SyncEntity>[],
        nextCursor: after,
        hasMore: false,
      );
    }
    return PullPage(
      changes: <SyncEntity>[
        SyncEntity(
          collection: SyncCollection.categories,
          entityId: 'category:remote',
          revision: 1,
          isDeleted: false,
          payloadVersion: 1,
          clientUpdatedAtUtc: categoryCursor.serverUpdatedAtUtc,
          serverUpdatedAtUtc: categoryCursor.serverUpdatedAtUtc,
          payload: const <String, Object?>{'name': 'Remote'},
        ),
      ],
      nextCursor: categoryCursor,
      hasMore: false,
    );
  }

  @override
  Future<CloudSyncPolicy> fetchPolicy() async => CloudSyncPolicy(
    enabled: true,
    source: CloudSyncPolicySource.remote,
    fetchedAtUtc: categoryCursor.serverUpdatedAtUtc,
    expiresAtUtc: categoryCursor.serverUpdatedAtUtc.add(
      const Duration(hours: 1),
    ),
  );
}

Future<Map<String, Object>> _restartSnapshot(AppDatabase database) async {
  final operations = await database
      .customSelect(
        'SELECT operation_id, entity_type, entity_id, state, attempt_count, '
        'acknowledged_at_utc_ms FROM outbox_operations ORDER BY operation_id',
      )
      .get();
  return <String, Object>{
    'categoryIds': (await database.select(database.vocabularyCategories).get())
        .map((row) => row.id)
        .toSet(),
    'wordIds': (await database.select(database.vocabularyWords).get())
        .map((row) => row.id)
        .toSet(),
    'attemptIds': (await database.select(database.answerAttempts).get())
        .map((row) => row.id)
        .toSet(),
    'srsIds': (await database.select(database.srsStates).get())
        .map((row) => row.id)
        .toSet(),
    'operationRows': operations
        .map(
          (row) =>
              '${row.read<String>('operation_id')}|'
              '${row.read<String>('entity_type')}|'
              '${row.read<String>('entity_id')}|'
              '${row.read<String>('state')}|'
              '${row.read<int>('attempt_count')}|'
              '${row.readNullable<int>('acknowledged_at_utc_ms')}',
        )
        .toList(),
  };
}

Future<void> _seedRestartInventory(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
    "VALUES ('owner-a', 'firebase-a', 'firebaseBound', 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, sort_order, local_revision, '
    'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) '
    "VALUES ('category:local', 'owner-a', 'Local', 'local', 0, 1, 0, 0, 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
    'normalized_meaning, part_of_speech, source, is_global, local_revision, '
    'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) VALUES '
    "('word:local', 'owner-a', 'category:local', 'station', 'station', "
    "'station', 'station', 'noun', 'manual', 0, 1, 0, 0, 1, 1)",
  );
  await database.customInsert(
    "INSERT INTO learning_sessions VALUES ('session:local', 'owner-a', "
    "'quiz', 'completed', 1, 2, 1, 0, 100, '1', '1')",
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, '
    'provider_provenance) VALUES '
    "('attempt:local', 'owner-a', 'session:local', 'word:local', 'meaning', "
    '1, 100, 1, 2, NULL)',
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES ('srs:local', 'owner-a', 'word:local', "
    '1, 1, 1, 1, 0, 2, 3, 1)',
  );

  const operations = <(String, String, String)>[
    (_lostAckOperationId, 'category', 'category:local'),
    ('word:local:1', 'word', 'word:local'),
    ('attempt:local:1', 'attempt', 'attempt:local'),
    ('srsState:word:local:1', 'srsState', 'word:local'),
  ];
  var createdAt = 1;
  for (final operation in operations) {
    await database.customInsert(
      'INSERT INTO outbox_operations '
      '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
      'created_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<String>(operation.$1),
        const Variable<String>('owner-a'),
        Variable<String>(operation.$2),
        Variable<String>(operation.$3),
        const Variable<String>('upsert'),
        Variable<int>(createdAt++),
      ],
    );
  }
}
