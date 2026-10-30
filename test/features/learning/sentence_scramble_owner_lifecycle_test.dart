import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

import '../../support/sentence_scramble_native_harness.dart';

void main() {
  late SentenceScrambleNativeHarness h;
  setUp(() async => h = await SentenceScrambleNativeHarness.open());
  tearDown(() => h.close());

  test(
    'same-owner bind and replay preserve original sentence attempt and wire bytes',
    () async {
      await h.database.customStatement(
        "UPDATE local_owners SET firebase_uid = NULL, account_state = 'localGuest' WHERE id = ?",
        [configuredOwnerId],
      );
      final exercise = await _complete(
        h,
        configuredOwnerId,
        configuredCategoryId,
      );
      final before = await _nativeFacts(h.database, configuredOwnerId);
      final upgrade = _upgrade(h);
      Map<String, Object?>? afterFirstBind;
      for (var count = 0; count < 2; count++) {
        final result = await upgrade.upgrade(
          activeOwnerId: configuredOwnerId,
          firebaseUid: 'synthetic-sentence-new-uid',
        );
        expect(result.targetOwnerId, configuredOwnerId);
        expect(await _nativeFacts(h.database, configuredOwnerId), before);
        if (count == 0) {
          afterFirstBind = await h.storage.snapshot();
        } else {
          expect(await h.storage.snapshot(), afterFirstBind);
        }
      }
      expect(jsonEncode(before), isNot(contains(exercise.content.sentence)));
      final research = await h.storage.researchCounts();
      expect(research, hasLength(7));
      expect(research.values, everyElement(0));
    },
  );

  test(
    'ordinary owner merge hard-deletes duplicate word but retains original evidence and provenance',
    () async {
      await h.database.customStatement(
        "UPDATE local_owners SET firebase_uid = NULL, account_state = 'localGuest' WHERE id = ?",
        [configuredOwnerId],
      );
      await h.database.customStatement(
        "UPDATE vocabulary_categories SET name = 'Synthetic travel', normalized_name = 'synthetic travel' WHERE id = ?",
        [configuredOtherCategoryId],
      );
      await h.database.customStatement(
        'UPDATE vocabulary_words SET spelling = ?, normalized_spelling = ?, meaning = ?, normalized_meaning = ? WHERE owner_id = ?',
        ['station', 'station', 'สถานี', 'สถานี', configuredOtherOwnerId],
      );
      final exercise = await _complete(
        h,
        configuredOwnerId,
        configuredCategoryId,
      );
      final session = await h.storage.session(exercise.id);
      final attempt = (await _rows(
        h.database,
        'answer_attempts',
        configuredOwnerId,
      )).single;
      final operation = (await _rows(
        h.database,
        'outbox_operations',
        configuredOwnerId,
      )).where((row) => row['entity_type'] == 'attempt').single;
      final upgrade = _upgrade(h);
      final result = await upgrade.upgrade(
        activeOwnerId: configuredOwnerId,
        firebaseUid: 'synthetic-configured-uid-b',
      );
      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      expect(result.targetOwnerId, configuredOtherOwnerId);
      expect(
        await h.database
            .customSelect(
              'SELECT * FROM vocabulary_words WHERE id = ?',
              variables: [drift.Variable<String>(exercise.word.id)],
            )
            .get(),
        isEmpty,
        reason:
            'the actual guest duplicate word must be removed rather than merely copied',
      );
      expect(await h.storage.session(exercise.id), {
        ...session,
        'owner_id': configuredOtherOwnerId,
      });
      final moved = (await _rows(
        h.database,
        'answer_attempts',
        configuredOtherOwnerId,
      )).single;
      expect(moved, {
        ...attempt,
        'owner_id': configuredOtherOwnerId,
        'word_id': 'synthetic-configured-other-word',
      });
      expect(moved['provider_provenance'], exercise.providerProvenance);
      expect(jsonEncode(moved), isNot(contains(exercise.content.sentence)));
      expect(
        (await _rows(
          h.database,
          'outbox_operations',
          configuredOtherOwnerId,
        )).where((row) => row['entity_type'] == 'attempt').single,
        {...operation, 'owner_id': configuredOtherOwnerId},
      );
      final after = await h.storage.snapshot();
      await upgrade.upgrade(
        activeOwnerId: configuredOtherOwnerId,
        firebaseUid: 'synthetic-configured-uid-b',
      );
      expect(await h.storage.snapshot(), after);
      for (final table in [
        'srs_states',
        'points_ledger_entries',
        'reward_transactions',
        'achievement_unlocks',
        'quest_instances',
        'quest_objective_progress',
        'streak_states',
        'assessment_runs',
      ]) {
        expect(await h.storage.count(table), 0, reason: table);
      }
      final research = await h.storage.researchCounts();
      expect(research, hasLength(7));
      expect(research.values, everyElement(0));
      expect(
        await h.database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'personal export and cloud-confirmed purge retain other owner native facts byte-for-byte',
    () async {
      final source = await _complete(
        h,
        configuredOwnerId,
        configuredCategoryId,
      );
      await _complete(h, configuredOtherOwnerId, configuredOtherCategoryId);
      await h.storage.switchOwner(configuredOwnerId);
      final sourceFacts = await _nativeFacts(h.database, configuredOwnerId);
      final other = await _ownerSnapshot(h.database, configuredOtherOwnerId);
      final exported = await DriftAccountSnapshotBuilder(
        h.database,
        nowUtc: () => h.now,
      ).build(ownerId: configuredOwnerId);
      final document =
          jsonDecode(utf8.decode(exported.bytes)) as Map<String, dynamic>;
      final data = document['data'] as Map;
      expect(data['learning_sessions'], sourceFacts['learning_sessions']);
      expect(data['answer_attempts'], sourceFacts['answer_attempts']);
      expect(
        (data['answer_attempts'] as List).single['provider_provenance'],
        source.providerProvenance,
      );
      expect(exported.coveredScopes, requiredFullAccountExportScopes);
      expect(
        utf8.decode(exported.bytes),
        isNot(contains(source.content.sentence)),
      );

      const operation = 'synthetic-sentence-owner-delete';
      final cloud = CloudDeletionReceipt(
        receiptId: 'synthetic-sentence-cloud-receipt',
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: operation,
        completedAtUtc: h.now,
      ).durableMarker();
      final token = await h.storage.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: operation,
      );
      await h.storage.ownerWrites.markPending(token);
      await h.storage.ownerWrites.markCloud(token, cloud);
      final receipt = await DriftLocalAccountDeletionGateway(
        h.database,
        nowUtc: () => h.now,
        purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {},
      ).deleteAfterCloud(ownerId: configuredOwnerId, cloudReceipt: cloud);
      expect(receipt.deletedOwnerId, configuredOwnerId);
      for (final table in ownerUpgradeInventory) {
        expect(
          await _rows(h.database, table, configuredOwnerId),
          isEmpty,
          reason: table,
        );
      }
      expect(await _ownerSnapshot(h.database, configuredOtherOwnerId), other);
      await h.storage.ownerWrites.markLocal(token, cloud, receipt);
      await h.storage.ownerWrites.clearCompleted(token);
      expect(await h.storage.ownerWrites.inspect(), isNull);
      expect(await _ownerSnapshot(h.database, configuredOtherOwnerId), other);
      expect(
        await h.database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

DriftOwnerUpgradeRepository _upgrade(SentenceScrambleNativeHarness h) {
  var conflict = 0;
  return DriftOwnerUpgradeRepository(
    h.database,
    nowUtc: () => h.now,
    generateConflictId: () => 'synthetic-sentence-conflict-${++conflict}',
    generateOwnerId: () => 'synthetic-sentence-new-guest',
  );
}

Future<SentenceScrambleSession> _complete(
  SentenceScrambleNativeHarness h,
  String ownerId,
  String categoryId,
) async {
  await h.storage.switchOwner(ownerId);
  final prepared = (await h.prepare(categoryId: categoryId))!;
  final exercise = await h.learning.startNativeExercise(
    prepared,
    stillCurrent: () => true,
  );
  final answer = h.answer(exercise);
  await h.learning.commitNativeAnswer(
    exercise,
    answer,
    stillCurrent: () => true,
  );
  await h.learning.finishNativeExercise(
    h.learning.prepareNativeFinish(exercise, answer),
    stillCurrent: () => true,
  );
  return exercise;
}

Future<List<Map<String, Object?>>> _rows(
  AppDatabase database,
  String table,
  String ownerId,
) async =>
    (await database
            .customSelect(
              'SELECT * FROM $table WHERE owner_id = ? ORDER BY 1',
              variables: [drift.Variable<String>(ownerId)],
            )
            .get())
        .map((row) => Map<String, Object?>.from(row.data))
        .toList();

Future<Map<String, List<Map<String, Object?>>>> _nativeFacts(
  AppDatabase database,
  String ownerId,
) async => {
  for (final table in [
    'learning_sessions',
    'answer_attempts',
    'outbox_operations',
  ])
    table: [
      for (final row in await _rows(database, table, ownerId))
        if (table != 'outbox_operations' || row['entity_type'] == 'attempt')
          row,
    ],
};

Future<Map<String, List<Map<String, Object?>>>> _ownerSnapshot(
  AppDatabase database,
  String ownerId,
) async => {
  for (final table in ownerUpgradeInventory)
    table: await _rows(database, table, ownerId),
  'local_owners':
      (await database
              .customSelect(
                'SELECT * FROM local_owners WHERE id = ?',
                variables: [drift.Variable<String>(ownerId)],
              )
              .get())
          .map((row) => Map<String, Object?>.from(row.data))
          .toList(),
};
