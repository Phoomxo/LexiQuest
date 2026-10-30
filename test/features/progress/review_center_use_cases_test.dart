import 'dart:async';

import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/application/review_center_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_review_center_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_history_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/saved_words_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/application/word_report_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/saved_words.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

import '../../support/review_center_harness.dart';

void main() {
  late ReviewCenterHarness h;
  setUp(() async => h = await ReviewCenterHarness.open());
  tearDown(() => h.close());

  test(
    'real sources preserve three reasons and two historical report receipts',
    () async {
      final id = configuredWordIds.first;
      await h.seedDue(id);
      await h.seedWrong(wordId: id);
      final saved = await h.save(id);
      final first = await h.report(id);
      await h.database.customStatement(
        'UPDATE vocabulary_words SET meaning=?,normalized_meaning=?,local_revision=2 WHERE id=?',
        ['synthetic revised meaning', 'synthetic revised meaning', id],
      );
      final second = await h.report(id);
      final before = await h.snapshotAllTables();
      final value = await _ready(h.reviewCenter, h);
      final row = value.wordRows.single;
      expect(row.wordId, id);
      expect(row.queues, {
        ReviewQueue.due,
        ReviewQueue.incorrect,
        ReviewQueue.saved,
      });
      expect(
        (row.reasons.whereType<SavedReason>().single).state.sameFacts(saved),
        isTrue,
      );
      expect(value.distinctWordCount, 1);
      expect(value.eligibleWordCount, 1);
      expect(value.reportRows.map((r) => r.reportId), [first.id, second.id]);
      expect(value.reportRows.first.report.sameFacts(first), isTrue);
      expect(value.reportRows.last.report.sameFacts(second), isTrue);
      expect(first.target.wordRevision, 1);
      expect(second.target.wordRevision, 2);
      expect(value.reportCount, 2);
      expect(before.length, 37);
      expect(await h.snapshotAllTables(), before);
    },
  );

  test(
    'unavailable saved and incorrect IDs survive without current spelling',
    () async {
      final id = configuredWordIds.first;
      await h.save(id);
      await h.seedWrong(wordId: id);
      await h.seedDue(id);
      await h.database.customStatement(
        'UPDATE vocabulary_words SET is_deleted=1 WHERE id=?',
        [id],
      );
      final before = await h.snapshotAllTables();
      final value = await _ready(h.reviewCenter, h);
      final row = value.wordRows.single;
      expect(row.word, isNull);
      expect(row.categoryName, isNull);
      expect(row.queues, {ReviewQueue.incorrect, ReviewQueue.saved});
      expect(value.unavailableWordCount, 1);
      expect((value.queueStates[ReviewQueue.due] as ReviewQueueReady).count, 0);
      expect(await h.snapshotAllTables(), before);
    },
  );

  test('unsaved tombstone is state and never a review reason', () async {
    await h.save(configuredWordIds.first);
    await h.save(configuredWordIds.first, isSaved: false);
    final value = await _ready(h.reviewCenter, h);
    expect(value.wordRows, isEmpty);
    expect((value.queueStates[ReviewQueue.saved] as ReviewQueueReady).count, 0);
  });

  test('real reads refresh and reopen leave all37 tables unchanged', () async {
    await h.seedDue(configuredWordIds.first);
    await h.seedWrong(
      wordId: configuredWordIds[1],
      evidenceClass: 'recreational',
      promptMode: 'sentenceScramble',
    );
    await h.save(configuredWordIds[2]);
    await h.report(configuredWordIds[3]);
    final before = await h.snapshotAllTables();
    for (var i = 0; i < 3; i++) {
      final result = await _ready(h.reviewCenter, h);
      expect(result.wordRows.length, 3);
      expect(result.reportCount, 1);
    }
    expect(await h.snapshotAllTables(), before);
  });

  test(
    'evaluated clock is captured once per subscription and normalized to milliseconds',
    () async {
      final original = h.now;
      h.now = original.add(const Duration(microseconds: 7));
      final first = await _ready(h.reviewCenter, h);
      expect(first.evaluatedAtUtc, original);
      h.now = original.add(const Duration(hours: 1));
      final next = await _ready(h.reviewCenter, h);
      expect(next.evaluatedAtUtc, h.now);
    },
  );

  test(
    'ordinary section error drops old facts but keeps independent saved and reports',
    () async {
      final facts = await _ordinary(h);
      final source = _Queries(h, initial: facts);
      addTearDown(source.close);
      await h.save(configuredWordIds[1]);
      await h.report(configuredWordIds[2]);
      final iterator = _watch(h.compose(queries: source), h);
      addTearDown(iterator.cancel);
      expect((await _next(iterator, _allReady)).wordRows.length, 2);
      final before = await h.snapshotAllTables();
      source.events.addError(StateError('synthetic ordinary read failure'));
      final value = await _next(
        iterator,
        (v) => v.queueStates[ReviewQueue.due] is ReviewQueueUnavailable,
      );
      expect(value.wordRows.single.wordId, configuredWordIds[1]);
      expect(value.reportCount, 1);
      expect(
        value.queueStates[ReviewQueue.incorrect],
        isA<ReviewQueueUnavailable>(),
      );
      expect(value.queueStates[ReviewQueue.saved], isA<ReviewQueueReady>());
      expect(await h.snapshotAllTables(), before);
    },
  );

  test(
    'ordinary stream completion is unavailable rather than a zero ready queue',
    () async {
      final source = _Queries(h, initial: await _ordinary(h));
      final iterator = _watch(h.compose(queries: source), h);
      addTearDown(iterator.cancel);
      await _next(iterator, _allReady);
      await source.close();
      final value = await _next(
        iterator,
        (v) => v.queueStates[ReviewQueue.due] is ReviewQueueUnavailable,
      );
      expect(value.wordRows, isEmpty);
      expect(
        value.queueStates[ReviewQueue.incorrect],
        isA<ReviewQueueUnavailable>(),
      );
      expect(value.queueStates[ReviewQueue.saved], isA<ReviewQueueReady>());
    },
  );

  test(
    'saved error drops only saved reasons and keeps ordinary plus reports',
    () async {
      final saved = await h.save(configuredWordIds[1]);
      final source = _Saved(
        initial: SavedWordsSnapshot(
          ownerId: configuredOwnerId,
          states: [saved],
          savedItems: [
            SavedWordItem(
              state: saved,
              word: await h.word(saved.wordId),
              categoryName: 'Synthetic travel',
            ),
          ],
        ),
      );
      addTearDown(source.close);
      await h.seedDue(configuredWordIds.first);
      await h.report(configuredWordIds[2]);
      final iterator = _watch(h.compose(savedWords: source.useCases), h);
      addTearDown(iterator.cancel);
      await _next(iterator, _allReady);
      source.events.addError(StateError('synthetic saved read failure'));
      final value = await _next(
        iterator,
        (v) => v.queueStates[ReviewQueue.saved] is ReviewQueueUnavailable,
      );
      expect(value.wordRows.single.wordId, configuredWordIds.first);
      expect(value.reportCount, 1);
      expect(value.queueStates[ReviewQueue.due], isA<ReviewQueueReady>());
    },
  );

  test(
    'report completion drops receipts while other sections remain ready',
    () async {
      final receipt = await h.report(configuredWordIds.first);
      final reports = _Reports(initial: [receipt]);
      await h.save(configuredWordIds[1]);
      final iterator = _watch(h.compose(wordReports: reports.useCases), h);
      addTearDown(iterator.cancel);
      await _next(iterator, _allReady);
      await reports.close();
      final value = await _next(
        iterator,
        (v) => v.queueStates[ReviewQueue.reported] is ReviewQueueUnavailable,
      );
      expect(value.reportRows, isEmpty);
      expect(value.wordRows.single.wordId, configuredWordIds[1]);
      expect(value.queueStates[ReviewQueue.saved], isA<ReviewQueueReady>());
    },
  );

  for (final failed in [
    ReviewQueue.due,
    ReviewQueue.saved,
    ReviewQueue.reported,
  ]) {
    test(
      'synchronous ${failed.name} setup failure affects only its section',
      () async {
        await h.seedDue(configuredWordIds.first);
        await h.save(configuredWordIds[1]);
        await h.report(configuredWordIds[2]);
        final query = _Queries(h, throwOnWatch: true);
        final saved = _Saved(
          initial: SavedWordsSnapshot(
            ownerId: configuredOwnerId,
            states: [],
            savedItems: [],
          ),
          throwOnWatch: true,
        );
        final reports = _Reports(initial: [], throwOnWatch: true);
        addTearDown(query.close);
        addTearDown(saved.close);
        addTearDown(reports.close);
        final before = await h.snapshotAllTables();
        final iterator = _watch(
          h.compose(
            queries: failed == ReviewQueue.due ? query : null,
            savedWords: failed == ReviewQueue.saved ? saved.useCases : null,
            wordReports: failed == ReviewQueue.reported
                ? reports.useCases
                : null,
          ),
          h,
        );
        addTearDown(iterator.cancel);
        final value = await _next(
          iterator,
          (v) => v.queueStates.values.every(
            (state) => state is! ReviewQueueLoading,
          ),
        );
        final failedQueues = failed == ReviewQueue.due
            ? {ReviewQueue.due, ReviewQueue.incorrect}
            : {failed};
        for (final queue in ReviewQueue.values) {
          final state = value.queueStates[queue];
          if (failedQueues.contains(queue)) {
            expect(
              state,
              isA<ReviewQueueUnavailable>().having(
                (state) => state.code,
                'code',
                ReviewReadFailureCode.readFailed,
              ),
            );
          } else {
            expect(state, isA<ReviewQueueReady>());
          }
        }
        expect(
          value.wordRows.expand((row) => row.queues).any(failedQueues.contains),
          isFalse,
        );
        expect(value.reportCount, failed == ReviewQueue.reported ? 0 : 1);
        expect(await h.snapshotAllTables(), before);
      },
    );
  }

  test('synchronous owner-invalidated source failure remains global', () async {
    final query = _Queries(h, throwOnWatch: true, ownerFailure: true);
    addTearDown(query.close);
    final before = await h.snapshotAllTables();
    await expectLater(
      _ready(h.compose(queries: query), h),
      throwsA(_ownerInvalid),
    );
    expect(await h.snapshotAllTables(), before);
  });

  test(
    'pending source has loading state without pretending zero ready facts',
    () async {
      final source = _Queries(h);
      addTearDown(source.close);
      final iterator = _watch(h.compose(queries: source), h);
      addTearDown(iterator.cancel);
      final value = await _next(
        iterator,
        (v) =>
            v.queueStates[ReviewQueue.saved] is ReviewQueueReady &&
            v.queueStates[ReviewQueue.reported] is ReviewQueueReady,
      );
      expect(value.queueStates[ReviewQueue.due], isA<ReviewQueueLoading>());
      expect(
        value.queueStates[ReviewQueue.incorrect],
        isA<ReviewQueueLoading>(),
      );
      expect(value.wordRows, isEmpty);
    },
  );

  test(
    'same word snapshot conflict preserves reasons but cannot choose latest spelling',
    () async {
      final id = configuredWordIds.first;
      final saved = await h.save(id);
      final current = await h.word(id);
      final ordinary = _Queries(
        h,
        initial: ReviewReadFacts(
          ownerId: configuredOwnerId,
          evaluatedAtUtc: h.now,
          wordRows: [
            ReviewWordRow(
              ownerId: configuredOwnerId,
              wordId: id,
              word: current,
              categoryName: 'Synthetic travel',
              reasons: [DueReason(dueAtUtc: h.now)],
            ),
          ],
        ),
      );
      final savedSource = _Saved(
        initial: SavedWordsSnapshot(
          ownerId: configuredOwnerId,
          states: [saved],
          savedItems: [
            SavedWordItem(
              state: saved,
              word: current.copyWith(
                meaning: 'different snapshot',
                localRevision: 9,
              ),
              categoryName: 'Synthetic travel',
            ),
          ],
        ),
      );
      addTearDown(ordinary.close);
      addTearDown(savedSource.close);
      final iterator = _watch(
        h.compose(queries: ordinary, savedWords: savedSource.useCases),
        h,
      );
      addTearDown(iterator.cancel);
      final mismatched = await _next(iterator, _allReady);
      expect(mismatched.wordRows.single.isEligible, isFalse);
      expect(mismatched.wordRows.single.queues, {
        ReviewQueue.due,
        ReviewQueue.saved,
      });
      savedSource.events.add(
        SavedWordsSnapshot(
          ownerId: configuredOwnerId,
          states: [saved],
          savedItems: [
            SavedWordItem(
              state: saved,
              word: current,
              categoryName: 'Synthetic travel',
            ),
          ],
        ),
      );
      final matched = await _next(
        iterator,
        (v) => _allReady(v) && v.wordRows.single.isEligible,
      );
      expect(matched.wordRows.single.word!.meaning, current.meaning);
    },
  );

  test(
    'failed ordinary section releases its conflicting current snapshot',
    () async {
      final id = configuredWordIds.first;
      final saved = await h.save(id);
      final word = await h.word(id);
      final ordinary = _Queries(
        h,
        initial: ReviewReadFacts(
          ownerId: configuredOwnerId,
          evaluatedAtUtc: h.now,
          wordRows: [
            ReviewWordRow(
              ownerId: configuredOwnerId,
              wordId: id,
              word: word.copyWith(meaning: 'stale read'),
              categoryName: 'Synthetic travel',
              reasons: [DueReason(dueAtUtc: h.now)],
            ),
          ],
        ),
      );
      addTearDown(ordinary.close);
      final iterator = _watch(h.compose(queries: ordinary), h);
      addTearDown(iterator.cancel);
      expect(
        (await _next(iterator, _allReady)).wordRows.single.isEligible,
        isFalse,
      );
      ordinary.events.addError(StateError('synthetic failed stale source'));
      final value = await _next(
        iterator,
        (v) => v.queueStates[ReviewQueue.due] is ReviewQueueUnavailable,
      );
      expect(value.wordRows.single.isEligible, isTrue);
      expect(value.wordRows.single.queues, {ReviewQueue.saved});
      expect(
        (value.wordRows.single.reasons.single as SavedReason).state.sameFacts(
          saved,
        ),
        isTrue,
      );
    },
  );

  test(
    'source foreign owner is global invalidation and cannot become partial data',
    () async {
      final source = _Queries(h);
      addTearDown(source.close);
      final iterator = _watch(h.compose(queries: source), h);
      addTearDown(iterator.cancel);
      await _next(
        iterator,
        (v) =>
            v.queueStates[ReviewQueue.saved] is ReviewQueueReady &&
            v.queueStates[ReviewQueue.reported] is ReviewQueueReady,
      );
      final before = await h.snapshotAllTables();
      source.events.add(
        ReviewReadFacts(
          ownerId: configuredOtherOwnerId,
          evaluatedAtUtc: h.now,
          wordRows: [],
        ),
      );
      await expectLater(_next(iterator, (_) => true), throwsA(_ownerInvalid));
      expect(await h.snapshotAllTables(), before);
    },
  );

  test('foreign saved snapshot invalidates all sections', () async {
    final source = _Saved(
      initial: SavedWordsSnapshot(
        ownerId: configuredOwnerId,
        states: [],
        savedItems: [],
      ),
    );
    addTearDown(source.close);
    final iterator = _watch(h.compose(savedWords: source.useCases), h);
    addTearDown(iterator.cancel);
    await _next(iterator, _allReady);
    source.events.add(
      SavedWordsSnapshot(
        ownerId: configuredOtherOwnerId,
        states: [],
        savedItems: [],
      ),
    );
    await expectLater(_next(iterator, (_) => true), throwsA(_ownerInvalid));
  });

  test('foreign historical receipt invalidates all sections', () async {
    final receipt = await h.report(configuredWordIds.first);
    final source = _Reports(initial: []);
    addTearDown(source.close);
    final iterator = _watch(h.compose(wordReports: source.useCases), h);
    addTearDown(iterator.cancel);
    await _next(iterator, _allReady);
    source.events.add([
      StoredWordReport(
        id: receipt.id,
        ownerId: configuredOtherOwnerId,
        target: receipt.target,
        reason: receipt.reason,
        comment: receipt.comment,
        queuedAtUtc: receipt.queuedAtUtc,
      ),
    ]);
    await expectLater(_next(iterator, (_) => true), throwsA(_ownerInvalid));
  });

  test(
    'caller invalidated during a pending read cannot emit stale private facts',
    () async {
      final source = _Queries(h);
      addTearDown(source.close);
      final iterator = _watch(h.compose(queries: source), h);
      addTearDown(iterator.cancel);
      await _next(
        iterator,
        (v) =>
            v.queueStates[ReviewQueue.saved] is ReviewQueueReady &&
            v.queueStates[ReviewQueue.reported] is ReviewQueueReady,
      );
      h.current = false;
      source.events.add(await _ordinary(h));
      await expectLater(_next(iterator, (_) => true), throwsA(_ownerInvalid));
    },
  );

  for (final returnToA in [false, true]) {
    test(
      'actual owner change${returnToA ? " A-B-A" : " A-B"} burns subscription',
      () async {
        final iterator = _watch(h.reviewCenter, h);
        addTearDown(iterator.cancel);
        await _next(iterator, _allReady);
        await h.switchOwner(configuredOtherOwnerId);
        if (returnToA) await h.switchOwner(configuredOwnerId);
        await expectLater(_next(iterator, (_) => true), throwsA(_ownerInvalid));
      },
    );
  }

  test('no active owner read creates no owner or any other row', () async {
    await h.database.customStatement('UPDATE local_owners SET is_active=0');
    final before = await h.snapshotAllTables();
    await expectLater(_ready(h.reviewCenter, h), throwsA(_ownerInvalid));
    expect(await h.snapshotAllTables(), before);
  });

  test(
    'owner stream completion closes private view instead of retaining ready data',
    () async {
      final iterator = _watch(h.reviewCenter, h);
      addTearDown(iterator.cancel);
      await _next(iterator, _allReady);
      await h.close();
      await expectLater(_next(iterator, (_) => true), throwsA(_ownerInvalid));
    },
  );

  test(
    'constructor rejects progress authority from a different database',
    () async {
      final other = await ReviewCenterHarness.open();
      addTearDown(other.close);
      expect(
        () => ReviewCenterUseCases(
          queries: h.queries,
          progress: other.progress,
          savedWords: h.savedWords,
          wordReports: h.wordReports,
          nowUtc: () => h.now,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'loadForOwner reads without creation and rejects stale caller',
    () async {
      final before = await h.snapshotAllTables();
      await h.progress.loadForOwner(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(await h.snapshotAllTables(), before);
      await expectLater(
        h.progress.loadForOwner(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => false,
        ),
        throwsA(_ownerInvalid),
      );
      await h.switchOwner(configuredOtherOwnerId);
      final switched = await h.snapshotAllTables();
      await expectLater(
        h.progress.loadForOwner(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsA(_ownerInvalid),
      );
      expect(await h.snapshotAllTables(), switched);
    },
  );

  test(
    'final owner-read completion cannot resolve a Progress view after caller invalidation',
    () async {
      final before = await h.snapshotAllTables();
      final probe = _FinalProgressRead();
      var scheduled = false;
      await expectLater(
        h.database.runWithInterceptor(
          () => h.progress.loadForOwner(
            expectedOwnerId: configuredOwnerId,
            stillCurrent: () {
              if (probe.finalCheckReached && !scheduled) {
                scheduled = true;
                scheduleMicrotask(() => h.current = false);
              }
              return h.current;
            },
          ),
          interceptor: probe,
        ),
        throwsA(_ownerInvalid),
      );
      expect(probe.finalCheckReached, isTrue);
      expect(scheduled, isTrue);
      expect(h.current, isFalse);
      expect(await h.snapshotAllTables(), before);
    },
  );

  test(
    'final owner-read completion cannot publish a Review Center after caller invalidation',
    () async {
      await h.close();
      final probe = _FinalPublishRead();
      h = await ReviewCenterHarness.open(interceptor: probe);
      final facts = await _ordinary(h);
      final source = _Queries(h, initial: facts);
      addTearDown(source.close);
      var scheduled = false;
      final iterator = StreamIterator(
        h
            .compose(queries: source)
            .watchOwner(
              expectedOwnerId: configuredOwnerId,
              stillCurrent: () {
                if (probe.finalCheckReached && !scheduled) {
                  scheduled = true;
                  scheduleMicrotask(() => h.current = false);
                }
                return h.current;
              },
            ),
      );
      addTearDown(iterator.cancel);
      await _next(iterator, _allReady);
      final before = await h.snapshotAllTables();
      probe.armed = true;
      source.events.add(facts);
      await expectLater(_next(iterator, (_) => true), throwsA(_ownerInvalid));
      expect(probe.finalCheckReached, isTrue);
      expect(scheduled, isTrue);
      expect(h.current, isFalse);
      expect(await h.snapshotAllTables(), before);
    },
  );

  test(
    'guarded History read uses captured owner and mutates no tables',
    () async {
      await h.seedWrong();
      final before = await h.snapshotAllTables();
      final result = await h.progress.loadHistoryForOwner(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(result.ownerId, configuredOwnerId);
      expect(result.entries.single.answerCount, 1);
      expect(await h.snapshotAllTables(), before);
      await expectLater(
        h.progress.loadHistoryForOwner(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
          before: LearningHistoryCursor(
            ownerId: configuredOtherOwnerId,
            sessionId: 'synthetic-foreign-cursor',
            startedAtUtc: h.now,
          ),
        ),
        throwsA(isA<LearningHistoryOwnerChanged>()),
      );
      expect(await h.snapshotAllTables(), before);
    },
  );

  test('guarded History does not recreate a missing owner', () async {
    await h.database.customStatement('UPDATE local_owners SET is_active=0');
    final before = await h.snapshotAllTables();
    await expectLater(
      h.progress.loadHistoryForOwner(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      ),
      throwsA(_ownerInvalid),
    );
    expect(await h.snapshotAllTables(), before);
  });

  test(
    'guarded History rejects owner ABA during its awaited snapshot',
    () async {
      await h.seedWrong();
      final before = await h.snapshotAllTables();
      final probe = _HistoryOwnerAba(h);
      await expectLater(
        h.database.runWithInterceptor(
          () => h.progress.loadHistoryForOwner(
            expectedOwnerId: configuredOwnerId,
            stillCurrent: () => true,
          ),
          interceptor: probe,
        ),
        throwsA(_ownerInvalid),
      );
      expect(probe.triggered, isTrue);
      expect(await h.snapshotAllTables(), before);
    },
  );

  test(
    'immutable rows snapshots and reason collections cannot be mutated',
    () async {
      final row = ReviewWordRow(
        ownerId: configuredOwnerId,
        wordId: configuredWordIds.first,
        word: await h.word(configuredWordIds.first),
        categoryName: 'Synthetic travel',
        reasons: [DueReason(dueAtUtc: h.now)],
      );
      final rows = [row];
      final states = {
        for (final q in ReviewQueue.values)
          q: ReviewQueueReady(count: q == ReviewQueue.due ? 1 : 0),
      };
      final snapshot = ReviewCenterSnapshot(
        ownerId: configuredOwnerId,
        evaluatedAtUtc: h.now,
        wordRows: rows,
        reportRows: [],
        queueStates: states,
      );
      rows.clear();
      states.clear();
      expect(snapshot.wordRows, [row]);
      expect(() => snapshot.wordRows.clear(), throwsUnsupportedError);
      expect(() => snapshot.queueStates.clear(), throwsUnsupportedError);
      expect(() => row.reasons.clear(), throwsUnsupportedError);
      expect(() => row.queues.clear(), throwsUnsupportedError);
    },
  );

  test(
    'model rejects duplicate foreign reasons and invalid section counts',
    () async {
      final word = await h.word(configuredWordIds.first);
      expect(
        () => ReviewWordRow(
          ownerId: configuredOwnerId,
          wordId: word.id,
          reasons: [
            DueReason(dueAtUtc: h.now),
            DueReason(dueAtUtc: h.now),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => ReviewWordRow(
          ownerId: configuredOwnerId,
          wordId: word.id,
          word: word,
          reasons: [DueReason(dueAtUtc: h.now)],
        ),
        throwsArgumentError,
      );
      expect(
        () => IncorrectReason(incorrectCount: 0, lastIncorrectAtUtc: h.now),
        throwsArgumentError,
      );
      expect(
        () => ReviewReadFacts(
          ownerId: configuredOwnerId,
          evaluatedAtUtc: h.now,
          wordRows: [
            ReviewWordRow(
              ownerId: configuredOwnerId,
              wordId: word.id,
              reasons: [DueReason(dueAtUtc: h.now)],
            ),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => ReviewCenterSnapshot(
          ownerId: configuredOwnerId,
          evaluatedAtUtc: h.now,
          wordRows: [],
          reportRows: [],
          queueStates: {
            for (final q in ReviewQueue.values) q: ReviewQueueReady(count: 1),
          },
        ),
        throwsArgumentError,
      );
    },
  );
}

final _ownerInvalid = isA<ReviewCenterReadException>().having(
  (error) => error.code,
  'code',
  ReviewReadFailureCode.ownerInvalidated,
);
bool _allReady(ReviewCenterSnapshot value) =>
    value.queueStates.values.every((s) => s is ReviewQueueReady);
StreamIterator<ReviewCenterSnapshot> _watch(
  ReviewCenterUseCases cases,
  ReviewCenterHarness h,
) => StreamIterator(
  cases.watchOwner(
    expectedOwnerId: configuredOwnerId,
    stillCurrent: () => h.current,
  ),
);
Future<ReviewCenterSnapshot> _ready(
  ReviewCenterUseCases cases,
  ReviewCenterHarness h,
) async {
  final iterator = _watch(cases, h);
  try {
    return await _next(iterator, _allReady);
  } finally {
    await iterator.cancel();
  }
}

Future<ReviewCenterSnapshot> _next(
  StreamIterator<ReviewCenterSnapshot> iterator,
  bool Function(ReviewCenterSnapshot) predicate,
) async {
  while (await iterator.moveNext().timeout(const Duration(seconds: 3))) {
    if (predicate(iterator.current)) return iterator.current;
  }
  throw StateError('Review stream closed without the required snapshot');
}

Future<ReviewReadFacts> _ordinary(ReviewCenterHarness h) async =>
    ReviewReadFacts(
      ownerId: configuredOwnerId,
      evaluatedAtUtc: h.now,
      wordRows: [
        ReviewWordRow(
          ownerId: configuredOwnerId,
          wordId: configuredWordIds.first,
          word: await h.word(configuredWordIds.first),
          categoryName: 'Synthetic travel',
          reasons: [
            DueReason(dueAtUtc: h.now),
            IncorrectReason(incorrectCount: 1, lastIncorrectAtUtc: h.now),
          ],
        ),
      ],
    );

final class _Queries extends DriftReviewCenterQueries {
  _Queries(
    ReviewCenterHarness h, {
    this.initial,
    this.throwOnWatch = false,
    this.ownerFailure = false,
  }) : super(h.database);
  final ReviewReadFacts? initial;
  final bool throwOnWatch;
  final bool ownerFailure;
  final events = StreamController<ReviewReadFacts>.broadcast(sync: true);
  @override
  Stream<ReviewReadFacts> watchOwner({
    required String expectedOwnerId,
    required DateTime evaluatedAtUtc,
    required bool Function() stillCurrent,
  }) {
    if (throwOnWatch) {
      if (ownerFailure) {
        throw const ReviewCenterReadException(
          ReviewReadFailureCode.ownerInvalidated,
        );
      }
      throw StateError('synthetic synchronous query setup failure');
    }
    return _source(initial, events);
  }

  Future<void> close() => events.close();
}

final class _Saved implements SavedWordsRepository {
  _Saved({required this.initial, this.throwOnWatch = false});
  final SavedWordsSnapshot initial;
  final bool throwOnWatch;
  final events = StreamController<SavedWordsSnapshot>.broadcast(sync: true);
  SavedWordsUseCases get useCases => SavedWordsUseCases(
    repository: this,
    generateId: () => throw StateError('A read allocated a mutation ID'),
    nowUtc: () => throw StateError('A read prepared a mutation'),
  );
  @override
  Stream<SavedWordsSnapshot> watchOwner(String expectedOwnerId) {
    if (throwOnWatch) {
      throw StateError('synthetic synchronous saved setup failure');
    }
    return _source(initial, events);
  }

  @override
  Future<SavedWordApplyResult> apply(SavedWordMutation command) =>
      throw StateError('A read mutated saved words');
  Future<void> close() => events.close();
}

final class _Reports implements WordReportRepository {
  _Reports({required this.initial, this.throwOnWatch = false});
  final List<StoredWordReport> initial;
  final bool throwOnWatch;
  final events = StreamController<List<StoredWordReport>>.broadcast(sync: true);
  WordReportUseCases get useCases => WordReportUseCases(
    repository: this,
    generateId: () => throw StateError('A read allocated a report ID'),
    nowUtc: () => throw StateError('A read prepared a report'),
  );
  @override
  Stream<List<StoredWordReport>> watchOwner(String expectedOwnerId) {
    if (throwOnWatch) {
      throw StateError('synthetic synchronous report setup failure');
    }
    return _source(initial, events);
  }

  @override
  Future<SubmitResult> submit(WordReportCommand command) =>
      throw StateError('A read submitted a report');
  Future<void> close() => events.close();
}

final class _FinalPublishRead extends drift.QueryInterceptor {
  bool armed = false;
  int ownerReads = 0;
  bool finalCheckReached = false;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (armed && statement.contains('SELECT id FROM local_owners')) {
      ownerReads++;
      if (ownerReads == 2) finalCheckReached = true;
    }
    return rows;
  }
}

final class _FinalProgressRead extends drift.QueryInterceptor {
  bool progressReadFinished = false;
  bool finalCheckReached = false;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.contains('FROM vocabulary_words w')) {
      progressReadFinished = true;
    }
    if (progressReadFinished &&
        statement.contains('SELECT id FROM local_owners')) {
      finalCheckReached = true;
    }
    return rows;
  }
}

final class _HistoryOwnerAba extends drift.QueryInterceptor {
  _HistoryOwnerAba(this.h);
  final ReviewCenterHarness h;
  bool triggered = false;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (!triggered && statement.contains('FROM learning_sessions')) {
      triggered = true;
      await executor.runUpdate('UPDATE local_owners SET is_active = (id = ?)', [
        configuredOtherOwnerId,
      ]);
      h.database.notifyUpdates({drift.TableUpdate('local_owners')});
      await Future<void>.delayed(Duration.zero);
      await executor.runUpdate('UPDATE local_owners SET is_active = (id = ?)', [
        configuredOwnerId,
      ]);
      h.database.notifyUpdates({drift.TableUpdate('local_owners')});
      await Future<void>.delayed(Duration.zero);
    }
    return rows;
  }
}

Stream<T> _source<T>(T? initial, StreamController<T> events) =>
    Stream<T>.multi((out) {
      final sub = events.stream.listen(
        out.add,
        onError: out.addError,
        onDone: out.close,
      );
      if (initial != null) out.add(initial);
      out.onCancel = sub.cancel;
    });
