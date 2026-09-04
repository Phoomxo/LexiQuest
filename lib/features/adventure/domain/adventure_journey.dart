import '../../learning_packs/domain/content_manifest.dart';
import '../../learning/domain/lesson_mode.dart';
import '../../today_hub/domain/today_hub_models.dart';
import 'adventure_world_catalog.dart';

enum AdventureNodeState {
  hidden,
  locked,
  available,
  current,
  completed,
  unavailable,
}

enum AdventureSnapshotFreshness { current, stale, unavailable, corrupt }

enum AdventureJourneyAuthority {
  today,
  quest,
  streak,
  achievement,
  reward,
  history,
  packCompletion,
}

enum AdventureJourneyDependencyState {
  ready,
  empty,
  stale,
  unavailable,
  corrupt,
}

enum AdventureMissionKind { resume, review, recommendation }

final class AdventureMissionRef {
  AdventureMissionRef({
    required this.missionId,
    required this.ownerId,
    required this.nodeId,
    required this.kind,
    required this.sourceId,
    required List<ContentIdentity> content,
    required this.reasonCode,
    required this.sourceEvaluatedAtUtc,
    this.suggestedMode,
    this.learnerOverrideApplied = false,
  }) : content = List<ContentIdentity>.unmodifiable(content);

  final String missionId;
  final String ownerId;
  final String nodeId;
  final AdventureMissionKind kind;
  final String sourceId;
  final List<ContentIdentity> content;
  final String reasonCode;
  final DateTime sourceEvaluatedAtUtc;
  final LessonMode? suggestedMode;
  final bool learnerOverrideApplied;

  AdventureMissionRef copyWith({
    String? ownerId,
    List<ContentIdentity>? content,
    String? reasonCode,
    DateTime? sourceEvaluatedAtUtc,
    bool? learnerOverrideApplied,
  }) => AdventureMissionRef(
    missionId: missionId,
    ownerId: ownerId ?? this.ownerId,
    nodeId: nodeId,
    kind: kind,
    sourceId: sourceId,
    content: content ?? this.content,
    reasonCode: reasonCode ?? this.reasonCode,
    sourceEvaluatedAtUtc: sourceEvaluatedAtUtc ?? this.sourceEvaluatedAtUtc,
    suggestedMode: suggestedMode,
    learnerOverrideApplied:
        learnerOverrideApplied ?? this.learnerOverrideApplied,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'missionId': missionId,
    'ownerId': ownerId,
    'nodeId': nodeId,
    'kind': kind.name,
    'sourceId': sourceId,
    'content': content
        .map(
          (identity) => <String, Object?>{
            'type': identity.type.name,
            'id': identity.id,
            'revision': identity.revision,
          },
        )
        .toList(growable: false),
    'reasonCode': reasonCode,
    'sourceEvaluatedAtUtc': sourceEvaluatedAtUtc.toIso8601String(),
    'suggestedMode': suggestedMode?.name,
    'learnerOverrideApplied': learnerOverrideApplied,
  };
}

final class AdventureNodeSnapshot {
  const AdventureNodeSnapshot({
    required this.nodeId,
    required this.kind,
    required this.state,
    required this.label,
    required this.accessibilityLabel,
    required this.reasonCode,
    this.mission,
  });

  final String nodeId;
  final AdventureNodeKind kind;
  final AdventureNodeState state;
  final String label;
  final String accessibilityLabel;
  final String reasonCode;
  final AdventureMissionRef? mission;

  Map<String, Object?> toJson() => <String, Object?>{
    'nodeId': nodeId,
    'kind': kind.name,
    'state': state.name,
    'label': label,
    'accessibilityLabel': accessibilityLabel,
    'reasonCode': reasonCode,
    'mission': mission?.toJson(),
  };
}

final class AdventureJourneySnapshot {
  AdventureJourneySnapshot({
    required this.ownerId,
    required this.evaluatedAtUtc,
    required this.sourceEvaluatedAtUtc,
    required this.catalogId,
    required this.catalogVersion,
    required this.catalogSchemaVersion,
    required this.freshness,
    required Map<AdventureJourneyAuthority, AdventureJourneyDependencyState>
    dependencyStates,
    required List<AdventureNodeSnapshot> nodes,
    required this.primaryMission,
    required this.inputFingerprintSha256,
  }) : dependencyStates =
           Map<
             AdventureJourneyAuthority,
             AdventureJourneyDependencyState
           >.unmodifiable(dependencyStates),
       nodes = List<AdventureNodeSnapshot>.unmodifiable(nodes);

  final String ownerId;
  final DateTime evaluatedAtUtc;
  final DateTime sourceEvaluatedAtUtc;
  final String catalogId;
  final String catalogVersion;
  final int catalogSchemaVersion;
  final AdventureSnapshotFreshness freshness;
  final Map<AdventureJourneyAuthority, AdventureJourneyDependencyState>
  dependencyStates;
  final List<AdventureNodeSnapshot> nodes;
  final AdventureMissionRef? primaryMission;
  final String inputFingerprintSha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'ownerId': ownerId,
    'evaluatedAtUtc': evaluatedAtUtc.toIso8601String(),
    'sourceEvaluatedAtUtc': sourceEvaluatedAtUtc.toIso8601String(),
    'catalogId': catalogId,
    'catalogVersion': catalogVersion,
    'catalogSchemaVersion': catalogSchemaVersion,
    'freshness': freshness.name,
    'dependencyStates': <String, String>{
      for (final authority in AdventureJourneyAuthority.values)
        authority.name: dependencyStates[authority]!.name,
    },
    'nodes': nodes.map((node) => node.toJson()).toList(growable: false),
    'primaryMission': primaryMission?.toJson(),
    'inputFingerprintSha256': inputFingerprintSha256,
  };
}

final class AdventureJourneyRequest {
  const AdventureJourneyRequest({
    required this.ownerId,
    required this.evaluatedAtUtc,
    required this.catalog,
    required this.today,
  });

  final String ownerId;
  final DateTime evaluatedAtUtc;
  final AdventureWorldCatalog catalog;
  final TodayHubSnapshot today;
}

abstract interface class AdventureJourneyReader {
  Future<AdventureJourneySnapshot> compose(AdventureJourneyRequest request);
}

final class AdventureJourneyFacts {
  AdventureJourneyFacts({
    required this.authority,
    required this.state,
    required Set<String> completedNodeIds,
    required this.fingerprintPart,
  }) : completedNodeIds = Set<String>.unmodifiable(completedNodeIds);

  final AdventureJourneyAuthority authority;
  final AdventureJourneyDependencyState state;
  final Set<String> completedNodeIds;
  final String fingerprintPart;
}

abstract interface class AdventureJourneyFactReader {
  AdventureJourneyAuthority get authority;

  Future<AdventureJourneyFacts> read({
    required String ownerId,
    required DateTime evaluatedAtUtc,
  });
}
