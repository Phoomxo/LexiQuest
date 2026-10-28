import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../learning/domain/session_configuration.dart';
import '../../learning/pair_matching/application/pair_matching_atomic_start.dart';
import '../../learning/pair_matching/domain/pair_matching_session_purpose.dart';

/// Immutable historical session facts. Decoding establishes consistency only;
/// callers must authenticate provenance, current permit and participant policy.
/// Projections are for in-memory authorization, never resumable session inserts.
final class ResearchSessionProof {
  ResearchSessionProof._(Map<String, Object?> payload)
    : _payload = Map.unmodifiable(payload);

  static const schema = 'lexiquest.research-session-proof.v1';
  static const maximumPayloadBytes = 131072;
  static const maximumConfigurationBytes = 16384;
  static const maximumInitialStateBytes = 65536;
  static const _maximumUtcMs = 8640000000000000;
  static const _keys = [
    'schema',
    'id',
    'ownerId',
    'measurementRunId',
    'learningSessionId',
    'proofRevision',
    'activityType',
    'sessionState',
    'startedAtUtcMs',
    'endedAtUtcMs',
    'appVersion',
    'buildId',
    'sessionConfigurationIdentity',
    'sessionConfigurationJson',
    'pairStartOperation',
    'pairCheckpointEventVersion',
    'pairOwnerLineage',
    'permitId',
    'permitPayloadSha256',
    'permitRevision',
  ];
  static const _lineageKeys = {
    'ownerId',
    'createdAtUtcMs',
    'upgradedAtUtcMs',
    'mergedIntoOwnerId',
  };
  static const _phaseKeys = {
    'id',
    'proofRevision',
    'sessionState',
    'endedAtUtcMs',
  };
  static const _invalid = FormatException('Invalid research session proof');

  final Map<String, Object?> _payload;

  String get id => _payload['id'] as String;
  String get ownerId => _payload['ownerId'] as String;
  String get permitId => _payload['permitId'] as String;
  String get permitPayloadSha256 => _payload['permitPayloadSha256'] as String;
  int get permitRevision => _payload['permitRevision'] as int;
  String get measurementRunId => _payload['measurementRunId'] as String;
  String get learningSessionId => _payload['learningSessionId'] as String;
  int get proofRevision => _payload['proofRevision'] as int;
  String get activityType => _payload['activityType'] as String;
  String get sessionState => _payload['sessionState'] as String;
  int get startedAtUtcMs => _payload['startedAtUtcMs'] as int;
  int? get endedAtUtcMs => _payload['endedAtUtcMs'] as int?;
  String get appVersion => _payload['appVersion'] as String;
  String get buildId => _payload['buildId'] as String;
  String? get sessionConfigurationIdentity =>
      _payload['sessionConfigurationIdentity'] as String?;
  String? get sessionConfigurationJson =>
      _payload['sessionConfigurationJson'] as String?;
  String? get pairStartOperation => _payload['pairStartOperation'] as String?;
  int? get pairCheckpointEventVersion =>
      _payload['pairCheckpointEventVersion'] as int?;
  List<Map<String, Object?>>? get pairOwnerLineage =>
      _payload['pairOwnerLineage'] as List<Map<String, Object?>>?;

  static String identityFor({
    required String ownerId,
    required String permitId,
    required String measurementRunId,
    required String learningSessionId,
    required int proofRevision,
  }) {
    for (final value in [
      ownerId,
      permitId,
      measurementRunId,
      learningSessionId,
    ]) {
      _text(value);
    }
    _phase(proofRevision);
    return 'research-session-proof:${sha256.convert(utf8.encode(jsonEncode([ownerId, permitId, measurementRunId, learningSessionId, proofRevision])))}';
  }

