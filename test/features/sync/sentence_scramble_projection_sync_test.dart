import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

import '../../support/answer_attempt_evidence_fixture.dart';

final _now = DateTime.utc(2026, 10, 30, 12);

final _contentRevision =
    'sentence-scramble-v1:${sha256.convert(utf8.encode('synthetic-frozen-sentence-and-bank'))}';

final _provenance =
    'sentence-scramble-model-v1:${sha256.convert(utf8.encode('synthetic-sentence-provider-v1'))}';

EvidenceContext _scramble() => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.recreational,
  skillId: 'sentence-scramble',
  hintLevel: 0,
  contentRevision: _contentRevision,
  rolloutMode: EvidencePolicyRolloutMode.legacy,
);

void main() {
  late _PullFixture f;
  setUp(() async => f = await _PullFixture.open());
  tearDown(() => f.database.close());

  test(
    'actual v2 Sentence Scramble alias pull and replay preserve only session outcome',
    () async {
      await f.aliases();
      final context = _scramble();
      final entity = f.attempt('scramble-answer', context: context);
      expect(entity.payload.keys.toSet(), {
        'sessionId',
        'wordId',
        'promptMode',
        'isCorrect',
        'responseTimeMs',
        'attemptNumber',
        'occurredAtUtcMs',
        'providerProvenance',
        'evidenceClass',
        'evidenceContext',
      });
      expect(entity.payload['providerProvenance'], _provenance);
      await f.pull(entity);
      final beforeReplay = await f.effects();
      await f.pull(entity);
      expect(await f.effects(), beforeReplay);
      final answer = await f.database
          .select(f.database.answerAttempts)
          .getSingle();
      expect(answer.wordId, 'word-a');
      expect(answer.ownerId, 'owner-a');
      expect(answer.promptMode, 'sentenceScramble');
      expect(answer.evidenceClass, 'recreational');
      expect(answer.evidenceContextJson, jsonEncode(context.toJson()));
      expect(answer.providerProvenance, _provenance);
      expect(answer.responseTimeMs, 1234);
      expect(answer.occurredAtUtcMs, _now.millisecondsSinceEpoch);
      final session = await f.database
          .select(f.database.learningSessions)
          .getSingle();
      expect(session.id, 'session:sentence-scramble-v1:scramble-answer');
      expect(session.correctCount, 1);
      expect(session.wrongCount, 0);
      expect(session.state, 'syncedEvidence');
      expect(session.acceptedPlanJson, isNull);
      expect(await f.rows('srs_states'), isEmpty);
      await f.expectNoMotivation();
      final progress = await DriftProgressQueries(
        f.database,
      ).load(ownerId: 'owner-a', nowUtc: _now);
      expect(progress.sampleSize, 0);
      expect(progress.totalXp, 0);
      expect(progress.streakDays, 0);
      final conflicts = await f.database.select(f.database.syncConflicts).get();
      expect(conflicts, hasLength(2));
      expect(
        conflicts.every(
          (row) => row.resolutionPolicy == 'naturalKeyLocalTarget',
        ),
        isTrue,
      );
      expect(conflicts.any((row) => row.entityType == 'attempt'), isFalse);
      final other = await DriftProgressQueries(
        f.database,
      ).load(ownerId: 'owner-b', nowUtc: _now);
      expect(other.sampleSize, 0);
      expect(other.totalXp, 0);
    },
  );

  for (final baselineFirst in [true, false]) {
    test(
      'genuine remote SRS ${baselineFirst ? 'before' : 'after'} recreational alias evidence stays byte-identical',
      () async {
        await f.aliases();
        final game = f.attempt('scramble-answer', context: _scramble());
        if (baselineFirst) {
          await f.pull(f.remoteSrs());
        } else {
          await f.pull(game);
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
        await f.pull(game);
        await f.pull(game);
        await f.pull(f.remoteSrs());
        expect(await f.rows('srs_states'), baseline);
        expect(await f.rows('answer_attempts'), hasLength(1));
        await f.expectNoMotivation();
        final progress = await DriftProgressQueries(
          f.database,
        ).load(ownerId: 'owner-a', nowUtc: _now);
        expect(progress.sampleSize, 0);
        expect(progress.totalXp, 0);
        expect(progress.streakDays, 0);
        expect(progress.masteredWordCount, 1);
      },
    );
  }

  test(
    'ordinary alias effects remain identical after a recreational pull and replay',
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
      final game = f.attempt(
        'scramble-answer',
        context: _scramble(),
        at: _now.add(const Duration(seconds: 1)),
      );
      await f.pull(game);
      await f.pull(game);
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
    'old inferred Sentence Scramble alias evidence keeps ordinary compatibility',
    () async {
      await f.aliases();
      final old = f.attempt('old-scramble-answer', version: 1);
      await f.pull(old);
      final before = await f.effects();
      expect(before['srs_states'], hasLength(1));
      expect(before['points_ledger_entries'], hasLength(1));
      expect(before['reward_transactions'], hasLength(1));
      expect(before['achievement_unlocks'], hasLength(2));
      await f.pull(old);
      expect(await f.effects(), before);
      final progress = await DriftProgressQueries(
        f.database,
      ).load(ownerId: 'owner-a', nowUtc: _now);
      expect(progress.sampleSize, 1);
      expect(progress.totalXp, 1);
      expect(progress.streakDays, 1);
    },
  );

  test(
    'mismatched recreational sync metadata is rejected atomically',
    () async {
      await f.aliases();
      final before = await f.effects();
      final original = f.attempt(
        'invalid-scramble-answer',
        context: _scramble(),
      );
      final invalid = f.entity(SyncCollection.attempts, original.entityId, {
        ...original.payload,
        'evidenceClass': 'independentRecall',
      }, version: 2);
      await expectLater(
        f.pull(invalid),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      expect(await f.effects(), before);
      expect(await f.rows('answer_attempts'), isEmpty);
      expect(await f.rows('learning_sessions'), isEmpty);
    },
  );
  for (final rawSentenceKey in [
    'targetSentence',
    'tokenOrder',
    'translation',
  ]) {
    test(
      'v2 rejects extra raw sentence field $rawSentenceKey atomically',
      () async {
        await f.aliases();
        final before = await f.effects();
        final original = f.attempt('extra-raw-sentence', context: _scramble());
        final invalid = f.entity(SyncCollection.attempts, original.entityId, {
          ...original.payload,
          rawSentenceKey:
              'synthetic full generated sentence is not a wire field',
        }, version: 2);
        await expectLater(
          f.pull(invalid),
          throwsA(isA<InvalidSyncPayloadFailure>()),
        );
        expect(await f.effects(), before);
        expect(await f.rows('answer_attempts'), isEmpty);
        expect(await f.rows('learning_sessions'), isEmpty);
      },
    );
  }
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
    String prompt = 'sentenceScramble',
    DateTime? at,
  }) => entity(SyncCollection.attempts, id, {
    ...answerPayload(evidence: context),
    'sessionId': 'session:sentence-scramble-v1:$id',
    'wordId': 'remote-word',
    'promptMode': prompt,
    'responseTimeMs': 1234,
    'providerProvenance': version == 2 ? _provenance : null,
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
      'quest_instances',
      'quest_objective_progress',
      'streak_states',
      'research_consents',
      'experiment_assignments',
      'research_participation_permits',
      'motivation_measurement_runs',
      'motivation_responses',
      'measurement_opportunities',
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
      'quest_instances',
      'quest_objective_progress',
      'streak_states',
      'research_consents',
      'experiment_assignments',
      'research_participation_permits',
      'motivation_measurement_runs',
      'motivation_responses',
      'measurement_opportunities',
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
