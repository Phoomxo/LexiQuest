import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../learning/domain/session_configuration.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../../recommendation/domain/recommendation_policy.dart';
import '../../today_hub/domain/today_hub_models.dart';
import '../domain/adventure_entry.dart';
import '../domain/adventure_journey.dart';
import '../domain/adventure_session_plan.dart';

abstract interface class AdventureSessionComposer {
  Future<AdventureSessionPlanV1> compose({
    required AdventureMissionRef mission,
    required TodayHubSnapshot today,
    required SessionConfiguration requestedConfiguration,
    required AdventureProductEntryDecision entry,
  });
}

final class CanonicalAdventureSessionComposer
    implements AdventureSessionComposer {
  const CanonicalAdventureSessionComposer();

  @override
  Future<AdventureSessionPlanV1> compose({
    required AdventureMissionRef mission,
    required TodayHubSnapshot today,
    required SessionConfiguration requestedConfiguration,
    required AdventureProductEntryDecision entry,
  }) async {
    if (mission.ownerId != today.ownerId ||
        requestedConfiguration.ownerId != today.ownerId) {
      throw const AdventureSessionPlanException(
        AdventureSessionPlanFailure.ownerMismatch,
      );
    }
    if (mission.sourceEvaluatedAtUtc != today.evaluatedAtUtc) {
      throw const AdventureSessionPlanException(
        AdventureSessionPlanFailure.staleSource,
      );
    }
    if (entry.destination != AdventureEntryDestination.adventure ||
        entry.availability != AdventureAvailability.available) {
      throw const AdventureSessionPlanException(
        AdventureSessionPlanFailure.unavailableEntry,
      );
    }
    if (requestedConfiguration.mode !=
            (mission.suggestedMode ?? requestedConfiguration.mode) ||
        requestedConfiguration.itemCount <= 0 ||
        requestedConfiguration.itemCount > mission.content.length) {
      throw const AdventureSessionPlanException(
        AdventureSessionPlanFailure.incompatibleConfiguration,
      );
    }

    final resolved = <ContentIdentity>[];
    final checksums = <String, String>{};
    for (final identity in mission.content) {
      final matches = today.reviewWork
          .where((work) => work.identity == identity)
          .toList(growable: false);
      if (matches.length != 1) {
        throw AdventureSessionPlanException(
          AdventureSessionPlanFailure.unresolvedContent,
          identity.id,
        );
      }
      final checksum = matches.single.snapshot.coreChecksumSha256;
      if (!_sha256.hasMatch(checksum) || checksums.containsKey(identity.id)) {
        throw AdventureSessionPlanException(
          AdventureSessionPlanFailure.unresolvedContent,
          identity.id,
        );
      }
      resolved.add(identity);
      checksums[identity.id] = checksum;
    }
    final selected = resolved
        .take(requestedConfiguration.itemCount)
        .toList(growable: false);
    final selectedChecksums = <String, String>{
      for (final identity in selected) identity.id: checksums[identity.id]!,
    };
    final planPayload = <String, Object?>{
      'schemaVersion': 1,
      'ownerId': today.ownerId,
      'sourceEvaluatedAtUtc': today.evaluatedAtUtc.toIso8601String(),
      'missionId': mission.missionId,
      'nodeId': mission.nodeId,
      'content': selected
          .map(
            (identity) => <String, Object?>{
              'type': identity.type.name,
              'id': identity.id,
              'revision': identity.revision,
              'checksumSha256': selectedChecksums[identity.id],
            },
          )
          .toList(growable: false),
      'mode': requestedConfiguration.mode.name,
      'configurationIdentity': requestedConfiguration.contentIdentity,
      'recommendationPolicyVersion':
          FlashcardFirstRecommendationPolicy.policyVersion,
      'sourceReasonCode': mission.reasonCode,
      'learnerOverrideApplied': mission.learnerOverrideApplied,
      'catalogId': entry.catalogId,
      'catalogVersion': entry.catalogVersion,
      'catalogSchemaVersion': entry.catalogSchemaVersion,
      'assignmentId': entry.assignmentId,
      'treatment': entry.treatment,
    };
    final planId =
        'adventure-plan:${sha256.convert(utf8.encode(jsonEncode(planPayload)))}';
    final origin = AdventureOriginContextV1(
      planId: planId,
      nodeId: mission.nodeId,
      catalogId: entry.catalogId,
      catalogVersion: entry.catalogVersion,
      catalogSchemaVersion: entry.catalogSchemaVersion,
      presentation: TodayExperiencePresentation.adventure,
    );
    return AdventureSessionPlanV1(
      planId: planId,
      ownerId: today.ownerId,
      createdAtUtc: today.evaluatedAtUtc,
      sourceEvaluatedAtUtc: today.evaluatedAtUtc,
      content: selected,
      contentChecksumsSha256: selectedChecksums,
      mode: requestedConfiguration.mode,
      configuration: requestedConfiguration,
      recommendationPolicyVersion:
          FlashcardFirstRecommendationPolicy.policyVersion,
      sourceReasonCode: mission.reasonCode,
      learnerOverrideApplied: mission.learnerOverrideApplied,
      origin: origin,
      assignmentId: entry.assignmentId,
      treatment: entry.treatment,
    );
  }
}

final RegExp _sha256 = RegExp(r'^[0-9a-f]{64}$');
