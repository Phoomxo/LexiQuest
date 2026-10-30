import 'dart:async';

import '../../vocabulary/application/saved_words_use_cases.dart';
import '../../vocabulary/application/word_report_use_cases.dart';
import '../../vocabulary/domain/saved_words.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../../vocabulary/domain/word_report.dart';
import '../data/drift_review_center_queries.dart';
import '../domain/review_center_models.dart';
import 'progress_use_cases.dart';

class ReviewCenterUseCases {
  ReviewCenterUseCases({
    required this.queries,
    required this.progress,
    required this.savedWords,
    required this.wordReports,
    required this.nowUtc,
  }) {
    if (!identical(queries.database, progress.queries.database)) {
      throw ArgumentError('Review reads require the same progress database');
    }
  }

  final DriftReviewCenterQueries queries;
  final ProgressUseCases progress;
  final SavedWordsUseCases savedWords;
  final WordReportUseCases wordReports;
  final DateTime Function() nowUtc;

  Stream<ReviewCenterSnapshot> watchOwner({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) {
    late final StreamController<_QueuedReviewSnapshot> output;
    StreamSubscription<String?>? ownerSubscription;
    StreamSubscription<ReviewReadFacts>? ordinarySubscription;
    StreamSubscription<SavedWordsSnapshot>? savedSubscription;
    StreamSubscription<List<StoredWordReport>>? reportSubscription;
    ReviewReadFacts? ordinary;
    SavedWordsSnapshot? saved;
    List<StoredWordReport>? reports;
    final states = <ReviewQueue, ReviewQueueState>{
      for (final queue in ReviewQueue.values) queue: const ReviewQueueLoading(),
    };
    var retired = false;
    var started = false;
    var revision = 0;
    DateTime? evaluatedAt;

    Future<void> cancel() async {
      retired = true;
      await Future.wait([
        if (ownerSubscription != null) ownerSubscription!.cancel(),
        if (ordinarySubscription != null) ordinarySubscription!.cancel(),
        if (savedSubscription != null) savedSubscription!.cancel(),
        if (reportSubscription != null) reportSubscription!.cancel(),
      ]);
      ordinary = null;
      saved = null;
      reports = null;
    }

    void invalidate([StackTrace? stack]) {
      if (retired) return;
      retired = true;
      ordinary = null;
      saved = null;
      reports = null;
      output.addError(
        const ReviewCenterReadException(ReviewReadFailureCode.ownerInvalidated),
        stack,
      );
      unawaited(output.close());
      unawaited(cancel());
    }

    Future<void> publish() async {
      final captured = ++revision;
      try {
        await requireReviewReadOwner(
          queries.database,
          expectedOwnerId: expectedOwnerId,
          stillCurrent: () => !retired && stillCurrent(),
        );
        if (retired || captured != revision) return;
        final result = _snapshot(
          expectedOwnerId,
          evaluatedAt!,
          ordinary,
          saved,
          reports,
          states,
        );
        await requireReviewReadOwner(
          queries.database,
          expectedOwnerId: expectedOwnerId,
          stillCurrent: () => !retired && stillCurrent(),
        );
        if (retired) return;
        if (!stillCurrent()) {
          invalidate();
          return;
        }
        if (captured == revision) {
          output.add((revision: captured, value: result));
        }
      } catch (_, stack) {
        invalidate(stack);
      }
    }

    void sectionError(ReviewQueue queue, Object error, [StackTrace? stack]) {
      if (retired) return;
      if (error is ReviewCenterReadException &&
          error.code == ReviewReadFailureCode.ownerInvalidated) {
        invalidate(stack);
        return;
      }
      const unavailable = ReviewQueueUnavailable(
        code: ReviewReadFailureCode.readFailed,
      );
      switch (queue) {
        case ReviewQueue.due:
        case ReviewQueue.incorrect:
          ordinary = null;
          states[ReviewQueue.due] = unavailable;
          states[ReviewQueue.incorrect] = unavailable;
          unawaited(ordinarySubscription?.cancel());
          break;
        case ReviewQueue.saved:
          saved = null;
          states[ReviewQueue.saved] = unavailable;
          unawaited(savedSubscription?.cancel());
          break;
        case ReviewQueue.reported:
          reports = null;
          states[ReviewQueue.reported] = unavailable;
          unawaited(reportSubscription?.cancel());
          break;
      }
      unawaited(publish());
    }

    Future<void> startSources() async {
      if (started || retired) return;
      started = true;
      try {
        await requireReviewReadOwner(
          queries.database,
          expectedOwnerId: expectedOwnerId,
          stillCurrent: () => !retired && stillCurrent(),
        );
        final now = nowUtc();
        if (!now.isUtc || now.microsecondsSinceEpoch < 0) {
          throw ArgumentError('Review clock must be nonnegative UTC');
        }
        evaluatedAt = DateTime.fromMillisecondsSinceEpoch(
          now.millisecondsSinceEpoch,
          isUtc: true,
        );
        if (retired) return;
        unawaited(publish());
        try {
          ordinarySubscription = queries
              .watchOwner(
                expectedOwnerId: expectedOwnerId,
                evaluatedAtUtc: evaluatedAt!,
                stillCurrent: () => !retired && stillCurrent(),
              )
              .listen(
                (facts) {
                  if (retired ||
                      states[ReviewQueue.due] is ReviewQueueUnavailable) {
                    return;
                  }
                  if (facts.ownerId != expectedOwnerId) {
                    invalidate();
                    return;
                  }
                  if (facts.evaluatedAtUtc != evaluatedAt) {
                    sectionError(
                      ReviewQueue.due,
                      const FormatException('Invalid review cutoff'),
                    );
                    return;
                  }
                  ordinary = facts;
                  states[ReviewQueue.due] = ReviewQueueReady(count: 0);
                  states[ReviewQueue.incorrect] = ReviewQueueReady(count: 0);
                  unawaited(publish());
                },
                onError: (Object error, StackTrace stack) =>
                    sectionError(ReviewQueue.due, error, stack),
                onDone: () => sectionError(
                  ReviewQueue.due,
                  const ReviewCenterReadException(
                    ReviewReadFailureCode.readFailed,
                  ),
                ),
              );
        } catch (error, stack) {
          sectionError(ReviewQueue.due, error, stack);
        }
        if (retired) {
          unawaited(ordinarySubscription?.cancel());
          return;
        }
        try {
          savedSubscription = savedWords
              .watchOwner(expectedOwnerId)
              .listen(
                (facts) {
                  if (retired ||
                      states[ReviewQueue.saved] is ReviewQueueUnavailable) {
                    return;
                  }
                  if (facts.ownerId != expectedOwnerId) {
                    invalidate();
                    return;
                  }
                  saved = facts;
                  states[ReviewQueue.saved] = ReviewQueueReady(count: 0);
                  unawaited(publish());
                },
                onError: (Object error, StackTrace stack) =>
                    sectionError(ReviewQueue.saved, error, stack),
                onDone: () => sectionError(
                  ReviewQueue.saved,
                  const ReviewCenterReadException(
                    ReviewReadFailureCode.readFailed,
                  ),
                ),
              );
        } catch (error, stack) {
          sectionError(ReviewQueue.saved, error, stack);
        }
        if (retired) {
          unawaited(savedSubscription?.cancel());
          return;
        }
        try {
          reportSubscription = wordReports
              .watchOwner(expectedOwnerId)
              .listen(
                (facts) {
                  if (retired ||
                      states[ReviewQueue.reported] is ReviewQueueUnavailable) {
                    return;
                  }
                  if (facts.any((row) => row.ownerId != expectedOwnerId)) {
                    invalidate();
                    return;
                  }
                  if (facts.map((row) => row.id).toSet().length !=
                      facts.length) {
                    sectionError(
                      ReviewQueue.reported,
                      const FormatException('Duplicate review receipt'),
                    );
                    return;
                  }
                  reports = List.unmodifiable(facts);
                  states[ReviewQueue.reported] = ReviewQueueReady(count: 0);
                  unawaited(publish());
                },
                onError: (Object error, StackTrace stack) =>
                    sectionError(ReviewQueue.reported, error, stack),
                onDone: () => sectionError(
                  ReviewQueue.reported,
                  const ReviewCenterReadException(
                    ReviewReadFailureCode.readFailed,
                  ),
                ),
              );
        } catch (error, stack) {
          sectionError(ReviewQueue.reported, error, stack);
        }
        if (retired) {
          unawaited(reportSubscription?.cancel());
          return;
        }
      } catch (_, stack) {
        invalidate(stack);
      }
    }

    void begin() {
      ownerSubscription = progress.watchActiveOwnerId().listen(
        (ownerId) {
          if (retired) return;
          if (ownerId != expectedOwnerId) {
            invalidate();
            return;
          }
          unawaited(startSources());
        },
        onError: (Object _, StackTrace stack) => invalidate(stack),
        onDone: invalidate,
      );
    }

    output = StreamController<_QueuedReviewSnapshot>(
      onListen: begin,
      onCancel: cancel,
    );
    return output.stream.transform(
      StreamTransformer<
        _QueuedReviewSnapshot,
        ReviewCenterSnapshot
      >.fromHandlers(
        handleData: (event, sink) {
          if (retired) return;
          try {
            if (!stillCurrent()) {
              invalidate();
              return;
            }
            if (event.revision == revision) sink.add(event.value);
          } catch (_, stack) {
            invalidate(stack);
          }
        },
      ),
    );
  }

  ReviewCenterSnapshot _snapshot(
    String ownerId,
    DateTime evaluatedAt,
    ReviewReadFacts? ordinary,
    SavedWordsSnapshot? saved,
    List<StoredWordReport>? reports,
    Map<ReviewQueue, ReviewQueueState> states,
  ) {
    final words = {
      for (final row in ordinary?.wordRows ?? <ReviewWordRow>[])
        row.wordId: row,
    };
    for (final item in saved?.savedItems ?? <SavedWordItem>[]) {
      final previous = words[item.wordId];
      var word = item.word;
      var category = item.categoryName;
      if (previous != null &&
          (!_sameWord(previous.word, item.word) ||
              previous.categoryName != item.categoryName)) {
        word = null;
        category = null;
      }
      words[item.wordId] = ReviewWordRow(
        ownerId: ownerId,
        wordId: item.wordId,
        word: word,
        categoryName: category,
        reasons: [
          ...?previous?.reasons,
          SavedReason(state: item.state),
        ],
      );
    }
    final rows = words.values.toList();
    final reportRows = [
      for (final report in reports ?? <StoredWordReport>[])
        ReviewReportRow(report: report),
    ];
    return ReviewCenterSnapshot(
      ownerId: ownerId,
      evaluatedAtUtc: evaluatedAt,
      wordRows: rows,
      reportRows: reportRows,
      queueStates: {
        for (final queue in ReviewQueue.values)
          queue: states[queue] is ReviewQueueReady
              ? ReviewQueueReady(
                  count: queue == ReviewQueue.reported
                      ? reportRows.length
                      : rows.where((row) => row.queues.contains(queue)).length,
                )
              : states[queue]!,
      },
    );
  }
}

typedef _QueuedReviewSnapshot = ({int revision, ReviewCenterSnapshot value});

bool _sameWord(VocabularyWord? a, VocabularyWord? b) {
  if (a == null || b == null) return a == null && b == null;
  return (
        a.id,
        a.ownerId,
        a.categoryId,
        a.spelling,
        a.normalizedSpelling,
        a.meaning,
        a.normalizedMeaning,
        a.partOfSpeech,
        a.cefrLevel,
        a.source,
        a.isGlobal,
        a.localRevision,
        a.isDeleted,
        a.createdAtUtc,
        a.updatedAtUtc,
      ) ==
      (
        b.id,
        b.ownerId,
        b.categoryId,
        b.spelling,
        b.normalizedSpelling,
        b.meaning,
        b.normalizedMeaning,
        b.partOfSpeech,
        b.cefrLevel,
        b.source,
        b.isGlobal,
        b.localRevision,
        b.isDeleted,
        b.createdAtUtc,
        b.updatedAtUtc,
      );
}
