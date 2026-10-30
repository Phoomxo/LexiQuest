import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_projection_rebuilder.dart';

import '../../support/answer_attempt_evidence_fixture.dart';

final _now = DateTime.utc(2026, 10, 30, 12);

void main() {
  for (final mixedOrdinary in [false, true]) {
    test(
      mixedOrdinary
          ? 'valid mixed ordinary fact preserves independent session carry beside corrupt Dictation'
          : 'corrupt Dictation-only context cannot revive native session carry as coins or XP',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        await seedAnswerEvidenceOwners(database);
        await database.customStatement(
          'INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,ended_at_utc_ms,app_version,build_id) '
          "VALUES ('synthetic-corrupt-dictation-session','owner-a','dictation','completed',?,?,'synthetic','native-carry-red')",
          [_now.millisecondsSinceEpoch - 1000, _now.millisecondsSinceEpoch],
        );
        await database.customStatement(
          'INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,response_time_ms,attempt_number,occurred_at_utc_ms,evidence_class,evidence_context_json) '
          "VALUES ('synthetic-corrupt-native-answer','owner-a','synthetic-corrupt-dictation-session','word-a','dictation',1,40,1,?,'guidedPractice','{}')",
          [_now.millisecondsSinceEpoch],
        );
        for (final projection in LearningProjection.values) {
          expect(
            LearningEvidenceContract.allowsOrdinaryProjection(
              promptMode: 'dictation',
              evidenceClass: 'guidedPractice',
              evidenceContextJson: '{}',
              projection: projection,
            ),
            isFalse,
          );
        }
        if (mixedOrdinary) {
          final original =
              LearningEvidenceContract.frozenV13LegacyEvidenceContext();
          await database.customStatement(
            'INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,response_time_ms,attempt_number,occurred_at_utc_ms,evidence_class,evidence_context_json) '
            "VALUES ('synthetic-old-ordinary-answer','owner-a','synthetic-corrupt-dictation-session','word-a','meaningChoice',0,40,1,?,?,?)",
            [
              _now.millisecondsSinceEpoch,
              original.evidenceClass.name,
              jsonEncode(original.toJson()),
            ],
          );
        }
        await database.customStatement(
          'INSERT INTO points_ledger_entries (id,owner_id,idempotency_key,entry_type,amount,source_event_id,occurred_at_utc_ms) '
          "VALUES ('synthetic-native-session-carry','owner-a','synthetic-native-session-carry','legacy',20,'synthetic-corrupt-dictation-session',?),"
          "('synthetic-independent-carry','owner-a','synthetic-independent-carry','legacy',7,NULL,?)",
          [_now.millisecondsSinceEpoch, _now.millisecondsSinceEpoch],
        );
        final pointsBefore = await _rows(database, 'points_ledger_entries');
        final attemptsBefore = await _rows(database, 'answer_attempts');
        final rewards = DriftRewardProjectionRebuilder(database);
        final expected = mixedOrdinary ? 27 : 7;
        expect((await rewards.readLedger('owner-a')).balance, expected);
        await rewards.rebuild('owner-a');
        expect((await rewards.readLedger('owner-a')).balance, expected);
        final progress = await DriftProgressQueries(
          database,
        ).load(ownerId: 'owner-a', nowUtc: _now);
        expect(progress.totalXp, expected);
        expect(progress.sampleSize, mixedOrdinary ? 1 : 0);
        expect(await _rows(database, 'points_ledger_entries'), pointsBefore);
        expect(await _rows(database, 'answer_attempts'), attemptsBefore);
        expect(await _rows(database, 'outbox_operations'), isEmpty);
        expect(await _rows(database, 'events_v2'), isEmpty);
      },
    );
  }
}

Future<List<Map<String, Object?>>> _rows(
  AppDatabase database,
  String table,
) async => [
  for (final row
      in await database.customSelect('SELECT * FROM $table ORDER BY 1').get())
    row.data,
];
