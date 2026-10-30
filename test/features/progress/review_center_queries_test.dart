import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';

import '../../support/review_center_harness.dart';

void main() {
  test(
    'due and incorrect keep their independent facts on one current word',
    () async {
      final h = await ReviewCenterHarness.open();
      try {
        final first = configuredWordIds.first;
        final second = configuredWordIds[1];
        final due = h.now.subtract(const Duration(hours: 1));
        final earlier = h.now.subtract(const Duration(minutes: 10));
        await h.seedDue(first, dueAtUtc: due);
        await h.seedDue(second, dueAtUtc: h.now);
        await h.seedWrong(
          wordId: first,
          sessionId: 'synthetic-wrong-first',
          occurredAtUtc: earlier,
        );
        await h.seedWrong(
          wordId: first,
          sessionId: 'synthetic-wrong-second',
          occurredAtUtc: h.now,
        );
        final before = await h.snapshotAllTables();

        final result = await _facts(h);
        expect(result.ownerId, configuredOwnerId);
        expect(result.evaluatedAtUtc, h.now);
        expect(result.wordRows.map((row) => row.wordId).toSet(), {
          first,
          second,
        });
        final row = result.wordRows.singleWhere((row) => row.wordId == first);
        expect(row.queues, {ReviewQueue.due, ReviewQueue.incorrect});
        expect(row.word?.spelling, 'station');
        expect(row.word?.ownerId, configuredOwnerId);
        expect(row.categoryName, isNotEmpty);
        expect(row.isEligible, isTrue);
        expect(row.reasons.whereType<DueReason>().single.dueAtUtc, due);
        final wrong = row.reasons.whereType<IncorrectReason>().single;
        expect(wrong.incorrectCount, 2);
        expect(wrong.lastIncorrectAtUtc, h.now);
        expect(before, hasLength(37));
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'ordinary recreational errors appear without creating mastery or rewards',
    () async {
      final h = await ReviewCenterHarness.open();
      try {
        final context = EvidenceContext.forNewEvidence(
          evidenceClass: EvidenceClass.recreational,
          skillId: 'word-scramble',
          hintLevel: 0,
          contentRevision: 'synthetic-word-scramble-v1',
          rolloutMode: EvidencePolicyRolloutMode.legacy,
        );
        await h.seedWrong(
          wordId: configuredWordIds.first,
          sessionId: 'synthetic-recreational-history',
          activityType: 'wordScramble',
          promptMode: 'wordScramble',
          evidenceClass: 'recreational',
          evidenceContextJson: jsonEncode(context.toJson()),
        );
        final before = await h.snapshotAllTables();
        final result = await _facts(h);
        expect(result.wordRows.single.wordId, configuredWordIds.first);
        expect(result.wordRows.single.queues, {ReviewQueue.incorrect});
        expect(
          result.wordRows.single.reasons
              .whereType<IncorrectReason>()
              .single
              .incorrectCount,
          1,
        );
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'incorrect uses valid ordinary owner-session history, not session counters',
    () async {
      final h = await ReviewCenterHarness.open();
      try {
        final word = configuredWordIds.first;
        await h.seedWrong(wordId: word, sessionId: 'synthetic-valid-history');
        await h.seedWrong(
          wordId: word,
          sessionId: 'synthetic-correct-history',
          isCorrect: true,
        );
        await h.seedWrong(
          wordId: word,
          sessionId: 'synthetic-assessment-history',
          activityType: 'assessment',
        );
        await h.seedWrong(
          wordId: word,
          sessionId: 'synthetic-malformed-history',
          evidenceContextJson: '{}',
        );
        await h.seedWrong(
          wordId: word,
          sessionId: 'synthetic-class-mismatch-history',
          evidenceClass: 'recognition',
          evidenceContextJson:
              LearningEvidenceContract.frozenV13LegacyEvidenceContextJson,
        );
        await h.seedWrong(wordId: word, sessionId: 'synthetic-foreign-session');
        await h.database.customStatement(
          'UPDATE learning_sessions SET owner_id = ? WHERE id = ?',
          [configuredOtherOwnerId, 'synthetic-foreign-session'],
        );
        await h.seedWrong(
          wordId: 'synthetic-configured-other-word',
          ownerId: configuredOtherOwnerId,
          sessionId: 'synthetic-other-owner-history',
        );
        await h.database.customStatement(
          'UPDATE learning_sessions SET wrong_count = 99,correct_count = 99 WHERE id = ?',
          ['synthetic-valid-history'],
        );
        final before = await h.snapshotAllTables();

        final result = await _facts(h);
        expect(result.wordRows.map((row) => row.wordId), [word]);
        expect(
          result.wordRows.single.reasons
              .whereType<IncorrectReason>()
              .single
              .incorrectCount,
          1,
        );
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'an orphan historical answer is not an incorrect review reason',
    () async {
      final h = await ReviewCenterHarness.open();
      try {
        await h.seedWrong(
          wordId: configuredWordIds.first,
          sessionId: 'synthetic-orphan-history',
        );
        await h.database.customStatement('PRAGMA foreign_keys = OFF');
        try {
          await h.database.customStatement(
            'UPDATE answer_attempts SET session_id = ? WHERE session_id = ?',
            ['synthetic-missing-session', 'synthetic-orphan-history'],
          );
        } finally {
          await h.database.customStatement('PRAGMA foreign_keys = ON');
        }
        final before = await h.snapshotAllTables();
        expect((await _facts(h)).wordRows, isEmpty);
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'deleted current vocabulary retains historical incorrect ID as unavailable',
    () async {
      final h = await ReviewCenterHarness.open();
      try {
        final word = configuredWordIds.first;
        await h.seedDue(word);
        await h.seedWrong(wordId: word, sessionId: 'synthetic-deleted-history');
        await h.database.customStatement(
          'UPDATE vocabulary_words SET is_deleted = 1 WHERE id = ?',
          [word],
        );
        final before = await h.snapshotAllTables();
        final row = (await _facts(h)).wordRows.single;
        expect(row.wordId, word);
        expect(row.queues, {ReviewQueue.incorrect});
        expect(row.word, isNull);
        expect(row.categoryName, isNull);
        expect(row.isEligible, isFalse);
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'hard-missing word retains historical incorrect ID without invented content',
    () async {
      final h = await ReviewCenterHarness.open();
      try {
        final word = configuredWordIds.first;
        await h.seedWrong(
          wordId: word,
          sessionId: 'synthetic-missing-word-history',
        );
        await h.database.customStatement('PRAGMA foreign_keys = OFF');
        try {
          await h.database.customStatement(
            'DELETE FROM vocabulary_words WHERE id = ?',
            [word],
          );
        } finally {
          await h.database.customStatement('PRAGMA foreign_keys = ON');
        }
        final before = await h.snapshotAllTables();
        final row = (await _facts(h)).wordRows.single;
        expect(row.wordId, word);
        expect(row.queues, {ReviewQueue.incorrect});
        expect(row.word, isNull);
        expect(row.categoryName, isNull);
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );

  for (final categoryState in ['deleted', 'foreign']) {
    test(
      '$categoryState category excludes due and current incorrect content',
      () async {
        final h = await ReviewCenterHarness.open();
        try {
          final word = configuredWordIds.first;
          await h.seedDue(word);
          await h.seedWrong(
            wordId: word,
            sessionId: 'synthetic-category-history',
          );
          if (categoryState == 'deleted') {
            await h.database.customStatement(
              'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
              [configuredCategoryId],
            );
          } else {
            await h.database.customStatement(
              'UPDATE vocabulary_words SET category_id = ? WHERE id = ?',
              [configuredOtherCategoryId, word],
            );
          }
          final before = await h.snapshotAllTables();
          final row = (await _facts(h)).wordRows.single;
          expect(row.wordId, word);
          expect(row.queues, {ReviewQueue.incorrect});
          expect(row.word, isNull);
          expect(row.categoryName, isNull);
          final progress = await h.progressQueries.load(
            ownerId: configuredOwnerId,
            nowUtc: h.now,
          );
          expect(progress.dueReviewCount, 0);
          expect(progress.weaknesses, isEmpty);
          expect(await h.snapshotAllTables(), before);
        } finally {
          await h.close();
        }
      },
    );
  }

  test(
    'full due queue has stable due time and ID order without a practice limit',
    () async {
      final h = await ReviewCenterHarness.open();
      try {
        final ids = <String>[];
        for (var index = 0; index < 24; index++) {
          final id = 'synthetic-review-full-$index';
          ids.add(id);
          await _addWord(h, id);
          await h.seedDue(
            id,
            dueAtUtc: h.now.subtract(Duration(hours: index % 3)),
          );
        }
        await h.seedDue(
          configuredWordIds.first,
          dueAtUtc: h.now.add(const Duration(milliseconds: 1)),
        );
        final before = await h.snapshotAllTables();
        final result = await _facts(h);
        final expected = List<String>.of(ids)
          ..sort((left, right) {
            final leftIndex = int.parse(left.split('-').last);
            final rightIndex = int.parse(right.split('-').last);
            final due = (rightIndex % 3).compareTo(leftIndex % 3);
            return due == 0 ? left.compareTo(right) : due;
          });
        expect(result.wordRows.map((row) => row.wordId), expected);
        expect(result.wordRows, hasLength(24));
        expect(
          result.wordRows.every(
            (row) =>
                row.queues.length == 1 && row.queues.contains(ReviewQueue.due),
          ),
          isTrue,
        );
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );

  test('incorrect queue includes more than the History page size', () async {
    final h = await ReviewCenterHarness.open();
    try {
      for (var index = 0; index < 51; index++) {
        final id = 'synthetic-review-history-$index';
        await _addWord(h, id);
        await h.seedWrong(
          wordId: id,
          sessionId: 'synthetic-history-session-$index',
        );
      }
      final before = await h.snapshotAllTables();
      final result = await _facts(h);
      expect(result.wordRows, hasLength(51));
      expect(
        result.wordRows.every(
          (row) =>
              row.queues.length == 1 &&
              row.queues.contains(ReviewQueue.incorrect),
        ),
        isTrue,
      );
      expect(await h.snapshotAllTables(), before);
    } finally {
      await h.close();
    }
  });

  test(
    'empty read and explicit refresh create no rows in all 37 tables',
    () async {
      final h = await ReviewCenterHarness.open();
      try {
        final before = await h.snapshotAllTables();
        expect(before, hasLength(37));
        final first = await _facts(h);
        h.now = h.now.add(const Duration(days: 1));
        final refreshed = await _facts(h);
        expect(first.wordRows, isEmpty);
        expect(refreshed.wordRows, isEmpty);
        expect(refreshed.evaluatedAtUtc, h.now);
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );

  test('missing active owner fails closed without creating an owner', () async {
    final h = await ReviewCenterHarness.open(seed: false);
    try {
      final before = await h.snapshotAllTables();
      expect(before, hasLength(37));
      await expectLater(_facts(h), throwsA(_ownerInvalidated));
      expect(await h.snapshotAllTables(), before);
    } finally {
      await h.close();
    }
  });

  test(
    'ambiguous active owners fail closed without selecting a first owner',
    () async {
      final h = await ReviewCenterHarness.open();
      try {
        await h.database.customStatement(
          'UPDATE local_owners SET is_active = 1',
        );
        final before = await h.snapshotAllTables();
        await expectLater(_facts(h), throwsA(_ownerInvalidated));
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'current visibility loss during an awaited data read emits no private facts',
    () async {
      final gate = _AfterReviewRead((_) async {});
      final h = await ReviewCenterHarness.open(interceptor: gate);
      try {
        await h.seedDue(configuredWordIds.first);
        final before = await h.snapshotAllTables();
        gate.after = (_) async => h.current = false;
        gate.armed = true;
        await expectLater(_facts(h), throwsA(_ownerInvalidated));
        expect(gate.fired, isTrue);
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'actual owner change after data SQL rejects the old-owner read',
    () async {
      final gate = _AfterReviewRead(
        (executor) => executor
            .runUpdate('UPDATE local_owners SET is_active = (id = ?)', [
              configuredOtherOwnerId,
            ])
            .then((_) {}),
      );
      final h = await ReviewCenterHarness.open(interceptor: gate);
      try {
        await h.seedDue(configuredWordIds.first);
        gate.armed = true;
        await expectLater(_facts(h), throwsA(_ownerInvalidated));
        expect(gate.fired, isTrue);
        final owners = await h.database
            .customSelect('SELECT id FROM local_owners WHERE is_active = 1')
            .get();
        expect(owners.single.read<String>('id'), configuredOtherOwnerId);
        expect(
          await h.database.select(h.database.answerAttempts).get(),
          isEmpty,
        );
      } finally {
        await h.close();
      }
    },
  );

  test(
    'live owner ABA invalidates a stream instead of resuming old rows',
    () async {
      final h = await ReviewCenterHarness.open();
      _FactsWatch? watch;
      try {
        await h.seedDue(configuredWordIds.first);
        watch = _FactsWatch(
          h.queries.watchOwner(
            expectedOwnerId: configuredOwnerId,
            evaluatedAtUtc: h.now,
            stillCurrent: () => h.current,
          ),
        );
        await watch.waitFor(() => watch!.values.isNotEmpty);
        expect(
          watch.values.single.wordRows.single.wordId,
          configuredWordIds.first,
        );
        await h.database.transaction(() async {
          await h.database.customUpdate(
            'UPDATE local_owners SET is_active = (id = ?)',
            variables: [drift.Variable(configuredOtherOwnerId)],
            updates: {h.database.localOwners},
          );
          await h.database.customUpdate(
            'UPDATE local_owners SET is_active = (id = ?)',
            variables: [drift.Variable(configuredOwnerId)],
            updates: {h.database.localOwners},
          );
        });
        await watch.waitFor(() => watch!.errors.isNotEmpty || watch.done);
        expect(watch.errors, contains(_ownerInvalidated));
        expect(watch.values, hasLength(1));
        expect(watch.values.single.ownerId, configuredOwnerId);
      } finally {
        await watch?.cancel();
        await h.close();
      }
    },
  );

  test(
    'live current vocabulary change recomputes availability without writing',
    () async {
      final h = await ReviewCenterHarness.open();
      _FactsWatch? watch;
      try {
        final word = configuredWordIds.first;
        await h.seedDue(word);
        await h.seedWrong(wordId: word, sessionId: 'synthetic-live-history');
        watch = _FactsWatch(
          h.queries.watchOwner(
            expectedOwnerId: configuredOwnerId,
            evaluatedAtUtc: h.now,
            stillCurrent: () => h.current,
          ),
        );
        await watch.waitFor(() => watch!.values.isNotEmpty);
        await h.database.customUpdate(
          'UPDATE vocabulary_words SET is_deleted = 1 WHERE id = ?',
          variables: [drift.Variable(word)],
          updates: {h.database.vocabularyWords},
        );
        final afterMutation = await h.snapshotAllTables();
        await watch.waitFor(
          () => watch!.values.any(
            (facts) => facts.wordRows.single.queues.length == 1,
          ),
        );
        final row = watch.values.last.wordRows.single;
        expect(row.queues, {ReviewQueue.incorrect});
        expect(row.isEligible, isFalse);
        expect(row.word, isNull);
        expect(await h.snapshotAllTables(), afterMutation);
      } finally {
        await watch?.cancel();
        await h.close();
      }
    },
  );
  test(
    'candidate SQL failure is a redacted typed read failure at the public query boundary',
    () async {
      const marker = 'synthetic-private-SQL-owner-content-marker';
      final probe = _CandidateReadFailure(marker);
      final h = await ReviewCenterHarness.open(interceptor: probe);
      try {
        await h.seedDue(configuredWordIds.first);
        final before = await h.snapshotAllTables();
        probe.armed = true;
        await expectLater(
          _facts(h),
          throwsA(
            isA<ReviewCenterReadException>()
                .having(
                  (error) => error.code,
                  'code',
                  ReviewReadFailureCode.readFailed,
                )
                .having(
                  (error) => error.toString(),
                  'public error text',
                  isNot(contains(marker)),
                ),
          ),
        );
        expect(probe.fired, isTrue);
        probe.armed = false;
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );
  test(
    'final owner-read completion cannot publish query facts after caller invalidation',
    () async {
      final probe = _FinalQueryRead();
      final h = await ReviewCenterHarness.open(interceptor: probe);
      try {
        await h.seedDue(configuredWordIds.first);
        final before = await h.snapshotAllTables();
        var scheduled = false;
        probe.armed = true;
        await expectLater(
          h.queries
              .watchOwner(
                expectedOwnerId: configuredOwnerId,
                evaluatedAtUtc: h.now,
                stillCurrent: () {
                  if (probe.finalCheckReached && !scheduled) {
                    scheduled = true;
                    scheduleMicrotask(() => h.current = false);
                  }
                  return h.current;
                },
              )
              .first
              .timeout(const Duration(seconds: 3)),
          throwsA(_ownerInvalidated),
        );
        expect(probe.candidateReadFinished, isTrue);
        expect(probe.ownerReadsAfterCandidate, 2);
        expect(probe.finalCheckReached, isTrue);
        expect(scheduled, isTrue);
        expect(h.current, isFalse);
        probe.armed = false;
        expect(await h.snapshotAllTables(), before);
      } finally {
        await h.close();
      }
    },
  );
}

Future<ReviewReadFacts> _facts(ReviewCenterHarness h) => h.queries
    .watchOwner(
      expectedOwnerId: configuredOwnerId,
      evaluatedAtUtc: h.now,
      stillCurrent: () => h.current,
    )
    .first
    .timeout(const Duration(seconds: 3));

final Matcher _ownerInvalidated = isA<ReviewCenterReadException>().having(
  (error) => error.code,
  'code',
  ReviewReadFailureCode.ownerInvalidated,
);

Future<void> _addWord(
  ReviewCenterHarness h,
  String id,
) => h.database.customStatement(
  'INSERT INTO vocabulary_words '
  '(id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) '
  'VALUES (?,?,?,?,?,?,?,?,?,?)',
  [
    id,
    configuredOwnerId,
    configuredCategoryId,
    id,
    id,
    'synthetic meaning',
    'synthetic meaning',
    'noun',
    h.now.millisecondsSinceEpoch,
    h.now.millisecondsSinceEpoch,
  ],
);

final class _AfterReviewRead extends drift.QueryInterceptor {
  _AfterReviewRead(this.after);
  Future<void> Function(drift.QueryExecutor executor) after;
  bool armed = false;
  bool fired = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    final sql = statement.toLowerCase().replaceAll('"', '');
    if (armed &&
        !fired &&
        (sql.contains('srs_states') || sql.contains('answer_attempts'))) {
      fired = true;
      await after(executor);
    }
    return result;
  }
}

final class _CandidateReadFailure extends drift.QueryInterceptor {
  _CandidateReadFailure(this.marker);
  final String marker;
  bool armed = false;
  bool fired = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    final sql = statement.toLowerCase().replaceAll('"', '');
    if (armed &&
        !fired &&
        (sql.contains('srs_states') || sql.contains('answer_attempts'))) {
      fired = true;
      throw StateError(marker);
    }
    return executor.runSelect(statement, args);
  }
}

final class _FinalQueryRead extends drift.QueryInterceptor {
  bool armed = false;
  bool candidateReadFinished = false;
  int ownerReadsAfterCandidate = 0;
  bool get finalCheckReached => ownerReadsAfterCandidate == 2;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (!armed) return rows;
    final sql = statement.toLowerCase().replaceAll('"', '');
    if (sql.contains('srs_states') && sql.contains('answer_attempts')) {
      candidateReadFinished = true;
    }
    if (candidateReadFinished && sql.contains('select id from local_owners')) {
      ownerReadsAfterCandidate++;
    }
    return rows;
  }
}

final class _FactsWatch {
  _FactsWatch(Stream<ReviewReadFacts> source) {
    subscription = source.listen(
      (value) {
        values.add(value);
        _notify();
      },
      onError: (Object error, StackTrace _) {
        errors.add(error);
        _notify();
      },
      onDone: () {
        done = true;
        _notify();
      },
    );
  }

  late final StreamSubscription<ReviewReadFacts> subscription;
  final values = <ReviewReadFacts>[];
  final errors = <Object>[];
  bool done = false;
  Completer<void> _next = Completer<void>();

  void _notify() {
    final previous = _next;
    _next = Completer<void>();
    if (!previous.isCompleted) previous.complete();
  }

  Future<void> waitFor(bool Function() predicate) async {
    while (!predicate()) {
      if (done) fail('Review read ended before its expected result');
      await _next.future.timeout(const Duration(seconds: 3));
    }
  }

  Future<void> cancel() => subscription.cancel();
}
