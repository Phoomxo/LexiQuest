import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/progress/data/drift_learning_history_queries.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_projection_rebuilder.dart';

import '../../support/answer_attempt_evidence_fixture.dart';

final _now = DateTime.utc(2026, 10, 30, 12);

final _contentRevision =
    'sentence-scramble-v1:${sha256.convert(utf8.encode('synthetic-frozen-sentence-and-bank'))}';

final _provenance =
    'sentence-scramble-model-v1:${sha256.convert(utf8.encode('synthetic-sentence-provider-v1'))}';

EvidenceContext _scramble({
  EvidencePolicyRolloutMode rollout = EvidencePolicyRolloutMode.legacy,
}) => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.recreational,
  skillId: 'sentence-scramble',
  hintLevel: 0,
  contentRevision: _contentRevision,
  rolloutMode: rollout,
  protocolId: rollout == EvidencePolicyRolloutMode.legacy
      ? null
      : 'synthetic-protocol',
  protocolVersion: rollout == EvidencePolicyRolloutMode.legacy ? null : 'v1',
  experimentId: rollout == EvidencePolicyRolloutMode.legacy
      ? null
      : 'synthetic-experiment',
  experimentVersion: rollout == EvidencePolicyRolloutMode.legacy ? null : 1,
  assignmentId: rollout == EvidencePolicyRolloutMode.legacy
      ? null
      : 'synthetic-assignment',
  cohort: rollout == EvidencePolicyRolloutMode.legacy
      ? null
      : 'synthetic-cohort',
  researchConsentVersion: rollout == EvidencePolicyRolloutMode.legacy
      ? null
      : 1,
);

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.open());
  tearDown(() => fixture.database.close());

  for (final prompt in ['sentenceScramble']) {
    for (final correct in [true, false]) {
      test(
        '$prompt $correct keeps ordinary outcomes without mastery or motivation',
        () async {
          await fixture.answer(
            'native',
            prompt: prompt,
            context: _scramble(),
            correct: correct,
          );
          expect(
            await fixture.learning.rebuildWord(
              ownerId: 'owner-a',
              wordId: 'word-a',
            ),
            isNull,
          );
          await fixture.rebuild();
          for (final table in [
            'srs_states',
            'points_ledger_entries',
            'achievement_unlocks',
            'reward_transactions',
            'owned_reward_items',
            'equipped_reward_items',
            'quest_instances',
            'quest_objective_progress',
            'streak_states',
            'research_consents',
            'experiment_assignments',
            'research_participation_permits',
            'motivation_measurement_runs',
            'motivation_responses',
            'measurement_opportunities',
            'assessment_runs',
          ]) {
            expect(await fixture.rows(table), isEmpty, reason: table);
          }
          final session = (await fixture.rows('learning_sessions')).single;
          expect(session['correct_count'], correct ? 1 : 0);
          expect(session['wrong_count'], correct ? 0 : 1);
          expect(session['score'], correct ? 100 : 0);
          final history = await DriftLearningHistoryQueries(
            fixture.database,
          ).load(ownerId: 'owner-a', nowUtc: _now);
          expect(history.entries.single.answerCount, 1);
          expect(history.entries.single.correctCount, correct ? 1 : 0);
          expect(history.entries.single.hasAcceptedQuiz, isFalse);
          final progress = await DriftProgressQueries(
            fixture.database,
          ).load(ownerId: 'owner-a', nowUtc: _now);
          expect(progress.sampleSize, 0);
          expect(progress.totalXp, 0);
          expect(progress.streakDays, 0);
          expect(progress.completedSessions, 1);
          expect(progress.weaknesses, isEmpty);
          expect(
            progress.skills.every((skill) => skill.sampleSize == 0),
            isTrue,
          );
          final other = await DriftProgressQueries(
            fixture.database,
          ).load(ownerId: 'owner-b', nowUtc: _now);
          expect(other.completedSessions, 0);
          expect(other.totalXp, 0);
          expect(await fixture.rows('outbox_operations'), isEmpty);
          expect(await fixture.rows('events_v2'), isEmpty);
        },
      );
    }

    test(
      '$prompt inferred old rows retain their original ordinary effects',
      () async {
        await fixture.answer(
          'legacy',
          prompt: prompt,
          context: LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
        );
        await fixture.rebuild();
        expect(await fixture.rows('srs_states'), hasLength(1));
        expect(await fixture.rows('points_ledger_entries'), hasLength(1));
        expect(await fixture.rows('achievement_unlocks'), hasLength(2));
        expect(await fixture.rows('reward_transactions'), hasLength(1));
        final progress = await DriftProgressQueries(
          fixture.database,
        ).load(ownerId: 'owner-a', nowUtc: _now);
        expect(progress.sampleSize, 1);
        expect(progress.totalXp, 1);
        expect(progress.streakDays, 1);
      },
    );

    test(
      '$prompt cannot change independent prior ordinary effects on rebuild',
      () async {
        await fixture.answer(
          'ordinary',
          prompt: 'meaningChoice',
          context: LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
          at: _now.subtract(const Duration(days: 1)),
        );
        await fixture.rebuild();
        final before = await fixture.effects();
        await fixture.answer('native', prompt: prompt, context: _scramble());
        await fixture.rebuild();
        await fixture.rebuild();
        expect(await fixture.effects(), before);
        final history = await DriftLearningHistoryQueries(
          fixture.database,
        ).load(ownerId: 'owner-a', nowUtc: _now);
        expect(history.entries, hasLength(2));
        expect(
          history.entries.every((entry) => entry.answerCount == 1),
          isTrue,
        );
        final progress = await DriftProgressQueries(
          fixture.database,
        ).load(ownerId: 'owner-a', nowUtc: _now);
        expect(progress.sampleSize, 1);
        expect(progress.totalXp, 1);
        expect(progress.streakDays, 1);
      },
    );

    test('$prompt leaves a pre-existing SRS row byte-identical', () async {
      await fixture.database.customStatement(
        'INSERT INTO srs_states (id,owner_id,word_id,stability,difficulty,interval_days,repetitions,lapses,last_review_at_utc_ms,due_at_utc_ms,algorithm_version) '
        "VALUES ('synthetic-remote-state','owner-a','word-a',2.5,5,3,7,2,1,2,1)",
      );
      final before = await fixture.rows('srs_states');
      await fixture.answer('native', prompt: prompt, context: _scramble());
      expect(
        await fixture.learning.rebuildWord(
          ownerId: 'owner-a',
          wordId: 'word-a',
        ),
        isNull,
      );
      expect(await fixture.rows('srs_states'), before);
    });
  }
  for (final rollout in [
    EvidencePolicyRolloutMode.shadow,
    EvidencePolicyRolloutMode.enforced,
  ]) {
    test(
      'injected ${rollout.name} metadata cannot activate ordinary projections',
      () async {
        await fixture.answer(
          'invalid-nonlegacy',
          prompt: 'sentenceScramble',
          context: _scramble(rollout: rollout),
        );
        final effects = await fixture.effects();
        final attempts = await fixture.rows('answer_attempts');
        await fixture.rebuild();
        await fixture.rebuild();
        expect(await fixture.effects(), effects);
        expect(await fixture.rows('answer_attempts'), attempts);
        expect(await fixture.rows('outbox_operations'), isEmpty);
        expect(await fixture.rows('events_v2'), isEmpty);
        final progress = await DriftProgressQueries(
          fixture.database,
        ).load(ownerId: 'owner-a', nowUtc: _now);
        expect(progress.sampleSize, 0);
        expect(progress.totalXp, 0);
        expect(progress.streakDays, 0);
      },
    );
  }
}