  static ResearchSessionProof decode(Map<String, Object?> payload) {
    try {
      _require(
        payload.length == _keys.length && payload.keys.every(_keys.contains),
      );
      _require(payload['schema'] == schema);
      for (final key in [
        'id',
        'ownerId',
        'permitId',
        'measurementRunId',
        'learningSessionId',
        'activityType',
        'appVersion',
        'buildId',
      ]) {
        _text(payload[key]);
      }
      final phase = _phase(payload['proofRevision']);
      final start = _utc(payload['startedAtUtcMs']);
      final end = _optionalUtc(payload['endedAtUtcMs']);
      _require(
        phase == 1
            ? payload['sessionState'] == 'active' && end == null
            : payload['sessionState'] == 'completed' &&
                  end != null &&
                  end >= start,
      );
      final digest = _text(payload['permitPayloadSha256']);
      _require(RegExp(r'^[0-9a-f]{64}$').hasMatch(digest));
      _require(
        payload['permitRevision'] is int &&
            (payload['permitRevision'] as int) > 0,
      );
      final owner = payload['ownerId'] as String;
      _require(
        payload['id'] ==
            identityFor(
              ownerId: owner,
              permitId: payload['permitId'] as String,
              measurementRunId: payload['measurementRunId'] as String,
              learningSessionId: payload['learningSessionId'] as String,
              proofRevision: phase,
            ),
      );
      _configuration(
        owner,
        payload['sessionConfigurationIdentity'],
        payload['sessionConfigurationJson'],
      );

      final normalized = <String, Object?>{
        for (final key in _keys) key: payload[key],
      };
      if (payload['activityType'] == 'matching') {
        final source = payload['pairStartOperation'];
        _require(source is String && source.length <= 40000);
        final operation = PairMatchingStartOperation.fromStableSerialization(
          source as String,
        );
        final eventVersion = payload['pairCheckpointEventVersion'];
        _require(
          eventVersion is int && (eventVersion == 1 || eventVersion == 2),
        );
        final lineage = _lineage(
          payload['pairOwnerLineage'],
          owner,
          operation.plan.ownerId,
        );
        normalized['pairOwnerLineage'] = lineage;
        final initial = operation.initialCheckpoint;
        _boundedJson(initial.state, maximumInitialStateBytes);
        final key = PairMatchingSessionPurpose.checkpointKey(
          operation.plan.ownerId,
          operation.plan.learningSessionId,
          1,
        );
        final occurrence = initial.occurredAtUtc.millisecondsSinceEpoch ~/ 1000;
        final checkpoint = <String, Object?>{
          'event_id': key,
          'idempotency_key': key,
          'owner_id': owner,
          'actor_identity': operation.plan.ownerId,
          'aggregate_id': operation.plan.learningSessionId,
          'aggregate_type': 'LearningSession',
          'event_type': 'LearningActivityCheckpoint',
          'event_version': eventVersion,
          'occurred_at_utc': occurrence,
          'recorded_at_utc': occurrence,
          'app_version': operation.appVersion,
          'build_id': operation.buildId,
          'privacy_classification': 'ownerOnly',
          'consent_context_json': jsonEncode({
            'researchConsentVersion': 0,
            'aiConsentGranted': false,
            'voiceConsentGranted': false,
            'socialConsentGranted': false,
          }),
          'payload_json': jsonEncode({
            'schemaVersion': eventVersion,
            'activityType': initial.activityType,
            'sessionId': initial.sessionId,
            'revision': initial.revision,
            'state': initial.state,
            if (eventVersion == 2) ...{
              'terminalAtUtc': null,
              'terminalAcknowledged': false,
            },
          }),
        };
        final proof = ResearchSessionProof._(normalized);
        final purpose = PairMatchingSessionPurpose.decode(
          ownerId: owner,
          session: proof.toSessionProjection(),
          checkpoints: [checkpoint],
          historicalOwners: [
            for (final entry in lineage)
              {
                'id': entry['ownerId'],
                'created_at_utc_ms': entry['createdAtUtcMs'],
                'upgraded_at_utc_ms': entry['upgradedAtUtcMs'],
                'is_active': entry['ownerId'] == owner ? 1 : 0,
                'account_state': entry['ownerId'] == owner
                    ? 'localGuest'
                    : 'mergedInto:$owner',
              },
          ],
        );
        _require(purpose.allowsLearningAuthority && purpose.snapshot != null);
      } else {
        _require(
          payload['pairStartOperation'] == null &&
              payload['pairCheckpointEventVersion'] == null &&
              payload['pairOwnerLineage'] == null,
        );
      }
      _boundedJson(normalized, maximumPayloadBytes);
      return ResearchSessionProof._(normalized);
    } catch (_) {
      throw _invalid;
    }
  }

