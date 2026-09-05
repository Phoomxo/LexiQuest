import '../../../config/adventure_research_runtime_config.dart';
import '../../../data/local/app_database.dart';
import '../../consent/data/drift_research_consent_repository.dart';
import '../data/drift_measurement_opportunity_repository.dart';
import '../data/drift_motivation_measurement_repository.dart';
import '../data/drift_research_participation_repository.dart';
import '../data/research_p256_signature_verifier.dart';
import '../domain/motivation_measurement.dart';
import '../domain/research_permit_document.dart';
import '../domain/research_participation_permit.dart';
import 'motivation_measurement_use_cases.dart';
import 'research_participation_permit_validator.dart';

/// Optional composition, deliberately separate from learning evidence rollout.
final class AdventureResearchRuntime {
  AdventureResearchRuntime({
    required this.participation,
    required this.measurements,
    required this.opportunities,
    required this.consent,
    Future<void> Function(String ownerId)? onLocalMutation,
  }) : useCases = MotivationMeasurementUseCases(
         database: measurements.database,
         measurements: measurements,
         opportunities: opportunities,
         onLocalMutation: onLocalMutation,
       );
  static AdventureResearchRuntime? fromConfig(
    AppDatabase database,
    AdventureResearchRuntimeConfig config, {
    required DateTime Function() nowUtc,
    Future<void> Function(String ownerId)? onLocalMutation,
  }) {
    if (!config.enabled) return null;
    final study = config.study!;
    // Persisted/signed research time is millisecond UTC. Adapt only the system
    // clock, never signed documents or invalid/non-UTC caller timestamps.
    DateTime researchNowUtc() {
      final raw = nowUtc();
      return raw.isUtc && raw.microsecondsSinceEpoch >= 0
          ? DateTime.fromMillisecondsSinceEpoch(
              raw.millisecondsSinceEpoch,
              isUtc: true,
            )
          : raw;
    }

    final participation = DriftResearchParticipationRepository(
      database,
      study: study,
      validator: ResearchParticipationPermitValidator(
        protocolId: study.protocolId,
        protocolVersion: study.protocolVersion,
        signatures: ResearchP256SignatureVerifier(
          publicKeysSec1Hex: config.issuerPublicKeys,
        ),
        receipts: config.receipts ?? config.createReceipts!(database),
      ),
      nowUtc: researchNowUtc,
    );
    final measurements = DriftMotivationMeasurementRepository(
      database,
      study: study,
      participation: participation,
      nowUtc: researchNowUtc,
    );
    return AdventureResearchRuntime(
      participation: participation,
      measurements: measurements,
      opportunities: DriftMeasurementOpportunityRepository(
        database,
        measurements: measurements,
        nowUtc: researchNowUtc,
      ),
      consent: DriftResearchConsentRepository(database),
      onLocalMutation: onLocalMutation,
    );
  }

  final DriftResearchParticipationRepository participation;
  final DriftMotivationMeasurementRepository measurements;
  final DriftMeasurementOpportunityRepository opportunities;
  final DriftResearchConsentRepository consent;
  final MotivationMeasurementUseCases useCases;
  Future<bool> isCurrentOwner(String ownerId) async {
    final owners =
        await (participation.database.select(participation.database.localOwners)
              ..where((o) => o.isActive.equals(true))
              ..limit(2))
            .get();
    return owners.length == 1 && owners.single.id == ownerId;
  }

  Future<void> importDocument(String ownerId, String document) async {
    final permit = decodeResearchPermitDocument(document);
    if (permit.ownerId != ownerId) {
      throw const ResearchCaptureDenied(ResearchCaptureReason.ownerConflict);
    }
    await participation.importPermit(permit);
    await useCases.notifyCommitted(ownerId);
  }

  Future<ResearchParticipationPermit?> currentPermit(String ownerId) async {
    final active = await participation.readActivePermit(
      ownerId: ownerId,
      evaluatedAtUtc: participation.nowUtc(),
    );
    if (active == null) return null;
    try {
      return await participation.database.transaction(
        () async => (await participation.requireParticipant(
          ownerId,
          active.permitId,
        )).permit,
      );
    } on ResearchCaptureDenied {
      return null;
    }
  }

  Future<void> withdraw(String ownerId) async {
    await participation.database.transaction(() async {
      await participation.lockOwner(ownerId);
      await consent.decide(
        ownerId: ownerId,
        version: participation.study.consentVersion,
        accepted: false,
        decidedAtUtc: participation.nowUtc(),
      );
    });
    await useCases.notifyCommitted(ownerId);
  }
}