final class _Fixture {
  _Fixture(this.database);
  final AppDatabase database;
  late final learning = DriftLearningProjectionRebuilder(database);
  late final rewards = DriftRewardProjectionRebuilder(database);

  static Future<_Fixture> open() async {
    final fixture = _Fixture(AppDatabase(NativeDatabase.memory()));
    await seedAnswerEvidenceOwners(fixture.database);
    return fixture;
  }

  Future<void> answer(
    String id, {
    required String prompt,
    required EvidenceContext context,
    bool correct = true,
    DateTime? at,
  }) async {
    final occurred = at ?? _now;
    await database.customStatement(
      'INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,ended_at_utc_ms,app_version,build_id) '
      "VALUES (?,'owner-a','sentenceScramble','completed',?,?,'synthetic','sentence-scramble-projections')",
      [
        'session:sentence-scramble-v1:$id',
        occurred.millisecondsSinceEpoch - 1000,
        occurred.millisecondsSinceEpoch,
      ],
    );
    await database.customStatement(
      'INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,response_time_ms,attempt_number,occurred_at_utc_ms,provider_provenance,evidence_class,evidence_context_json) '
      "VALUES (?,'owner-a',?,'word-a',?,?,40,1,?,?,?,?)",
      [
        '$id-answer',
        'session:sentence-scramble-v1:$id',
        prompt,
        correct ? 1 : 0,
        occurred.millisecondsSinceEpoch,
        context.classificationSource == EvidenceClassificationSource.declared
            ? _provenance
            : null,
        context.evidenceClass.name,
        jsonEncode(context.toJson()),
      ],
    );
  }

  Future<void> rebuild() async {
    await learning.rebuildWord(ownerId: 'owner-a', wordId: 'word-a');
    for (final row in await rows('learning_sessions')) {
      await learning.rebuildSession(
        ownerId: 'owner-a',
        sessionId: row['id']! as String,
      );
    }
    await learning.rebuildAchievements('owner-a');
    await rewards.rebuild('owner-a');
  }

  Future<List<Map<String, Object?>>> rows(String table) async => [
    for (final row
        in await database.customSelect('SELECT * FROM $table ORDER BY 1').get())
      row.data,
  ];

  Future<Map<String, List<Map<String, Object?>>>> effects() async => {
    for (final table in [
      'srs_states',
      'points_ledger_entries',
      'achievement_unlocks',
      'reward_transactions',
      'owned_reward_items',
      'equipped_reward_items',
      'quest_instances',
      'quest_objective_progress',
      'streak_states',
      'research_consents',
      'experiment_assignments',
      'research_participation_permits',
      'motivation_measurement_runs',
      'motivation_responses',
      'measurement_opportunities',
      'assessment_runs',
      'events_v2',
    ])
      table: await rows(table),
  };
}
