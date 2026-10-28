import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../events/domain/event_envelope_v2.dart';
import '../domain/streak_policy.dart';

final class StreakProjectionApplication {
  const StreakProjectionApplication({
    required this.outcome,
    required this.receipt,
  }) : reasonCode = null;

  const StreakProjectionApplication.blocked(this.reasonCode)
    : outcome = null,
      receipt = null;

  final StreakOutcome? outcome;
  final StreakPolicyReceipt? receipt;
  final String? reasonCode;
}

/// Drift-backed persistence for [StreakState] and [LearningDayLog].
final class DriftStreakRepository {
  DriftStreakRepository(this._database);

  final db.AppDatabase _database;

  static const int cutoverVersion = 1;
  static const String cutoverPolicyVersion = 'gentle-streak-cutover-v1';

  // ── Read ──────────────────────────────────────────────────────────────────

  Future<StreakState> getOrCreate(String ownerId, int nowMs) async {
    final row = await (_database.select(
      _database.streakStates,
    )..where((t) => t.ownerId.equals(ownerId))).getSingleOrNull();
    if (row != null) return _rowToState(row);

    // First access — create initial row.
    await _database
        .into(_database.streakStates)
        .insert(
          db.StreakStatesCompanion.insert(
            ownerId: ownerId,
            updatedAtUtcMs: nowMs,
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return StreakState.initial(ownerId: ownerId, nowMs: nowMs);
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  Future<void> save(StreakState state) async {
    await _database
        .into(_database.streakStates)
        .insertOnConflictUpdate(
          db.StreakStatesCompanion(
            ownerId: Value(state.ownerId),
            currentStreakDays: Value(state.currentStreakDays),
            longestStreakDays: Value(state.longestStreakDays),
            freezeCount: Value(state.freezeCount),
            lastLearnedAtUtcMs: Value(state.lastLearnedAtUtcMs),
            updatedAtUtcMs: Value(state.updatedAtUtcMs),
          ),
        );
  }

  /// Establishes the immutable boundary between markerless legacy history and
  /// evidence created after this Streak policy became active for [ownerId].
  ///
  /// Bootstrap must await this before exposing learning writers or starting
  /// projection reconciliation. An empty owner is represented by a durable
  /// record with a null horizon, so the first later source remains eligible.
  Future<void> establishCutover({
    required String ownerId,
    required DateTime establishedAtUtc,
  }) => _database.transaction(
    () => _establishCutover(
      ownerId: _requiredOwnerId(ownerId),
      establishedAtUtc: _requireUtc(establishedAtUtc),
    ),
  );

  /// Establishes both owner boundaries before an owner namespace merge, then
  /// atomically retains the maximum canonical source tuple under [targetId].
  Future<void> mergeCutovers({
    required String sourceId,
    required String targetId,
    required DateTime establishedAtUtc,
  }) => _database.transaction(() async {
    final sourceOwnerId = _requiredOwnerId(sourceId);
    final targetOwnerId = _requiredOwnerId(targetId);
    if (sourceOwnerId == targetOwnerId) {
      await _establishCutover(
        ownerId: sourceOwnerId,
        establishedAtUtc: _requireUtc(establishedAtUtc),
      );
      return;
    }
    final establishedAt = _requireUtc(establishedAtUtc);
    await _establishCutover(
      ownerId: sourceOwnerId,
      establishedAtUtc: establishedAt,
    );
    await _establishCutover(
      ownerId: targetOwnerId,
      establishedAtUtc: establishedAt,
    );
    final source = await _readCutover(sourceOwnerId);
    final target = await _readCutover(targetOwnerId);
    if (source == null || target == null) {
      throw StateError('streak cutover merge is incomplete');
    }
    final mergedHorizon = _maxHorizon(source.horizon, target.horizon);
    final mergedEstablishedAtUtcMs =
        source.establishedAtUtcMs > target.establishedAtUtcMs
        ? source.establishedAtUtcMs
        : target.establishedAtUtcMs;
    await (_database.update(
      _database.eventsV2,
    )..where((row) => row.eventId.equals(_cutoverId(targetOwnerId)))).write(
      db.EventsV2Companion(
        occurredAtUtc: Value(
          DateTime.fromMillisecondsSinceEpoch(
            mergedEstablishedAtUtcMs,
            isUtc: true,
          ),
        ),
        recordedAtUtc: Value(
          DateTime.fromMillisecondsSinceEpoch(
            mergedEstablishedAtUtcMs,
            isUtc: true,
          ),
        ),
        payloadJson: Value(
          _cutoverPayload(
            ownerId: targetOwnerId,
            horizon: mergedHorizon,
            establishedAtUtcMs: mergedEstablishedAtUtcMs,
          ),
        ),
      ),
    );
    await (_database.delete(
      _database.eventsV2,
    )..where((row) => row.eventId.equals(_cutoverId(sourceOwnerId)))).go();
    final merged = await _readCutover(targetOwnerId);
    if (merged == null || !_sameHorizon(merged.horizon, mergedHorizon)) {
      throw StateError('streak cutover merge verification failed');
    }
  });

  /// Removes only the empty cutover created alongside a new owner when that
  /// owner transition is being rolled back before any learning can occur.
  Future<void> rollbackTransitionCutover({
    required String ownerId,
    required DateTime establishedAtUtc,
  }) => _database.transaction(() async {
    final canonicalOwnerId = _requiredOwnerId(ownerId);
    final expectedEstablishedAtUtcMs = _requireUtc(
      establishedAtUtc,
    ).millisecondsSinceEpoch;
    final cutover = await _readCutover(canonicalOwnerId);
    if (cutover == null ||
        cutover.horizon != null ||
        cutover.establishedAtUtcMs != expectedEstablishedAtUtcMs) {
      throw StateError('streak transition cutover is not rollback-safe');
    }
    final learningSource = await _database
        .customSelect(
          'SELECT 1 AS present FROM events_v2 '
          'WHERE owner_id = ? '
          "AND idempotency_key LIKE 'learning-attempt:%' LIMIT 1",
          variables: [Variable<String>(canonicalOwnerId)],
          readsFrom: {_database.eventsV2},
        )
        .getSingleOrNull();
    final application =
        await (_database.select(_database.eventsV2)
              ..where(
                (row) =>
                    row.ownerId.equals(canonicalOwnerId) &
                    row.eventType.equals('StreakPolicyApplied'),
              )
              ..limit(1))
            .getSingleOrNull();
    final state =
        await (_database.select(_database.streakStates)
              ..where((row) => row.ownerId.equals(canonicalOwnerId))
              ..limit(1))
            .getSingleOrNull();
    final day =
        await (_database.select(_database.learningDayLog)
              ..where((row) => row.ownerId.equals(canonicalOwnerId))
              ..limit(1))
            .getSingleOrNull();
    if (learningSource != null ||
        application != null ||
        state != null ||
        day != null) {
      throw StateError('streak transition cutover has durable learning');
    }
    final deleted =
        await (_database.delete(_database.eventsV2)..where(
              (row) =>
                  row.eventId.equals(_cutoverId(canonicalOwnerId)) &
                  row.ownerId.equals(canonicalOwnerId) &
                  row.eventType.equals('StreakPolicyCutover'),
            ))
            .go();
    if (deleted != 1 || await _readCutover(canonicalOwnerId) != null) {
      throw StateError('streak transition cutover rollback failed');
    }
  });

  /// Applies one canonical source event and its immutable Streak-domain record
  /// atomically. A Foundation receipt may be written later; replay always
  /// returns this stored application instead of evaluating in a new timezone.
  Future<StreakProjectionApplication> applyProjection({
    required EventEnvelopeV2 source,
    required String timezoneId,
    int activePolicyVersion = StreakPolicy.version,
  }) => _database.transaction(() async {
    final stored = await _readProjectionApplication(source);
    if (stored != null) return stored;
    if (activePolicyVersion != StreakPolicy.version) {
      throw StateError('unsupported active streak policy version');
    }
    final cutover = await _readCutover(source.ownerIdentity);
    if (cutover == null) {
      throw StateError('streak cutover is not established');
    }
    if (cutover.captures(source)) {
      return const StreakProjectionApplication.blocked('preMarkerCutover');
    }

    final occurredAtUtc = source.occurredAtUtc;
    final occurredAtUtcMs = occurredAtUtc.millisecondsSinceEpoch;
    final current = await getOrCreate(source.ownerIdentity, occurredAtUtcMs);
    final update = StreakPolicy.evaluate(
      current: current,
      nowUtc: occurredAtUtc,
      timezoneId: timezoneId,
    );
    if (update.changed) {
      await save(update.after.copyWith(updatedAtUtcMs: occurredAtUtcMs));
    }
    await recordLearningDay(
      ownerId: source.ownerIdentity,
      learningDay: update.receipt.learningDay,
      firstSessionAtUtcMs: occurredAtUtcMs,
    );
    await _writeProjectionApplication(
      source: source,
      timezoneId: timezoneId,
      update: update,
    );
    return StreakProjectionApplication(
      outcome: update.outcome,
      receipt: update.receipt,
    );
  });

  // ── LearningDayLog ────────────────────────────────────────────────────────

  /// Record that [ownerId] was active on [learningDay] (idempotent).
  ///
  /// [learningDay] must be a date string in `'YYYY-MM-DD'` format.
  Future<void> recordLearningDay({
    required String ownerId,
    required String learningDay,
    required int firstSessionAtUtcMs,
  }) async {
    final id = 'day:$ownerId:$learningDay';
    await _database
        .into(_database.learningDayLog)
        .insert(
          db.LearningDayLogCompanion.insert(
            id: id,
            ownerId: ownerId,
            learningDay: learningDay,
            firstSessionAtUtcMs: firstSessionAtUtcMs,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Returns all learning-day entries for [ownerId], newest first.
  Future<List<String>> getLearningDays(String ownerId) async {
    final rows =
        await (_database.select(_database.learningDayLog)
              ..where((t) => t.ownerId.equals(ownerId))
              ..orderBy([(t) => OrderingTerm.desc(t.firstSessionAtUtcMs)]))
            .get();
    return rows.map((r) => r.learningDay).toList(growable: false);
  }

  // ── Private ───────────────────────────────────────────────────────────────

  static String _applicationId(EventEnvelopeV2 source) =>
      'streak-application:${source.eventId}';

  static String _policyVersion(int version) => 'gentle-streak-v$version';

  static String _cutoverId(String ownerId) =>
      'streak-cutover:$ownerId:v$cutoverVersion';

  Future<void> _establishCutover({
    required String ownerId,
    required DateTime establishedAtUtc,
  }) async {
    if (await _readCutover(ownerId) != null) return;
    final lastSource = await _database
        .customSelect(
          'SELECT event_id, occurred_at_utc FROM events_v2 '
          'WHERE owner_id = ? '
          "AND idempotency_key LIKE 'learning-attempt:%' "
          'ORDER BY occurred_at_utc DESC, event_id DESC LIMIT 1',
          variables: [Variable<String>(ownerId)],
          readsFrom: {_database.eventsV2},
        )
        .getSingleOrNull();
    final horizon = lastSource == null
        ? null
        : _StreakCutoverHorizon(
            eventId: lastSource.read<String>('event_id'),
            occurredAtUtcMs: lastSource
                .read<DateTime>('occurred_at_utc')
                .toUtc()
                .millisecondsSinceEpoch,
          );
    final establishedAtUtcMs = establishedAtUtc.millisecondsSinceEpoch;
    final key = _cutoverId(ownerId);
    await _database
        .into(_database.eventsV2)
        .insert(
          db.EventsV2Companion.insert(
            eventId: key,
            eventType: 'StreakPolicyCutover',
            eventVersion: cutoverVersion,
            occurredAtUtc: establishedAtUtc,
            recordedAtUtc: establishedAtUtc,
            actorIdentity: ownerId,
            ownerId: ownerId,
            aggregateType: 'StreakPolicyCutover',
            aggregateId: ownerId,
            idempotencyKey: key,
            consentContextJson: jsonEncode(
              const ConsentContext.none().toJson(),
            ),
            policyVersion: const Value(cutoverPolicyVersion),
            appVersion: 'streak-cutover',
            buildId: 'v$cutoverVersion',
            privacyClassification: PrivacyClassification.ownerOnly.name,
            payloadJson: _cutoverPayload(
              ownerId: ownerId,
              horizon: horizon,
              establishedAtUtcMs: establishedAtUtcMs,
            ),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    if (await _readCutover(ownerId) == null) {
      throw StateError('durable streak cutover write conflict');
    }
  }

  Future<_StreakCutover?> _readCutover(String ownerId) async {
    final rows =
        await (_database.select(_database.eventsV2)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.eventType.equals('StreakPolicyCutover'),
            ))
            .get();
    if (rows.isEmpty) return null;
    if (rows.length != 1) {
      throw StateError('invalid durable streak cutover identity');
    }
    final row = rows.single;
    late final Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(row.payloadJson);
      if (decoded is! Map) throw const FormatException();
      payload = decoded.cast<String, dynamic>();
    } catch (_) {
      throw StateError('invalid durable streak cutover payload');
    }
    const keys = <String>{
      'ownerId',
      'horizonEventId',
      'horizonOccurredAtUtcMs',
      'establishedAtUtcMs',
      'policyVersion',
      'cutoverVersion',
    };
    final eventId = payload['horizonEventId'];
    final occurredAtUtcMs = payload['horizonOccurredAtUtcMs'];
    final establishedAtUtcMs = payload['establishedAtUtcMs'];
    final validEmptyHorizon = eventId == null && occurredAtUtcMs == null;
    final validSourceHorizon =
        eventId is String &&
        eventId.isNotEmpty &&
        occurredAtUtcMs is int &&
        occurredAtUtcMs >= 0;
    if (payload.keys.toSet().length != keys.length ||
        !payload.keys.toSet().containsAll(keys) ||
        payload['ownerId'] != ownerId ||
        (!validEmptyHorizon && !validSourceHorizon) ||
        establishedAtUtcMs is! int ||
        establishedAtUtcMs < 0 ||
        payload['policyVersion'] != StreakPolicy.version ||
        payload['cutoverVersion'] != cutoverVersion ||
        row.eventId != _cutoverId(ownerId) ||
        row.idempotencyKey != _cutoverId(ownerId) ||
        row.aggregateType != 'StreakPolicyCutover' ||
        row.aggregateId != ownerId ||
        row.policyVersion != cutoverPolicyVersion) {
      throw StateError('invalid durable streak cutover');
    }
    return _StreakCutover(
      horizon: validEmptyHorizon
          ? null
          : _StreakCutoverHorizon(
              eventId: eventId as String,
              occurredAtUtcMs: occurredAtUtcMs as int,
            ),
      establishedAtUtcMs: establishedAtUtcMs,
    );
  }

  static String _cutoverPayload({
    required String ownerId,
    required _StreakCutoverHorizon? horizon,
    required int establishedAtUtcMs,
  }) => jsonEncode(<String, dynamic>{
    'ownerId': ownerId,
    'horizonEventId': horizon?.eventId,
    'horizonOccurredAtUtcMs': horizon?.occurredAtUtcMs,
    'establishedAtUtcMs': establishedAtUtcMs,
    'policyVersion': StreakPolicy.version,
    'cutoverVersion': cutoverVersion,
  });

  static String _requiredOwnerId(String ownerId) {
    if (ownerId.trim() != ownerId || ownerId.isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'must be non-empty');
    }
    return ownerId;
  }

  static DateTime _requireUtc(DateTime value) {
    if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(value, 'establishedAtUtc', 'must be UTC');
    }
    return value;
  }

  static _StreakCutoverHorizon? _maxHorizon(
    _StreakCutoverHorizon? first,
    _StreakCutoverHorizon? second,
  ) {
    if (first == null) return second;
    if (second == null) return first;
    return first.isAfter(second) ? first : second;
  }

  static bool _sameHorizon(
    _StreakCutoverHorizon? first,
    _StreakCutoverHorizon? second,
  ) =>
      first?.eventId == second?.eventId &&
      first?.occurredAtUtcMs == second?.occurredAtUtcMs;

  Future<StreakProjectionApplication?> _readProjectionApplication(
    EventEnvelopeV2 source,
  ) async {
    final key = _applicationId(source);
    final rows =
        await (_database.select(_database.eventsV2)..where(
              (row) =>
                  row.eventId.equals(key) |
                  row.idempotencyKey.equals(key) |
                  (row.ownerId.equals(source.ownerIdentity) &
                      row.eventType.equals('StreakPolicyApplied') &
                      row.aggregateType.equals('StreakPolicy') &
                      row.aggregateId.equals(source.eventId)),
            ))
            .get();
    if (rows.isEmpty) return null;
    if (rows.length != 1) {
      throw StateError('invalid durable streak application identity');
    }
    final row = rows.single;
    late final Map<String, dynamic> payload;
    late final StreakPolicyReceipt receipt;
    late final StreakOutcome outcome;
    try {
      final decoded = jsonDecode(row.payloadJson);
      if (decoded is! Map) throw const FormatException();
      payload = decoded.cast<String, dynamic>();
      final rawResult = payload['result'];
      if (rawResult is! Map) throw const FormatException();
      receipt = StreakPolicyReceipt.fromJson(rawResult.cast<String, dynamic>());
      outcome = StreakOutcome.values.byName(payload['outcome'] as String);
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('invalid durable streak application payload');
    }
    final policyVersionMatch = RegExp(
      r'^gentle-streak-v([1-9][0-9]*)$',
    ).firstMatch(row.policyVersion ?? '');
    final storedPolicyVersion = policyVersionMatch == null
        ? null
        : int.tryParse(policyVersionMatch.group(1)!);
    final legacyKey = storedPolicyVersion == null
        ? null
        : '$key:v$storedPolicyVersion';
    final storedKey = row.eventId;
    const payloadKeys = <String>{
      'sourceEventId',
      'sourceOccurredAtUtcMs',
      'timezoneId',
      'outcome',
      'result',
    };
    final storedTimezoneId = payload['timezoneId'];
    final envelopeMismatches = <String>[
      if (storedKey != key && storedKey != legacyKey) 'eventId',
      if (row.eventType != 'StreakPolicyApplied') 'eventType',
      if (row.eventVersion != 1) 'eventVersion',
      if (row.occurredAtUtc.toUtc().millisecondsSinceEpoch !=
          source.occurredAtUtc.millisecondsSinceEpoch)
        'occurredAtUtc',
      if (row.recordedAtUtc.toUtc().millisecondsSinceEpoch !=
          source.recordedAtUtc.millisecondsSinceEpoch)
        'recordedAtUtc',
      if (row.actorIdentity != source.actorIdentity) 'actorIdentity',
      if (row.ownerId != source.ownerIdentity) 'ownerIdentity',
      if (row.tenantContextJson != _json(source.tenantContext?.toJson()))
        'tenantContext',
      if (row.aggregateType != 'StreakPolicy') 'aggregateType',
      if (row.aggregateId != source.eventId) 'aggregateId',
      if (row.correlationId != source.correlationId) 'correlationId',
      if (row.causationId != source.eventId) 'causationId',
      if (row.idempotencyKey != storedKey) 'idempotencyKey',
      if (row.consentContextJson != jsonEncode(source.consentContext.toJson()))
        'consentContext',
      if (row.experimentContextJson !=
          _json(source.experimentContext?.toJson()))
        'experimentContext',
      if (row.contentRevision != source.contentRevision) 'contentRevision',
      if (storedPolicyVersion == null) 'policyVersion',
      if (row.appVersion != source.appVersion) 'appVersion',
      if (row.buildId != source.buildId) 'buildId',
      if (row.providerProvenanceJson !=
          _json(source.providerProvenance?.toJson()))
        'providerProvenance',
      if (row.privacyClassification != source.privacyClassification.name)
        'privacyClassification',
    ];
    final invalidSections = <String>[
      if (payload.keys.toSet().length != payloadKeys.length ||
          !payload.keys.toSet().containsAll(payloadKeys))
        'payloadShape',
      if (envelopeMismatches.isNotEmpty)
        'eventEnvelope(${envelopeMismatches.join('|')})',
      if (payload['sourceEventId'] != source.eventId ||
          payload['sourceOccurredAtUtcMs'] !=
              source.occurredAtUtc.millisecondsSinceEpoch)
        'sourceBinding',
      if (storedTimezoneId is! String ||
          storedTimezoneId.trim() != storedTimezoneId ||
          storedTimezoneId.isEmpty)
        'timezoneBinding',
      if (receipt.ownerId != source.ownerIdentity ||
          receipt.policyVersion != storedPolicyVersion)
        'resultBinding',
    ];
    if (invalidSections.isNotEmpty) {
      throw StateError(
        'invalid durable streak application: ${invalidSections.join(',')}',
      );
    }
    if (storedKey != key) {
      final updated = await _database.customUpdate(
        'UPDATE events_v2 SET event_id = ?, idempotency_key = ? '
        'WHERE event_id = ? AND idempotency_key = ?',
        variables: [
          Variable<String>(key),
          Variable<String>(key),
          Variable<String>(storedKey),
          Variable<String>(storedKey),
        ],
        updates: {_database.eventsV2},
      );
      if (updated != 1) {
        throw StateError('durable streak application alias conflict');
      }
    }
    return StreakProjectionApplication(outcome: outcome, receipt: receipt);
  }

  Future<void> _writeProjectionApplication({
    required EventEnvelopeV2 source,
    required String timezoneId,
    required StreakUpdate update,
  }) async {
    final key = _applicationId(source);
    final payload = <String, dynamic>{
      'sourceEventId': source.eventId,
      'sourceOccurredAtUtcMs': source.occurredAtUtc.millisecondsSinceEpoch,
      'timezoneId': timezoneId,
      'outcome': update.outcome.name,
      'result': update.receipt.toJson(),
    };
    await _database
        .into(_database.eventsV2)
        .insert(
          db.EventsV2Companion.insert(
            eventId: key,
            eventType: 'StreakPolicyApplied',
            eventVersion: 1,
            occurredAtUtc: source.occurredAtUtc,
            recordedAtUtc: source.recordedAtUtc,
            actorIdentity: source.actorIdentity,
            ownerId: source.ownerIdentity,
            tenantContextJson: Value(_json(source.tenantContext?.toJson())),
            aggregateType: 'StreakPolicy',
            aggregateId: source.eventId,
            correlationId: Value(source.correlationId),
            causationId: Value(source.eventId),
            idempotencyKey: key,
            consentContextJson: jsonEncode(source.consentContext.toJson()),
            experimentContextJson: Value(
              _json(source.experimentContext?.toJson()),
            ),
            contentRevision: Value(source.contentRevision),
            policyVersion: Value(_policyVersion(update.receipt.policyVersion)),
            appVersion: source.appVersion,
            buildId: source.buildId,
            providerProvenanceJson: Value(
              _json(source.providerProvenance?.toJson()),
            ),
            privacyClassification: source.privacyClassification.name,
            payloadJson: jsonEncode(payload),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    final stored = await _readProjectionApplication(source);
    if (stored == null ||
        stored.receipt == null ||
        stored.outcome != update.outcome ||
        jsonEncode(stored.receipt!.toJson()) !=
            jsonEncode(update.receipt.toJson())) {
      throw StateError('durable streak application write conflict');
    }
  }

  static String? _json(Map<String, dynamic>? value) =>
      value == null ? null : jsonEncode(value);

  StreakState _rowToState(db.StreakState row) => StreakState(
    ownerId: row.ownerId,
    currentStreakDays: row.currentStreakDays,
    longestStreakDays: row.longestStreakDays,
    freezeCount: row.freezeCount,
    lastLearnedAtUtcMs: row.lastLearnedAtUtcMs,
    updatedAtUtcMs: row.updatedAtUtcMs,
  );
}

final class _StreakCutoverHorizon {
  const _StreakCutoverHorizon({
    required this.eventId,
    required this.occurredAtUtcMs,
  });

  final String eventId;
  final int occurredAtUtcMs;

  bool isAfter(_StreakCutoverHorizon other) =>
      occurredAtUtcMs > other.occurredAtUtcMs ||
      (occurredAtUtcMs == other.occurredAtUtcMs &&
          eventId.compareTo(other.eventId) > 0);
}

final class _StreakCutover {
  const _StreakCutover({
    required this.horizon,
    required this.establishedAtUtcMs,
  });

  final _StreakCutoverHorizon? horizon;
  final int establishedAtUtcMs;

  bool captures(EventEnvelopeV2 source) {
    final boundary = horizon;
    if (boundary == null) return false;
    final sourceTime = source.occurredAtUtc.millisecondsSinceEpoch;
    return sourceTime < boundary.occurredAtUtcMs ||
        (sourceTime == boundary.occurredAtUtcMs &&
            source.eventId.compareTo(boundary.eventId) <= 0);
  }
}
