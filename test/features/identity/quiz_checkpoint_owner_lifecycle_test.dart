import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

import '../../support/answer_attempt_evidence_fixture.dart';

final _now = DateTime.utc(2026, 10, 29, 12);

void main() {
  late AppDatabase database;
  late Map<String, Map<String, Object?>> stored;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await seedAnswerEvidenceOwners(database);
    stored = {};
    for (final suffix in ['a', 'b']) {
      final word = QuizWord(
        id: 'word-$suffix',
        categoryId: 'category-$suffix',
        spelling: 'word $suffix',
        meaning: 'meaning $suffix',
        partOfSpeech: 'noun',
        contentRevision: 'local-vocabulary-v1:1',
      );
      final plan = AcceptedQuizPlan.create(
        configuration: QuizConfiguration.category(categoryId: word.categoryId),
        questions: [
          QuizQuestion(word: word, options: [word.meaning]),
        ],
      );
      final checkpoint = AwaitingQuizAnswer(
        planId: plan.id,
        questionOrdinal: 0,
        assistance: QuizAssistance().showHint(2000).hideHint(),
      );
      await database.customStatement(
        'INSERT INTO learning_sessions '
        '(id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id, '
        'accepted_plan_id, accepted_plan_json, checkpoint_revision, checkpoint_json) '
        "VALUES (?, ?, 'quiz', 'active', 1000, 'synthetic', 'owner-storage', ?, ?, 3, ?)",
        [
          'quiz-$suffix',
          'owner-$suffix',
          plan.id,
          plan.stableSerialization,
          checkpoint.stableSerialization,
        ],
      );
      stored[suffix] = await _row(database, suffix);
    }
  });
  tearDown(() => database.close());

  test(
    'personal export retains the complete plan and checkpoint only for its owner',
    () async {
      final snapshot = await DriftAccountSnapshotBuilder(
        database,
        nowUtc: () => _now,
      ).build(ownerId: 'owner-a');
      final document =
          jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, dynamic>;
      final rows = (document['data'] as Map)['learning_sessions'] as List;
      expect(rows, [stored['a']]);
      expect(document['schemaVersion'], 20);
      expect((document['data'] as Map)['saved_words'], isEmpty);
      expect((document['data'] as Map)['word_reports'], isEmpty);
      expect((document['data'] as Map)['assessment_runs'], isEmpty);
      expect(snapshot.coveredScopes, requiredFullAccountExportScopes);
      final exported = rows.single as Map;
      expect(exported, hasLength(15));
      expect(exported['accepted_plan_json'], contains('word-a'));
      expect(exported['accepted_plan_json'], isNot(contains('word-b')));
      final plan = AcceptedQuizPlan.parse(
        id: exported['accepted_plan_id'] as String,
        json: exported['accepted_plan_json'] as String,
      );
      final checkpoint = QuizCheckpoint.parse(
        exported['checkpoint_json'] as String,
        plan: plan,
      );
      expect(checkpoint.assistance.hintFirstShownAtUtcMs, 2000);
      expect(checkpoint.assistance.hintVisible, isFalse);
    },
  );

  test(
    'same-owner bind and replay preserve every accepted byte and revision',
    () async {
      await database.customStatement(
        "UPDATE local_owners SET firebase_uid = NULL, account_state = 'localGuest' WHERE id = 'owner-a'",
      );
      final repository = _upgrade(database);
      for (var attempt = 0; attempt < 2; attempt++) {
        final result = await repository.upgrade(
          activeOwnerId: 'owner-a',
          firebaseUid: 'synthetic-new-uid',
        );
        expect(result.targetOwnerId, 'owner-a');
        expect(await _row(database, 'a'), stored['a']);
        expect(await _row(database, 'b'), stored['b']);
      }
    },
  );

  test(
    'ordinary owner rehome retains immutable bodies without rewriting their pins',
    () async {
      await database.customStatement(
        "UPDATE local_owners SET firebase_uid = NULL, account_state = 'localGuest' WHERE id = 'owner-a'",
      );
      final repository = _upgrade(database);
      final result = await repository.upgrade(
        activeOwnerId: 'owner-a',
        firebaseUid: 'uid-b',
      );
      expect(result.targetOwnerId, 'owner-b');
      final expected = {...stored['a']!, 'owner_id': 'owner-b'};
      expect(await _row(database, 'a'), expected);
      expect(await _row(database, 'b'), stored['b']);
      await repository.upgrade(activeOwnerId: 'owner-b', firebaseUid: 'uid-b');
      expect(await _row(database, 'a'), expected);
      // A retained body is storage evidence; the recovery reader must recheck pins.
      final operations = await database.select(database.outboxOperations).get();
      expect(
        operations.where(
          (row) =>
              row.entityType == 'session' ||
              row.entityType == 'quizPlan' ||
              row.entityType == 'quizCheckpoint',
        ),
        isEmpty,
      );
    },
  );

  test(
    'cloud-confirmed owner purge removes recovery data and preserves the other owner exactly',
    () async {
      final receipt =
          await DriftLocalAccountDeletionGateway(
            database,
            nowUtc: () => _now,
            purgeOwnerSecret:
                ({required ownerId, required firebaseUid}) async {},
          ).deleteAfterCloud(
            ownerId: 'owner-a',
            cloudReceipt: CloudDeletionReceipt(
              receiptId: 'synthetic-checkpoint-deletion-receipt',
              ownerId: 'owner-a',
              firebaseUid: 'uid-a',
              idempotencyKey: 'delete:00000000-0000-4000-8000-000000000001',
              completedAtUtc: _now,
            ),
          );
      expect(receipt.deletedOwnerId, 'owner-a');
      final rows = await database.select(database.learningSessions).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 'quiz-b');
      expect(await _row(database, 'b'), stored['b']);
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

DriftOwnerUpgradeRepository _upgrade(AppDatabase database) {
  var conflict = 0;
  return DriftOwnerUpgradeRepository(
    database,
    nowUtc: () => _now,
    generateConflictId: () => 'synthetic-quiz-conflict-${conflict++}',
    generateOwnerId: () => 'synthetic-unused-owner',
  );
}

Future<Map<String, Object?>> _row(AppDatabase database, String suffix) async =>
    (await database
            .customSelect(
              'SELECT * FROM learning_sessions WHERE id = ?',
              variables: [drift.Variable<String>('quiz-$suffix')],
            )
            .getSingle())
        .data;
