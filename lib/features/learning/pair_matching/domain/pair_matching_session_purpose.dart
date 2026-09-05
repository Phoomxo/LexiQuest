import 'dart:convert';
import '../data/pair_matching_checkpoint_codec.dart';
import '../application/pair_matching_atomic_start.dart';
import 'pair_matching_launch.dart';
import 'pair_matching_plan.dart';
import '../../application/matching_mode_adapter.dart';
import '../../domain/learning_models.dart';

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
  });
  final bool unknownMatching;
  final PairMatchingCheckpointSnapshot? snapshot;
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
      final legacyRevisions = <int>{};
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
            (legacy &&
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
        if (plan.ownerId != ownerId ||
            plan.learningSessionId != session['id'] ||
            plan.sourceSessionId == plan.learningSessionId ||
            plan.createdAtUtc.millisecondsSinceEpoch !=
                session['started_at_utc_ms'] ||
            start.appVersion != session['app_version'] ||
            start.buildId != session['build_id'] ||
            start.configuration?.contentIdentity !=
                session['session_configuration_identity'] ||
            start.configuration?.stableSerialization !=
                session['session_configuration_json'] ||
            snapshot.terminal?.atUtc.toIso8601String() != p['terminalAtUtc'] ||
            (snapshot.terminal?.acknowledged ?? false) !=
                (p['terminalAcknowledged'] ?? false)) {
          throw const FormatException();
        }
        if (revision == 1 &&
            jsonEncode(state) != jsonEncode(start.initialCheckpoint.state)) {
          throw const FormatException();
        }
        byRevision[revision] = snapshot;
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
      return PairMatchingSessionPurpose._(latest);
    } catch (_) {
      throw StateError('Persisted Pair purpose is unavailable or corrupt');
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
    final actors =
        checkpoints
            .map((row) => row['actor_identity'])
            .whereType<String>()
            .where((actor) => actor != owner)
            .toSet()
            .toList()
          ..sort();
    return (
      sql:
          'SELECT * FROM local_owners WHERE id IN (${actors.isEmpty ? "NULL" : List.filled(actors.length, "?").join(",")}) ORDER BY id',
      args: actors,
    );
  }
}
