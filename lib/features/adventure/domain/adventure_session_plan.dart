import '../../learning/domain/lesson_mode.dart';
import '../../learning/domain/session_configuration.dart';
import '../../learning_packs/domain/content_manifest.dart';
import 'adventure_entry.dart';

enum AdventureSessionPlanFailure {
  ownerMismatch,
  staleSource,
  unresolvedContent,
  incompatibleConfiguration,
  unavailableEntry,
}

final class AdventureSessionPlanException implements Exception {
  const AdventureSessionPlanException(this.reason, [this.detail]);

  final AdventureSessionPlanFailure reason;
  final String? detail;

  @override
  String toString() =>
      'AdventureSessionPlanException(${reason.name}${detail == null ? '' : ': $detail'})';
}

final class AdventureOriginContextV1 {
  const AdventureOriginContextV1({
    required this.planId,
    required this.nodeId,
    required this.catalogId,
    required this.catalogVersion,
    required this.catalogSchemaVersion,
    required this.presentation,
  });

  static const int schemaVersion = 1;

  final String planId;
  final String nodeId;
  final String catalogId;
  final String catalogVersion;
  final int catalogSchemaVersion;
  final TodayExperiencePresentation presentation;

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'planId': planId,
    'nodeId': nodeId,
    'catalogId': catalogId,
    'catalogVersion': catalogVersion,
    'catalogSchemaVersion': catalogSchemaVersion,
    'presentation': presentation.wireName,
  };
}

final class AdventureSessionPlanV1 {
  AdventureSessionPlanV1({
    required this.planId,
    required this.ownerId,
    required this.createdAtUtc,
    required this.sourceEvaluatedAtUtc,
    required List<ContentIdentity> content,
    required Map<String, String> contentChecksumsSha256,
    required this.mode,
    required this.configuration,
    required this.recommendationPolicyVersion,
    required this.sourceReasonCode,
    required this.learnerOverrideApplied,
    required this.origin,
    this.assignmentId,
    this.treatment,
  }) : content = List<ContentIdentity>.unmodifiable(content),
       contentChecksumsSha256 = Map<String, String>.unmodifiable(
         contentChecksumsSha256,
       ) {
    if (origin.planId != planId) {
      throw ArgumentError('Origin must pin the same Adventure plan identity.');
    }
  }

  final String planId;
  final String ownerId;
  final DateTime createdAtUtc;
  final DateTime sourceEvaluatedAtUtc;
  final List<ContentIdentity> content;
  final Map<String, String> contentChecksumsSha256;
  final LessonMode mode;
  final SessionConfiguration configuration;
  final String recommendationPolicyVersion;
  final String sourceReasonCode;
  final bool learnerOverrideApplied;
  final AdventureOriginContextV1 origin;
  final String? assignmentId;
  final String? treatment;

  Map<String, Object?> toJson() => <String, Object?>{
    'planId': planId,
    'ownerId': ownerId,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'sourceEvaluatedAtUtc': sourceEvaluatedAtUtc.toIso8601String(),
    'content': content
        .map(
          (identity) => <String, Object?>{
            'type': identity.type.name,
            'id': identity.id,
            'revision': identity.revision,
            'checksumSha256': contentChecksumsSha256[identity.id],
          },
        )
        .toList(growable: false),
    'mode': mode.name,
    'configuration': configuration.stableSerialization,
    'recommendationPolicyVersion': recommendationPolicyVersion,
    'sourceReasonCode': sourceReasonCode,
    'learnerOverrideApplied': learnerOverrideApplied,
    'origin': origin.toJson(),
    'assignmentId': assignmentId,
    'treatment': treatment,
  };
}
