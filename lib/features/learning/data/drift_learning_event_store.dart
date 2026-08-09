import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../events/domain/event_envelope_v2.dart';

final class PendingLearningProjectionEvent {
  const PendingLearningProjectionEvent({
    required this.event,
    this.prerequisiteApplied,
    this.prerequisitePayload = const <String, dynamic>{},
  });

  final EventEnvelopeV2 event;
  final bool? prerequisiteApplied;
  final Map<String, dynamic> prerequisitePayload;
}

final class DriftLearningEventStore {
  const DriftLearningEventStore(this.database);

  static const int appliedProjectionVersion = 1;
  static const List<String> _projectionNames = ['quest', 'streak', 'reward'];

  final db.AppDatabase database;

  static List<String> projectionCursorIds({
    required String ownerId,
    required int appliedVersion,
  }) => _projectionNames
      .map(
        (projection) =>
            'learning-projection-cursor:$ownerId:$projection:v$appliedVersion',
      )
      .toList(growable: false);

  Future<void> append(EventEnvelopeV2 event) async {
    final existing =
        await (database.select(database.eventsV2)..where(
              (row) =>
                  row.eventId.equals(event.eventId) |
                  (row.ownerId.equals(event.ownerIdentity) &
                      row.idempotencyKey.equals(event.idempotencyKey)),
            ))
            .getSingleOrNull();
    if (existing != null) {
      if (!_sameEvent(existing, event)) {
        throw StateError(
          'learning event identity already exists with different evidence',
        );
      }
      return;
    }

    await database.transaction(() async {
      await database
          .into(database.eventsV2)
          .insert(_companion(event), mode: InsertMode.insertOrIgnore);
      await _rewindCursorsPastLateSource(event);
    });
  }

  Future<void> _rewindCursorsPastLateSource(EventEnvelopeV2 event) async {
    // Projection order remains the durable (occurredAtUtc, eventId) tuple.
    // When the device clock moves backwards, a newly committed source can
    // sort behind an existing cursor. Rewind only affected fixed-key cursors;
    // immutable receipts and idempotent sinks make the bounded tail replay
    // safe, while keeping semantic occurrence time intact for quest/streak.
    final fixedCursorIds = projectionCursorIds(
      ownerId: event.ownerIdentity,
      appliedVersion: appliedProjectionVersion,
    );
    final cursors = await (database.select(
      database.eventsV2,
    )..where((row) => row.eventId.isIn(fixedCursorIds))).get();
    final lateCursors = cursors
        .where((cursor) {
          final time = cursor.occurredAtUtc.compareTo(event.occurredAtUtc);
          return time > 0 ||
              (time == 0 && cursor.aggregateId.compareTo(event.eventId) >= 0);
        })
        .toList(growable: false);
    final ids = lateCursors
        .map((cursor) => cursor.eventId)
        .toList(growable: false);
    if (ids.isEmpty) return;
    final predecessorId = await database
        .customSelect(
          '''
          SELECT event_id
          FROM events_v2 INDEXED BY idx_events_v2_owner_occurred
          WHERE owner_id = ?
            AND idempotency_key LIKE 'learning-attempt:%'
            AND (
              occurred_at_utc < ? OR
              (occurred_at_utc = ? AND event_id < ?)
            )
          ORDER BY occurred_at_utc DESC, event_id DESC
          LIMIT 1
          ''',
          variables: [
            Variable<String>(event.ownerIdentity),
            Variable<DateTime>(event.occurredAtUtc),
            Variable<DateTime>(event.occurredAtUtc),
            Variable<String>(event.eventId),
          ],
          readsFrom: {database.eventsV2},
        )
        .getSingleOrNull();
    if (predecessorId == null) {
      await (database.delete(
        database.eventsV2,
      )..where((row) => row.eventId.isIn(ids))).go();
      return;
    }
    final predecessor =
        await (database.select(database.eventsV2)..where(
              (row) =>
                  row.eventId.equals(predecessorId.read<String>('event_id')),
            ))
            .getSingle();
    final source = _toEvent(predecessor);
    for (final cursor in lateCursors) {
      final payload = jsonDecode(cursor.payloadJson) as Map<String, dynamic>;
      final rewound = EventEnvelopeV2(
        eventId: cursor.eventId,
        eventType: 'LearningProjectionCursor',
        eventVersion: cursor.eventVersion,
        occurredAtUtc: source.occurredAtUtc,
        recordedAtUtc: source.recordedAtUtc,
        actorIdentity: source.actorIdentity,
        ownerIdentity: source.ownerIdentity,
        aggregateType: 'LearningProjectionCursor',
        aggregateId: source.eventId,
        causationId: source.eventId,
        idempotencyKey: cursor.idempotencyKey,
        consentContext: source.consentContext,
        appVersion: source.appVersion,
        buildId: source.buildId,
        privacyClassification: source.privacyClassification,
        payload: {
          'sourceEventId': source.eventId,
          'projection': payload['projection'],
          'appliedVersion': payload['appliedVersion'],
        },
      );
      await database
          .into(database.eventsV2)
          .insertOnConflictUpdate(_companion(rewound));
    }
  }

