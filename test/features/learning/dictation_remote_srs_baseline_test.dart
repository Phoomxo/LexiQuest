import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

import '../../support/dictation_session_harness.dart';

void main() {
  late DictationSessionHarness h;
  late String wordId;
  setUp(() async {
    h = await DictationSessionHarness.open();
    final word = (await h.repository.listQuizWords(
      ownerId: configuredOwnerId,
      limit: 1,
    )).single;
    wordId = word.id;
    final originalAt = h.now.subtract(const Duration(days: 5));
    await h.repository.startSession(
      LearningSessionDraft(
        id: 'synthetic-old-ordinary-session',
        ownerId: configuredOwnerId,
        activityType: 'quiz',
        startedAtUtc: originalAt,
        appVersion: 'synthetic',
        buildId: 'ordinary-baseline',
      ),
    );
    await h.repository.recordAnswer(
      RecordAnswerCommand(
        id: 'synthetic-old-ordinary-answer',
        ownerId: configuredOwnerId,
        sessionId: 'synthetic-old-ordinary-session',
        wordId: wordId,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 100,
        attemptNumber: 1,
        occurredAtUtc: originalAt,
      ),
    );
  });
  tearDown(() => h.close());

  Future<List<Map<String, Object?>>> srsRows() async => [
    for (final row
        in await h.database
            .customSelect(
              'SELECT * FROM srs_states WHERE owner_id = ? AND word_id = ? ORDER BY id',
              variables: [Variable(configuredOwnerId), Variable(wordId)],
            )
            .get())
      row.data,
  ];

  Future<Map<String, List<Map<String, Object?>>>> motivationRows() async => {
    for (final table in const [
      'points_ledger_entries',
      'reward_transactions',
      'achievement_unlocks',
    ])
      table: [
        for (final row
            in await h.database
                .customSelect('SELECT * FROM $table ORDER BY id')
                .get())
          row.data,
      ],
  };

  Future<void> pull(SyncEntity entity) =>
      DriftSyncStore(h.database).applyPullPage(
        ownerId: configuredOwnerId,
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

  Future<void> applyNewerRemoteBaseline() async {
    final old = (await srsRows()).single;
    expect(old['repetitions'], 1);
    expect(
      old['last_review_at_utc_ms'],
      h.now.subtract(const Duration(days: 5)).millisecondsSinceEpoch,
    );
    await pull(
      SyncEntity(
        collection: SyncCollection.srsStates,
        entityId: wordId,
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: h.now,
        serverUpdatedAtUtc: h.now,
        payload: {
          'wordId': wordId,
          'stability': 12.5,
          'difficulty': 4.5,
          'intervalDays': 14,
          'repetitions': 8,
          'lapses': 2,
          'lastReviewAtUtcMs': h.now
              .subtract(const Duration(days: 1))
              .millisecondsSinceEpoch,
          'dueAtUtcMs': h.now
              .add(const Duration(days: 13))
              .millisecondsSinceEpoch,
          'algorithmVersion': 1,
        },
      ),
    );
    final current = (await srsRows()).single;
    expect(current['repetitions'], 8);
    expect(current['interval_days'], 14);
    expect(
      current['last_review_at_utc_ms'],
      h.now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
    );
  }

  SyncEntity pulledAnswer(String id, {bool legacy = false}) {
    final context = captureCurrentActivityEvidence(
      promptMode: 'dictation',
      contentRevision: 'local-vocabulary-v1:1',
      hintLevel: 1,
    );
    return SyncEntity(
      collection: SyncCollection.attempts,
      entityId: id,
      revision: 1,
      isDeleted: false,
      payloadVersion: legacy ? 1 : 2,
      clientUpdatedAtUtc: h.now,
      serverUpdatedAtUtc: h.now,
      payload: {
        'sessionId': 'session-$id',
        'wordId': wordId,
        'promptMode': legacy ? 'meaningChoice' : 'dictation',
        'isCorrect': true,
        'responseTimeMs': 100,
        'attemptNumber': 1,
        'occurredAtUtcMs': h.now.millisecondsSinceEpoch,
        'providerProvenance': null,
        if (!legacy) ...{
          'evidenceClass': context.evidenceClass.name,
          'evidenceContext': context.toJson(),
        },
      },
    );
  }

  test(
    'generic ineligible new answer and exact replay preserve baseline while conflicting evidence still rejects',
    () async {
      await applyNewerRemoteBaseline();
      final baseline = await srsRows();
      final motivation = await motivationRows();
      final context = captureCurrentActivityEvidence(
        promptMode: 'dictation',
        contentRevision: 'local-vocabulary-v1:1',
        hintLevel: 1,
      );
      await h.repository.startSession(
        LearningSessionDraft(
          id: 'synthetic-pre-prefix-assisted-session',
          ownerId: configuredOwnerId,
          activityType: 'dictation',
          startedAtUtc: h.now,
          appVersion: 'synthetic',
          buildId: 'generic-assisted-control',
        ),
      );
      final command = RecordAnswerCommand(
        id: 'synthetic-pre-prefix-assisted-answer',
        ownerId: configuredOwnerId,
        sessionId: 'synthetic-pre-prefix-assisted-session',
        wordId: wordId,
        promptMode: 'dictation',
        isCorrect: true,
        responseTimeMs: 100,
        attemptNumber: 1,
        occurredAtUtc: h.now,
        evidenceContext: context,
      );
      final inserted = await h.repository.recordAnswer(command);
      expect(inserted.inserted, isTrue);
      expect(inserted.srs!.repetitions, 8);
      expect(await srsRows(), baseline);
      final replay = await h.repository.recordAnswer(command);
      expect(replay.inserted, isFalse);
      expect(replay.srs!.repetitions, 8);
      expect(await srsRows(), baseline);
      await expectLater(
        h.repository.recordAnswer(
          RecordAnswerCommand(
            id: command.id,
            ownerId: command.ownerId,
            sessionId: command.sessionId,
            wordId: command.wordId,
            promptMode: command.promptMode,
            isCorrect: false,
            responseTimeMs: command.responseTimeMs,
            attemptNumber: command.attemptNumber,
            occurredAtUtc: command.occurredAtUtc,
            evidenceContext: context,
          ),
        ),
        throwsStateError,
      );
      expect(await srsRows(), baseline);
      expect(await motivationRows(), motivation);
      expect(
        await h.database.select(h.database.answerAttempts).get(),
        hasLength(2),
      );
    },
  );

  test(
    'conflicting eligible sync replay keeps retained assisted metadata and quarantine without rewinding baseline',
    () async {
      await applyNewerRemoteBaseline();
      final baseline = await srsRows();
      final motivation = await motivationRows();
      const id = 'synthetic-conflicting-assisted-answer';
      final assisted = pulledAnswer(id);
      await pull(assisted);
      expect(await srsRows(), baseline);
      await pull(pulledAnswer(id, legacy: true));
      expect(await srsRows(), baseline);
      expect(await motivationRows(), motivation);
      final rows = await h.database.select(h.database.answerAttempts).get();
      final retained = rows.singleWhere((row) => row.id == id);
      expect(retained.promptMode, 'dictation');
      expect(
        jsonDecode(retained.evidenceContextJson),
        assisted.payload['evidenceContext'],
      );
      final conflict = await h.database
          .select(h.database.syncConflicts)
          .getSingle();
      expect(conflict.entityId, id);
      expect(conflict.entityType, 'attempt');
      expect(conflict.outcome, 'quarantined');
      expect(rows, hasLength(2));
    },
  );

  test(
    'eligible native answer still rebuilds canonical old and new evidence',
    () async {
      await applyNewerRemoteBaseline();
      final baseline = await srsRows();
      final session = await h.ready();
      final command = h.answer(session);
      final result = await h.learning.commitDictationAnswer(
        session,
        command,
        stillCurrent: () => true,
      );
      expect(result.inserted, isTrue);
      expect(result.srs!.repetitions, 2);
      expect(result.srs!.lastReviewAtUtc, h.now);
      expect(await srsRows(), isNot(baseline));
      final actual = (await srsRows()).single;
      expect(actual['repetitions'], 2);
      expect(actual['last_review_at_utc_ms'], h.now.millisecondsSinceEpoch);
    },
  );

  test(
    'legacy v1 eligible pull and replay still rebuild canonical ordinary evidence',
    () async {
      await applyNewerRemoteBaseline();
      final ordinary = pulledAnswer(
        'synthetic-new-legacy-answer',
        legacy: true,
      );
      await pull(ordinary);
      final actual = await srsRows();
      expect(actual.single['repetitions'], 2);
      expect(
        actual.single['last_review_at_utc_ms'],
        h.now.millisecondsSinceEpoch,
      );
      await pull(ordinary);
      expect(await srsRows(), actual);
      expect(
        await h.database.select(h.database.pointsLedgerEntries).get(),
        hasLength(2),
      );
      expect(
        await h.database.select(h.database.rewardTransactions).get(),
        hasLength(2),
      );
    },
  );

  test(
    'assisted native save cannot rewind newer remote SRS over old eligible ordinary facts',
    () async {
      await applyNewerRemoteBaseline();
      final baseline = await srsRows();
      final motivation = await motivationRows();
      final session = await h.ready();
      expect(session.word.id, wordId);
      expect(await srsRows(), baseline);
      final assisted = h.answer(session, assisted: true);
      final result = await h.learning.commitDictationAnswer(
        session,
        assisted,
        stillCurrent: () => true,
      );
      expect(result.inserted, isTrue);
      expect(
        await srsRows(),
        baseline,
        reason:
            'an ineligible fact must not rebuild older eligible facts over an independent newer baseline',
      );
      await h.learning.commitDictationAnswer(
        session,
        assisted,
        stillCurrent: () => true,
      );
      expect(await srsRows(), baseline);
      expect(await motivationRows(), motivation);
      expect(
        await h.database.select(h.database.answerAttempts).get(),
        hasLength(2),
      );
    },
  );

  test(
    'assisted SyncStore pull cannot rewind newer remote SRS over old eligible ordinary facts',
    () async {
      await applyNewerRemoteBaseline();
      final baseline = await srsRows();
      final motivation = await motivationRows();
      final context = captureCurrentActivityEvidence(
        promptMode: 'dictation',
        contentRevision: 'local-vocabulary-v1:1',
        hintLevel: 1,
      );
      final assisted = SyncEntity(
        collection: SyncCollection.attempts,
        entityId: 'synthetic-remote-assisted-answer',
        revision: 1,
        isDeleted: false,
        payloadVersion: 2,
        clientUpdatedAtUtc: h.now,
        serverUpdatedAtUtc: h.now,
        payload: {
          'sessionId': 'session:dictation-v1:synthetic-remote-assisted',
          'wordId': wordId,
          'promptMode': 'dictation',
          'isCorrect': true,
          'responseTimeMs': 1234,
          'attemptNumber': 1,
          'occurredAtUtcMs': h.now.millisecondsSinceEpoch,
          'providerProvenance': null,
          'evidenceClass': context.evidenceClass.name,
          'evidenceContext': context.toJson(),
        },
      );
      await pull(assisted);
      expect(
        await srsRows(),
        baseline,
        reason:
            'SyncStore must retain the genuine remote baseline when only ineligible evidence arrives',
      );
      await pull(assisted);
      expect(await srsRows(), baseline);
      expect(await motivationRows(), motivation);
      expect(
        await h.database.select(h.database.answerAttempts).get(),
        hasLength(2),
      );
    },
  );
}
