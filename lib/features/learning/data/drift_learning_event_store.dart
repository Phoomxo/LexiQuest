import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../events/domain/event_envelope_v2.dart';

final class DriftLearningEventStore {
  const DriftLearningEventStore(this.database);

  final db.AppDatabase database;

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

    await database
        .into(database.eventsV2)
        .insert(_companion(event), mode: InsertMode.insertOrIgnore);
  }

  Future<List<EventEnvelopeV2>> listPendingProjectionEvents({
    required String ownerId,
    required String projection,
    required int appliedVersion,
    required int limit,
    bool requireQuestApplied = false,
  }) async {
    if (limit <= 0) return const [];
    final versionSuffix = ':v$appliedVersion';
    final prerequisite = requireQuestApplied
        ? '''AND EXISTS (
              SELECT 1 FROM events_v2 quest_receipt
              WHERE quest_receipt.owner_id = source.owner_id
                AND quest_receipt.aggregate_id = source.event_id
                AND quest_receipt.event_type = 'LearningProjectionApplied'
                AND quest_receipt.idempotency_key =
                  'learning-projection:quest:' || source.event_id || ?
            )'''
        : '';
    final variables = <Variable<Object>>[
      Variable<String>(ownerId),
      Variable<String>(projection),
      Variable<String>(versionSuffix),
      if (requireQuestApplied) Variable<String>(versionSuffix),
      Variable<int>(limit),
    ];
    final idRows = await database
        .customSelect(
          '''SELECT source.event_id
         FROM events_v2 source
         WHERE source.owner_id = ?
           AND source.idempotency_key LIKE 'learning-attempt:%'
           AND NOT EXISTS (
             SELECT 1 FROM events_v2 receipt
             WHERE receipt.owner_id = source.owner_id
               AND receipt.aggregate_id = source.event_id
               AND receipt.event_type IN (
                 'LearningProjectionApplied', 'LearningProjectionSkipped'
               )
               AND receipt.idempotency_key =
                 'learning-projection:' || ? || ':' || source.event_id || ?
           )
           $prerequisite
         ORDER BY source.occurred_at_utc ASC, source.event_id ASC
         LIMIT ?''',
          variables: variables,
          readsFrom: {database.eventsV2},
        )
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
    return rows.map(_toEvent).toList(growable: false);
  }

  Future<void> markProjectionOutcome({
    required EventEnvelopeV2 source,
    required String projection,
    required int appliedVersion,
    required bool applied,
  }) {
    final key = _projectionKey(
      sourceEventId: source.eventId,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    return append(
      EventEnvelopeV2(
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
        },
      ),
    );
  }

  String _projectionKey({
    required String sourceEventId,
    required String projection,
    required int appliedVersion,
  }) => 'learning-projection:$projection:$sourceEventId:v$appliedVersion';

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
