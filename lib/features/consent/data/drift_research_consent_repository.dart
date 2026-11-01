import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../domain/research_consent.dart';

final class DriftResearchConsentRepository
    implements AuthoritativeResearchConsentRepository {
  const DriftResearchConsentRepository(this.database, {this.ownerWrites});

  final db.AppDatabase database;
  final DriftOwnerWriteCoordinator? ownerWrites;

  @override
  Future<bool> mirrorAcknowledgement({
    required ResearchConsentStatus expected,
    required ResearchConsentStatus acknowledged,
    required String authSubjectId,
    required bool Function() stillCurrent,
  }) async {
    if (acknowledged.ownerId != expected.ownerId ||
        acknowledged.version != expected.version ||
        acknowledged.decidedAtUtc == null ||
        (acknowledged.accepted && acknowledged.withdrawnAtUtc != null) ||
        (!acknowledged.accepted && acknowledged.withdrawnAtUtc == null)) {
      return false;
    }
    return _authoritativeWrite(
      expected.ownerId,
      authSubjectId,
      stillCurrent,
      () async {
        final current = await load(
          ownerId: expected.ownerId,
          version: expected.version,
        );
        if (current.sameFacts(acknowledged)) return true;
        if (!current.sameFacts(expected) ||
            (current.withdrawnAtUtc != null && acknowledged.accepted)) {
          return false;
        }
        await _replaceStatus(acknowledged);
        return true;
      },
    );
  }

  @override
  Future<bool> withdrawLocally({
    required ResearchConsentStatus expected,
    required DateTime withdrawnAtUtc,
    required String authSubjectId,
    required bool Function() stillCurrent,
  }) => _authoritativeWrite(
    expected.ownerId,
    authSubjectId,
    stillCurrent,
    () async {
      final current = await load(
        ownerId: expected.ownerId,
        version: expected.version,
      );
      if (!current.sameFacts(expected)) return false;
      if (current.withdrawnAtUtc != null) return true;
      final decision = current.decidedAtUtc ?? withdrawnAtUtc;
      await _replaceStatus(
        ResearchConsentStatus(
          ownerId: current.ownerId,
          version: current.version,
          accepted: false,
          decidedAtUtc: decision,
          withdrawnAtUtc: withdrawnAtUtc.isBefore(decision)
              ? decision
              : withdrawnAtUtc,
        ),
      );
      return true;
    },
  );

  Future<bool> _authoritativeWrite(
    String ownerId,
    String authSubjectId,
    bool Function() stillCurrent,
    Future<bool> Function() write,
  ) async {
    final coordinator =
        ownerWrites ??
        DriftOwnerWriteCoordinator(
          database,
          nowUtc: () => DateTime.now().toUtc(),
        );
    if (!identical(coordinator.database, database) ||
        !stillCurrent() ||
        await coordinator.hasAmbientTransaction()) {
      return false;
    }
    return coordinator.writeForActiveOwner(
      expectedOwnerId: ownerId,
      write: () async {
        void requireCurrent() {
          if (!stillCurrent()) {
            throw StateError('Retired research consent command');
          }
        }

        requireCurrent();
        final owner = await (database.select(
          database.localOwners,
        )..where((row) => row.id.equals(ownerId))).getSingleOrNull();
        if (owner == null ||
            owner.firebaseUid != authSubjectId ||
            owner.accountState != 'firebaseBound') {
          return false;
        }
        final result = await write();
        requireCurrent();
        return result;
      },
    );
  }

  Future<void> _replaceStatus(ResearchConsentStatus status) async {
    final decision = status.decidedAtUtc;
    final withdrawal = status.withdrawnAtUtc;
    if (status.version < 1 ||
        decision == null ||
        !decision.isUtc ||
        decision.millisecondsSinceEpoch < 0 ||
        decision.millisecondsSinceEpoch > 8640000000000000 ||
        (withdrawal != null &&
            (!withdrawal.isUtc ||
                withdrawal.millisecondsSinceEpoch < 0 ||
                withdrawal.millisecondsSinceEpoch > 8640000000000000 ||
                withdrawal.isBefore(decision)))) {
      throw const FormatException('Invalid authoritative consent time');
    }
    final updated =
        await (database.update(database.researchConsents)..where(
              (row) =>
                  row.ownerId.equals(status.ownerId) &
                  row.consentVersion.equals(status.version),
            ))
            .write(
              db.ResearchConsentsCompanion(
                consentState: Value(status.accepted ? 'accepted' : 'withdrawn'),
                decidedAtUtcMs: Value(decision.millisecondsSinceEpoch),
                withdrawnAtUtcMs: Value(withdrawal?.millisecondsSinceEpoch),
              ),
            );
    if (updated == 0) {
      await database
          .into(database.researchConsents)
          .insert(
            db.ResearchConsentsCompanion.insert(
              id: 'consent:${status.ownerId}:${status.version}',
              ownerId: status.ownerId,
              consentVersion: status.version,
              consentState: status.accepted ? 'accepted' : 'withdrawn',
              decidedAtUtcMs: decision.millisecondsSinceEpoch,
              withdrawnAtUtcMs: Value(withdrawal?.millisecondsSinceEpoch),
            ),
          );
    }
  }

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
      final existing =
          await (database.select(database.researchConsents)..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.consentVersion.equals(version),
              ))
              .getSingleOrNull();
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
      if (existing?.consentState == 'withdrawn' ||
          existing?.withdrawnAtUtcMs != null) {
        return false;
      }
      if (existing?.consentState == 'accepted') {
        return true;
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
