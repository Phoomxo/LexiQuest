import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;

import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../learning_time/application/learning_time_use_cases.dart';
import '../data/drift_learning_calendar_queries.dart';
import '../data/drift_learning_history_queries.dart';
import '../data/drift_progress_queries.dart';
import '../data/drift_review_center_queries.dart';
import '../domain/learning_history_models.dart';
import '../domain/learning_calendar.dart';
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

  Future<LearningCalendarSnapshot> loadCalendarForOwner({
    required LearningCalendarPeriod period,
    required String expectedOwnerId,
    required bool Function() stillCurrent,
    LearningTimeUseCases? learningTime,
  }) => _readForOwner(
    expectedOwnerId,
    stillCurrent,
    (now) => queries.database.transaction(() async {
      final facts = await DriftLearningCalendarQueries(
        queries.database,
      ).load(ownerId: expectedOwnerId, period: period, nowUtc: now);
      final days = <LearningCalendarDay>[];
      for (var index = 0; index < facts.days.length; index++) {
        var time = const RecordedTimeRead.unavailable();
        try {
          time =
              await learningTime?.readForOwner(
                ObservedEndRangeTimeRead(
                  startInclusiveUtc: period.dayAt(index).toUtc(),
                  endExclusiveUtc: period.dayAt(index + 1).toUtc(),
                ),
                expectedOwnerId: expectedOwnerId,
                stillCurrent: stillCurrent,
              ) ??
              const RecordedTimeRead.unavailable();
        } on Object {
          time = const RecordedTimeRead.unavailable();
        }
        days.add(facts.days[index].withTime(time));
      }
      return LearningCalendarSnapshot(
        ownerId: expectedOwnerId,
        period: period,
        days: days,
      );
    }),
  );

  Future<T> _readForOwner<T>(
    String expectedOwnerId,
    bool Function() stillCurrent,
    Future<T> Function(DateTime now) read,
  ) async {
    var valid = true;
    final changes = Zone.root
        .run(
          () => queries.database.tableUpdates(
          TableUpdateQuery.allOf([
              TableUpdateQuery.onTable(queries.database.localOwners),
            TableUpdateQuery.onTable(queries.database.runtimeFlags),
            ]),
          ),
        )
        .listen(
          (_) => valid = false,
          onError: (Object _) => valid = false,
          onDone: () => valid = false,
        );
    bool current() => valid && stillCurrent();
    Future<void> requireCurrentOwner() async {
      await requireReviewReadOwner(
        queries.database,
        expectedOwnerId: expectedOwnerId,
        stillCurrent: current,
      );
      final fence = await DriftOwnerWriteCoordinator(
        queries.database,
        nowUtc: nowUtc,
      ).inspect();
      if (!current() ||
          (fence != null &&
              (fence.casToken == null ||
                  fence.casToken!.matchesOwner(expectedOwnerId) ||
                  (fence.cloudReceipt != null &&
                      accountDeletionReplacementGuestOwnerId(
                            fence.cloudReceipt!,
                          ) ==
                          expectedOwnerId)))) {
        throw const ReviewCenterReadException(
          ReviewReadFailureCode.ownerInvalidated,
        );
      }
    }

    late final T result;
    try {
      await requireCurrentOwner();
      final now = nowUtc();
      if (!now.isUtc || now.microsecondsSinceEpoch < 0) {
        throw ArgumentError('Progress clock must be nonnegative UTC');
      }
      result = await read(now);
      await requireCurrentOwner();
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
