import 'dart:convert';
import '../data/pair_matching_checkpoint_codec.dart';
import '../application/pair_matching_atomic_start.dart';
import 'pair_matching_launch.dart';
import 'pair_matching_plan.dart';
import '../../application/matching_mode_adapter.dart';
import '../../application/current_activity_evidence.dart';
import '../../domain/learning_models.dart';
import '../../domain/evidence_context.dart';
import '../../domain/lexical_prompt_artifact_identity.dart';
import '../../domain/session_configuration.dart';

abstract interface class PairMatchingSessionPurposeReader {
  Future<PairMatchingSessionPurpose> read({
    required String ownerId,
    required String sessionId,
  });
}

/// Authenticated projection of existing session and checkpoint rows.
/// The decoder performs no reads, allowing upload's tracked snapshot to own IO.
final class PairMatchingSessionPurpose {
  const PairMatchingSessionPurpose._(
    this.snapshot, {
    this.unknownMatching = false,
    this.reservations = const {},
  });
  final bool unknownMatching;
  final PairMatchingCheckpointSnapshot? snapshot;

  /// Exact durable pending bytes from the entire authenticated prefix, including
  /// occurrences that the latest snapshot has already acknowledged.
  final Map<String, Map<String, Object?>> reservations;
  PairSessionPurpose? get purpose => unknownMatching
      ? null
      : snapshot?.engine.plan.sessionPurpose ?? PairSessionPurpose.learning;
  bool get isReplay => purpose == PairSessionPurpose.practiceReplay;
  bool get allowsLearningAuthority => !unknownMatching && !isReplay;