  Future<List<PendingLearningProjectionEvent>> listPendingProjectionEvents({
    required String ownerId,
    required String projection,
    required int appliedVersion,
    required int limit,
    String? prerequisiteProjection,
  }) async {
    if (limit <= 0) return const [];
    final cursor =
        await (database.select(database.eventsV2)..where(
              (row) => row.eventId.equals(
                _cursorKey(
                  ownerId: ownerId,
                  projection: projection,
                  appliedVersion: appliedVersion,
                ),
              ),
            ))
            .getSingleOrNull();
    final afterCursor = cursor == null
        ? ''
        : '''AND (
              source.occurred_at_utc > ? OR
              (source.occurred_at_utc = ? AND source.event_id > ?)
            )''';
    final variables = <Variable<Object>>[
      Variable<String>(ownerId),
      if (cursor != null) ...[
        Variable<DateTime>(cursor.occurredAtUtc),
        Variable<DateTime>(cursor.occurredAtUtc),
        Variable<String>(cursor.aggregateId),
      ],
      Variable<int>(limit),
    ];
    final candidateSql =
        '''
      SELECT source.event_id, source.occurred_at_utc
      FROM events_v2 source INDEXED BY idx_events_v2_owner_occurred
      WHERE source.owner_id = ?
        AND source.idempotency_key LIKE 'learning-attempt:%'
        $afterCursor
      ORDER BY source.occurred_at_utc ASC, source.event_id ASC
      LIMIT ?''';
    final prerequisite = prerequisiteProjection;
    final sql = prerequisite == null
        ? candidateSql
        : '''SELECT candidate.event_id, candidate.occurred_at_utc,
                    prerequisite.event_type AS prerequisite_type,
                    prerequisite.payload_json AS prerequisite_payload
             FROM ($candidateSql) candidate
             LEFT JOIN events_v2 prerequisite
               ON prerequisite.event_id =
                 'learning-projection:$prerequisite:' ||
                 candidate.event_id || ':v$appliedVersion'
             ORDER BY candidate.occurred_at_utc ASC, candidate.event_id ASC''';
    final idRows = await database
        .customSelect(sql, variables: variables, readsFrom: {database.eventsV2})
        .get();
    final ids = idRows.map((row) => row.read<String>('event_id')).toList();
    if (ids.isEmpty) return const [];
    final rows =
        await (database.select(database.eventsV2)
              ..where((row) => row.eventId.isIn(ids))
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtc),
                (row) => OrderingTerm.asc(row.eventId),
              ]))
            .get();
    final eventsById = <String, EventEnvelopeV2>{
      for (final row in rows) row.eventId: _toEvent(row),
    };
    return idRows
        .map((row) {
          final eventId = row.read<String>('event_id');
          if (prerequisite == null) {
            return PendingLearningProjectionEvent(event: eventsById[eventId]!);
          }
          final prerequisiteType = row.readNullable<String>(
            'prerequisite_type',
          );
          final prerequisiteJson = row.readNullable<String>(
            'prerequisite_payload',
          );
          final receiptPayload = prerequisiteJson == null
              ? const <String, dynamic>{}
              : jsonDecode(prerequisiteJson) as Map<String, dynamic>;
          return PendingLearningProjectionEvent(
            event: eventsById[eventId]!,
            prerequisiteApplied: prerequisiteType == null
                ? null
                : prerequisiteType == 'LearningProjectionApplied',
            prerequisitePayload:
                (receiptPayload['result'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{},
          );
        })
        .toList(growable: false);
  }

  Future<void> markProjectionOutcome({
    required EventEnvelopeV2 source,
    required String projection,
    required int appliedVersion,
    required bool applied,
    Map<String, dynamic> result = const <String, dynamic>{},
  }) async {
    final key = _projectionKey(
      sourceEventId: source.eventId,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    final receipt = EventEnvelopeV2(
      eventId: key,
      eventType: applied
          ? 'LearningProjectionApplied'
          : 'LearningProjectionSkipped',
      eventVersion: 1,
      occurredAtUtc: source.occurredAtUtc,
      recordedAtUtc: source.recordedAtUtc,
      actorIdentity: source.actorIdentity,
      ownerIdentity: source.ownerIdentity,
      aggregateType: 'LearningProjection',
      aggregateId: source.eventId,
      causationId: source.eventId,
      idempotencyKey: key,
      consentContext: source.consentContext,
      appVersion: source.appVersion,
      buildId: source.buildId,
      privacyClassification: source.privacyClassification,
      payload: {
        'sourceEventId': source.eventId,
        'projection': projection,
        'appliedVersion': appliedVersion,
        'outcome': applied ? 'applied' : 'notApplicable',
        'result': result,
      },
    );
    final cursorKey = _cursorKey(
      ownerId: source.ownerIdentity,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    final cursor = EventEnvelopeV2(
      eventId: cursorKey,
      eventType: 'LearningProjectionCursor',
      eventVersion: 1,
      occurredAtUtc: source.occurredAtUtc,
      recordedAtUtc: source.recordedAtUtc,
      actorIdentity: source.actorIdentity,
      ownerIdentity: source.ownerIdentity,
      aggregateType: 'LearningProjectionCursor',
      aggregateId: source.eventId,
      causationId: source.eventId,
      idempotencyKey: cursorKey,
      consentContext: source.consentContext,
      appVersion: source.appVersion,
      buildId: source.buildId,
      privacyClassification: source.privacyClassification,
      payload: {
        'sourceEventId': source.eventId,
        'projection': projection,
        'appliedVersion': appliedVersion,
      },
    );
    await database.transaction(() async {
      await database
          .into(database.eventsV2)
          .insert(_companion(receipt), mode: InsertMode.insertOrIgnore);
      await database
          .into(database.eventsV2)
          .insertOnConflictUpdate(_companion(cursor));
    });
  }

  String _projectionKey({
    required String sourceEventId,
    required String projection,
    required int appliedVersion,
  }) => 'learning-projection:$projection:$sourceEventId:v$appliedVersion';

  String _cursorKey({
    required String ownerId,
    required String projection,
    required int appliedVersion,
  }) => 'learning-projection-cursor:$ownerId:$projection:v$appliedVersion';

  db.EventsV2Companion _companion(EventEnvelopeV2 event) {
    return db.EventsV2Companion.insert(
      eventId: event.eventId,
      eventType: event.eventType,
      eventVersion: event.eventVersion,
      occurredAtUtc: event.occurredAtUtc,
      recordedAtUtc: event.recordedAtUtc,
      actorIdentity: event.actorIdentity,
      ownerId: event.ownerIdentity,
      tenantContextJson: Value(
        event.tenantContext == null
            ? null
            : jsonEncode(event.tenantContext!.toJson()),
      ),
      aggregateType: event.aggregateType,
      aggregateId: event.aggregateId,
      correlationId: Value(event.correlationId),
      causationId: Value(event.causationId),
      idempotencyKey: event.idempotencyKey,
      consentContextJson: jsonEncode(event.consentContext.toJson()),
      experimentContextJson: Value(
        event.experimentContext == null
            ? null
            : jsonEncode(event.experimentContext!.toJson()),
      ),
      contentRevision: Value(event.contentRevision),
      policyVersion: Value(event.policyVersion),
      appVersion: event.appVersion,
      buildId: event.buildId,
      providerProvenanceJson: Value(
        event.providerProvenance == null
            ? null
            : jsonEncode(event.providerProvenance!.toJson()),
      ),
      privacyClassification: event.privacyClassification.name,
      payloadJson: jsonEncode(event.payload),
    );
  }

  EventEnvelopeV2 _toEvent(db.EventsV2Data row) {
    final consentJson =
        jsonDecode(row.consentContextJson) as Map<String, dynamic>;
    return EventEnvelopeV2(
      eventId: row.eventId,
      eventType: row.eventType,
      eventVersion: row.eventVersion,
      occurredAtUtc: row.occurredAtUtc.toUtc(),
      recordedAtUtc: row.recordedAtUtc.toUtc(),
      actorIdentity: row.actorIdentity,
      ownerIdentity: row.ownerId,
      tenantContext: row.tenantContextJson == null
          ? null
          : TenantContext.fromJson(
              jsonDecode(row.tenantContextJson!) as Map<String, dynamic>,
            ),
      aggregateType: row.aggregateType,
      aggregateId: row.aggregateId,
      correlationId: row.correlationId,
      causationId: row.causationId,
      idempotencyKey: row.idempotencyKey,
      consentContext: ConsentContext(
        researchConsentVersion:
            consentJson['researchConsentVersion'] as int? ?? 0,
        aiConsentGranted: consentJson['aiConsentGranted'] as bool? ?? false,
        voiceConsentGranted:
            consentJson['voiceConsentGranted'] as bool? ?? false,
        socialConsentGranted:
            consentJson['socialConsentGranted'] as bool? ?? false,
      ),
      experimentContext: row.experimentContextJson == null
          ? null
          : ExperimentContext.fromJson(
              jsonDecode(row.experimentContextJson!) as Map<String, dynamic>,
            ),
      contentRevision: row.contentRevision,
      policyVersion: row.policyVersion,
      appVersion: row.appVersion,
      buildId: row.buildId,
      providerProvenance: row.providerProvenanceJson == null
          ? null
          : ProviderProvenance.fromJson(
              jsonDecode(row.providerProvenanceJson!) as Map<String, dynamic>,
            ),
      privacyClassification: PrivacyClassification.values.byName(
        row.privacyClassification,
      ),
      payload: jsonDecode(row.payloadJson) as Map<String, dynamic>,
    );
  }

  bool _sameEvent(db.EventsV2Data row, EventEnvelopeV2 event) {
    return jsonEncode(_toEvent(row).toJson()) == jsonEncode(event.toJson());
  }
}