  /// The caller supplies a coherent, tracked canonical snapshot and remains
  /// responsible for authorization. Validate full source history before taking
  /// the compact initial facts or deriving an earlier Started phase.
  static ResearchSessionProof fromCanonicalSnapshot({
    required String ownerId,
    required String permitId,
    required String permitPayloadSha256,
    required int permitRevision,
    required String measurementRunId,
    required int proofRevision,
    required Map<String, Object?> session,
    List<Map<String, Object?>> checkpoints = const [],
    List<Map<String, Object?>> historicalOwners = const [],
  }) {
    try {
      _phase(proofRevision);
      _require(
        const [
          'id',
          'owner_id',
          'activity_type',
          'state',
          'started_at_utc_ms',
          'ended_at_utc_ms',
          'app_version',
          'build_id',
          'session_configuration_identity',
          'session_configuration_json',
        ].every(session.containsKey),
      );
      _require(session['owner_id'] == ownerId);
      final start = _utc(session['started_at_utc_ms']);
      final end = _optionalUtc(session['ended_at_utc_ms']);
      final state = session['state'];
      _require(
        (state == 'active' && end == null) ||
            (state == 'completed' && end != null && end >= start) ||
            (state == 'abandoned' && (end == null || end >= start)),
      );
      _require(proofRevision == 1 || state == 'completed');
      _configuration(
        ownerId,
        session['session_configuration_identity'],
        session['session_configuration_json'],
      );

      String? pairStart;
      int? eventVersion;
      List<Map<String, Object?>>? lineage;
      if (session['activity_type'] == 'matching') {
        final purpose = PairMatchingSessionPurpose.decode(
          ownerId: ownerId,
          session: session,
          checkpoints: checkpoints,
          historicalOwners: historicalOwners,
        );
        _require(purpose.allowsLearningAuthority && purpose.snapshot != null);
        final operation = PairMatchingStartOperation.fromStableSerialization(
          purpose.snapshot!.startOperation,
        );
        final initials = checkpoints
            .where(
              (row) =>
                  (jsonDecode(row['payload_json'] as String)
                      as Map)['revision'] ==
                  1,
            )
            .toList();
        _require(initials.length == 1);
        final initial = initials.single;
        final stateJson =
            (jsonDecode(initial['payload_json'] as String) as Map)['state'];
        _require(
          jsonEncode(stateJson) ==
              jsonEncode(operation.initialCheckpoint.state),
        );
        _boundedJson(stateJson, maximumInitialStateBytes);
        pairStart = operation.stableSerialization;
        eventVersion = initial['event_version'] as int;
        final identities = {ownerId, operation.plan.ownerId}.toList()..sort();
        lineage = [];
        for (final identity in identities) {
          final matches = historicalOwners
              .where((row) => row['id'] == identity)
              .toList();
          _require(matches.length == 1);
          final row = matches.single;
          _require(
            identity == ownerId
                ? !(row['account_state'] is String &&
                      (row['account_state'] as String).startsWith(
                        'mergedInto:',
                      ))
                : row['is_active'] == 0 &&
                      row['account_state'] == 'mergedInto:$ownerId',
          );
          lineage.add({
            'ownerId': identity,
            'createdAtUtcMs': row['created_at_utc_ms'],
            'upgradedAtUtcMs': row['upgraded_at_utc_ms'],
            'mergedIntoOwnerId': identity == ownerId ? null : ownerId,
          });
        }
      }
      return decode({
        'schema': schema,
        'id': identityFor(
          ownerId: ownerId,
          permitId: permitId,
          measurementRunId: measurementRunId,
          learningSessionId: _text(session['id']),
          proofRevision: proofRevision,
        ),
        'ownerId': ownerId,
        'measurementRunId': measurementRunId,
        'learningSessionId': session['id'],
        'proofRevision': proofRevision,
        'activityType': session['activity_type'],
        'sessionState': proofRevision == 1 ? 'active' : 'completed',
        'startedAtUtcMs': start,
        'endedAtUtcMs': proofRevision == 1 ? null : end,
        'appVersion': session['app_version'],
        'buildId': session['build_id'],
        'sessionConfigurationIdentity':
            session['session_configuration_identity'],
        'sessionConfigurationJson': session['session_configuration_json'],
        'pairStartOperation': pairStart,
        'pairCheckpointEventVersion': eventVersion,
        'pairOwnerLineage': lineage,
        'permitId': permitId,
        'permitPayloadSha256': permitPayloadSha256,
        'permitRevision': permitRevision,
      });
    } catch (_) {
      throw _invalid;
    }
  }

