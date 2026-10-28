import 'package:drift/drift.dart';
import '../../../data/local/app_database.dart';
import '../data/drift_review_center_reader.dart';
import '../domain/review_queue_item.dart';

/// Authenticates a committed Pair source and exposes its existing Review item.
/// This adapter has no write path, queue, synthetic answer or SRS projection.
final class PairReviewDeferral {
  PairReviewDeferral(this.database)
    : reader = DriftReviewCenterReader(database);
  final AppDatabase database;
  final DriftReviewCenterReader reader;
  Future<ReviewQueueItem?> expose({
    required String ownerId,
    required String sessionId,
    required String wordId,
    required int contentRevision,
    required String answerId,
  }) async {
    final answer =
        await (database.select(database.answerAttempts)..where(
              (r) =>
                  r.id.equals(answerId) &
                  r.ownerId.equals(ownerId) &
                  r.sessionId.equals(sessionId) &
                  r.wordId.equals(wordId),
            ))
            .getSingleOrNull();
    if (answer == null ||
        answer.isCorrect ||
        answer.promptMode != 'matchingPair') {
      return null;
    }
    final items = await reader.compose(
      ReviewQueueFilter(
        ownerId: ownerId,
        evaluatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          answer.occurredAtUtcMs,
          isUtc: true,
        ),
        timezoneId: 'UTC',
        includeReasons: {ReviewQueueReason.incorrectAnswer},
      ),
    );
    for (final item in items) {
      if (item.identity.id == wordId &&
          item.identity.revision == contentRevision &&
          item.provenance.any(
            (p) =>
                p.authority == ReviewQueueAuthority.answerAttempts &&
                p.sourceId == answerId,
          )) {
        return item;
      }
    }
    return null;
  }
}
