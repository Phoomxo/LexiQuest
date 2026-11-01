import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../account_deletion/domain/account_deletion_contracts.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../progress/data/drift_review_center_queries.dart';
import '../domain/motivation_snapshot.dart';

Future<T> withMotivationOwner<T>(
  db.AppDatabase database,
  DriftOwnerWriteCoordinator ownerWrites,
  String ownerId,
  bool Function() stillCurrent,
  Future<T> Function(bool Function() current) operation,
) async {
  var valid = true;
  final changes = database
      .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
      .listen(
        (_) => valid = false,
        onError: (Object _) => valid = false,
        onDone: () => valid = false,
      );
  bool current() => valid && stillCurrent();
  try {
    await requireMotivationOwner(database, ownerWrites, ownerId, current);
    final value = await operation(current);
    await requireMotivationOwner(database, ownerWrites, ownerId, current);
    return value;
  } finally {
    await changes.cancel();
  }
}

Future<void> requireMotivationOwner(
  db.AppDatabase database,
  DriftOwnerWriteCoordinator ownerWrites,
  String ownerId,
  bool Function() current,
) async {
  if (!current()) {
    throw const MotivationException(MotivationFailureCode.ownerChanged);
  }
  await requireReviewReadOwner(
    database,
    expectedOwnerId: ownerId,
    stillCurrent: current,
  );
  final fence = await ownerWrites.inspect();
  if (fence != null &&
      (fence.casToken == null ||
          fence.casToken!.matchesOwner(ownerId) ||
          (fence.cloudReceipt != null &&
              ownerId ==
                  accountDeletionReplacementGuestOwnerId(
                    fence.cloudReceipt!,
                  )))) {
    throw const MotivationException(MotivationFailureCode.unavailable);
  }
  if (!current()) {
    throw const MotivationException(MotivationFailureCode.ownerChanged);
  }
}