  static PairMatchingSessionPurpose decode({
    required String ownerId,
    required Map<String, Object?> session,
    required List<Map<String, Object?>> checkpoints,
    List<Map<String, Object?>> historicalOwners = const [],
  }) {
    try {
      if (session['owner_id'] != ownerId) throw const FormatException();
      if (session['activity_type'] != 'matching') {
        return const PairMatchingSessionPurpose._(null);
      }
      if (checkpoints.length > 64) throw const FormatException();
      if (checkpoints.isEmpty) {
        return const PairMatchingSessionPurpose._(null, unknownMatching: true);
      }
      final payloads = [
        for (final row in checkpoints)
          (jsonDecode(row['payload_json'] as String) as Map)
              .cast<String, Object?>(),
      ];
      final versions = [
        for (final p in payloads) (p['state'] as Map)['schemaVersion'],
      ];
      final legacy = !versions.contains(6);
      if (legacy
          ? versions.any((v) => v is! int || v < 1 || v > 5)
          : versions.any((v) => v != 6)) {
        throw const FormatException();
      }
      final byRevision = <int, PairMatchingCheckpointSnapshot>{};
      final occurredByRevision = <int, int>{};
      final legacyRevisions = <int>{};
      final reservations = <String, Map<String, Object?>>{};
      for (var index = 0; index < checkpoints.length; index++) {
        final row = checkpoints[index], p = payloads[index];
        final version = p['schemaVersion'];
        final keys = {
          'schemaVersion',
          'activityType',
          'sessionId',
          'revision',
          'state',
          if (version == 2) ...['terminalAtUtc', 'terminalAcknowledged'],
        };
        final revision = p['revision'] as int;
        final actor = row['actor_identity'];
        final authorizedActor =
            actor == ownerId ||
            (!legacy ||
                historicalOwners.any(
                  (owner) =>
                      owner['id'] == actor &&
                      owner['is_active'] == 0 &&
                      owner['account_state'] == 'mergedInto:$ownerId',
                ));
        final key = checkpointKey(
          actor as String,
          session['id'] as String,
          revision,
        );
        if ((version != 1 && version != 2) ||
            p.length != keys.length ||
            !p.keys.every(keys.contains) ||
            revision < 1 ||
            revision > 64 ||
            byRevision.containsKey(revision) ||
            legacyRevisions.contains(revision) ||
            p['sessionId'] != session['id'] ||
            p['activityType'] != 'matching' ||
            row['event_id'] != key ||
            row['idempotency_key'] != key ||
            row['event_type'] != 'LearningActivityCheckpoint' ||
            row['event_version'] != version ||
            row['owner_id'] != ownerId ||
            !authorizedActor ||
            row['aggregate_id'] != session['id'] ||
            row['aggregate_type'] != 'LearningSession' ||
            row['recorded_at_utc'] != row['occurred_at_utc'] ||
            row['app_version'] != session['app_version'] ||
            row['build_id'] != session['build_id'] ||
            row['privacy_classification'] != 'ownerOnly' ||
            [
              'tenant_context_json',
              'correlation_id',
              'causation_id',
              'experiment_context_json',
              'content_revision',
              'policy_version',
              'provider_provenance_json',
            ].any((k) => row[k] != null) ||
            row['consent_context_json'] !=
                jsonEncode({
                  'researchConsentVersion': 0,
                  'aiConsentGranted': false,
                  'voiceConsentGranted': false,
                  'socialConsentGranted': false,
                })) {
          throw const FormatException();
        }
        final state = (p['state'] as Map).cast<String, Object?>();
        if (version == 2) {
          final terminal = p['terminalAtUtc'];
          final acknowledged = p['terminalAcknowledged'];
          if (acknowledged is! bool ||
              (terminal != null &&
                  (terminal is! String ||
                      !terminal.endsWith('Z') ||
                      DateTime.tryParse(terminal)?.isUtc != true)) ||
              (acknowledged && terminal == null)) {
            throw const FormatException();
          }
        }
        if (utf8.encode(jsonEncode(state)).length > 65536) {
          throw const FormatException();
        }
        if (legacy) {
          const MatchingModeAdapter().validateLegacyCheckpointShape(
            LearningActivityCheckpoint(
              sessionId: session['id'] as String,
              activityType: 'matching',
              revision: revision,
              occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
                (row['occurred_at_utc'] as int) * 1000,
                isUtc: true,
              ),
              state: state,
            ),
            DateTime.fromMillisecondsSinceEpoch(
              session['started_at_utc_ms'] as int,
              isUtc: true,
            ),
            ownerId,
          );
          legacyRevisions.add(revision);
          continue;
        }
        final snapshot = PairMatchingCheckpointCodec.decode(state);
        final start = PairMatchingStartOperation.fromStableSerialization(
          snapshot.startOperation,
        );
        final plan = snapshot.engine.plan;
        authorizeSnapshot(
          ownerId: ownerId,
          session: session,
          snapshot: snapshot,
          historicalOwners: historicalOwners,
        );
        authorizeActor(
          ownerId: ownerId,
          actorId: actor,
          occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
            (row['occurred_at_utc'] as int) * 1000,
            isUtc: true,
          ),
          historicalOwners: historicalOwners,
          secondPrecision: true,
        );
        if ((revision == 1 && actor != plan.ownerId) ||
            snapshot.terminal?.atUtc.toIso8601String() != p['terminalAtUtc'] ||
            (snapshot.terminal?.acknowledged ?? false) !=
                (p['terminalAcknowledged'] ?? false)) {
          throw const FormatException();
        }
        if (revision == 1 &&
            jsonEncode(state) != jsonEncode(start.initialCheckpoint.state)) {
          throw const FormatException();
        }
        final frozen = snapshot.frozenEvidence;
        if (frozen != null) {
          final id = frozen['sourceEvidenceId'] as String;
          final previous = reservations[id];
          if (previous != null && jsonEncode(previous) != jsonEncode(frozen)) {
            throw const FormatException('Pair reserved occurrence changed');
          }
          reservations[id] = frozen;
        }
        byRevision[revision] = snapshot;
        occurredByRevision[revision] = row['occurred_at_utc'] as int;
      }
      if (legacy) {
        for (var i = 1; i <= legacyRevisions.length; i++) {
          if (!legacyRevisions.contains(i)) throw const FormatException();
        }
        return const PairMatchingSessionPurpose._(null);
      }
      final initial = byRevision[1];
      if (initial == null) throw const FormatException();
      for (var revision = 1; revision <= byRevision.length; revision++) {
        final current = byRevision[revision];
        if (current == null ||
            current.startOperation != initial.startOperation ||
            current.engine.plan.planFingerprint !=
                initial.engine.plan.planFingerprint) {
          throw const FormatException();
        }
        if (revision > 1) {
          PairMatchingCheckpointCodec.validateTransition(
            byRevision[revision - 1]!,
            current,
            allowMeasuredAdmission:
                revision == 2 &&
                occurredByRevision[2] == occurredByRevision[1] &&
                occurredByRevision[2] ==
                    (session['started_at_utc_ms'] as int) ~/ 1000,
          );
        }
      }
      final latest = byRevision[byRevision.length]!;
      if (latest.terminal?.acknowledged == true &&
          (session['state'] != 'completed' ||
              session['ended_at_utc_ms'] !=
                  latest.terminal!.atUtc.millisecondsSinceEpoch)) {
        throw const FormatException();
      }
      if (latest.evidenceIds.any((id) => !reservations.containsKey(id))) {
        throw const FormatException('Pair committed reservation is missing');
      }
      return PairMatchingSessionPurpose._(
        latest,
        reservations: Map.unmodifiable(reservations),
      );
    } catch (_) {
      throw StateError('Persisted Pair purpose is unavailable or corrupt');
    }
  }

  /// Read-only canonical lineage authentication. Write callers must additionally
  /// require that [ownerId] is the sole active owner inside their transaction.
  static void authorizeActor({
    required String ownerId,
    required String actorId,
    required DateTime occurredAtUtc,
    required List<Map<String, Object?>> historicalOwners,
    bool secondPrecision = false,
  }) {
    final current = _ownerRow(ownerId, historicalOwners);
    final currentCreated = _utcMilliseconds(current['created_at_utc_ms']);
    if (!occurredAtUtc.isUtc) {
      throw StateError('Pair actor occurrence is invalid');
    }
    final occurred = _utcMilliseconds(occurredAtUtc.millisecondsSinceEpoch);
    final upper = occurred + (secondPrecision ? 999 : 0);
    if (actorId == ownerId) {
      if (upper < currentCreated) {
        throw StateError('Pair actor predates owner');
      }
      return;
    }
    final historical = _ownerRow(actorId, historicalOwners);
    final created = _utcMilliseconds(historical['created_at_utc_ms']);
    final upgraded = _utcMilliseconds(historical['upgraded_at_utc_ms']);
    final destinationUpgraded = _utcMilliseconds(current['upgraded_at_utc_ms']);
    if (historical['is_active'] != 0 ||
        historical['account_state'] != 'mergedInto:$ownerId' ||
        created > upgraded ||
        currentCreated > upgraded ||
        currentCreated > destinationUpgraded ||
        upgraded > destinationUpgraded ||
        upper < created ||
        occurred > upgraded) {
      throw StateError('Pair actor lineage is unavailable or corrupt');
    }
  }

  static Map<String, Object?> _ownerRow(
    String id,
    List<Map<String, Object?>> owners,
  ) {
    final found = owners.where((row) => row['id'] == id).toList();
    if (found.length != 1) {
      throw StateError('Pair canonical owner is unavailable');
    }
    return found.single;
  }

  static int _utcMilliseconds(Object? value) {
    if (value is! int || value < 0 || value > 8640000000000000) {
      throw StateError('Pair owner timestamp is invalid');
    }
    return value;
  }

  static SessionConfiguration? projectConfigurationOwner(
    SessionConfiguration? accepted,
    String ownerId,
  ) => accepted == null
      ? null
      : SessionConfiguration.validated(
          schemaVersion: accepted.schemaVersion,
          policyVersion: accepted.policyVersion,
          ownerId: ownerId,
          mode: accepted.mode,
          itemCount: accepted.itemCount,
          direction: accepted.direction,
          difficulty: accepted.difficulty,
          hintBudget: accepted.hintBudget,
          timing: accepted.timing,
          packIdentity: accepted.packIdentity,
          protocolId: accepted.protocolId,
          protocolVersion: accepted.protocolVersion,
          protocolLimitsIdentity: accepted.protocolLimitsIdentity,
          pairDensityPreference: accepted.pairDensityPreference,
        );

  /// Authenticates accepted P against canonical R without changing the start,
  /// configuration, lexical pins, frozen occurrence, or command namespace.
  static void authorizeSnapshot({
    required String ownerId,
    required Map<String, Object?> session,
    required PairMatchingCheckpointSnapshot snapshot,
    required List<Map<String, Object?>> historicalOwners,
  }) {
    final plan = snapshot.engine.plan;
    final start = PairMatchingStartOperation.fromStableSerialization(
      snapshot.startOperation,
    );
    authorizeActor(
      ownerId: ownerId,
      actorId: plan.ownerId,
      occurredAtUtc: plan.createdAtUtc,
      historicalOwners: historicalOwners,
    );
    final projected = projectConfigurationOwner(start.configuration, ownerId);
    if (session['owner_id'] != ownerId ||
        session['activity_type'] != 'matching' ||
        plan.learningSessionId != session['id'] ||
        plan.sourceSessionId == plan.learningSessionId ||
        plan.createdAtUtc.millisecondsSinceEpoch !=
            session['started_at_utc_ms'] ||
        start.appVersion != session['app_version'] ||
        start.buildId != session['build_id'] ||
        projected?.contentIdentity !=
            session['session_configuration_identity'] ||
        projected?.stableSerialization !=
            session['session_configuration_json']) {
      throw StateError('Pair checkpoint session or configuration changed');
    }
    final frozenJson = snapshot.frozenEvidence;
    if (frozenJson != null) {
      final frozen = FrozenPendingCurrentActivityEvidence.fromJson(frozenJson);
      final pending = snapshot.engine.pending!;
      final item = plan.orderedLexicalItems.singleWhere(
        (item) => item.wordId == pending.promptWordId,
      );
      final content = LexicalPromptArtifactResolver.resolveForAdapter(
        promptMode: 'matchingPair',
        wordId: item.wordId,
        coreRevision: item.contentRevision,
        coreChecksumSha256: item.checksum,
      );
      if (frozen.ownerId != frozen.actorIdentity ||
          frozen.contentRevision != content?.evidenceContentRevision ||
          frozen.declaredEvidenceClass !=
              (plan.sessionPurpose == PairSessionPurpose.practiceReplay
                  ? EvidenceClass.recreational
                  : snapshot.engine.classificationFor(pending).evidenceClass) ||
          frozen.contrastiveFeedback != null) {
        throw StateError('Pair frozen actor is inconsistent');
      }
      authorizeActor(
        ownerId: ownerId,
        actorId: frozen.actorIdentity,
        occurredAtUtc: frozen.occurredAtUtc,
        historicalOwners: historicalOwners,
      );
    }
  }

  static String checkpointKey(String owner, String session, int revision) =>
      'learning-activity-checkpoint:${pairHash('$owner\u0000$session\u0000matching\u0000$revision')}';

  static ({String sql, List<Object?> args}) checkpointQuery(
    String owner,
    String session,
  ) {
    final ids = [
      for (var i = 1; i <= 64; i++) checkpointKey(owner, session, i),
    ];
    return (
      sql:
          "SELECT * FROM events_v2 WHERE event_id IN (${List.filled(64, '?').join(',')}) OR (aggregate_id = ? AND (event_type = 'LearningActivityCheckpoint' OR event_id LIKE 'learning-activity-checkpoint:%')) ORDER BY event_id LIMIT 65",
      args: [...ids, session],
    );
  }

  static ({String sql, List<Object?> args}) historicalOwnerQuery(
    String owner,
    List<Map<String, Object?>> checkpoints,
  ) {
    // This query is also consumed by research's tracked _Reads snapshot. Keep
    // absent identities in its parameters so insertion/removal invalidates an
    // authorization that awaited external policy or signature work.
    final identities = <String>{owner};
    for (final row in checkpoints) {
      final actor = row['actor_identity'];
      if (actor is String) identities.add(actor);
      try {
        final payload = jsonDecode(row['payload_json'] as String) as Map;
        final state = payload['state'] as Map;
        if (state['schemaVersion'] != 6) continue;
        final planOwner = (state['plan'] as Map)['ownerId'];
        if (planOwner is String) identities.add(planOwner);
        final frozen = state['frozenEvidence'];
        if (frozen is Map) {
          for (final key in ['ownerId', 'actorIdentity']) {
            final id = frozen[key];
            if (id is String) identities.add(id);
          }
        }
      } catch (_) {
        // Extraction grants no authority; decode rejects malformed payloads.
      }
    }
    final actors = identities.toList()..sort();
    return (
      sql:
          'SELECT * FROM local_owners WHERE id IN (${actors.isEmpty ? "NULL" : List.filled(actors.length, "?").join(",")}) ORDER BY id',
      args: actors,
    );
  }
}
