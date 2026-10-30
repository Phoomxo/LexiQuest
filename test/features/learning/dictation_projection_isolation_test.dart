import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/progress/data/drift_learning_history_queries.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_projection_rebuilder.dart';

import '../../support/answer_attempt_evidence_fixture.dart';

final _now = DateTime.utc(2026, 10, 30, 12);

EvidenceContext _dictation({required bool assisted}) =>
    EvidenceContext.forNewEvidence(
      evidenceClass: assisted
          ? EvidenceClass.guidedPractice
          : EvidenceClass.independentRecall,
      skillId: 'dictation-spelling',
      hintLevel: assisted ? 1 : 0,
      contentRevision: 'local-vocabulary-v1:1',
      rolloutMode: EvidencePolicyRolloutMode.legacy,
    );

void main() {
  late _Fixture fixture;
  setUp(() async => fixture = await _Fixture.open());
  tearDown(() => fixture.database.close());

  for (final correct in [true, false]) {
    test(
      'assisted $correct Dictation keeps session and history without mastery or motivation',
      () async {
        await fixture.answer(
          'guided',
          context: _dictation(assisted: true),
          correct: correct,
        );
        final state = await fixture.learning.rebuildWord(
          ownerId: 'owner-a',
          wordId: 'word-a',
        );
        expect(state, isNull);
        await fixture.rebuild();
        for (final table in [
          'srs_states',
          'points_ledger_entries',
          'achievement_unlocks',
          'reward_transactions',
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
        expect(progress.streakDays, 0);
        expect(progress.totalXp, 0);
        expect(progress.weaknesses, isEmpty);
        expect(progress.skills.every((skill) => skill.sampleSize == 0), isTrue);
        expect(progress.completedSessions, 1);
        expect(await fixture.rows('outbox_operations'), isEmpty);
        expect(await fixture.rows('events_v2'), isEmpty);
      },
    );
  }

  test(
    'normal declared Dictation updates SRS but false engagement grants no motivation',
    () async {
      await fixture.answer('normal', context: _dictation(assisted: false));
      final state = await fixture.learning.rebuildWord(
        ownerId: 'owner-a',
        wordId: 'word-a',
      );
      expect(state, isNotNull);
      await fixture.rebuild();
      expect(await fixture.rows('srs_states'), hasLength(1));
      for (final table in [
        'points_ledger_entries',
        'achievement_unlocks',
        'reward_transactions',
      ]) {
        expect(await fixture.rows(table), isEmpty, reason: table);
      }
      final progress = await DriftProgressQueries(
        fixture.database,
      ).load(ownerId: 'owner-a', nowUtc: _now);
      expect(progress.sampleSize, 1);
      expect(
        progress.skills
            .singleWhere((skill) => skill.key == 'listening')
            .sampleSize,
        1,
      );
      expect(progress.streakDays, 0);
      expect(progress.totalXp, 0);
    },
  );

  for (final vector in [
    'inferred-dictation',
    'meaningChoice',
    'pronunciationTranscript',
    'unknown-guided',
  ]) {
    test(
      'existing $vector compatibility still produces its original ordinary projections',
      () async {
        final context = switch (vector) {
          'inferred-dictation' =>
            LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
          'unknown-guided' => EvidenceContext.forNewEvidence(
            evidenceClass: EvidenceClass.guidedPractice,
            skillId: 'old-guided',
            hintLevel: 1,
            contentRevision: 'local-vocabulary-v1:1',
            rolloutMode: EvidencePolicyRolloutMode.legacy,
          ),
          _ => captureCurrentActivityEvidence(
            promptMode: vector,
            contentRevision: 'local-vocabulary-v1:1',
          ),
        };
        await fixture.answer(
          'old',
          context: context,
          prompt: vector == 'inferred-dictation' ? 'dictation' : vector,
        );
        await fixture.rebuild();
        expect(await fixture.rows('srs_states'), hasLength(1));
        expect(await fixture.rows('points_ledger_entries'), hasLength(1));
        expect(await fixture.rows('reward_transactions'), hasLength(1));
        expect(await fixture.rows('achievement_unlocks'), hasLength(2));
        final progress = await DriftProgressQueries(
          fixture.database,
        ).load(ownerId: 'owner-a', nowUtc: _now);
        expect(progress.sampleSize, 1);
        expect(progress.totalXp, 1);
        expect(progress.streakDays, 1);
      },
    );
  }

  test(
    'assisted evidence leaves prior SRS XP rewards and achievements byte-identical',
    () async {
      await fixture.answer(
        'old',
        context: LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
        prompt: 'meaningChoice',
        at: _now.subtract(const Duration(days: 1)),
      );
      await fixture.rebuild();
      final before = await fixture.effects();
      await fixture.answer('guided', context: _dictation(assisted: true));
      await fixture.rebuild();
      await fixture.rebuild();
      expect(await fixture.effects(), before);
      final progress = await DriftProgressQueries(
        fixture.database,
      ).load(ownerId: 'owner-a', nowUtc: _now);
      expect(progress.sampleSize, 1);
      expect(progress.streakDays, 1);
      final history = await DriftLearningHistoryQueries(
        fixture.database,
      ).load(ownerId: 'owner-a', nowUtc: _now);
      expect(history.entries, hasLength(2));
      expect(history.entries.every((entry) => entry.answerCount == 1), isTrue);
    },
  );

  test(
    'native answer and session XP carry cannot mint coins or dashboard XP',
    () async {
      await fixture.answer('guided', context: _dictation(assisted: true));
      await fixture.carry('native-answer-carry', 'guided-answer', 20);
      await fixture.carry('native-session-carry', 'guided-session', 30);
      await fixture.carry('independent-legacy-carry', null, 7);
      final originalPoints = await fixture.rows('points_ledger_entries');
      expect((await fixture.rewards.readLedger('owner-a')).balance, 7);
      await fixture.rewards.rebuild('owner-a');
      expect((await fixture.rewards.readLedger('owner-a')).balance, 7);
      final credits = await fixture.rows('reward_transactions');
      expect(credits, hasLength(1));
      expect(credits.single['source_event_id'], 'independent-legacy-carry');
      final progress = await DriftProgressQueries(
        fixture.database,
      ).load(ownerId: 'owner-a', nowUtc: _now);
      expect(progress.totalXp, 7);
      expect(await fixture.rows('points_ledger_entries'), originalPoints);
    },
  );

  test(
    'a mixed old ordinary session retains independent legacy carry',
    () async {
      await fixture.answer('mixed', context: _dictation(assisted: true));
      await fixture.answer(
        'ordinary',
        context: LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
        prompt: 'meaningChoice',
        sessionId: 'mixed-session',
        correct: false,
      );
      await fixture.carry('mixed-session-carry', 'mixed-session', 9);
      expect((await fixture.rewards.readLedger('owner-a')).balance, 9);
      final progress = await DriftProgressQueries(
        fixture.database,
      ).load(ownerId: 'owner-a', nowUtc: _now);
      expect(progress.totalXp, 9);
      expect(progress.sampleSize, 1);
    },
  );

  test(
    'genuine prior remote SRS baseline survives assisted-only local evidence',
    () async {
      await fixture.database.customStatement(
        'INSERT INTO srs_states (id,owner_id,word_id,stability,difficulty,interval_days,repetitions,lapses,last_review_at_utc_ms,due_at_utc_ms,algorithm_version) '
        "VALUES ('synthetic-remote-state','owner-a','word-a',2.5,5,3,7,2,1,2,1)",
      );
      final original = await fixture.rows('srs_states');
      await fixture.answer('guided', context: _dictation(assisted: true));
      expect(
        await fixture.learning.rebuildWord(
          ownerId: 'owner-a',
          wordId: 'word-a',
        ),
        isNull,
      );
      expect(await fixture.rows('srs_states'), original);
    },
  );

  test(
    'an earlier assisted fact never becomes the source of an ordinary achievement',
    () async {
      await fixture.answer(
        'guided',
        context: _dictation(assisted: true),
        at: _now.subtract(const Duration(minutes: 2)),
      );
      await fixture.answer(
        'ordinary',
        context: LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
        prompt: 'meaningChoice',
        at: _now.subtract(const Duration(minutes: 1)),
      );
      await fixture.rebuild();
      expect(
        (await fixture.rows(
          'achievement_unlocks',
        )).every((row) => row['source_event_id'] == 'ordinary-answer'),
        isTrue,
      );
    },
  );
}

final class _Fixture {
  _Fixture(this.database);
  final AppDatabase database;
  late final learning = DriftLearningProjectionRebuilder(database);
  late final rewards = DriftRewardProjectionRebuilder(database);

  static Future<_Fixture> open() async {
    final result = _Fixture(AppDatabase(NativeDatabase.memory()));
    await seedAnswerEvidenceOwners(result.database);
    return result;
  }

  Future<void> answer(
    String id, {
    required EvidenceContext context,
    bool correct = true,
    String prompt = 'dictation',
    DateTime? at,
    String? sessionId,
  }) async {
    final occurred = at ?? _now;
    final session = sessionId ?? '$id-session';
    await database.customStatement(
      'INSERT OR IGNORE INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,ended_at_utc_ms,app_version,build_id) '
      "VALUES (?,'owner-a','dictation','completed',?,?,'synthetic','dictation-projections')",
      [
        session,
        occurred.subtract(const Duration(seconds: 1)).millisecondsSinceEpoch,
        occurred.millisecondsSinceEpoch,
      ],
    );
    await database.customStatement(
      'INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,response_time_ms,attempt_number,occurred_at_utc_ms,evidence_class,evidence_context_json) '
      "VALUES (?,'owner-a',?,'word-a',?,?,40,1,?,?,?)",
      [
        '$id-answer',
        session,
        prompt,
        correct ? 1 : 0,
        occurred.millisecondsSinceEpoch,
        context.evidenceClass.name,
        jsonEncode(context.toJson()),
      ],
    );
  }

  Future<void> carry(
    String id,
    String? source,
    int amount,
  ) => database.customStatement(
    'INSERT INTO points_ledger_entries (id,owner_id,idempotency_key,entry_type,amount,source_event_id,occurred_at_utc_ms) '
    "VALUES (?,'owner-a',?,'legacy',?,?,?)",
    [id, id, amount, source, _now.millisecondsSinceEpoch],
  );

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
    ])
      table: await rows(table),
  };
}
