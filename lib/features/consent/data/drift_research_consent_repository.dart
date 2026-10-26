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
      ownerId: ownerId,
      version: version,
      accepted: row?.consentState == 'accepted',
      decidedAtUtc: row == null ? null : _utc(row.decidedAtUtcMs),
      withdrawnAtUtc: row?.withdrawnAtUtcMs == null
          ? null
          : _utc(row!.withdrawnAtUtcMs!),
    );
  }

  @override
  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) {
    final epoch = decidedAtUtc.millisecondsSinceEpoch;
    return database.transaction(() async {
      final activeOwners =
          await (database.select(database.localOwners)
                ..where((row) => row.isActive.equals(true))
                ..limit(2))
              .get();
      if (activeOwners.length != 1 || activeOwners.single.id != ownerId) {
        return false;
      }
      if (!accepted) {
        final updated =
            await (database.update(database.researchConsents)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.consentVersion.equals(version) &
                      row.consentState.equals('accepted'),
                ))
                .write(
                  db.ResearchConsentsCompanion(
                    consentState: const Value('withdrawn'),
                    decidedAtUtcMs: Value(epoch),
                    withdrawnAtUtcMs: Value(epoch),
                  ),
                );
        return updated == 1;
      }
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
              consentState: 'accepted',
              decidedAtUtcMs: epoch,
            ),
          );
      return true;
    });
  }
}

DateTime _utc(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);
