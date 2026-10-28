import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  late ConfiguredQuizHarness h;
  late DriftLearningRepository repository;

  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    repository = _repository(h);
  });
  tearDown(() => h.close());

  test('rejects a coordinator from another database before writing', () async {
    final other = await ConfiguredQuizHarness.open();
    addTearDown(other.close);
    expect(
      () => DriftLearningRepository(h.database, ownerWrites: other.ownerWrites),
      throwsArgumentError,
    );
    expect(await h.count('learning_sessions'), 0);
  });

  test('acceptance observes the complete plan and first checkpoint', () async {
    final observer = ConfiguredQuizObserver(h.database);
    repository = _repository(h, observer: observer);
    final plan = await _plan(h);

    final state = await repository.startConfiguredQuiz(
      session: _session(),
      plan: plan,
    );

    final row = observer.acceptedRows.single;
    expect(row['accepted_plan_id'], plan.id);
    expect(row['accepted_plan_json'], plan.stableSerialization);
    expect(row['checkpoint_revision'], 1);
    expect(
      QuizCheckpoint.parse(row['checkpoint_json']! as String, plan: plan),
      isA<AwaitingQuizAnswer>(),
    );
    expect(state.sessionId, 'synthetic-configured-session');
    expect(state.ownerId, configuredOwnerId);
    expect(state.activityType, 'quiz');
    expect(state.checkpointRevision, 1);
    expect(await h.count('answer_attempts'), 0);
    expect(await h.count('outbox_operations'), 0);
    expect((await h.researchCounts()).values, everyElement(0));
  });

  test(
    'same launch returns the first accepted plan without resetting state',
    () async {
      final observer = ConfiguredQuizObserver(h.database);
      repository = _repository(h, observer: observer);
      final first = await repository.startConfiguredQuiz(
        session: _session(),
        plan: await _plan(h),
      );
      final hinted = await repository.saveQuizCheckpoint(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: first.checkpointRevision,
        checkpoint: AwaitingQuizAnswer(
          planId: first.plan.id,
          questionOrdinal: 0,
          assistance: QuizAssistance().showHint(
            configuredStart.millisecondsSinceEpoch,
          ),
        ),
      );
      final before = await h.snapshot();
      final candidate = await _plan(
        h,
        distractor: 'a different accepted candidate',
      );

      final replay = await repository.startConfiguredQuiz(
        session: _session(),
        plan: candidate,
      );

      expect(replay.plan.stableSerialization, first.plan.stableSerialization);
      expect(replay.checkpointRevision, hinted.checkpointRevision);
      expect(await h.snapshot(), before);
      expect(observer.acceptedFacts, hasLength(1));
    },
  );

  test(
    'concurrent identical launch identities return one first persisted plan',
    () async {
      final observer = ConfiguredQuizObserver(h.database);
      repository = _repository(h, observer: observer);
      final otherInstance = _repository(h, observer: observer);
      final firstPlan = await _plan(h, distractor: 'first candidate');
      final secondPlan = await _plan(h, distractor: 'second candidate');

      final results = await Future.wait([
        repository.startConfiguredQuiz(session: _session(), plan: firstPlan),
        otherInstance.startConfiguredQuiz(
          session: _session(),
          plan: secondPlan,
        ),
      ]);

      final stored = await h.session(results.first.sessionId);
      expect(results.map((state) => state.plan.id).toSet(), {
        stored['accepted_plan_id'],
      });
      expect(results.map((state) => state.plan.stableSerialization).toSet(), {
        stored['accepted_plan_json'],
      });
      expect(results.where((state) => !state.restored), hasLength(1));
      expect(results.where((state) => state.restored), hasLength(1));
      expect(await h.count('learning_sessions'), 1);
      expect(observer.acceptedFacts, hasLength(1));
    },
  );

  for (final conflict in ['owner', 'start', 'app', 'build', 'configuration']) {
    test(
      'a changed $conflict cannot reuse an accepted launch identity',
      () async {
        final plan = await _plan(h);
        await repository.startConfiguredQuiz(session: _session(), plan: plan);
        if (conflict == 'owner') await h.switchOwner(configuredOtherOwnerId);
        final before = await h.snapshot();
        final changed = _session(
          ownerId: conflict == 'owner'
              ? configuredOtherOwnerId
              : configuredOwnerId,
          startedAtUtc: conflict == 'start'
              ? configuredStart.add(const Duration(milliseconds: 1))
              : configuredStart,
          appVersion: conflict == 'app' ? 'synthetic-v2' : 'synthetic-v1',
          buildId: conflict == 'build'
              ? 'synthetic-build-2'
              : 'synthetic-build-1',
        );
        final conflictingPlan = conflict == 'configuration'
            ? await _plan(h, limit: 1)
            : plan;

        await expectLater(
          repository.startConfiguredQuiz(
            session: changed,
            plan: conflictingPlan,
          ),
          throwsA(anything),
        );

        expect(await h.snapshot(), before);
      },
    );
  }

  test(
    'changed live word pins reject acceptance without any learning writes',
    () async {
      final observer = ConfiguredQuizObserver(h.database);
      repository = _repository(h, observer: observer);
      final plan = await _plan(h);
      await h.database.customStatement(
        'UPDATE vocabulary_words SET meaning = ?, local_revision = local_revision + 1 WHERE id = ?',
        ['คำใหม่', configuredWordIds.first],
      );
      final before = await h.snapshot();

      await expectLater(
        repository.startConfiguredQuiz(session: _session(), plan: plan),
        _unavailable('contentChanged'),
      );

      expect(await h.snapshot(), before);
      expect(observer.acceptedFacts, isEmpty);
    },
  );

  test(
    'research rejection preserves ordinary acceptance and cannot backfill on replay',
    () async {
      final observer = ConfiguredQuizObserver(h.database)..denyAccepted = true;
      repository = _repository(h, observer: observer);
      final plan = await _plan(h);

      await repository.startConfiguredQuiz(session: _session(), plan: plan);
      observer.denyAccepted = false;
      await repository.startConfiguredQuiz(session: _session(), plan: plan);

      expect(await h.count('learning_sessions'), 1);
      expect((await h.session(_session().id))['checkpoint_revision'], 1);
      expect(await h.count('runtime_flags'), 0);
      expect(observer.acceptedFacts, hasLength(1));
      expect((await h.researchCounts()).values, everyElement(0));
    },
  );

  test(
    'outer canonical rollback removes the accepted plan and sidecar together',
    () async {
      final observer = ConfiguredQuizObserver(h.database);
      repository = _repository(h, observer: observer);
      final plan = await _plan(h);
      final before = await h.snapshot();

      await expectLater(
        h.database.transaction(() async {
          await repository.startConfiguredQuiz(session: _session(), plan: plan);
          throw StateError('synthetic canonical failure after acceptance');
        }),
        throwsStateError,
      );

      expect(await h.snapshot(), before);
      expect(observer.acceptedFacts, hasLength(1));
    },
  );

  test(
    'reopened database restores the same deck instead of the new live pool',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-configured-quiz-',
      );
      addTearDown(() async {
        await h.close();
        await directory.delete(recursive: true);
      });
      await h.close();
      h = await ConfiguredQuizHarness.open(
        file: File('${directory.path}/quiz.sqlite'),
      );
      repository = _repository(h);
      final first = await repository.startConfiguredQuiz(
        session: _session(),
        plan: await _plan(h),
      );
      await h.addWord(
        id: 'synthetic-configured-new-distractor',
        spelling: 'added',
        meaning: 'a new live option',
      );
      h = await h.reopen();
      repository = _repository(h);

      final restored = await repository.resumeQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
      );

      expect(restored.sessionId, first.sessionId);
      expect(restored.plan.stableSerialization, first.plan.stableSerialization);
      expect(
        restored.plan.questions.map((question) => question.word.id),
        configuredWordIds.take(2),
      );
      expect(restored.plan.questions.first.options, [
        'สถานี',
        'synthetic distractor',
      ]);
      expect(await h.count('learning_sessions'), 1);
      expect(await h.count('outbox_operations'), 0);
    },
  );

  for (final legacyState in ['active', 'syncedEvidence']) {
    test('a $legacyState row cannot fabricate an accepted plan', () async {
      await h.database.customStatement(
        'INSERT INTO learning_sessions '
        '(id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'synthetic-legacy-session',
          configuredOwnerId,
          legacyState == 'syncedEvidence' ? 'syncedEvidence' : 'quiz',
          legacyState,
          configuredStart.millisecondsSinceEpoch,
          'unknown',
          'synced',
        ],
      );
      final before = await h.snapshot();

      await expectLater(
        repository.resumeQuiz(
          sessionId: 'synthetic-legacy-session',
          expectedOwnerId: configuredOwnerId,
        ),
        _unavailable(
          legacyState == 'syncedEvidence' ? 'syncedEvidence' : 'legacy',
        ),
      );

      expect(await h.snapshot(), before);
    });
  }

  test(
    'corrupt checkpoint remains unavailable without overwriting its plan',
    () async {
      final state = await repository.startConfiguredQuiz(
        session: _session(),
        plan: await _plan(h),
      );
      await h.database.customStatement(
        'UPDATE learning_sessions SET checkpoint_json = ? WHERE id = ?',
        ['{"schemaVersion":999}', state.sessionId],
      );
      final before = await h.snapshot();

      await expectLater(
        repository.resumeQuiz(
          sessionId: state.sessionId,
          expectedOwnerId: configuredOwnerId,
        ),
        _unavailable('corrupt'),
      );

      expect(await h.snapshot(), before);
    },
  );

  for (final activeCount in [0, 2]) {
    test(
      '$activeCount active owners cannot accept a configured session',
      () async {
        final plan = await _plan(h);
        await h.database.customStatement(
          'UPDATE local_owners SET is_active = ?',
          [activeCount == 0 ? 0 : 1],
        );
        final before = await h.snapshot();

        await expectLater(
          repository.startConfiguredQuiz(session: _session(), plan: plan),
          throwsA(anything),
        );

        expect(await h.snapshot(), before);
      },
    );
  }

  test(
    'persistent deletion intent rejects the configured write before mutation',
    () async {
      final plan = await _plan(h);
      await h.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'delete:00000000-0000-4000-8000-000000000041',
      );
      final before = await h.snapshot();

      await expectLater(
        repository.startConfiguredQuiz(session: _session(), plan: plan),
        throwsA(anything),
      );

      expect(await h.snapshot(), before);
    },
  );

  test(
    'checkpoint CAS allows exact ACK replay and rejects a stale different state',
    () async {
      final first = await repository.startConfiguredQuiz(
        session: _session(),
        plan: await _plan(h),
      );
      final hinted = AwaitingQuizAnswer(
        planId: first.plan.id,
        questionOrdinal: 0,
        assistance: QuizAssistance().showHint(
          configuredStart.millisecondsSinceEpoch,
        ),
      );
      final saved = await repository.saveQuizCheckpoint(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: 1,
        checkpoint: hinted,
      );
      final replay = await repository.saveQuizCheckpoint(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: 1,
        checkpoint: hinted,
      );
      final before = await h.snapshot();

      await expectLater(
        _repository(h).saveQuizCheckpoint(
          sessionId: first.sessionId,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: 1,
          checkpoint: QuizCheckpoint.initial(first.plan),
        ),
        throwsA(anything),
      );

      expect(saved.checkpointRevision, 2);
      expect(replay.checkpointRevision, 2);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'answer and checkpoint ACK commit once through the canonical authorities',
    () async {
      final pending = await _pending(h, repository);
      final first = await repository.commitQuizAnswer(
        sessionId: pending.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: pending.checkpointRevision,
      );
      final afterFirst = await h.snapshot();

      final replay = await repository.commitQuizAnswer(
        sessionId: pending.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: pending.checkpointRevision,
      );

      expect(first.record.inserted, isTrue);
      expect(replay.record.inserted, isFalse);
      expect(first.state.checkpoint, isA<AnsweredQuizQuestion>());
      expect(await h.snapshot(), afterFirst);
      expect(await h.count('answer_attempts'), 1);
      expect(await h.count('srs_states'), 1);
      expect(await h.count('points_ledger_entries'), 1);
      final outbox = await h.database.select(h.database.outboxOperations).get();
      expect(outbox.where((row) => row.entityType == 'attempt'), hasLength(1));
      expect(outbox.where((row) => row.entityType == 'srsState'), hasLength(1));
      expect((await h.researchCounts()).values, everyElement(0));
    },
  );

  test(
    'failed checkpoint ACK rolls back answer SRS rewards and outbox together',
    () async {
      final pending = await _pending(h, repository);
      final before = await h.snapshot();
      await h.database.customStatement(
        'CREATE TEMP TRIGGER synthetic_configured_ack_failure '
        'BEFORE UPDATE OF checkpoint_json ON learning_sessions '
        "BEGIN SELECT RAISE(ABORT, 'synthetic checkpoint ACK failure'); END",
      );

      await expectLater(
        repository.commitQuizAnswer(
          sessionId: pending.sessionId,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: pending.checkpointRevision,
        ),
        throwsA(anything),
      );

      expect(await h.snapshot(), before);
      await h.database.customStatement(
        'DROP TRIGGER synthetic_configured_ack_failure',
      );
      final committed = await repository.commitQuizAnswer(
        sessionId: pending.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: pending.checkpointRevision,
      );
      expect(committed.record.inserted, isTrue);
      expect(await h.count('answer_attempts'), 1);
    },
  );

  test(
    'a deletion fence raised after preparation prevents the answer commit',
    () async {
      final pending = await _pending(h, repository);
      await h.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'delete:00000000-0000-4000-8000-000000000043',
      );
      final before = await h.snapshot();
      await expectLater(
        repository.commitQuizAnswer(
          sessionId: pending.sessionId,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: pending.checkpointRevision,
        ),
        throwsA(anything),
      );
      expect(await h.snapshot(), before);
      expect(await h.count('answer_attempts'), 0);
    },
  );

  test(
    'a changed pending word cannot produce new evidence from the old plan',
    () async {
      final pending = await _pending(h, repository);
      await h.database.customStatement(
        'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
        [configuredWordIds.first],
      );
      final before = await h.snapshot();
      await expectLater(
        repository.commitQuizAnswer(
          sessionId: pending.sessionId,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: pending.checkpointRevision,
        ),
        _unavailable('contentChanged'),
      );
      expect(await h.snapshot(), before);
      expect(await h.count('answer_attempts'), 0);
    },
  );

  test('legacy public writers cannot bypass a configured checkpoint', () async {
    final first = await repository.startConfiguredQuiz(
      session: _session(),
      plan: await _plan(h),
    );
    final receipt = _answer(first);
    final before = await h.snapshot();

    await expectLater(
      repository.recordAnswer(receipt.toCommand(sessionId: first.sessionId)),
      throwsStateError,
    );
    await expectLater(
      repository.finishSession(
        ownerId: configuredOwnerId,
        sessionId: first.sessionId,
        endedAtUtc: configuredStart.add(const Duration(minutes: 2)),
      ),
      throwsStateError,
    );

    expect(await h.snapshot(), before);
  });

  test(
    'ordinary exact-ID rehome preserves immutable plan and can resume',
    () async {
      final first = await repository.startConfiguredQuiz(
        session: _session(),
        plan: await _plan(h),
      );
      final before = await h.session(first.sessionId);

      await _upgrade(h).upgrade(
        activeOwnerId: configuredOwnerId,
        firebaseUid: 'synthetic-configured-uid-b',
      );
      final restored = await repository.resumeQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: configuredOtherOwnerId,
      );

      expect(restored.ownerId, configuredOtherOwnerId);
      expect(restored.plan.stableSerialization, before['accepted_plan_json']);
      expect(restored.plan.id, before['accepted_plan_id']);
      expect(restored.sessionId, first.sessionId);
    },
  );

  for (final categoryChange in ['deleted', 'foreignOwner']) {
    test(
      'new quiz input rejects an original category that became $categoryChange',
      () async {
        final first = await repository.startConfiguredQuiz(
          session: _session(),
          plan: await _plan(h),
        );
        if (categoryChange == 'deleted') {
          await h.database.customStatement(
            'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
            [configuredCategoryId],
          );
        } else {
          await h.database.customStatement(
            'UPDATE vocabulary_categories SET owner_id = ? WHERE id = ?',
            [configuredOtherOwnerId, configuredCategoryId],
          );
        }
        final before = await h.snapshot();
        await expectLater(
          repository.saveQuizCheckpoint(
            sessionId: first.sessionId,
            expectedOwnerId: configuredOwnerId,
            expectedRevision: first.checkpointRevision,
            checkpoint: PendingQuizAnswer(
              planId: first.plan.id,
              questionOrdinal: 0,
              assistance: QuizAssistance(),
              answer: _answer(first),
            ),
          ),
          _unavailable('contentChanged'),
        );
        expect(await h.snapshot(), before);
        expect(await h.count('answer_attempts'), 0);
      },
    );
  }

  test(
    'committed answer ACK survives content drift while fresh next input is refused',
    () async {
      final pending = await _pending(h, repository);
      final accepted = await repository.commitQuizAnswer(
        sessionId: pending.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: pending.checkpointRevision,
      );
      await h.database.customStatement(
        'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
        [accepted.state.plan.questions.first.word.id],
      );
      final before = await h.snapshot();
      final replay = await repository.commitQuizAnswer(
        sessionId: pending.sessionId,
        expectedOwnerId: configuredOwnerId,
        expectedRevision: pending.checkpointRevision,
      );
      expect(replay.record.inserted, isFalse);
      expect(
        replay.state.checkpoint.stableSerialization,
        accepted.state.checkpoint.stableSerialization,
      );
      expect(
        replay.state.plan.stableSerialization,
        accepted.state.plan.stableSerialization,
      );
      expect(await h.snapshot(), before);
      await expectLater(
        repository.saveQuizCheckpoint(
          sessionId: pending.sessionId,
          expectedOwnerId: configuredOwnerId,
          expectedRevision: replay.state.checkpointRevision,
          checkpoint: AwaitingQuizAnswer(
            planId: replay.state.plan.id,
            questionOrdinal: 1,
            assistance: QuizAssistance(),
          ),
        ),
        _unavailable('contentChanged'),
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'natural-key remap preserves the old plan and makes exact resume unavailable',
    () async {
      final first = await repository.startConfiguredQuiz(
        session: _session(),
        plan: await _plan(h),
      );
      await h.database.customStatement(
        'UPDATE vocabulary_categories SET name = ?, normalized_name = ? WHERE id = ?',
        ['Synthetic travel', 'synthetic travel', configuredOtherCategoryId],
      );
      await h.addWord(
        id: 'synthetic-configured-target-station',
        spelling: 'station',
        meaning: 'สถานี',
        ownerId: configuredOtherOwnerId,
        categoryId: configuredOtherCategoryId,
      );
      final planBytes = (await h.session(
        first.sessionId,
      ))['accepted_plan_json'];
      await _upgrade(h).upgrade(
        activeOwnerId: configuredOwnerId,
        firebaseUid: 'synthetic-configured-uid-b',
      );
      final beforeResume = await h.snapshot();

      await expectLater(
        repository.resumeQuiz(
          sessionId: first.sessionId,
          expectedOwnerId: configuredOtherOwnerId,
        ),
        _unavailable('contentChanged'),
      );

      expect(
        (await h.session(first.sessionId))['accepted_plan_json'],
        planBytes,
      );
      expect(await h.snapshot(), beforeResume);
    },
  );

  test(
    'a pending old-owner command cannot be rewritten after ordinary rehome',
    () async {
      final pending = await _pending(h, repository);
      final before = await h.session(pending.sessionId);
      await _upgrade(h).upgrade(
        activeOwnerId: configuredOwnerId,
        firebaseUid: 'synthetic-configured-uid-b',
      );
      final afterUpgrade = await h.snapshot();

      await expectLater(
        repository.resumeQuiz(
          sessionId: pending.sessionId,
          expectedOwnerId: configuredOtherOwnerId,
        ),
        _unavailable('ownerChanged'),
      );

      final row = await h.session(pending.sessionId);
      expect(row['accepted_plan_json'], before['accepted_plan_json']);
      expect(row['checkpoint_json'], before['checkpoint_json']);
      expect(await h.snapshot(), afterUpgrade);
    },
  );
}

DriftLearningRepository _repository(
  ConfiguredQuizHarness h, {
  ConfiguredQuizObserver? observer,
}) => DriftLearningRepository(
  h.database,
  ownerWrites: h.ownerWrites,
  lifecycleObserver: observer,
);

LearningSessionDraft _session({
  String ownerId = configuredOwnerId,
  DateTime? startedAtUtc,
  String appVersion = 'synthetic-v1',
  String buildId = 'synthetic-build-1',
}) => LearningSessionDraft(
  id: 'synthetic-configured-session',
  ownerId: ownerId,
  activityType: 'quiz',
  startedAtUtc: startedAtUtc ?? configuredStart,
  appVersion: appVersion,
  buildId: buildId,
);

Future<AcceptedQuizPlan> _plan(
  ConfiguredQuizHarness h, {
  int limit = 2,
  String distractor = 'synthetic distractor',
}) async {
  final words = await _repository(h).listQuizWords(
    ownerId: configuredOwnerId,
    categoryId: configuredCategoryId,
    limit: limit,
  );
  return AcceptedQuizPlan.create(
    configuration: QuizConfiguration.category(
      categoryId: configuredCategoryId,
      limit: limit,
    ),
    questions: words.map(
      (word) => QuizQuestion(word: word, options: [word.meaning, distractor]),
    ),
  );
}

QuizAnswerReceipt _answer(ConfiguredQuizState state) =>
    QuizAnswerReceipt.capture(
      plan: state.plan,
      ownerId: configuredOwnerId,
      attemptId: 'attempt:00000000-0000-4000-8000-000000000042',
      questionOrdinal: 0,
      selectedOptionOrdinal: 0,
      revealed: false,
      assistance: QuizAssistance(),
      occurredAtUtcMs: configuredStart
          .add(const Duration(seconds: 2))
          .millisecondsSinceEpoch,
      responseTimeMs: 2000,
    );

Future<ConfiguredQuizState> _pending(
  ConfiguredQuizHarness h,
  DriftLearningRepository repository,
) async {
  final first = await repository.startConfiguredQuiz(
    session: _session(),
    plan: await _plan(h),
  );
  return repository.saveQuizCheckpoint(
    sessionId: first.sessionId,
    expectedOwnerId: configuredOwnerId,
    expectedRevision: first.checkpointRevision,
    checkpoint: PendingQuizAnswer(
      planId: first.plan.id,
      questionOrdinal: 0,
      assistance: QuizAssistance(),
      answer: _answer(first),
    ),
  );
}

DriftOwnerUpgradeRepository _upgrade(ConfiguredQuizHarness h) {
  var sequence = 0;
  return DriftOwnerUpgradeRepository(
    h.database,
    nowUtc: () => h.now,
    generateConflictId: () => 'synthetic-configured-conflict-${++sequence}',
    generateOwnerId: () => 'synthetic-configured-next-owner',
  );
}

Matcher _unavailable(String reason) => throwsA(
  isA<ConfiguredQuizUnavailable>().having(
    (error) => error.reason.name,
    'reason',
    reason,
  ),
);
