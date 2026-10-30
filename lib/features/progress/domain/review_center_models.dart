import '../../vocabulary/domain/saved_words.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../../vocabulary/domain/word_report.dart';

enum ReviewQueue { due, incorrect, saved, reported }

sealed class ReviewWordReason {
  const ReviewWordReason();
  ReviewQueue get queue;
}

final class DueReason extends ReviewWordReason {
  DueReason({required this.dueAtUtc}) {
    _time(dueAtUtc);
  }
  final DateTime dueAtUtc;
  @override
  ReviewQueue get queue => ReviewQueue.due;
}

final class IncorrectReason extends ReviewWordReason {
  IncorrectReason({
    required this.incorrectCount,
    required this.lastIncorrectAtUtc,
  }) {
    if (incorrectCount < 1) throw ArgumentError('Invalid incorrect count');
    _time(lastIncorrectAtUtc);
  }
  final int incorrectCount;
  final DateTime lastIncorrectAtUtc;
  @override
  ReviewQueue get queue => ReviewQueue.incorrect;
}

final class SavedReason extends ReviewWordReason {
  SavedReason({required this.state}) {
    if (!state.isSaved) {
      throw ArgumentError('A tombstone is not a review reason');
    }
  }
  final StoredSavedWordState state;
  @override
  ReviewQueue get queue => ReviewQueue.saved;
}

final class ReviewWordRow {
  ReviewWordRow({
    required this.ownerId,
    required this.wordId,
    this.word,
    this.categoryName,
    required Iterable<ReviewWordReason> reasons,
  }) : reasons = List.unmodifiable(reasons) {
    _id(ownerId);
    _id(wordId);
    final current = word;
    if ((current == null) != (categoryName == null) ||
        (current != null &&
            (current.id != wordId ||
                current.ownerId != ownerId ||
                current.isDeleted))) {
      throw ArgumentError('Invalid current review word');
    }
    final kinds = <ReviewQueue>{};
    for (final reason in this.reasons) {
      if (!kinds.add(reason.queue)) {
        throw ArgumentError('Duplicate review reason');
      }
      if (reason case SavedReason(:final state)) {
        if (state.ownerId != ownerId || state.wordId != wordId) {
          throw ArgumentError('Foreign saved-word reason');
        }
      }
    }
    if (kinds.isEmpty) throw ArgumentError('A review word needs a reason');
  }

  final String ownerId;
  final String wordId;
  final VocabularyWord? word;
  final String? categoryName;
  final List<ReviewWordReason> reasons;
  bool get isEligible => word != null;
  Set<ReviewQueue> get queues =>
      Set.unmodifiable(reasons.map((reason) => reason.queue));
}

final class ReviewReportRow {
  const ReviewReportRow({required this.report});
  final StoredWordReport report;
  String get reportId => report.id;
}

final class ReviewReadFacts {
  ReviewReadFacts({
    required this.ownerId,
    required this.evaluatedAtUtc,
    required Iterable<ReviewWordRow> wordRows,
  }) : wordRows = List.unmodifiable(wordRows) {
    _id(ownerId);
    _time(evaluatedAtUtc);
    _rows(ownerId, this.wordRows);
    for (final row in this.wordRows) {
      for (final reason in row.reasons) {
        if (reason is SavedReason || (reason is DueReason && !row.isEligible)) {
          throw ArgumentError('Invalid ordinary review facts');
        }
      }
    }
  }
  final String ownerId;
  final DateTime evaluatedAtUtc;
  final List<ReviewWordRow> wordRows;
}

sealed class ReviewQueueState {
  const ReviewQueueState();
}

final class ReviewQueueLoading extends ReviewQueueState {
  const ReviewQueueLoading();
}

final class ReviewQueueReady extends ReviewQueueState {
  ReviewQueueReady({required this.count}) {
    if (count < 0) throw ArgumentError('Invalid review count');
  }
  final int count;
}

enum ReviewReadFailureCode {
  dependencyUnavailable,
  readFailed,
  ownerInvalidated,
}

final class ReviewQueueUnavailable extends ReviewQueueState {
  const ReviewQueueUnavailable({required this.code});
  final ReviewReadFailureCode code;
}

final class ReviewCenterReadException implements Exception {
  const ReviewCenterReadException(this.code);
  final ReviewReadFailureCode code;
  @override
  String toString() => 'ReviewCenterReadException(${code.name})';
}

final class ReviewCenterSnapshot {
  ReviewCenterSnapshot({
    required this.ownerId,
    required this.evaluatedAtUtc,
    required Iterable<ReviewWordRow> wordRows,
    required Iterable<ReviewReportRow> reportRows,
    required Map<ReviewQueue, ReviewQueueState> queueStates,
  }) : wordRows = List.unmodifiable(wordRows),
       reportRows = List.unmodifiable(reportRows),
       queueStates = Map.unmodifiable(queueStates) {
    _id(ownerId);
    _time(evaluatedAtUtc);
    _rows(ownerId, this.wordRows);
    if (this.queueStates.length != ReviewQueue.values.length ||
        !ReviewQueue.values.every(this.queueStates.containsKey)) {
      throw ArgumentError('Incomplete review sections');
    }
    final reports = <String>{};
    for (final row in this.reportRows) {
      if (row.report.ownerId != ownerId || !reports.add(row.reportId)) {
        throw ArgumentError('Invalid review receipts');
      }
    }
    for (final queue in ReviewQueue.values) {
      final count = queue == ReviewQueue.reported
          ? this.reportRows.length
          : this.wordRows.where((row) => row.queues.contains(queue)).length;
      final state = this.queueStates[queue]!;
      if ((state is ReviewQueueReady && state.count != count) ||
          (state is! ReviewQueueReady && count != 0)) {
        throw ArgumentError('Review section facts do not match its state');
      }
    }
  }

  final String ownerId;
  final DateTime evaluatedAtUtc;
  final List<ReviewWordRow> wordRows;
  final List<ReviewReportRow> reportRows;
  final Map<ReviewQueue, ReviewQueueState> queueStates;
  int get distinctWordCount => wordRows.length;
  int get eligibleWordCount => wordRows.where((row) => row.isEligible).length;
  int get unavailableWordCount => distinctWordCount - eligibleWordCount;
  int get reportCount => reportRows.length;
}

void _rows(String ownerId, Iterable<ReviewWordRow> rows) {
  final ids = <String>{};
  for (final row in rows) {
    if (row.ownerId != ownerId || !ids.add(row.wordId)) {
      throw ArgumentError('Invalid review word rows');
    }
  }
}

void _id(String value) {
  if (value.trim().isEmpty || value.runes.length > 256) {
    throw ArgumentError('Invalid review identifier');
  }
}

void _time(DateTime value) {
  if (!value.isUtc ||
      value.microsecondsSinceEpoch < 0 ||
      value.microsecondsSinceEpoch % 1000 != 0) {
    throw ArgumentError('Review time must be nonnegative UTC milliseconds');
  }
}