  /// All nested containers are immutable; no caller-supplied maps are retained.
  Map<String, Object?> toJson() => _payload;

  bool hasSameStartCore(ResearchSessionProof other) =>
      jsonEncode({
        for (final key in _keys)
          if (!_phaseKeys.contains(key)) key: _payload[key],
      }) ==
      jsonEncode({
        for (final key in _keys)
          if (!_phaseKeys.contains(key)) key: other._payload[key],
      });

  Map<String, Object?> toSessionProjection() => Map.unmodifiable({
    'id': learningSessionId,
    'owner_id': ownerId,
    'activity_type': activityType,
    'state': sessionState,
    'started_at_utc_ms': startedAtUtcMs,
    'ended_at_utc_ms': endedAtUtcMs,
    'app_version': appVersion,
    'build_id': buildId,
    'session_configuration_identity': sessionConfigurationIdentity,
    'session_configuration_json': sessionConfigurationJson,
  });

  static void _configuration(String owner, Object? identity, Object? source) {
    _require((identity == null) == (source == null));
    if (source == null) return;
    _text(identity);
    _require(source is String);
    final encoded = source as String;
    _boundedText(encoded, maximumConfigurationBytes);
    final configuration = SessionConfiguration.fromStableSerialization(encoded);
    _require(
      configuration.ownerId == owner &&
          configuration.contentIdentity == identity &&
          configuration.stableSerialization == encoded,
    );
  }

  static List<Map<String, Object?>> _lineage(
    Object? value,
    String owner,
    String actor,
  ) {
    _require(value is List && value.isNotEmpty && value.length <= 2);
    final expected = {owner, actor}.toList()..sort();
    final rows = value as List;
    _require(rows.length == expected.length);
    final result = <Map<String, Object?>>[];
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      _require(
        row is Map &&
            row.length == _lineageKeys.length &&
            row.keys.every(_lineageKeys.contains),
      );
      final map = row as Map;
      final identity = _text(map['ownerId']);
      final created = _utc(map['createdAtUtcMs']);
      final upgraded = _optionalUtc(map['upgradedAtUtcMs']);
      _require(
        identity == expected[index] &&
            (upgraded == null || upgraded >= created),
      );
      _require(
        identity == owner
            ? map['mergedIntoOwnerId'] == null
            : map['mergedIntoOwnerId'] == owner && upgraded != null,
      );
      result.add(
        Map<String, Object?>.unmodifiable({
          'ownerId': identity,
          'createdAtUtcMs': created,
          'upgradedAtUtcMs': upgraded,
          'mergedIntoOwnerId': map['mergedIntoOwnerId'],
        }),
      );
    }
    return List.unmodifiable(result);
  }

  static String _text(Object? value) {
    _require(
      value is String &&
          value.isNotEmpty &&
          value.length <= 256 &&
          value == value.trim() &&
          !value.contains('\u0000'),
    );
    return value as String;
  }

  static int _phase(Object? value) {
    _require(value is int && (value == 1 || value == 2));
    return value as int;
  }

  static int _utc(Object? value) {
    _require(value is int && value >= 0 && value <= _maximumUtcMs);
    return value as int;
  }

  static int? _optionalUtc(Object? value) => value == null ? null : _utc(value);

  static void _boundedJson(Object? value, int maximum) =>
      _boundedText(jsonEncode(value), maximum);

  static void _boundedText(String value, int maximum) {
    _require(value.length <= maximum && utf8.encode(value).length <= maximum);
  }

  static void _require(bool condition) {
    if (!condition) throw _invalid;
  }
}
