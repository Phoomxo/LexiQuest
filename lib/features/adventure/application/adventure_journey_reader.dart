import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../learning_packs/domain/content_manifest.dart';
import '../../review/domain/review_queue_item.dart';
import '../../today_hub/domain/today_hub_models.dart';
import '../domain/adventure_journey.dart';
import '../domain/adventure_world_catalog.dart';

final class AdventureJourneyUseCases implements AdventureJourneyReader {
  AdventureJourneyUseCases({
    List<AdventureJourneyFactReader> factReaders =
        const <AdventureJourneyFactReader>[],
    this.maximumSourceAge = const Duration(minutes: 15),
  }) : _factReaders = _indexReaders(factReaders) {
    _configuredAuthorities = Set<AdventureJourneyAuthority>.unmodifiable(
      AdventureJourneyAuthority.values.where(_factReaders.containsKey),
    );
  }

  final Map<AdventureJourneyAuthority, AdventureJourneyFactReader> _factReaders;
  late final Set<AdventureJourneyAuthority> _configuredAuthorities;
  final Duration maximumSourceAge;

  Set<AdventureJourneyAuthority> get configuredAuthorities =>
      _configuredAuthorities;

  @override
  Future<AdventureJourneySnapshot> compose(
    AdventureJourneyRequest request,
  ) async {
    _validateRequest(request);
    final facts = <AdventureJourneyAuthority, AdventureJourneyFacts>{};
    for (final authority in AdventureJourneyAuthority.values) {
      final reader = _factReaders[authority];
      if (reader != null) {
        try {
          final value = await reader.read(
            ownerId: request.ownerId,
            evaluatedAtUtc: request.evaluatedAtUtc,
          );
          facts[authority] = value.authority == authority
              ? value
              : _containedFact(
                  authority,
                  AdventureJourneyDependencyState.corrupt,
                );
        } on Object {
          facts[authority] = _containedFact(
            authority,
            AdventureJourneyDependencyState.unavailable,
          );
        }
      }
    }

    final states = _dependencyStates(request.today, facts);
    var freshness = _freshness(states, _requiredAuthorities);
    if (request.evaluatedAtUtc.difference(request.today.evaluatedAtUtc) >
        maximumSourceAge) {
      freshness = AdventureSnapshotFreshness.stale;
      states[AdventureJourneyAuthority.today] =
          AdventureJourneyDependencyState.stale;
    }

    final completedNodeIds = <String>{
      for (final value in facts.values)
        if (value.state == AdventureJourneyDependencyState.ready)
          ...value.completedNodeIds,
    };
    final primary = freshness == AdventureSnapshotFreshness.current
        ? _primaryMission(request.today)
        : null;
    final supplementalState = _worstState(states, _supplementalAuthorities);
    final orderedDefinitions = _canonicalNodes(request.catalog);
    final nodes = <AdventureNodeSnapshot>[
      for (final definition in orderedDefinitions)
        _projectNode(
          definition,
          request.catalog.locale,
          freshness,
          supplementalState,
          completedNodeIds,
          primary,
        ),
    ];
    final fingerprint = _fingerprint(
      request,
      facts,
      states,
      completedNodeIds,
      primary,
    );
    return AdventureJourneySnapshot(
      ownerId: request.ownerId,
      evaluatedAtUtc: request.evaluatedAtUtc,
      sourceEvaluatedAtUtc: request.today.evaluatedAtUtc,
      catalogId: request.catalog.catalogId,
      catalogVersion: request.catalog.catalogVersion,
      catalogSchemaVersion: request.catalog.schemaVersion,
      freshness: freshness,
      dependencyStates: states,
      nodes: nodes,
      primaryMission: primary,
      inputFingerprintSha256: fingerprint,
    );
  }
}

const _requiredAuthorities = <AdventureJourneyAuthority>[
  AdventureJourneyAuthority.today,
  AdventureJourneyAuthority.quest,
  AdventureJourneyAuthority.streak,
];

const _supplementalAuthorities = <AdventureJourneyAuthority>[
  AdventureJourneyAuthority.achievement,
  AdventureJourneyAuthority.reward,
  AdventureJourneyAuthority.history,
  AdventureJourneyAuthority.packCompletion,
];

