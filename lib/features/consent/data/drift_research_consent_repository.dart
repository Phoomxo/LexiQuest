import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/research_consent.dart';

final class DriftResearchConsentRepository
    implements ResearchConsentRepository {
  const DriftResearchConsentRepository(this.database);

  final db.AppDatabase database;

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) async {
    final row =
        await (database.select(database.researchConsents)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.consentVersion.equals(version),
            ))
            .getSingleOrNull();
    return ResearchConsentStatus(
      version: version,
      accepted: row?.consentState == 'accepted',
      decidedAtUtc: row == null ? null : _utc(row.decidedAtUtcMs),
      withdrawnAtUtc: row?.withdrawnAtUtcMs == null
          ? null
          : _utc(row!.withdrawnAtUtcMs!),
    );
  }

  @override
  Future<void> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) {
    final epoch = decidedAtUtc.millisecondsSinceEpoch;
    return database.transaction(() async {
      await (database.delete(database.researchConsents)..where(
            (row) =>
                row.ownerId.equals(ownerId) &
                row.consentVersion.equals(version),
          ))
          .go();
      await database
          .into(database.researchConsents)
          .insert(
            db.ResearchConsentsCompanion.insert(
              id: 'consent:$ownerId:$version',
              ownerId: ownerId,
              consentVersion: version,
              consentState: accepted ? 'accepted' : 'withdrawn',
              decidedAtUtcMs: epoch,
              withdrawnAtUtcMs: Value(accepted ? null : epoch),
            ),
          );
    });
  }
}

DateTime _utc(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);
