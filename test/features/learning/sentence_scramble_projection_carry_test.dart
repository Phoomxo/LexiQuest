import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_projection_rebuilder.dart';

import '../../support/answer_attempt_evidence_fixture.dart';

final _now = DateTime.utc(2026, 10, 30, 12);

final _contentRevision =
    'sentence-scramble-v1:${sha256.convert(utf8.encode('synthetic-frozen-sentence-and-bank'))}';

final _provenance =
    'sentence-scramble-model-v1:${sha256.convert(utf8.encode('synthetic-sentence-provider-v1'))}';

void main() {
  for (final prompt in ['sentenceScramble']) {
    for (final corrupt in [false, true]) {
      for (final mixed in [false, true]) {
        test(
          '$prompt corrupt=$corrupt mixed=$mixed excludes native carry and preserves independent legacy',
          () async {
            final database = AppDatabase(NativeDatabase.memory());
            addTearDown(database.close);
            await seedAnswerEvidenceOwners(database);
            final context = EvidenceContext.forNewEvidence(
              evidenceClass: EvidenceClass.recreational,
              skillId: 'sentence-scramble',
              hintLevel: 0,
              contentRevision: _contentRevision,
              rolloutMode: EvidencePolicyRolloutMode.legacy,
            );
            await database.customStatement(
              'INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,ended_at_utc_ms,app_version,build_id) '
              "VALUES ('session:sentence-scramble-v1:synthetic','owner-a','sentenceScramble','completed',?,?,'synthetic','sentence-scramble-carry')",
              [_now.millisecondsSinceEpoch - 1000, _now.millisecondsSinceEpoch],
            );
            await database.customStatement(
              'INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,response_time_ms,attempt_number,occurred_at_utc_ms,provider_provenance,evidence_class,evidence_context_json) '
              "VALUES ('synthetic-native-answer','owner-a','session:sentence-scramble-v1:synthetic','word-a',?,1,40,1,?,?,?,?)",
              [
                prompt,
                _now.millisecondsSinceEpoch,
                _provenance,
                context.evidenceClass.name,
                corrupt ? '{}' : jsonEncode(context.toJson()),
              ],
            );
            if (mixed) {
              final ordinary =
                  LearningEvidenceContract.frozenV13LegacyEvidenceContext();
              await database.customStatement(
                'INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,response_time_ms,attempt_number,occurred_at_utc_ms,evidence_class,evidence_context_json) '
                "VALUES ('synthetic-old-ordinary-answer','owner-a','session:sentence-scramble-v1:synthetic','word-a','meaningChoice',0,40,1,?,?,?)",
                [
                  _now.millisecondsSinceEpoch,
                  ordinary.evidenceClass.name,
                  jsonEncode(ordinary.toJson()),
                ],
              );
            }
            for (final (id, source, amount) in <(String, String?, int)>[
              (
                'synthetic-native-session-carry',
                'session:sentence-scramble-v1:synthetic',
                20,
              ),
              ('synthetic-native-answer-carry', 'synthetic-native-answer', 30),
              ('synthetic-independent-carry', null, 7),
            ]) {
              await database.customStatement(
                'INSERT INTO points_ledger_entries (id,owner_id,idempotency_key,entry_type,amount,source_event_id,occurred_at_utc_ms) '
                "VALUES (?,'owner-a',?,'legacy',?,?,?)",
                [id, id, amount, source, _now.millisecondsSinceEpoch],
              );
            }
            final pointsBefore = await _rows(database, 'points_ledger_entries');
            final attemptsBefore = await _rows(database, 'answer_attempts');
            final rewards = DriftRewardProjectionRebuilder(database);
            final expected = mixed ? 27 : 7;
            expect((await rewards.readLedger('owner-a')).balance, expected);
            await rewards.rebuild('owner-a');
            await rewards.rebuild('owner-a');
            expect((await rewards.readLedger('owner-a')).balance, expected);
            final progress = await DriftProgressQueries(
              database,
            ).load(ownerId: 'owner-a', nowUtc: _now);
            expect(progress.totalXp, expected);
            expect(progress.sampleSize, mixed ? 1 : 0);
            expect(progress.streakDays, mixed ? 1 : 0);
            expect(
              await _rows(database, 'points_ledger_entries'),
              pointsBefore,
            );
            expect(await _rows(database, 'answer_attempts'), attemptsBefore);
            expect(await _rows(database, 'outbox_operations'), isEmpty);
            expect(await _rows(database, 'events_v2'), isEmpty);
            final other = await DriftProgressQueries(
              database,
            ).load(ownerId: 'owner-b', nowUtc: _now);
            expect(other.totalXp, 0);
          },
        );
      }
    }
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
