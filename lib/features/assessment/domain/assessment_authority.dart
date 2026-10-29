import '../../research/domain/experiment_assignment.dart';
import '../../research/domain/research_authority_snapshot.dart';
import '../../research/domain/research_operation_authorizer.dart';
import 'assessment_instrument_catalog.dart';
import 'assessment_models.dart';

/// Supplied numeric-to-content binding. This mapping does not establish approval.
final class AssessmentAuthorityMapping {
  AssessmentAuthorityMapping({
    required this.protocolId,
    required this.protocolVersion,
    required this.protocolRevision,
    required this.instrumentId,
    required this.instrumentRevision,
    required this.instrumentVersion,
    required this.formId,
    required this.formVersion,
    required this.formContentRevision,
    required this.instrumentChecksumSha256,
    required this.formChecksumSha256,
    required this.experimentId,
    required this.experimentVersion,
    required this.contentRevision,
  }) {
    for (final pin in <String, String>{
      'protocolId': protocolId,
      'protocolVersion': protocolVersion,
      'instrumentId': instrumentId,
      'instrumentVersion': instrumentVersion,
      'formId': formId,
      'formVersion': formVersion,
      'experimentId': experimentId,
      'contentRevision': contentRevision,
    }.entries) {
      AssessmentRun.validateCanonicalText(pin.value, pin.key);
    }
    for (final pin in <String, int>{
      'protocolRevision': protocolRevision,
      'instrumentRevision': instrumentRevision,
      'formContentRevision': formContentRevision,
      'experimentVersion': experimentVersion,
    }.entries) {
      if (pin.value <= 0) {
        throw ArgumentError.value(pin.value, pin.key, 'must be positive');
      }
    }
    for (final pin in <String, String>{
      'instrumentChecksumSha256': instrumentChecksumSha256,
      'formChecksumSha256': formChecksumSha256,
    }.entries) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(pin.value)) {
        throw ArgumentError.value(
          pin.value,
          pin.key,
          'must be a lowercase SHA-256 digest',
        );
      }
    }
  }

  final String protocolId;
  final String protocolVersion;
  final int protocolRevision;
  final String instrumentId;
  final int instrumentRevision;
  final String instrumentVersion;
  final String formId;
  final String formVersion;
  final int formContentRevision;
  final String instrumentChecksumSha256;
  final String formChecksumSha256;
  final String experimentId;
  final int experimentVersion;
  final String contentRevision;

  /// Integrity and exact configuration matching, not a collection authorization.
  void requireMatches({
    required ResearchAuthorityScope scope,
    required AssessmentInstrumentDefinition definition,
    AssessmentRun? pinnedRun,
  }) {
    AssessmentInstrumentCatalog(entries: [definition]).lookup(
      instrumentId: definition.instrumentId,
      instrumentVersion: definition.instrumentVersion,
      formId: definition.formId,
      formVersion: definition.formVersion,
    );
    final requirements = scope.requirements;
    if (requirements.protocolId != protocolId ||
        requirements.protocolRevision != protocolRevision ||
        scope.protocolVersion != protocolVersion ||
        requirements.instrumentId != instrumentId ||
        requirements.instrumentRevision != instrumentRevision ||
        definition.protocolId != protocolId ||
        definition.instrumentId != instrumentId ||
        definition.instrumentVersion != instrumentVersion ||
        definition.formId != formId ||
        definition.formVersion != formVersion ||
        definition.formContentRevision != formContentRevision ||
        definition.instrumentChecksumSha256 != instrumentChecksumSha256 ||
        definition.formChecksumSha256 != formChecksumSha256 ||
        definition.experimentId != experimentId ||
        definition.experimentVersion != experimentVersion ||
        definition.contentRevision != contentRevision) {
      throw StateError('Assessment authority mapping does not match.');
    }
    if (pinnedRun != null &&
        (pinnedRun.ownerId != scope.binding.ownerId ||
            pinnedRun.assignmentId != requirements.assignmentId ||
            pinnedRun.assignmentRevision != requirements.assignmentRevision ||
            pinnedRun.consentVersion != scope.consentVersion ||
            pinnedRun.protocolId != protocolId ||
            pinnedRun.protocolVersion != protocolVersion ||
            pinnedRun.protocolRevision != protocolRevision ||
            pinnedRun.instrumentId != instrumentId ||
            pinnedRun.instrumentVersion != instrumentVersion ||
            pinnedRun.instrumentRevision != instrumentRevision ||
            pinnedRun.formId != formId ||
            pinnedRun.formVersion != formVersion ||
            pinnedRun.formContentRevision != formContentRevision ||
            pinnedRun.instrumentChecksumSha256 != instrumentChecksumSha256 ||
            pinnedRun.formChecksumSha256 != formChecksumSha256 ||
            pinnedRun.experimentId != experimentId ||
            pinnedRun.experimentVersion != experimentVersion ||
            pinnedRun.contentRevision != contentRevision)) {
      throw StateError('Stored Assessment pins cannot be reinterpreted.');
    }
  }
}

abstract interface class AssessmentAuthority {
  /// Checks current local authority. Content retrieval occurs before the SQL TX.
  Future<AssessmentAuthorityReceipt> requireCurrent({
    required ResearchAuthorityScope expectedScope,
    required AssessmentInstrumentDefinition definition,
    required String expectedParticipationPermitId,
    AssessmentRun? pinnedRun,
  });
}

/// Snapshot of a completed check, never permission for a later write.
/// The verifying data adapter supplies its private implementation.
abstract interface class AssessmentAuthorityReceipt {
  ResearchAuthorityScope get scope;
  AssessmentAuthorityMapping get mapping;
  ExperimentAssignment get assignment;
  DateTime get consentDecidedAtUtc;
  AuthorizedResearchOperation get operation;
  String get participationPermitId;
  int get participationPermitRevision;
  String get participationPermitPayloadSha256;
  DateTime get verifiedAtUtc;
  DateTime get validUntilUtc;
}

abstract interface class AssessmentCycleReader {
  /// Rechecks the exact existing R3 cycle for a new phase-specific capture.
  /// A stored terminal ACK replay does not create another capture.
  Future<AssessmentCycleReceipt> requirePhase({required AssessmentRun run});
}

/// Historical read proof, not continuing permission or an intervention writer.
/// Pre proves no opportunity exists and has no intervention facts. Post supplies
/// all facts from the exact first Presented opportunity and completed first index.
abstract interface class AssessmentCycleReceipt {
  String get ownerId;
  String get studyCycleId;
  AssessmentPhase get phase;
  String? get opportunityId;
  DateTime? get firstExposureAtUtc;
  String? get interventionSessionId;
  DateTime? get interventionStartedAtUtc;
  DateTime? get interventionCompletedAtUtc;
}
