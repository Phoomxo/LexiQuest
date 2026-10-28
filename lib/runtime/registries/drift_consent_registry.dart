import '../../features/consent/domain/research_consent.dart';
import 'consent_registry.dart';

final class DriftConsentRegistry implements ConsentRegistry {
  const DriftConsentRegistry(this._repository);

  final ResearchConsentRepository _repository;

  @override
  Future<ConsentSnapshot> snapshot({
    required ConsentPurpose purpose,
    required String ownerId,
    required int consentVersion,
  }) async {
    final unknown = ConsentSnapshot(
      purpose: purpose,
      ownerId: ownerId,
      consentVersion: consentVersion,
      state: ConsentState.unknown,
      decisionUtc: null,
      withdrawalUtc: null,
    );
    if (purpose != ConsentPurpose.researchDataUpload ||
        ownerId.isEmpty ||
        ownerId != ownerId.trim() ||
        ownerId.runes.length > 256 ||
        consentVersion <= 0) {
      return unknown;
    }

    try {
      final consent = await _repository.load(
        ownerId: ownerId,
        version: consentVersion,
      );
      final decision = consent.decidedAtUtc;
      final withdrawal = consent.withdrawnAtUtc;
      if (consent.ownerId != ownerId ||
          consent.version != consentVersion ||
          decision == null ||
          !_canonicalUtc(decision) ||
          (withdrawal != null &&
              (!_canonicalUtc(withdrawal) || withdrawal.isBefore(decision)))) {
        return unknown;
      }
      return ConsentSnapshot(
        purpose: purpose,
        ownerId: ownerId,
        consentVersion: consentVersion,
        state: consent.accepted && withdrawal == null
            ? ConsentState.granted
            : ConsentState.denied,
        decisionUtc: decision,
        withdrawalUtc: withdrawal,
      );
    } on Object {
      return unknown;
    }
  }
}

bool _canonicalUtc(DateTime value) =>
    value.isUtc &&
    value.millisecondsSinceEpoch >= 0 &&
    value.microsecondsSinceEpoch % 1000 == 0;
