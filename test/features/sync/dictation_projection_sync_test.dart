import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

import '../../support/answer_attempt_evidence_fixture.dart';
import '../../support/dictation_session_harness.dart';

final _now = DateTime.utc(2026, 10, 30, 12);

void main() {
  late _PullFixture f;
  setUp(() async => f = await _PullFixture.open());
  tearDown(() => f.database.close());

  for (final assisted in [true, false]) {
    test(
      'v2 ${assisted ? 'assisted' : 'normal'} alias pull and replay retain exact metadata and projection floor',
      () async {
        await f.aliases();
        final context = captureCurrentActivityEvidence(
          promptMode: 'dictation',
          contentRevision: 'local-vocabulary-v1:1',
          hintLevel: assisted ? 1 : 0,
        );
        final entity = f.attempt('native-answer', context: context);
        await f.pull(entity);
        final beforeReplay = await f.effects();
        await f.pull(entity);
        expect(await f.effects(), beforeReplay);
        final answer = await f.database
            .select(f.database.answerAttempts)
            .getSingle();
        expect(answer.wordId, 'word-a');
        expect(answer.promptMode, 'dictation');
        expect(answer.evidenceClass, context.evidenceClass.name);
        expect(answer.evidenceContextJson, jsonEncode(context.toJson()));
        expect(answer.occurredAtUtcMs, _now.millisecondsSinceEpoch);
        expect(answer.responseTimeMs, 1234);
        final session = await f.database
            .select(f.database.learningSessions)
            .getSingle();
        expect(session.correctCount, 1);
        expect(session.wrongCount, 0);
        expect(session.state, 'syncedEvidence');
        expect(session.acceptedPlanJson, isNull);
        final srs = await f.rows('srs_states');
        if (assisted) {
          expect(srs, isEmpty);
        } else {
          expect(srs, hasLength(1));
          expect(srs.single['word_id'], 'word-a');
          expect(srs.single['repetitions'], 1);
          expect(
            srs.single['last_review_at_utc_ms'],
            _now.millisecondsSinceEpoch,
          );
        }
        await f.expectNoMotivation();
        final progress = await DriftProgressQueries(
          f.database,
        ).load(ownerId: 'owner-a', nowUtc: _now);
        expect(progress.sampleSize, assisted ? 0 : 1);
        expect(progress.streakDays, 0);
        expect(progress.totalXp, 0);
        final conflicts = await f.database
            .select(f.database.syncConflicts)
            .get();
        expect(conflicts, hasLength(2));
        expect(
          conflicts.every(
            (row) => row.resolutionPolicy == 'naturalKeyLocalTarget',
          ),
          isTrue,
        );
        expect(conflicts.any((row) => row.entityType == 'attempt'), isFalse);
      },
    );
  }

  for (final baselineFirst in [true, false]) {
    test(
      'genuine remote SRS baseline ${baselineFirst ? 'before' : 'after'} assisted alias evidence stays independent',
      () async {
        await f.aliases();
        final assisted = f.attempt(
          'assisted-answer',
          context: captureCurrentActivityEvidence(
            promptMode: 'dictation',
            contentRevision: 'local-vocabulary-v1:1',
            hintLevel: 1,
          ),
        );
        if (baselineFirst) {
          await f.pull(f.remoteSrs());
        } else {
          await f.pull(assisted);
          expect(await f.rows('srs_states'), isEmpty);
        }
        await f.pull(f.remoteSrs());
        final baseline = await f.rows('srs_states');
        expect(baseline, hasLength(1));
        expect(baseline.single['word_id'], 'word-a');
        expect(baseline.single['repetitions'], 7);
        expect(baseline.single['interval_days'], 14);
        expect(
          baseline.single['last_review_at_utc_ms'],
          _now.subtract(const Duration(days: 4)).millisecondsSinceEpoch,
        );
        await f.pull(assisted);
        await f.pull(assisted);
        await f.pull(f.remoteSrs());
        expect(await f.rows('srs_states'), baseline);
        expect(
          await f.database.select(f.database.answerAttempts).get(),
          hasLength(1),
        );
        await f.expectNoMotivation();
        final progress = await DriftProgressQueries(
          f.database,
        ).load(ownerId: 'owner-a', nowUtc: _now);
        expect(progress.sampleSize, 0);
        expect(progress.streakDays, 0);
        expect(progress.masteredWordCount, 1);
      },
    );
  }

  test(
    'ordinary alias evidence retains identical SRS XP coin and achievement projections after assisted pull',
    () async {
      await f.aliases();
      final ordinary = f.attempt(
        'ordinary-answer',
        version: 1,
        prompt: 'meaningChoice',
      );
      await f.pull(ordinary);
      final before = await f.effects();
      expect(before['srs_states'], hasLength(1));
      expect(before['points_ledger_entries'], hasLength(1));
      expect(before['reward_transactions'], hasLength(1));
      expect(before['achievement_unlocks'], hasLength(2));
      final assisted = f.attempt(
        'assisted-answer',
        context: captureCurrentActivityEvidence(
          promptMode: 'dictation',
          contentRevision: 'local-vocabulary-v1:1',
          hintLevel: 1,
        ),
        at: _now.add(const Duration(seconds: 1)),
      );
      await f.pull(assisted);
      await f.pull(assisted);
      await f.pull(ordinary);
      expect(await f.effects(), before);
      final attempts = await f.database.select(f.database.answerAttempts).get();
      expect(attempts, hasLength(2));
      expect(attempts.every((attempt) => attempt.wordId == 'word-a'), isTrue);
      final progress = await DriftProgressQueries(
        f.database,
      ).load(ownerId: 'owner-a', nowUtc: _now);
      expect(progress.sampleSize, 1);
      expect(progress.totalXp, 1);
      expect(progress.streakDays, 1);
      expect(
        (await DriftRewardProjectionRebuilder(
          f.database,
        ).readLedger('owner-a')).balance,
        1,
      );
    },
  );

  test(
    'actual assisted capability queues v2 metadata and SyncStore claims only its immutable attempt',
    () async {
      final h = await DictationSessionHarness.open();
      try {
        final session = await h.ready();
        final command = h.answer(session, assisted: true);
        await h.learning.commitNativeAnswer(
          session,
          command,
          stillCurrent: () => true,
        );
        final claims = await DriftSyncStore(h.database).claimPending(
          ownerId: session.ownerId,
          firebaseUid: 'synthetic-configured-uid-a',
          limit: 10,
          leaseToken: 'synthetic-dictation-lease',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: h.now,
        );
        expect(claims, hasLength(1));
        final mutation = claims.single.mutation;
        expect(mutation.collection, SyncCollection.attempts);
        expect(mutation.entityId, command.id);
        expect(mutation.payloadVersion, 2);
        expect(
          mutation.payload['evidenceClass'],
          command.evidenceContext.evidenceClass.name,
        );
        expect(
          mutation.payload['evidenceContext'],
          command.evidenceContext.toJson(),
        );
        expect(mutation.payload['wordId'], session.word.id);
        expect(
          mutation.payload['occurredAtUtcMs'],
          command.occurredAtUtc.millisecondsSinceEpoch,
        );
        expect(await h.database.select(h.database.srsStates).get(), isEmpty);
        expect(
          await h.database.select(h.database.rewardTransactions).get(),
          isEmpty,
        );
        expect((await h.storage.researchCounts()).values, everyElement(0));
      } finally {
        await h.close();
      }
    },
  );

  test(
    'ordinary SyncStore still rejects Assessment declarations atomically',
    () async {
      await f.aliases();
      final before = await f.effects();
      final assessment = EvidenceContext.forNewEvidence(
        evidenceClass: EvidenceClass.assessment,
        skillId: 'word-meaning',
        hintLevel: 0,
        contentRevision: 'synthetic-assessment-content-v1',
        rolloutMode: EvidencePolicyRolloutMode.enforced,
        protocolId: 'synthetic-protocol',
        protocolVersion: '1',
        experimentId: 'synthetic-experiment',
        experimentVersion: 1,
        assignmentId: 'synthetic-assignment',
        cohort: 'synthetic-standard',
        researchConsentVersion: 4,
        instrumentId: 'synthetic-instrument',
        instrumentVersion: '1',
        formId: 'synthetic-form',
        formVersion: '1',
        assessmentItemId: 'synthetic-item',
        assessmentResponseCode: 'correct',
        scoringRuleVersion: 'synthetic-scoring-v1',
      );
      await expectLater(
        f.pull(f.attempt('assessment-answer', context: assessment)),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      expect(await f.effects(), before);
      expect(await f.rows('answer_attempts'), isEmpty);
      expect(await f.rows('learning_sessions'), isEmpty);
      expect(await f.rows('assessment_runs'), isEmpty);
    },
  );
}

final class _PullFixture {
  _PullFixture(this.database);
  final AppDatabase database;

  static Future<_PullFixture> open() async {
    final f = _PullFixture(AppDatabase(NativeDatabase.memory()));
    await seedAnswerEvidenceOwners(f.database);
    return f;
  }

  SyncEntity entity(
    SyncCollection collection,
    String id,
    Map<String, Object?> payload, {
    int version = 1,
  }) => SyncEntity(
    collection: collection,
    entityId: id,
    revision: 1,
    isDeleted: false,
    payloadVersion: version,
    clientUpdatedAtUtc: _now,
    serverUpdatedAtUtc: _now.add(const Duration(seconds: 1)),
    payload: payload,
  );

  Future<void> pull(SyncEntity entity) =>
      DriftSyncStore(database).applyPullPage(
        ownerId: 'owner-a',
        collection: entity.collection,
        page: PullPage(
          changes: [entity],
          hasMore: false,
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
            documentId: entity.entityId,
          ),
        ),
      );

  Future<void> aliases() async {
    await pull(
      entity(SyncCollection.categories, 'remote-category', {
        'name': 'a',
        'normalizedName': 'a',
      }),
    );
    await pull(
      entity(SyncCollection.words, 'remote-word', {
        'categoryId': 'remote-category',
        'spelling': 'word a',
        'meaning': 'meaning a',
        'partOfSpeech': 'noun',
      }),
    );
  }

  SyncEntity attempt(
    String id, {
    EvidenceContext? context,
    int version = 2,
    String prompt = 'dictation',
    DateTime? at,
  }) => entity(SyncCollection.attempts, id, {
    ...answerPayload(evidence: context),
    'sessionId': 'session-$id',
    'wordId': 'remote-word',
    'promptMode': prompt,
    'responseTimeMs': 1234,
    'occurredAtUtcMs': (at ?? _now).millisecondsSinceEpoch,
  }, version: version);

  SyncEntity remoteSrs() => entity(SyncCollection.srsStates, 'remote-word', {
    'wordId': 'remote-word',
    'stability': 9.5,
    'difficulty': 4.0,
    'intervalDays': 14,
    'repetitions': 7,
    'lapses': 2,
    'lastReviewAtUtcMs': _now
        .subtract(const Duration(days: 4))
        .millisecondsSinceEpoch,
    'dueAtUtcMs': _now.add(const Duration(days: 3)).millisecondsSinceEpoch,
    'algorithmVersion': 1,
  });

  Future<List<Map<String, Object?>>> rows(String table) async => [
    for (final row
        in await database.customSelect('SELECT * FROM $table ORDER BY 1').get())
      row.data,
  ];

  Future<Map<String, List<Map<String, Object?>>>> effects() async => {
    for (final table in const [
      'srs_states',
      'points_ledger_entries',
      'achievement_unlocks',
      'reward_transactions',
      'owned_reward_items',
      'equipped_reward_items',
      'outbox_operations',
      'events_v2',
      'assessment_runs',
    ])
      table: await rows(table),
  };

  Future<void> expectNoMotivation() async {
    for (final table in const [
      'points_ledger_entries',
      'achievement_unlocks',
      'reward_transactions',
      'owned_reward_items',
      'equipped_reward_items',
      'outbox_operations',
      'events_v2',
      'assessment_runs',
    ]) {
      expect(await rows(table), isEmpty, reason: table);
    }
    expect(
      (await DriftRewardProjectionRebuilder(
        database,
      ).readLedger('owner-a')).balance,
      0,
    );
  }
}