AdventureJourneyFacts _containedFact(
  AdventureJourneyAuthority authority,
  AdventureJourneyDependencyState state,
) => AdventureJourneyFacts(
  authority: authority,
  state: state,
  completedNodeIds: const <String>{},
  fingerprintPart: jsonEncode(<String, Object?>{
    'schemaVersion': 1,
    'authority': authority.name,
    'state': state.name,
  }),
);

Map<AdventureJourneyAuthority, AdventureJourneyFactReader> _indexReaders(
  List<AdventureJourneyFactReader> readers,
) {
  final indexed = <AdventureJourneyAuthority, AdventureJourneyFactReader>{};
  for (final reader in readers) {
    if (reader.authority == AdventureJourneyAuthority.today ||
        reader.authority == AdventureJourneyAuthority.quest ||
        reader.authority == AdventureJourneyAuthority.streak ||
        indexed.containsKey(reader.authority)) {
      throw ArgumentError.value(
        reader.authority,
        'factReaders',
        'must be one unique supplemental authority',
      );
    }
    indexed[reader.authority] = reader;
  }
  return Map<
    AdventureJourneyAuthority,
    AdventureJourneyFactReader
  >.unmodifiable(indexed);
}

void _validateRequest(AdventureJourneyRequest request) {
  if (request.ownerId.isEmpty ||
      request.ownerId != request.ownerId.trim() ||
      request.today.ownerId != request.ownerId ||
      !request.evaluatedAtUtc.isUtc ||
      request.evaluatedAtUtc.isBefore(request.today.evaluatedAtUtc) ||
      request.catalog.schemaVersion !=
          AdventureWorldCatalog.currentSchemaVersion) {
    throw ArgumentError('Adventure journey request is inconsistent.');
  }
}

Map<AdventureJourneyAuthority, AdventureJourneyDependencyState>
_dependencyStates(
  TodayHubSnapshot today,
  Map<AdventureJourneyAuthority, AdventureJourneyFacts> facts,
) {
  AdventureJourneyDependencyState fromToday(TodayHubDependency dependency) =>
      switch (today.dependencyStates[dependency]!) {
        TodayHubDependencyState.ready => AdventureJourneyDependencyState.ready,
        TodayHubDependencyState.empty => AdventureJourneyDependencyState.empty,
        TodayHubDependencyState.stale => AdventureJourneyDependencyState.stale,
        TodayHubDependencyState.unavailable =>
          AdventureJourneyDependencyState.unavailable,
        TodayHubDependencyState.corrupt =>
          AdventureJourneyDependencyState.corrupt,
      };

  final todayState = today.dependencyStates.values
      .map(
        (state) => switch (state) {
          TodayHubDependencyState.ready =>
            AdventureJourneyDependencyState.ready,
          TodayHubDependencyState.empty =>
            AdventureJourneyDependencyState.empty,
          TodayHubDependencyState.stale =>
            AdventureJourneyDependencyState.stale,
          TodayHubDependencyState.unavailable =>
            AdventureJourneyDependencyState.unavailable,
          TodayHubDependencyState.corrupt =>
            AdventureJourneyDependencyState.corrupt,
        },
      )
      .fold(AdventureJourneyDependencyState.ready, _worseDependencyState);
  return <AdventureJourneyAuthority, AdventureJourneyDependencyState>{
    AdventureJourneyAuthority.today: todayState,
    AdventureJourneyAuthority.quest: fromToday(TodayHubDependency.quests),
    AdventureJourneyAuthority.streak: fromToday(
      TodayHubDependency.gentleStreak,
    ),
    for (final authority in <AdventureJourneyAuthority>[
      AdventureJourneyAuthority.achievement,
      AdventureJourneyAuthority.reward,
      AdventureJourneyAuthority.history,
      AdventureJourneyAuthority.packCompletion,
    ])
      authority:
          facts[authority]?.state ?? AdventureJourneyDependencyState.empty,
  };
}

AdventureJourneyDependencyState _worseDependencyState(
  AdventureJourneyDependencyState left,
  AdventureJourneyDependencyState right,
) => _dependencySeverity(left) >= _dependencySeverity(right) ? left : right;

