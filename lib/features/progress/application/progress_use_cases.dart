import 'package:drift/drift.dart' show TableUpdateQuery;

import '../../identity/domain/local_owner_repository.dart';
import '../data/drift_learning_history_queries.dart';
import '../data/drift_progress_queries.dart';
import '../data/drift_review_center_queries.dart';
import '../domain/learning_history_models.dart';
import '../domain/progress_models.dart';
import '../domain/review_center_models.dart';

typedef ProgressUtcNow = DateTime Function();

final class ProgressUseCases {
  const ProgressUseCases({
    required this.owners,
    required this.queries,
    required this.nowUtc,
  });

  final LocalOwnerRepository owners;
  final DriftProgressQueries queries;
  final ProgressUtcNow nowUtc;

  Future<ProgressSnapshot> load() async {
    final owner = await owners.getOrCreateActiveOwner();
    final now = nowUtc();
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'nowUtc', 'must be UTC');
    }
    return queries.load(ownerId: owner.id, nowUtc: now);
  }

  Future<LearningHistorySnapshot> loadHistory({
    LearningHistoryCursor? before,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    if (before != null && before.ownerId != owner.id) {
      throw LearningHistoryOwnerChanged();
    }
    final result = await DriftLearningHistoryQueries(
      queries.database,
    ).load(ownerId: owner.id, nowUtc: nowUtc(), before: before);
    final currentOwner = await owners.getOrCreateActiveOwner();
    if (currentOwner.id != owner.id) {
      throw LearningHistoryOwnerChanged();
    }
    return result;
  }

  Future<ProgressSnapshot> loadForOwner({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => _readForOwner(
    expectedOwnerId,
    stillCurrent,
    (now) => queries.load(ownerId: expectedOwnerId, nowUtc: now),
  );

  Future<LearningHistorySnapshot> loadHistoryForOwner({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
    LearningHistoryCursor? before,
  }) async {
    if (before != null && before.ownerId != expectedOwnerId) {
      throw LearningHistoryOwnerChanged();
    }
    return _readForOwner(
      expectedOwnerId,
      stillCurrent,
      (now) => DriftLearningHistoryQueries(
        queries.database,
      ).load(ownerId: expectedOwnerId, nowUtc: now, before: before),
    );
  }

  Future<T> _readForOwner<T>(
    String expectedOwnerId,
    bool Function() stillCurrent,
    Future<T> Function(DateTime now) read,
  ) async {
    var valid = true;
    final changes = queries.database
        .tableUpdates(TableUpdateQuery.onTable(queries.database.localOwners))
        .listen(
          (_) => valid = false,
          onError: (Object _) => valid = false,
          onDone: () => valid = false,
        );
    bool current() => valid && stillCurrent();
    late final T result;
    try {
      await requireReviewReadOwner(
        queries.database,
        expectedOwnerId: expectedOwnerId,
        stillCurrent: current,
      );
      final now = nowUtc();
      if (!now.isUtc || now.microsecondsSinceEpoch < 0) {
        throw ArgumentError('Progress clock must be nonnegative UTC');
      }
      result = await read(now);
      await requireReviewReadOwner(
        queries.database,
        expectedOwnerId: expectedOwnerId,
        stillCurrent: current,
      );
    } finally {
      await changes.cancel();
    }
    if (!current()) {
      throw const ReviewCenterReadException(
        ReviewReadFailureCode.ownerInvalidated,
      );
    }
    return result;
  }

  Stream<String?> watchActiveOwnerId() => Stream<String?>.multi((events) {
    final database = queries.database;
    // Owner snapshots can coalesce A→B→A; invalidate before reading the new owner.
    final changes = database
        .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
        .listen((_) => events.add(null), onError: events.addError);
    final owners =
        (database.select(database.localOwners)
              ..where((owner) => owner.isActive.equals(true))
              ..limit(1))
            .watchSingleOrNull()
            .listen(
              (owner) => events.add(owner?.id),
              onError: events.addError,
              onDone: events.close,
            );
    events.onCancel = () async {
      await Future.wait([changes.cancel(), owners.cancel()]);
    };
  }, isBroadcast: true).distinct();
}
