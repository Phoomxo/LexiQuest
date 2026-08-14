import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../events/domain/event_envelope_v2.dart';
import '../domain/evidence_context.dart';
import '../domain/evidence_eligibility_policy.dart';
import '../domain/learning_evidence_contract.dart';

abstract interface class EvidencePolicyRolloutModeProvider {
  Future<EvidencePolicyRolloutMode> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
  });
}

final class ContextEvidencePolicyRolloutModeProvider
    implements EvidencePolicyRolloutModeProvider {
  const ContextEvidencePolicyRolloutModeProvider();

  @override
  Future<EvidencePolicyRolloutMode> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
  }) async => evidenceContext.rolloutMode;
}

final class FixedEvidencePolicyRolloutModeProvider
    implements EvidencePolicyRolloutModeProvider {
  const FixedEvidencePolicyRolloutModeProvider(this.mode);

  const FixedEvidencePolicyRolloutModeProvider.legacy()
    : mode = EvidencePolicyRolloutMode.legacy;

  final EvidencePolicyRolloutMode mode;

  @override
  Future<EvidencePolicyRolloutMode> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
  }) async => mode;
}

enum LearningProjectionOutcome { applied, notApplicable, blocked }

final class LearningEvidenceProjectionDecisionRecord {
  const LearningEvidenceProjectionDecisionRecord({
    required this.projection,
    required this.rolloutMode,
    required this.effectiveDecision,
    required this.candidateV1Decision,
    required this.policyVersion,
    required this.divergence,
  });

  final LearningProjection projection;
  final EvidencePolicyRolloutMode rolloutMode;
  final ProjectionDisposition effectiveDecision;
  final ProjectionDisposition? candidateV1Decision;
  final String policyVersion;
  final bool divergence;

  Map<String, Object?> toJson() => <String, Object?>{
    'projection': projection.name,
    'rolloutMode': rolloutMode.name,
    'effectiveDecision': effectiveDecision.name,
    'candidateV1Decision': candidateV1Decision?.name,
    'policyVersion': policyVersion,
    'divergence': divergence,
  };
}

final class LearningEvidenceDecisionSet {
  const LearningEvidenceDecisionSet({
    required this.sourceEvidenceId,
    required this.context,
    required this.decisions,
  });

  final String sourceEvidenceId;
  final EvidenceContext context;
  final List<LearningEvidenceProjectionDecisionRecord> decisions;

  LearningEvidenceProjectionDecisionRecord decisionFor(
    LearningProjection projection,
  ) => decisions.singleWhere((decision) => decision.projection == projection);

  bool allows(LearningProjection projection) {
    return switch (decisionFor(projection).effectiveDecision) {
      ProjectionDisposition.allow => true,
      ProjectionDisposition.deny => false,
      ProjectionDisposition.protocolControlled => context.engagementAllowed,
    };
  }

  Map<String, Object?> toPayload() => <String, Object?>{
    'sourceEvidenceId': sourceEvidenceId,
    'evidenceClass': context.evidenceClass.name,
    'policyVersion': context.policyVersion,
    'rolloutMode': context.rolloutMode.name,
    'decisions': decisions.map((decision) => decision.toJson()).toList(),
  };
}

final class ResolvedLearningEvidence {
  const ResolvedLearningEvidence({
    required this.attempt,
    required this.context,
    required this.decisionSet,
  });

  final db.AnswerAttempt attempt;
  final EvidenceContext context;
  final LearningEvidenceDecisionSet decisionSet;
}

final class LearningEvidenceResolution {
  const LearningEvidenceResolution.resolved(this.evidence) : reasonCode = null;

  const LearningEvidenceResolution.blocked(this.reasonCode) : evidence = null;

  final ResolvedLearningEvidence? evidence;
  final String? reasonCode;

  bool get isResolved => evidence != null;
}

final class LearningProjectionReceipt {
  const LearningProjectionReceipt({
    required this.outcome,
    required this.result,
    this.reasonCode,
    this.bridgedFromVersion,
  });