int _dependencySeverity(AdventureJourneyDependencyState state) =>
    switch (state) {
      AdventureJourneyDependencyState.ready => 0,
      AdventureJourneyDependencyState.empty => 0,
      AdventureJourneyDependencyState.stale => 1,
      AdventureJourneyDependencyState.unavailable => 2,
      AdventureJourneyDependencyState.corrupt => 3,
    };

AdventureSnapshotFreshness _freshness(
  Map<AdventureJourneyAuthority, AdventureJourneyDependencyState> states,
  Iterable<AdventureJourneyAuthority> authorities,
) {
  final worst = _worstState(states, authorities);
  return switch (worst) {
    AdventureJourneyDependencyState.ready ||
    AdventureJourneyDependencyState.empty => AdventureSnapshotFreshness.current,
    AdventureJourneyDependencyState.stale => AdventureSnapshotFreshness.stale,
    AdventureJourneyDependencyState.unavailable =>
      AdventureSnapshotFreshness.unavailable,
    AdventureJourneyDependencyState.corrupt =>
      AdventureSnapshotFreshness.corrupt,
  };
}

AdventureJourneyDependencyState _worstState(
  Map<AdventureJourneyAuthority, AdventureJourneyDependencyState> states,
  Iterable<AdventureJourneyAuthority> authorities,
) => authorities
    .map((authority) => states[authority]!)
    .fold(AdventureJourneyDependencyState.ready, _worseDependencyState);

AdventureMissionRef? _primaryMission(TodayHubSnapshot today) {
  final resumable = today.resumableSession;
  if (resumable != null) {
    return AdventureMissionRef(
      missionId: 'resume:${resumable.id}',
      ownerId: today.ownerId,
      nodeId: 'resume-review',
      kind: AdventureMissionKind.resume,
      sourceId: resumable.id,
      content: const <ContentIdentity>[],
      reasonCode: 'resume_active_session',
      sourceEvaluatedAtUtc: today.evaluatedAtUtc,
    );
  }
  if (today.reviewWork.isNotEmpty) {
    final review = today.reviewWork.toList()
      ..sort((left, right) {
        final leftSource = left.provenance.first;
        final rightSource = right.provenance.first;
        var result = leftSource.reason.priority.compareTo(
          rightSource.reason.priority,
        );
        if (result != 0) return result;
        result = leftSource.priorityTimeUtc.compareTo(
          rightSource.priorityTimeUtc,
        );
        if (result != 0) return result;
        return left.identity.id.compareTo(right.identity.id);
      });
    final content = review.map((work) => work.identity).toList(growable: false);
    return AdventureMissionRef(
      missionId: 'review:${content.map((item) => item.id).join(',')}',
      ownerId: today.ownerId,
      nodeId: 'resume-review',
      kind: AdventureMissionKind.review,
      sourceId: content.first.id,
      content: content,
      reasonCode: 'due_review',
      sourceEvaluatedAtUtc: today.evaluatedAtUtc,
    );
  }
  final recommendation = today.authoritativeRecommendation;
  final identity = recommendation?.mergedInto;
  if (recommendation != null && identity != null) {
    return AdventureMissionRef(
      missionId: 'recommendation:${identity.id}',
      ownerId: today.ownerId,
      nodeId: 'today-mission',
      kind: AdventureMissionKind.recommendation,
      sourceId: identity.id,
      content: <ContentIdentity>[identity],
      reasonCode: recommendation.result.reason.name,
      sourceEvaluatedAtUtc: today.evaluatedAtUtc,
      suggestedMode: recommendation.result.recommendedMode,
      learnerOverrideApplied: recommendation.result.learnerOverrideApplied,
    );
  }
  return null;
}

