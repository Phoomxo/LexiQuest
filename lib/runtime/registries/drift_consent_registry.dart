import 'package:drift/drift.dart';

import '../../data/local/app_database.dart';
import 'consent_registry.dart';

final class DriftConsentRegistry implements ConsentRegistry {
  const DriftConsentRegistry(this._database);

  final AppDatabase _database;

  @override
  Future<ConsentSnapshot> snapshot({
    required ConsentPurpose purpose,
    required String ownerId,
    required int consentVersion,
  }) async {
    if (purpose != ConsentPurpose.researchDataUpload ||
        !_isCanonical(ownerId) ||
        consentVersion <= 0) {
      return _unknown(
        purpose: purpose,
        ownerId: ownerId,
        consentVersion: consentVersion,
      );
    }

    final row =
        await (_database.select(_database.researchConsents)..where(
              (candidate) =>
                  candidate.ownerId.equals(ownerId) &
                  candidate.consentVersion.equals(consentVersion),
            ))
            .getSingleOrNull();
    if (row == null ||
        row.ownerId != ownerId ||
        row.consentVersion != consentVersion ||
        row.decidedAtUtcMs < 0) {
      return _unknown(
        purpose: purpose,
        ownerId: ownerId,
        consentVersion: consentVersion,
      );
    }

    final decisionUtc = _utc(row.decidedAtUtcMs);
    final withdrawalMs = row.withdrawnAtUtcMs;
    final withdrawalUtc = withdrawalMs == null ? null : _utc(withdrawalMs);
    if (withdrawalMs != null &&
        (withdrawalMs < 0 || withdrawalMs < row.decidedAtUtcMs)) {
      return _unknown(
        purpose: purpose,
        ownerId: ownerId,
        consentVersion: consentVersion,
      );
    }

    final state = switch (row.consentState) {
      'accepted' when withdrawalUtc == null => ConsentState.granted,
      'accepted' => ConsentState.denied,
      'declined' when withdrawalUtc == null => ConsentState.denied,
      'withdrawn' when withdrawalUtc != null => ConsentState.denied,
      _ => ConsentState.unknown,
    };
    if (state == ConsentState.unknown) {
      return _unknown(
        purpose: purpose,
        ownerId: ownerId,
        consentVersion: consentVersion,
      );
    }

    return ConsentSnapshot(
      purpose: purpose,
      ownerId: ownerId,
      consentVersion: consentVersion,
      state: state,
      decisionUtc: decisionUtc,
      withdrawalUtc: withdrawalUtc,
    );
  }
}

ConsentSnapshot _unknown({
  required ConsentPurpose purpose,
  required String ownerId,
  required int consentVersion,
}) {
  return ConsentSnapshot(
    purpose: purpose,
    ownerId: ownerId,
    consentVersion: consentVersion,
    state: ConsentState.unknown,
    decisionUtc: null,
    withdrawalUtc: null,
  );
}

DateTime _utc(int millisecondsSinceEpoch) {
  return DateTime.fromMillisecondsSinceEpoch(
    millisecondsSinceEpoch,
    isUtc: true,
  );
}

bool _isCanonical(String value) {
  return value.isNotEmpty && value == value.trim() && value.runes.length <= 256;
}