  final LearningProjectionOutcome outcome;
  final Map<String, dynamic> result;
  final String? reasonCode;
  final int? bridgedFromVersion;
}

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
  const DriftLearningEventStore(
    this.database, {
    this.evidencePolicy = const EvidenceEligibilityPolicySet(),
    this.rolloutModeProvider = const ContextEvidencePolicyRolloutModeProvider(),
  });

  static const int appliedProjectionVersion = 2;
  static const List<String> _projectionNames = ['quest', 'streak', 'reward'];

  final db.AppDatabase database;
  final EvidenceEligibilityPolicy evidencePolicy;
  final EvidencePolicyRolloutModeProvider rolloutModeProvider;

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
    _requireCanonicalEventTime(event);
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

  Future<EventEnvelopeV2?> readBySourceEvidenceId(
    String sourceEvidenceId,
  ) async {
    final eventId = LearningEvidenceContract.learningEventId(sourceEvidenceId);
    final expectedIdempotencyKey =
        LearningEvidenceContract.learningAttemptIdempotencyKey(
          sourceEvidenceId,
        );
    final row =
        await (database.select(database.eventsV2)
              ..where((candidate) => candidate.eventId.equals(eventId)))
            .getSingleOrNull();
    if (row == null) return null;
    final event = _toEvent(row);
    if (event.eventId != eventId ||
        event.eventVersion != 2 ||
        event.idempotencyKey != expectedIdempotencyKey ||
        event.payload['attemptId'] != sourceEvidenceId) {
      throw StateError('stored learning event has corrupt source identity');
    }
    _requireCanonicalEventTime(event, stateError: true);
    return event;
  }

  Future<LearningEvidenceDecisionSet> ensureDecisionSetForAttempt({
    required db.AnswerAttempt attempt,
    EventEnvelopeV2? sourceEvent,
  }) async {
    final context = _contextForAttempt(attempt);
    final expected = _buildDecisionSet(
      sourceEvidenceId: attempt.id,
      context: context,
      rolloutMode: context.rolloutMode,
    );
    final eventId = _decisionSetEventId(attempt.id);
    final existing = await (database.select(
      database.eventsV2,
    )..where((row) => row.eventId.equals(eventId))).getSingleOrNull();
    if (existing != null) {
      _validateStoredDecisionSet(
        row: existing,
        attempt: attempt,
        expected: expected,
      );
      return expected;
    }

    final configuredMode = await rolloutModeProvider.resolve(
      ownerId: attempt.ownerId,
      evidenceContext: context,
    );
    if (configuredMode != context.rolloutMode) {
      throw StateError(
        'evidence rollout ${context.rolloutMode.name} is not configured',
      );
    }
    final candidate = _decisionSetEvent(
      attempt: attempt,
      sourceEvent: sourceEvent,
      decisionSet: expected,
    );
    await database.transaction(() async {
      await database
          .into(database.eventsV2)
          .insert(_companion(candidate), mode: InsertMode.insertOrIgnore);
      final stored = await (database.select(
        database.eventsV2,
      )..where((row) => row.eventId.equals(eventId))).getSingle();
      _validateStoredDecisionSet(
        row: stored,
        attempt: attempt,
        expected: expected,
      );
    });
    return expected;
  }

  Future<LearningEvidenceResolution> resolveEvidenceForSource(
    EventEnvelopeV2 source,
  ) async {
    final attemptId = source.payload['attemptId'];
    if (attemptId is! String ||
        !LearningEvidenceContract.validIdentifier(attemptId)) {
      return const LearningEvidenceResolution.blocked('invalidAttemptId');
    }
    final attempt = await (database.select(
      database.answerAttempts,
    )..where((row) => row.id.equals(attemptId))).getSingleOrNull();
    if (attempt == null) {
      return const LearningEvidenceResolution.blocked(
        'canonicalAttemptMissing',
      );
    }
    if (attempt.ownerId != source.ownerIdentity) {
      return const LearningEvidenceResolution.blocked('attemptOwnerMismatch');
    }

    late final EvidenceContext context;
    try {
      context = _contextForAttempt(attempt);
    } on FormatException {
      return const LearningEvidenceResolution.blocked(
        'invalidCanonicalEvidenceContext',
      );
    } on TypeError {
      return const LearningEvidenceResolution.blocked(
        'invalidCanonicalEvidenceContext',
      );
    }

    if (source.payload.containsKey('evidenceContext')) {
      final payloadContext = source.payload['evidenceContext'];
      if (payloadContext is! Map) {
        return const LearningEvidenceResolution.blocked(
          'invalidPayloadEvidenceContext',
        );
      }
      try {
        final decoded = EvidenceContext.fromJson(
          payloadContext.cast<String, Object?>(),
        );
        if (decoded.evidenceClass.name != attempt.evidenceClass) {
          return const LearningEvidenceResolution.blocked(
            'evidenceClassMismatch',
          );
        }
        if (jsonEncode(decoded.toJson()) != attempt.evidenceContextJson) {
          return const LearningEvidenceResolution.blocked(
            'evidenceContextMismatch',
          );
        }
      } on FormatException {
        return const LearningEvidenceResolution.blocked(
          'invalidPayloadEvidenceContext',
        );
      } on TypeError {
        return const LearningEvidenceResolution.blocked(
          'invalidPayloadEvidenceContext',
        );
      }
    } else if (context.classificationSource !=
            EvidenceClassificationSource.legacyInferred ||
        context.policyVersion != EvidenceContext.legacyPolicyVersion ||
        context.rolloutMode != EvidencePolicyRolloutMode.legacy) {
      return const LearningEvidenceResolution.blocked(
        'contextlessNonLegacyAttempt',
      );
    }

    try {
      final decisionSet = await ensureDecisionSetForAttempt(
        attempt: attempt,
        sourceEvent: source,
      );
      return LearningEvidenceResolution.resolved(
        ResolvedLearningEvidence(
          attempt: attempt,
          context: context,
          decisionSet: decisionSet,
        ),
      );
    } on ArgumentError {
      return const LearningEvidenceResolution.blocked('decisionSetConflict');
    } on FormatException {
      return const LearningEvidenceResolution.blocked('decisionSetConflict');
    } on StateError {
      return const LearningEvidenceResolution.blocked('decisionSetConflict');
    }
  }

  EvidenceContext _contextForAttempt(db.AnswerAttempt attempt) {
    final decoded = jsonDecode(attempt.evidenceContextJson);
    if (decoded is! Map) {
      throw const FormatException('attempt evidence context must be an object');
    }
    final context = EvidenceContext.fromJson(decoded.cast<String, Object?>());
    if (attempt.evidenceClass != context.evidenceClass.name ||
        attempt.evidenceContextJson != jsonEncode(context.toJson())) {
      throw const FormatException('attempt evidence metadata mismatch');
    }
    return context;
  }

  LearningEvidenceDecisionSet _buildDecisionSet({
    required String sourceEvidenceId,
    required EvidenceContext context,
    required EvidencePolicyRolloutMode rolloutMode,
  }) {
    context.validate();
    if (rolloutMode != context.rolloutMode) {
      throw StateError('decision-set rollout does not match evidence');
    }
    final decisions = LearningProjection.values
        .map((projection) {
          final candidate = evidencePolicy.disposition(context, projection);
          final effective = switch (rolloutMode) {
            EvidencePolicyRolloutMode.legacy =>
              legacyEvidenceEligibilityV1[projection]!,
            EvidencePolicyRolloutMode.shadow =>
              legacyEvidenceEligibilityV1[projection]!,
            EvidencePolicyRolloutMode.enforced => candidate,
          };
          final candidateToRecord =
              rolloutMode == EvidencePolicyRolloutMode.shadow
              ? candidate
              : null;
          return LearningEvidenceProjectionDecisionRecord(
            projection: projection,
            rolloutMode: rolloutMode,
            effectiveDecision: effective,
            candidateV1Decision: candidateToRecord,
            policyVersion: context.policyVersion,
            divergence:
                candidateToRecord != null && candidateToRecord != effective,
          );
        })
        .toList(growable: false);
    if (decisions.length != LearningProjection.values.length) {
      throw StateError('incomplete learning evidence decision set');
    }
    return LearningEvidenceDecisionSet(
      sourceEvidenceId: sourceEvidenceId,
      context: context,
      decisions: List<LearningEvidenceProjectionDecisionRecord>.unmodifiable(
        decisions,
      ),
    );
  }

  EventEnvelopeV2 _decisionSetEvent({
    required db.AnswerAttempt attempt,
    required EventEnvelopeV2? sourceEvent,
    required LearningEvidenceDecisionSet decisionSet,
  }) {
    final eventId = _decisionSetEventId(attempt.id);
    final at = LearningEvidenceContract.canonicalEventUtcSecond(
      DateTime.fromMillisecondsSinceEpoch(attempt.occurredAtUtcMs, isUtc: true),
    );
    return EventEnvelopeV2(
      eventId: eventId,
      eventType: 'LearningEvidenceDecisionSet',
      eventVersion: 1,
      occurredAtUtc: at,
      recordedAtUtc: at,
      actorIdentity: sourceEvent?.actorIdentity ?? attempt.ownerId,
      ownerIdentity: attempt.ownerId,
      aggregateType: 'LearningEvidenceDecisionSet',
      aggregateId: attempt.id,
      causationId: sourceEvent?.eventId,
      idempotencyKey: eventId,
      consentContext:
          sourceEvent?.consentContext ?? const ConsentContext.none(),
      experimentContext: sourceEvent?.experimentContext,
      contentRevision: decisionSet.context.contentRevision,
      policyVersion: decisionSet.context.policyVersion,
      appVersion: sourceEvent?.appVersion ?? 'legacy-unversioned',
      buildId: sourceEvent?.buildId ?? 'legacy-unversioned',
      privacyClassification:
          sourceEvent?.privacyClassification ??
          PrivacyClassification.anonymized,
      payload: decisionSet.toPayload().cast<String, dynamic>(),
    );
  }

  void _validateStoredDecisionSet({
    required db.EventsV2Data row,
    required db.AnswerAttempt attempt,
    required LearningEvidenceDecisionSet expected,
  }) {
    if (row.eventId != _decisionSetEventId(attempt.id) ||
        row.eventType != 'LearningEvidenceDecisionSet' ||
        row.eventVersion != 1 ||
        row.ownerId != attempt.ownerId ||
        row.aggregateType != 'LearningEvidenceDecisionSet' ||
        row.aggregateId != attempt.id ||
        row.idempotencyKey != row.eventId) {
      throw StateError('learning evidence decision-set identity conflict');
    }
    final payload = jsonDecode(row.payloadJson);
    if (payload is! Map ||
        jsonEncode(payload) != jsonEncode(expected.toPayload())) {
      throw StateError('learning evidence decision-set content conflict');
    }
  }

  String _decisionSetEventId(String sourceEvidenceId) {
    final eventId = 'learning-evidence-decisions:$sourceEvidenceId:v1';
    if (!LearningEvidenceContract.validIdentifier(eventId)) {
      throw ArgumentError.value(
        sourceEvidenceId,
        'sourceEvidenceId',
        'decision-set identifier exceeds the canonical budget',
      );
    }
    return eventId;
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
    required LearningProjectionOutcome outcome,
    Map<String, dynamic> result = const <String, dynamic>{},
    String? reasonCode,
    int? bridgedFromVersion,
    Map<String, dynamic> decision = const <String, dynamic>{},
  }) async {
    if (outcome == LearningProjectionOutcome.blocked) {
      if (reasonCode == null ||
          reasonCode.trim() != reasonCode ||
          reasonCode.isEmpty) {
        throw ArgumentError.value(
          reasonCode,
          'reasonCode',
          'blocked receipts require a stable reason code',
        );
      }
    } else if (reasonCode != null) {
      throw ArgumentError.value(
        reasonCode,
        'reasonCode',
        'only blocked receipts carry a reason code',
      );
    }
    if (bridgedFromVersion != null &&
        (bridgedFromVersion < 1 || bridgedFromVersion >= appliedVersion)) {
      throw ArgumentError.value(
        bridgedFromVersion,
        'bridgedFromVersion',
        'must identify an earlier positive projection version',
      );
    }
    final key = _projectionKey(
      sourceEventId: source.eventId,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    final receipt = EventEnvelopeV2(
      eventId: key,
      eventType: switch (outcome) {
        LearningProjectionOutcome.applied => 'LearningProjectionApplied',
        LearningProjectionOutcome.notApplicable => 'LearningProjectionSkipped',
        LearningProjectionOutcome.blocked => 'LearningProjectionBlocked',
      },
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
        'outcome': outcome.name,
        'reasonCode': ?reasonCode,
        'bridgedFromVersion': ?bridgedFromVersion,
        if (decision.isNotEmpty) 'decision': decision,
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
      final existing = await (database.select(
        database.eventsV2,
      )..where((row) => row.eventId.equals(key))).getSingleOrNull();
      if (existing == null) {
        await database
            .into(database.eventsV2)
            .insert(_companion(receipt), mode: InsertMode.insertOrIgnore);
      } else if (!_sameEvent(existing, receipt)) {
        throw StateError('learning projection receipt is immutable');
      }
      await database
          .into(database.eventsV2)
          .insertOnConflictUpdate(_companion(cursor));
    });
  }

  Future<LearningProjectionReceipt?> readProjectionReceipt({
    required String sourceEventId,
    required String projection,
    required int appliedVersion,
  }) async {
    final key = _projectionKey(
      sourceEventId: sourceEventId,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    final row = await (database.select(
      database.eventsV2,
    )..where((candidate) => candidate.eventId.equals(key))).getSingleOrNull();
    if (row == null) return null;
    final outcome = switch (row.eventType) {
      'LearningProjectionApplied' => LearningProjectionOutcome.applied,
      'LearningProjectionSkipped' => LearningProjectionOutcome.notApplicable,
      'LearningProjectionBlocked' => LearningProjectionOutcome.blocked,
      _ => throw StateError('invalid learning projection receipt type'),
    };
    final decoded = jsonDecode(row.payloadJson);
    if (decoded is! Map) {
      throw StateError('invalid learning projection receipt payload');
    }
    final payload = decoded.cast<String, dynamic>();
    if (row.aggregateType != 'LearningProjection' ||
        row.aggregateId != sourceEventId ||
        row.idempotencyKey != key ||
        payload['projection'] != projection ||
        (payload['appliedVersion'] != null &&
            payload['appliedVersion'] != appliedVersion)) {
      throw StateError('invalid learning projection receipt identity');
    }
    final result = payload['result'];
    if (result != null && result is! Map) {
      throw StateError('invalid learning projection receipt result');
    }
    final reasonCode = payload['reasonCode'];
    final bridgedFromVersion = payload['bridgedFromVersion'];
    if ((reasonCode != null && reasonCode is! String) ||
        (bridgedFromVersion != null && bridgedFromVersion is! int)) {
      throw StateError('invalid learning projection receipt metadata');
    }
    return LearningProjectionReceipt(
      outcome: outcome,
      result: result == null
          ? const <String, dynamic>{}
          : result.cast<String, dynamic>(),
      reasonCode: reasonCode as String?,
      bridgedFromVersion: bridgedFromVersion as int?,
    );
  }

  String _projectionKey({
    required String sourceEventId,
    required String projection,
    required int appliedVersion,
  }) => LearningEvidenceContract.learningProjectionReceiptId(
    projection: projection,
    sourceEventId: sourceEventId,
    appliedVersion: appliedVersion,
  );

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

  void _requireCanonicalEventTime(
    EventEnvelopeV2 event, {
    bool stateError = false,
  }) {
    final valid =
        LearningEvidenceContract.isCanonicalEventUtcSecond(
          event.occurredAtUtc,
        ) &&
        LearningEvidenceContract.isCanonicalEventUtcSecond(event.recordedAtUtc);
    if (valid) return;
    if (stateError) {
      throw StateError('stored learning event has non-canonical timestamp');
    }
    throw ArgumentError.value(
      event,
      'event',
      'learning event timestamps must be UTC whole seconds',
    );
  }
}