AdventureNodeSnapshot _projectNode(
  AdventureNodeDefinition definition,
  String locale,
  AdventureSnapshotFreshness freshness,
  AdventureJourneyDependencyState supplementalState,
  Set<String> completedNodeIds,
  AdventureMissionRef? primary,
) {
  final isMissionNode =
      definition.nodeId == 'resume-review' ||
      definition.nodeId == 'today-mission';
  late final AdventureNodeState state;
  late final String reason;
  if (primary?.nodeId == definition.nodeId) {
    state = AdventureNodeState.current;
    reason = primary!.reasonCode;
  } else if (completedNodeIds.contains(definition.nodeId)) {
    state = AdventureNodeState.completed;
    reason = 'canonical_completion';
  } else if (freshness != AdventureSnapshotFreshness.current && isMissionNode) {
    state = AdventureNodeState.unavailable;
    reason = switch (freshness) {
      AdventureSnapshotFreshness.stale => 'source_stale',
      AdventureSnapshotFreshness.unavailable => 'source_unavailable',
      AdventureSnapshotFreshness.corrupt => 'source_corrupt',
      AdventureSnapshotFreshness.current => 'available',
    };
  } else if (definition.kind == AdventureNodeKind.rewardPreview &&
      supplementalState != AdventureJourneyDependencyState.ready &&
      supplementalState != AdventureJourneyDependencyState.empty) {
    state = AdventureNodeState.unavailable;
    reason = switch (supplementalState) {
      AdventureJourneyDependencyState.stale => 'source_stale',
      AdventureJourneyDependencyState.unavailable => 'source_unavailable',
      AdventureJourneyDependencyState.corrupt => 'source_corrupt',
      AdventureJourneyDependencyState.ready ||
      AdventureJourneyDependencyState.empty => 'preview_locked',
    };
  } else if (definition.kind == AdventureNodeKind.rewardPreview) {
    state = AdventureNodeState.locked;
    reason = 'preview_locked';
  } else {
    state = AdventureNodeState.available;
    reason = 'available';
  }
  return AdventureNodeSnapshot(
    nodeId: definition.nodeId,
    kind: definition.kind,
    state: state,
    label: definition.labelsByLocale[locale]!,
    accessibilityLabel: definition.accessibilityLabelsByLocale[locale]!,
    reasonCode: reason,
    mission: primary?.nodeId == definition.nodeId ? primary : null,
  );
}

List<AdventureNodeDefinition> _canonicalNodes(AdventureWorldCatalog catalog) {
  final byId = <String, AdventureNodeDefinition>{
    for (final world in catalog.worlds)
      for (final node in world.nodes) node.nodeId: node,
  };
  final remaining = <String, Set<String>>{
    for (final entry in byId.entries)
      entry.key: entry.value.prerequisiteNodeIds.toSet(),
  };
  final result = <AdventureNodeDefinition>[];
  while (remaining.isNotEmpty) {
    final ready =
        remaining.entries
            .where(
              (entry) => entry.value.every((id) => !remaining.containsKey(id)),
            )
            .map((entry) => entry.key)
            .toList()
          ..sort();
    if (ready.isEmpty) throw StateError('Adventure catalog graph is cyclic.');
    for (final id in ready) {
      result.add(byId[id]!);
      remaining.remove(id);
    }
  }
  return List<AdventureNodeDefinition>.unmodifiable(result);
}

String _fingerprint(
  AdventureJourneyRequest request,
  Map<AdventureJourneyAuthority, AdventureJourneyFacts> facts,
  Map<AdventureJourneyAuthority, AdventureJourneyDependencyState> states,
  Set<String> completedNodeIds,
  AdventureMissionRef? primary,
) {
  final completed = completedNodeIds.toList()..sort();
  final payload = <String, Object?>{
    'ownerId': request.ownerId,
    'evaluatedAtUtc': request.evaluatedAtUtc.toIso8601String(),
    'sourceEvaluatedAtUtc': request.today.evaluatedAtUtc.toIso8601String(),
    'catalogId': request.catalog.catalogId,
    'catalogVersion': request.catalog.catalogVersion,
    'catalogSchemaVersion': request.catalog.schemaVersion,
    'dependencies': <String, String>{
      for (final authority in AdventureJourneyAuthority.values)
        authority.name: states[authority]!.name,
    },
    'facts': <String, String>{
      for (final authority in AdventureJourneyAuthority.values)
        if (facts[authority] case final fact?)
          authority.name: fact.fingerprintPart,
    },
    'completedNodeIds': completed,
    'primaryMission': primary?.toJson(),
    'catalogNodes': _canonicalNodes(
      request.catalog,
    ).map((node) => node.nodeId).toList(growable: false),
  };
  return sha256.convert(utf8.encode(jsonEncode(payload))).toString();
}
