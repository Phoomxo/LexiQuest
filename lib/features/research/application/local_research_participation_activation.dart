import 'dart:convert';

import '../../assessment/data/drift_assessment_repository.dart';
import '../data/drift_motivation_measurement_repository.dart';
import '../data/local_research_authority_cache.dart';
import '../domain/motivation_study_protocol.dart';
import '../domain/research_authority_snapshot.dart';
import '../domain/research_operation_authorizer.dart';
import '../domain/research_transport_contracts.dart';
import 'local_study_runtime.dart';
import 'research_authority_lifecycle.dart';

/// Explicit local admission of an already provisioned, issuer-signed Study.
final class LocalResearchParticipationActivation {
  LocalResearchParticipationActivation({
    required this.study,
    required this.lifecycle,
    required this.participationPermitId,
  }) {
    final motivation = study.authorities.permits;
    if (motivation is! LocalResearchAuthorityCache ||
        !lifecycle.caches.contains(motivation) ||
        !identical(motivation.ownerWrites, study.context.ownerWrites)) {
      throw ArgumentError('Activation must share the actual Study authority');
    }
  }

  final LocalStudyRuntime study;
  final ResearchAuthorityLifecycle lifecycle;
  final String? Function(ResearchAuthorityBinding binding)
  participationPermitId;

  Future<bool> activate({
    required ResearchAuthorityBinding expectedBinding,
    required bool Function() stillCurrent,
  }) async {
    try {
      final motivation =
          study.authorities.permits as LocalResearchAuthorityCache;
      final writer = study.assessment?.repository;
      if (writer is! DriftAssessmentRepository) return false;
      final assessment = writer.authority.cache;
      final motivationScope = motivation.currentScope();
      final assessmentScope = assessment.currentScope();
      if (!lifecycle.caches.contains(assessment) ||
          identical(motivation, assessment) ||
          !identical(assessment.ownerWrites, study.context.ownerWrites) ||
          motivationScope?.binding != expectedBinding ||
          assessmentScope?.binding != expectedBinding ||
          motivationScope!.requirements.instrumentId ==
              assessmentScope!.requirements.instrumentId) {
        return false;
      }
      final generation = lifecycle.generation;
      final motivationGeneration = motivation.readGeneration;
      final assessmentGeneration = assessment.readGeneration;
      bool current() =>
          stillCurrent() &&
          lifecycle.readGate.isOpen &&
          lifecycle.generation == generation &&
          motivation.readGeneration == motivationGeneration &&
          assessment.readGeneration == assessmentGeneration &&
          motivation.currentScope() == motivationScope &&
          assessment.currentScope() == assessmentScope;
      void requireCurrent() {
        if (!current()) {
          throw const ResearchTransportException(
            ResearchTransportFailureCode.ownerChanged,
          );
        }
      }

      requireCurrent();
      final permitId = participationPermitId(expectedBinding);
      if (permitId == null) return false;
      requireResearchCode(permitId);
      if (await study.context.ownerWrites.hasAmbientTransaction()) return false;
      requireCurrent();
      Future<void> authorize() async {
        for (final cache in [motivation, assessment]) {
          final scope = cache.currentScope();
          if (scope == null) {
            throw const ResearchTransportException(
              ResearchTransportFailureCode.denied,
            );
          }
          final grant =
              await SignedPermitResearchOperationAuthorizer(
                permits: cache,
                states: cache,
                verifier: cache.operationSignatures,
                requirements: scope.requirements,
                trustedTime: cache,
              ).authorizeWithReceipt(
                ownerId: expectedBinding.ownerId,
                operation: ResearchOperation.collect,
              );
          requireCurrent();
          if (grant == null) {
            throw const ResearchTransportException(
              ResearchTransportFailureCode.denied,
            );
          }
        }
      }

      return await study.context.ownerWrites.writeForActiveOwner(
        expectedOwnerId: expectedBinding.ownerId,
        write: () async {
          requireCurrent();
          await authorize();
          final permit = await motivation.loadCurrent(
            ownerId: expectedBinding.ownerId,
            permitId: permitId,
          );
          requireCurrent();
          final other = await assessment.loadCurrent(
            ownerId: expectedBinding.ownerId,
            permitId: permitId,
          );
          requireCurrent();
          if (permit == null ||
              other == null ||
              permit.payloadSha256 != other.payloadSha256 ||
              permit.canonicalPayload() != other.canonicalPayload()) {
            throw const ResearchTransportException(
              ResearchTransportFailureCode.denied,
            );
          }
          final measurements =
              study.measurementsFor(expectedBinding.ownerId)
                  as DriftMotivationMeasurementRepository;
          final imported = await measurements.participation.importDocument(
            ownerId: expectedBinding.ownerId,
            document: jsonEncode({
              ...(jsonDecode(permit.canonicalPayload())
                  as Map<String, dynamic>),
              'payloadSha256': permit.payloadSha256,
              'signature': permit.signature,
            }),
          );
          if (!imported) {
            throw const ResearchTransportException(
              ResearchTransportFailureCode.denied,
            );
          }
          await authorize();
          requireCurrent();
          return true;
        },
      );
    } on Object {
      return false;
    }
  }
}
