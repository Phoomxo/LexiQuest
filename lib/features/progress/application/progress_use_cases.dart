import 'package:drift/drift.dart' show TableUpdateQuery;

import '../../identity/domain/local_owner_repository.dart';
import '../data/drift_learning_history_queries.dart';
import '../data/drift_progress_queries.dart';
import '../domain/learning_history_models.dart';
import '../domain/progress_models.dart';

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
