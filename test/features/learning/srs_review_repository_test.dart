import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';

import '../../support/srs_review_harness.dart';

void main() {
  late SrsReviewHarness h;
  setUp(() async => h = await SrsReviewHarness.open());
  tearDown(() => h.close());

  test(
    'source selection keeps explicit owned order without due rows or facts',
    () async {
      await h.database.customStatement('DELETE FROM srs_states');
      final before = await h.storage.snapshot();
      final requested = h.wordIds.reversed.toList();
      final review = (await h.prepare(sourceWordIds: requested))!;
      expect(review.selection, SrsReviewSelection.source);
      expect(review.words.map((word) => word.id), requested);
      expect(
        review.words.every((word) => word.contentRevision != null),
        isTrue,
      );
      expect(await h.storage.snapshot(), before);
      expect((h.notifications, h.questEvents, h.streakEvents), (0, 0, 0));
    },
  );

  test(
    'twenty due cards use deterministic tie order and preserve source order',
    () async {
      await h.close();
      h = await SrsReviewHarness.open(wordCount: 20);
      await h.database.customStatement(
        'UPDATE srs_states SET due_at_utc_ms = ?',
        [configuredStart.millisecondsSinceEpoch - 1],
      );
      final before = await h.storage.snapshot();
      final due = (await h.prepare())!;
      expect(due.selection, SrsReviewSelection.due);
      expect(due.words, hasLength(20));
      expect(due.words.map((word) => word.id), h.wordIds);
      final requested = h.wordIds.reversed.toList();
      final source = (await h.prepare(sourceWordIds: requested))!;
      expect(source.words.map((word) => word.id), requested);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'foreign requested owner cannot prepare a deck or create an owner',
    () async {
      final before = await h.storage.snapshot();
      await expectLater(h.prepare(ownerId: configuredOtherOwnerId), _denied);
      expect(await h.storage.snapshot(), before);
      expect(h.notifications, 0);
    },
  );

  test('repository rejects a coordinator from another database', () async {
    final other = await SrsReviewHarness.open();
    try {
      expect(
        () => DriftLearningRepository(
          h.database,
          ownerWrites: other.storage.ownerWrites,
        ),
        throwsArgumentError,
      );
    } finally {
      await other.close();
    }
  });

  test(
    'only the original prepared handle belongs to its preparing repository',
    () async {
      final prepared = (await h.prepare())!;
      final copied = SrsReviewSession(
        session: prepared.session,
        words: prepared.words,
        selection: prepared.selection,
      );
      final raw = SrsReviewSession(
        session: _session('${SrsReviewSession.idPrefix}raw'),
        words: prepared.words,
        selection: prepared.selection,
      );
      final otherRepository = DriftLearningRepository(
        h.database,
        ownerWrites: h.storage.ownerWrites,
      );
      final before = await h.storage.snapshot();
      for (final unprepared in [copied, raw]) {
        await expectLater(
          h.repository.startSrsReview(unprepared, stillCurrent: () => true),
          throwsStateError,
        );
      }
      await expectLater(
        otherRepository.startSrsReview(prepared, stillCurrent: () => true),
        throwsStateError,
      );
      expect(await h.storage.snapshot(), before);
      final accepted = await h.learning.startSrsReview(
        prepared,
        stillCurrent: () => h.current,
      );
      expect(accepted, same(prepared));
      expect(await h.storage.count('learning_sessions'), 1);
    },
  );

  test('every public SRS command rejects an inherited transaction', () async {
    for (final stage in _Stage.values) {
      final operation = await _operation(h, stage);
      await h.settleNotifications();
      final before = await h.storage.snapshot();
      final notifications = h.notifications;
      await expectLater(
        h.database.transaction(() => _invoke(h, stage, operation)),
        throwsStateError,
        reason: stage.name,
      );
      expect(await h.storage.snapshot(), before, reason: stage.name);
      expect(h.notifications, notifications, reason: stage.name);
    }
    expect(h.notificationTransactions, everyElement(isFalse));
  });

  for (final stage in [_Stage.start, _Stage.rating, _Stage.finish]) {
    for (final change in ['owner', 'fence', 'word', 'category', 'current']) {
      test(
        'actual ${stage.name} SQL then $change loss rolls back all 37 tables',
        () async {
          final operation = await _operation(h, stage);
          await h.settleNotifications();
          final before = await h.storage.snapshot();
          expect(before, hasLength(37));
          final hooks = (h.notifications, h.questEvents, h.streakEvents);
          final probe = _AfterSrsWrite(
            stage == _Stage.rating ? 'answer_attempts' : 'learning_sessions',
            onUpdate: stage == _Stage.finish,
            after: (executor) async {
              switch (change) {
                case 'owner':
                  await executor.runUpdate(
                    'UPDATE local_owners SET is_active = (id = ?)',
                    [configuredOtherOwnerId],
                  );
                case 'fence':
                  await h.storage.ownerWrites.beginDeletion(
                    ownerId: configuredOwnerId,
                    firebaseUid: configuredFirebaseUid,
                    idempotencyKey: 'synthetic-srs-postsql-${stage.name}',
                  );
                case 'word':
                  await executor.runUpdate(
                    'UPDATE vocabulary_words SET meaning = ?, local_revision = local_revision + 1 WHERE id = ?',
                    [
                      'synthetic changed target',
                      operation.review.words.first.id,
                    ],
                  );
                case 'category':
                  await executor.runUpdate(
                    'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
                    [operation.review.words.first.categoryId],
                  );
                case 'current':
                  h.current = false;
              }
            },
          );
          await expectLater(
            h.database.runWithInterceptor(
              () => _invoke(h, stage, operation),
              interceptor: probe,
            ),
            _denied,
          );
          expect(probe.fired, isTrue);
          expect(await h.storage.snapshot(), before);
          await h.settleNotifications();
          expect((h.notifications, h.questEvents, h.streakEvents), hooks);
          expect(h.notificationTransactions, everyElement(isFalse));
        },
      );
    }
  }

  for (final stage in [_Stage.start, _Stage.rating, _Stage.finish]) {
    test(
      '${stage.name} committed ACK loss reconciles once outside its transaction',
      () async {
        await h.close();
        late _LostAckRepository transport;
        h = await SrsReviewHarness.open(
          decorate: (repository) => transport = _LostAckRepository(repository),
        );
        final operation = await _operation(h, stage);
        await h.settleNotifications();
        final hooks = (h.notifications, h.questEvents, h.streakEvents);
        transport.lose = stage;
        await expectLater(_invoke(h, stage, operation), throwsStateError);
        final committed = await h.storage.snapshot();
        expect((h.notifications, h.questEvents, h.streakEvents), hooks);
        final spy = _BusinessWrites();
        await h.database.runWithInterceptor(
          () => _invoke(h, stage, operation),
          interceptor: spy,
        );
        await h.settleNotifications();
        expect(h.notifications, hooks.$1 + 1);
        expect(h.questEvents - hooks.$2, inInclusiveRange(0, 1));
        expect(h.streakEvents - hooks.$3, inInclusiveRange(0, 1));
        final acknowledged = (h.notifications, h.questEvents, h.streakEvents);
        await _invoke(h, stage, operation);
        await h.settleNotifications();
        expect((h.notifications, h.questEvents, h.streakEvents), acknowledged);
        expect(h.notificationTransactions, isNotEmpty);
        expect(h.notificationTransactions, everyElement(isFalse));
        expect(spy.statements, isEmpty);
        expect(await h.storage.snapshot(), committed);
        if (stage == _Stage.finish) {
          final row = await h.storage.session(operation.review.id);
          expect(row['state'], 'completed');
          expect(
            row['ended_at_utc_ms'],
            operation.finish!.endedAtUtc.millisecondsSinceEpoch,
          );
        }
      },
    );
  }

  test(
    'rating ACK returns the current saved SRS after a later legitimate review',
    () async {
      final first = await h.ready(source: true);
      final intent = h.answer(first);
      final initial = await h.learning.commitSrsRating(
        intent,
        stillCurrent: () => h.current,
      );
      expect(initial.inserted, isTrue);
      expect(initial.srs, isNotNull);
      h.now = h.now.add(const Duration(days: 2));
      final later = await h.ready(
        source: true,
        sourceWordIds: [first.words.first.id],
      );
      await h.learning.commitSrsRating(
        h.answer(later, recalled: false),
        stillCurrent: () => h.current,
      );
      final saved =
          (await h.database
                  .customSelect(
                    'SELECT * FROM srs_states WHERE owner_id = ? AND word_id = ?',
                    variables: [
                      drift.Variable<String>(first.ownerId),
                      drift.Variable<String>(first.words.first.id),
                    ],
                  )
                  .getSingle())
              .data;
      final before = await h.storage.snapshot();
      await h.settleNotifications();
      final hooks = (h.notifications, h.questEvents, h.streakEvents);
      final spy = _BusinessWrites();
      final replay = await h.database.runWithInterceptor(
        () => h.learning.commitSrsRating(intent, stillCurrent: () => h.current),
        interceptor: spy,
      );
      expect(replay.inserted, isFalse);
      final current = replay.srs!;
      expect(current.intervalDays, saved['interval_days']);
      expect(current.repetitions, saved['repetitions']);
      expect(current.lapses, saved['lapses']);
      expect(current.stability, saved['stability']);
      expect(current.difficulty, saved['difficulty']);
      expect(
        current.lastReviewAtUtc?.millisecondsSinceEpoch,
        saved['last_review_at_utc_ms'],
      );
      expect(current.dueAtUtc?.millisecondsSinceEpoch, saved['due_at_utc_ms']);
      expect(current.algorithmVersion, saved['algorithm_version']);
      expect(current.lastReviewAtUtc, h.now);
      expect(spy.statements, isEmpty);
      expect(await h.storage.snapshot(), before);
      expect((h.notifications, h.questEvents, h.streakEvents), hooks);
    },
  );

  for (final parent in ['word', 'category']) {
    test(
      'exact historical start rating and finish ACK survive deleted $parent',
      () async {
        final operation = await _operation(h, _Stage.finish);
        final summary = await h.learning.finishSrsReview(
          operation.finish!,
          stillCurrent: () => h.current,
        );
        await h.settleNotifications();
        await h.database.customStatement(
          parent == 'word'
              ? 'UPDATE vocabulary_words SET is_deleted = 1 WHERE id = ?'
              : 'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
          [
            parent == 'word'
                ? operation.review.words.first.id
                : operation.review.words.first.categoryId,
          ],
        );
        final before = await h.storage.snapshot();
        final hooks = (h.notifications, h.questEvents, h.streakEvents);
        final spy = _BusinessWrites();
        await h.database.runWithInterceptor(() async {
          expect(
            await h.learning.startSrsReview(
              operation.review,
              stillCurrent: () => h.current,
            ),
            same(operation.review),
          );
          expect(
            (await h.learning.commitSrsRating(
              operation.rating!,
              stillCurrent: () => h.current,
            )).inserted,
            isFalse,
          );
          final replay = await h.learning.finishSrsReview(
            operation.finish!,
            stillCurrent: () => h.current,
          );
          expect(_summary(replay), _summary(summary));
        }, interceptor: spy);
        expect(spy.statements, isEmpty);
        expect(await h.storage.snapshot(), before);
        expect((h.notifications, h.questEvents, h.streakEvents), hooks);
        expect(
          (await h.storage.session(operation.review.id))['ended_at_utc_ms'],
          operation.finish!.endedAtUtc.millisecondsSinceEpoch,
        );
      },
    );
  }

  test(
    'historical rating ACK survives a deleted target and purged SRS projection',
    () async {
      final operation = await _operation(h, _Stage.finish);
      final summary = await h.learning.finishSrsReview(
        operation.finish!,
        stillCurrent: () => h.current,
      );
      await h.settleNotifications();
      final target = operation.review.words.first;
      await h.database.customStatement(
        'UPDATE vocabulary_words SET is_deleted = 1 WHERE id = ? AND owner_id = ?',
        [target.id, operation.review.ownerId],
      );
      await h.database.customStatement(
        'DELETE FROM srs_states WHERE owner_id = ? AND word_id = ?',
        [operation.review.ownerId, target.id],
      );
      final before = await h.storage.snapshot();
      expect(before, hasLength(37));
      final hooks = (h.notifications, h.questEvents, h.streakEvents);
      final spy = _BusinessWrites();
      await h.database.runWithInterceptor(() async {
        expect(
          await h.learning.startSrsReview(
            operation.review,
            stillCurrent: () => h.current,
          ),
          same(operation.review),
        );
        final replay = await h.learning.commitSrsRating(
          operation.rating!,
          stillCurrent: () => h.current,
        );
        expect(replay.inserted, isFalse);
        expect(replay.srs, isNull);
        final finishReplay = await h.learning.finishSrsReview(
          operation.finish!,
          stillCurrent: () => h.current,
        );
        expect(_summary(finishReplay), _summary(summary));
      }, interceptor: spy);
      await h.settleNotifications();
      expect(spy.statements, isEmpty);
      expect(await h.storage.snapshot(), before);
      expect((h.notifications, h.questEvents, h.streakEvents), hooks);
      expect(
        (await h.storage.session(operation.review.id))['ended_at_utc_ms'],
        operation.finish!.endedAtUtc.millisecondsSinceEpoch,
      );
    },
  );

  test(
    'out-of-order card and partial finish never create a canonical rating',
    () async {
      final review = await h.ready(source: true);
      final original = h.answer(review);
      final second = SrsReviewAnswerIntent(
        review: review,
        cardIndex: 1,
        command: RecordAnswerCommand(
          id: 'attempt:srs:${review.id}:1',
          ownerId: review.ownerId,
          sessionId: review.id,
          wordId: review.words[1].id,
          promptMode: 'srsRecall',
          isCorrect: true,
          responseTimeMs: 1,
          attemptNumber: 2,
          occurredAtUtc: h.now,
          evidenceContext: original.command.evidenceContext,
        ),
      );
      final before = await h.storage.snapshot();
      await expectLater(
        h.repository.commitSrsRating(second, stillCurrent: () => h.current),
        throwsStateError,
      );
      await expectLater(
        h.repository.finishSrsReview(
          SrsReviewFinishIntent(review: review, endedAtUtc: h.now),
          stillCurrent: () => h.current,
        ),
        throwsStateError,
      );
      expect(
        () => SrsReviewAnswerIntent(
          review: review,
          cardIndex: review.words.length,
          command: original.command,
        ),
        throwsArgumentError,
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'a foreign extra canonical attempt prevents completion without deleting it',
    () async {
      final operation = await _operation(h, _Stage.finish);
      await h.database.customStatement(
        'INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,attempt_number,occurred_at_utc_ms) VALUES (?,?,?,?,?,?,?,?)',
        [
          'synthetic-foreign-extra-srs',
          configuredOtherOwnerId,
          operation.review.id,
          operation.review.words.first.id,
          'srsRecall',
          1,
          3,
          h.now.millisecondsSinceEpoch,
        ],
      );
      final before = await h.storage.snapshot();
      await expectLater(
        h.learning.finishSrsReview(
          operation.finish!,
          stillCurrent: () => h.current,
        ),
        throwsStateError,
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'altered frozen rating identity cannot overwrite its original receipt',
    () async {
      final review = await h.ready(source: true);
      final original = h.answer(review);
      await h.learning.commitSrsRating(original, stillCurrent: () => h.current);
      final changed = SrsReviewAnswerIntent(
        review: review,
        cardIndex: 0,
        command: _command(
          original.command,
          isCorrect: !original.command.isCorrect,
        ),
      );
      final before = await h.storage.snapshot();
      await expectLater(
        h.repository.commitSrsRating(changed, stillCurrent: () => h.current),
        throwsStateError,
      );
      expect(
        (await h.learning.commitSrsRating(
          original,
          stillCurrent: () => h.current,
        )).inserted,
        isFalse,
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'generic start answer and finish cannot bypass the reserved SRS prefix',
    () async {
      final prepared = (await h.prepare())!;
      final before = await h.storage.snapshot();
      await expectLater(
        h.repository.startSession(prepared.session),
        throwsStateError,
      );
      final started = await h.learning.startSrsReview(
        prepared,
        stillCurrent: () => h.current,
      );
      final accepted = await h.storage.snapshot();
      await expectLater(
        h.repository.recordAnswer(h.answer(started).command),
        throwsStateError,
      );
      await expectLater(
        h.repository.finishSession(
          ownerId: started.ownerId,
          sessionId: started.id,
          endedAtUtc: h.now,
        ),
        throwsStateError,
      );
      await expectLater(h.learning.finishSession(started.id), throwsStateError);
      expect(await h.storage.snapshot(), accepted);
      expect(accepted['answer_attempts'], before['answer_attempts']);
    },
  );

  for (final activity in ['srsReview', 'flashcard', 'flashcards']) {
    test(
      'nonprefix $activity cannot bypass generic start answer or finish',
      () async {
        final id = 'synthetic-generic-$activity';
        final session = _session(id, activity: activity);
        final before = await h.storage.snapshot();
        await expectLater(h.repository.startSession(session), throwsStateError);
        expect(await h.storage.snapshot(), before);
        await _seedSession(h, session);
        final stored = await h.storage.snapshot();
        final command = RecordAnswerCommand(
          id: 'synthetic-answer-$activity',
          ownerId: configuredOwnerId,
          sessionId: id,
          wordId: h.wordIds.first,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 2,
          attemptNumber: 1,
          occurredAtUtc: h.now,
        );
        await expectLater(h.repository.recordAnswer(command), throwsStateError);
        await expectLater(
          h.repository.finishSession(
            ownerId: configuredOwnerId,
            sessionId: id,
            endedAtUtc: h.now,
          ),
          throwsStateError,
        );
        await expectLater(h.learning.finishSession(id), throwsStateError);
        expect(await h.storage.snapshot(), stored);
      },
    );
  }

  test(
    'generic ordinary session cannot import the dedicated srsRecall prompt',
    () async {
      final session = _session('synthetic-ordinary-quiz', activity: 'quiz');
      await _seedSession(h, session);
      final before = await h.storage.snapshot();
      await expectLater(
        h.repository.recordAnswer(
          RecordAnswerCommand(
            id: 'synthetic-generic-srsRecall',
            ownerId: session.ownerId,
            sessionId: session.id,
            wordId: h.wordIds.first,
            promptMode: 'srsRecall',
            isCorrect: true,
            responseTimeMs: 1,
            attemptNumber: 1,
            occurredAtUtc: h.now,
          ),
        ),
        throwsStateError,
      );
      expect(await h.storage.snapshot(), before);
    },
  );
}

final _denied = throwsA(
  anyOf(isA<StateError>(), isA<AccountDeletionException>()),
);

enum _Stage { prepare, start, rating, finish }

final class _Operation {
  const _Operation(this.review, this.rating, this.finish);
  final SrsReviewSession review;
  final SrsReviewAnswerIntent? rating;
  final SrsReviewFinishIntent? finish;
}

Future<_Operation> _operation(SrsReviewHarness h, _Stage stage) async {
  final review = (await h.prepare(source: true))!;
  if (stage == _Stage.rating || stage == _Stage.finish) {
    await h.learning.startSrsReview(review, stillCurrent: () => h.current);
  }
  final first = stage == _Stage.rating || stage == _Stage.finish
      ? h.answer(review)
      : null;
  if (stage == _Stage.finish) {
    for (var i = 0; i < review.words.length; i++) {
      await h.learning.commitSrsRating(
        h.answer(review, cardIndex: i),
        stillCurrent: () => h.current,
      );
    }
    h.now = h.now.add(const Duration(seconds: 1));
  }
  return _Operation(
    review,
    first,
    stage == _Stage.finish ? h.learning.prepareSrsFinish(review) : null,
  );
}

Future<Object?> _invoke(
  SrsReviewHarness h,
  _Stage stage,
  _Operation operation,
) async => switch (stage) {
  _Stage.prepare => h.prepare(),
  _Stage.start => h.learning.startSrsReview(
    operation.review,
    stillCurrent: () => h.current,
  ),
  _Stage.rating => h.learning.commitSrsRating(
    operation.rating!,
    stillCurrent: () => h.current,
  ),
  _Stage.finish => h.learning.finishSrsReview(
    operation.finish!,
    stillCurrent: () => h.current,
  ),
};

LearningSessionDraft _session(String id, {String activity = 'srsReview'}) =>
    LearningSessionDraft(
      id: id,
      ownerId: configuredOwnerId,
      activityType: activity,
      startedAtUtc: configuredStart,
      appVersion: '1.0.0',
      buildId: 'srs-test',
    );

Future<void> _seedSession(
  SrsReviewHarness h,
  LearningSessionDraft session,
) => h.database.customStatement(
  'INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) VALUES (?,?,?,\'active\',?,?,?)',
  [
    session.id,
    session.ownerId,
    session.activityType,
    session.startedAtUtc!.millisecondsSinceEpoch,
    session.appVersion,
    session.buildId,
  ],
);

RecordAnswerCommand _command(
  RecordAnswerCommand original, {
  required bool isCorrect,
}) => RecordAnswerCommand(
  id: original.id,
  ownerId: original.ownerId,
  sessionId: original.sessionId,
  wordId: original.wordId,
  promptMode: original.promptMode,
  isCorrect: isCorrect,
  responseTimeMs: original.responseTimeMs,
  attemptNumber: original.attemptNumber,
  occurredAtUtc: original.occurredAtUtc,
  providerProvenance: original.providerProvenance,
  evidenceContext: original.evidenceContext,
);

(String, int, int, int?) _summary(LearningSessionSummary summary) =>
    (summary.state, summary.correctCount, summary.wrongCount, summary.score);

final class _LostAckRepository extends Fake
    implements LearningRepository, SrsReviewRepository {
  _LostAckRepository(this.repository);
  final DriftLearningRepository repository;
  _Stage? lose;
  Future<T> _receive<T>(_Stage stage, Future<T> operation) async {
    final result = await operation;
    if (lose == stage) {
      lose = null;
      throw StateError('synthetic committed ${stage.name} ACK loss');
    }
    return result;
  }

  @override
  Future<SrsReviewSession?> prepareSrsReview({
    required LearningSessionDraft session,
    required SrsReviewSelection selection,
    Iterable<String>? sourceWordIds,
    int limit = 20,
    required bool Function() stillCurrent,
  }) => repository.prepareSrsReview(
    session: session,
    selection: selection,
    sourceWordIds: sourceWordIds,
    limit: limit,
    stillCurrent: stillCurrent,
  );
  @override
  Future<SrsReviewStartResult> startSrsReview(
    SrsReviewSession review, {
    required bool Function() stillCurrent,
  }) => _receive(
    _Stage.start,
    repository.startSrsReview(review, stillCurrent: stillCurrent),
  );
  @override
  Future<AnswerRecordResult> commitSrsRating(
    SrsReviewAnswerIntent intent, {
    required bool Function() stillCurrent,
  }) => _receive(
    _Stage.rating,
    repository.commitSrsRating(intent, stillCurrent: stillCurrent),
  );
  @override
  Future<SrsReviewFinishResult> finishSrsReview(
    SrsReviewFinishIntent intent, {
    required bool Function() stillCurrent,
  }) => _receive(
    _Stage.finish,
    repository.finishSrsReview(intent, stillCurrent: stillCurrent),
  );
}

final class _AfterSrsWrite extends drift.QueryInterceptor {
  _AfterSrsWrite(this.table, {required this.onUpdate, required this.after});
  final String table;
  final bool onUpdate;
  final Future<void> Function(drift.QueryExecutor executor) after;
  bool fired = false;
  bool _matches(String statement, String operation) =>
      statement.toLowerCase().replaceAll('"', '').contains('$operation $table');
  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    if (!onUpdate && !fired && _matches(statement, 'into')) {
      fired = true;
      await after(executor);
    }
    return result;
  }

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runUpdate(statement, args);
    if (onUpdate && !fired && _matches(statement, 'update')) {
      fired = true;
      await after(executor);
    }
    return result;
  }
}

final class _BusinessWrites extends drift.QueryInterceptor {
  final statements = <String>[];
  void _record(String statement) {
    final sql = statement.toLowerCase().replaceAll('"', '');
    if (const [
      'learning_sessions',
      'answer_attempts',
      'srs_states',
      'outbox_operations',
      'points_ledger_entries',
      'achievement_unlocks',
      'reward_transactions',
      'owned_reward_items',
      'equipped_reward_items',
      'quest_instances',
      'quest_objective_progress',
      'streak_states',
      'events_v2',
    ].any(
      (table) =>
          sql.contains('into $table') ||
          sql.contains('update $table') ||
          sql.contains('from $table'),
    )) {
      statements.add(statement);
    }
  }

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return executor.runInsert(statement, args);
  }

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return executor.runUpdate(statement, args);
  }

  @override
  Future<int> runDelete(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    _record(statement);
    return executor.runDelete(statement, args);
  }
}
