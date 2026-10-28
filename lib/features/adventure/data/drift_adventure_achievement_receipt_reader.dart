import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../application/adventure_motivation_projection_reader.dart';

/// Read-only Drift adapter for already-committed achievement receipts.
final class DriftAdventureAchievementReceiptReader
    implements AdventureAchievementReceiptReader {
  const DriftAdventureAchievementReceiptReader(this._database);

  final AppDatabase _database;

  @override
  Future<List<AdventureAchievementReceipt>> readForSourceEvent({
    required String ownerId,
    required String sourceEventId,
  }) async {
    final rows =
        await (_database.select(_database.achievementUnlocks)
              ..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.sourceEventId.equals(sourceEventId),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.unlockedAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    return List<AdventureAchievementReceipt>.unmodifiable(
      rows.map(
        (row) => AdventureAchievementReceipt(
          receiptId: row.id,
          achievementId: row.achievementId,
        ),
      ),
    );
  }
}
