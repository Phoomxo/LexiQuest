import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../events/domain/event_envelope_v2.dart';
import '../domain/evidence_context.dart';
import '../domain/evidence_eligibility_policy.dart';
import '../domain/evidence_policy_rollout.dart';
import '../domain/learning_evidence_contract.dart';
import '../domain/learning_event_context.dart';
import '../domain/learning_models.dart';

export '../domain/evidence_policy_rollout.dart';

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
    'evidenceContext': context.toJson(),
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
    this.prerequisiteReceipt,
    this.prerequisiteInvalid = false,
  });

  final EventEnvelopeV2 event;
  final LearningProjectionReceipt? prerequisiteReceipt;
  final bool prerequisiteInvalid;
}

final class DriftLearningEventStore {
  const DriftLearningEventStore(
    this.database, {
    this.evidencePolicy = const EvidenceEligibilityPolicySet(),
    this.rolloutModeProvider =
        const FixedEvidencePolicyRolloutModeProvider.legacy(),
  });

  static const int appliedProjectionVersion = 2;
  static const String _projectionCursorAppVersion =
      'learning-projection-cursor-v1';
  static const String _projectionCursorBuildId =
      'learning-projection-cursor-v1';
  static const List<String> _projectionNames = [
    'coins',
    'quest',
    'streak',
    'reward',
  ];

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
    var validatedSource = sourceEvent;
    validatedSource ??= await _readSourceEventForAttempt(attempt.id);
    if (validatedSource == null) {
      if (!LearningEvidenceContract.isExactFrozenV13LegacyEvidence(context)) {
        throw StateError('canonical attempt has no correlated source event');
      }
    } else {
      final failure = await validateSourceForAttempt(
        attempt: attempt,
        source: validatedSource,
      );
      if (failure != null) {
        throw StateError('invalid correlated source event: $failure');
      }
    }
    final expected = _buildDecisionSet(
      sourceEvidenceId: attempt.id,
      context: context,
      rolloutMode: context.rolloutMode,
    );
    final candidate = _decisionSetEvent(
      attempt: attempt,
      sourceEvent: validatedSource,
      decisionSet: expected,
    );
    final eventId = _decisionSetEventId(attempt.id);
    final existing = await (database.select(
      database.eventsV2,
    )..where((row) => row.eventId.equals(eventId))).getSingleOrNull();
    if (existing != null) {
      await _validateStoredDecisionSet(
        row: existing,
        expected: candidate,
        allowHistoricalEventlessActor: validatedSource == null,
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
    await database.transaction(() async {
      await database
          .into(database.eventsV2)
          .insert(_companion(candidate), mode: InsertMode.insertOrIgnore);
      final stored = await (database.select(
        database.eventsV2,
      )..where((row) => row.eventId.equals(eventId))).getSingle();
      await _validateStoredDecisionSet(
        row: stored,
        expected: candidate,
        allowHistoricalEventlessActor: validatedSource == null,
      );
    });
    return expected;
  }

  bool isExactDeclaredSourceForCandidate({
    required RecordAnswerCandidate candidate,
    required EventEnvelopeV2 source,
  }) {
    if (source.actorIdentity != candidate.ownerId) return false;
    return _validateDeclaredSource(
          attemptId: candidate.id,
          ownerId: candidate.ownerId,
          sessionId: candidate.sessionId,
          wordId: candidate.wordId,
          promptMode: candidate.promptMode,
          isCorrect: candidate.isCorrect,
          attemptNumber: candidate.attemptNumber,
          occurredAtUtcMs: candidate.occurredAtUtc.millisecondsSinceEpoch,
          evidenceContextJson: jsonEncode(candidate.evidenceContext.toJson()),
          context: candidate.evidenceContext,
          source: source,
        ) ==
        null;
  }

  Future<String?> validateSourceForAttempt({
    required db.AnswerAttempt attempt,
    required EventEnvelopeV2 source,
  }) async {
    late final EvidenceContext context;
    try {
      context = _contextForAttempt(attempt);
    } on FormatException {
      return 'invalidCanonicalEvidenceContext';
    } on TypeError {
      return 'invalidCanonicalEvidenceContext';
    } on ArgumentError {
      return 'invalidCanonicalEvidenceContext';
    } on StateError {
      return 'invalidCanonicalEvidenceContext';
    }
    if (source.ownerIdentity != attempt.ownerId) {
      return 'attemptOwnerMismatch';
    }
    if (!await _isAuthorizedActor(
      actorIdentity: source.actorIdentity,
      ownerIdentity: attempt.ownerId,
    )) {
      return 'invalidSourceActorLineage';
    }
    if (source.payload.containsKey('evidenceContext')) {
      return _validateDeclaredSource(
        attemptId: attempt.id,
        ownerId: attempt.ownerId,
        sessionId: attempt.sessionId,
        wordId: attempt.wordId,
        promptMode: attempt.promptMode,
        isCorrect: attempt.isCorrect,
        attemptNumber: attempt.attemptNumber,
        occurredAtUtcMs: attempt.occurredAtUtcMs,
        evidenceContextJson: attempt.evidenceContextJson,
        context: context,
        source: source,
      );
    }
    if (!LearningEvidenceContract.isExactFrozenV13LegacyEvidence(context)) {
      return 'contextlessNonLegacyAttempt';
    }
    return _validateFrozenLegacySource(attempt: attempt, source: source);
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
    final validationFailure = await validateSourceForAttempt(
      attempt: attempt,
      source: source,
    );
    if (validationFailure != null) {
      return LearningEvidenceResolution.blocked(validationFailure);
    }
    final context = _contextForAttempt(attempt);

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

  Future<EventEnvelopeV2?> _readSourceEventForAttempt(String attemptId) async {
    final eventId = LearningEvidenceContract.learningEventId(attemptId);
    final row =
        await (database.select(database.eventsV2)
              ..where((candidate) => candidate.eventId.equals(eventId)))
            .getSingleOrNull();
    return row == null ? null : _toEvent(row);
  }

  Future<bool> _isAuthorizedActor({
    required String actorIdentity,
    required String ownerIdentity,
  }) async {
    if (actorIdentity == ownerIdentity) return true;
    final historicalActor = await (database.select(
      database.localOwners,
    )..where((row) => row.id.equals(actorIdentity))).getSingleOrNull();
    return historicalActor != null &&
        !historicalActor.isActive &&
        historicalActor.accountState == 'mergedInto:$ownerIdentity';
  }

  String? _validateDeclaredSource({
    required String attemptId,
    required String ownerId,
    required String sessionId,
    required String wordId,
    required String promptMode,
    required bool isCorrect,
    required int attemptNumber,
    required int occurredAtUtcMs,
    required String evidenceContextJson,
    required EvidenceContext context,
    required EventEnvelopeV2 source,
  }) {
    const payloadKeys = <String>{
      'attemptId',
      'wordId',
      'promptMode',
      'correct',
      'score',
      'attemptNumber',
      'evidenceContext',
    };
    final payload = source.payload;
    if (payload.length != payloadKeys.length ||
        !payload.keys.every(payloadKeys.contains)) {
      return 'invalidSourceEventCorrelation';
    }
    final payloadContext = payload['evidenceContext'];
    if (payloadContext is! Map) return 'invalidPayloadEvidenceContext';
    try {
      final decoded = EvidenceContext.fromJson(
        payloadContext.cast<String, Object?>(),
      );
      if (decoded.evidenceClass.name != context.evidenceClass.name) {
        return 'evidenceClassMismatch';
      }
      if (jsonEncode(decoded.toJson()) != evidenceContextJson ||
          jsonEncode(payloadContext) != evidenceContextJson) {
        return 'evidenceContextMismatch';
      }
    } on FormatException {
      return 'invalidPayloadEvidenceContext';
    } on TypeError {
      return 'invalidPayloadEvidenceContext';
    } on ArgumentError {
      return 'invalidPayloadEvidenceContext';
    } on StateError {
      return 'invalidPayloadEvidenceContext';
    }
    final at = LearningEvidenceContract.canonicalEventUtcSecond(
      DateTime.fromMillisecondsSinceEpoch(occurredAtUtcMs, isUtc: true),
    );
    if (!_matchesCommonSourceEnvelope(
          source: source,
          attemptId: attemptId,
          ownerId: ownerId,
          sessionId: sessionId,
          isCorrect: isCorrect,
          at: at,
        ) ||
        source.eventVersion != 2 ||
        source.idempotencyKey !=
            LearningEvidenceContract.learningAttemptIdempotencyKey(attemptId) ||
        source.contentRevision != context.contentRevision ||
        source.policyVersion != context.policyVersion ||
        payload['attemptId'] != attemptId ||
        payload['wordId'] != wordId ||
        payload['promptMode'] != promptMode ||
        payload['correct'] != isCorrect ||
        payload['score'] != (isCorrect ? 100 : 0) ||
        payload['attemptNumber'] != attemptNumber) {
      return 'invalidSourceEventCorrelation';
    }
    try {
      LearningEventContext.fromEvidenceEnvelope(
        envelope: source,
        evidenceContext: context,
      ).validateAgainst(
        evidenceContext: context,
        occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
          occurredAtUtcMs,
          isUtc: true,
        ),
      );
    } on ArgumentError {
      return 'invalidLearningEventContext';
    } on FormatException {
      return 'invalidLearningEventContext';
    } on StateError {
      return 'invalidLearningEventContext';
    }
    return null;
  }

  String? _validateFrozenLegacySource({
    required db.AnswerAttempt attempt,
    required EventEnvelopeV2 source,
  }) {
    final at = LearningEvidenceContract.canonicalEventUtcSecond(
      DateTime.fromMillisecondsSinceEpoch(attempt.occurredAtUtcMs, isUtc: true),
    );
    final payload = source.payload;
    final consent = source.consentContext;
    if (!_matchesCommonSourceEnvelope(
          source: source,
          attemptId: attempt.id,
          ownerId: attempt.ownerId,
          sessionId: attempt.sessionId,
          isCorrect: attempt.isCorrect,
          at: at,
        ) ||
        source.eventVersion != 1 ||
        source.idempotencyKey != 'learning-attempt:${attempt.id}:v1' ||
        source.experimentContext != null ||
        source.contentRevision != null ||
        source.policyVersion != null ||
        consent.researchConsentVersion != 0 ||
        consent.aiConsentGranted ||
        consent.voiceConsentGranted ||
        consent.socialConsentGranted ||
        payload.length != 1 ||
        payload.keys.single != 'attemptId' ||
        payload['attemptId'] != attempt.id) {
      return 'invalidLegacySourceEventCorrelation';
    }
    return null;
  }

  bool _matchesCommonSourceEnvelope({
    required EventEnvelopeV2 source,
    required String attemptId,
    required String ownerId,
    required String sessionId,
    required bool isCorrect,
    required DateTime at,
  }) {
    return source.eventId ==
            LearningEvidenceContract.learningEventId(attemptId) &&
        source.eventType == (isCorrect ? 'QuizCompleted' : 'QuizAttempted') &&
        source.occurredAtUtc == at &&
        source.recordedAtUtc == at &&
        source.ownerIdentity == ownerId &&
        source.tenantContext == null &&
        source.aggregateType == 'LearningSession' &&
        source.aggregateId == sessionId &&
        source.correlationId == null &&
        source.causationId == null &&
        source.providerProvenance == null &&
        source.privacyClassification == PrivacyClassification.anonymized;
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
          final effective = effectiveProjectionDisposition(
            context: context,
            projection: projection,
            policyDisposition: candidate,
          );
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

  Future<void> _validateStoredDecisionSet({
    required db.EventsV2Data row,
    required EventEnvelopeV2 expected,
    required bool allowHistoricalEventlessActor,
  }) async {
    if (_isExactStoredEvent(row, expected)) return;
    if (allowHistoricalEventlessActor &&
        row.actorIdentity != expected.actorIdentity &&
        await _isAuthorizedActor(
          actorIdentity: row.actorIdentity,
          ownerIdentity: expected.ownerIdentity,
        )) {
      try {
        final historicalExpectedJson = expected.toJson()
          ..['actorIdentity'] = row.actorIdentity;
        final historicalExpected = EventEnvelopeV2.fromJson(
          historicalExpectedJson,
        );
        if (_isExactStoredEvent(row, historicalExpected)) return;
      } catch (_) {
        // Fall through to the one stable conflict below.
      }
    }
    throw StateError('learning evidence decision-set identity conflict');
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
    final cursors = <db.EventsV2Data>[];
    for (final projection in _projectionNames) {
      final cursor = await _readProjectionCursor(
        ownerId: event.ownerIdentity,
        projection: projection,
        appliedVersion: appliedProjectionVersion,
      );
      if (cursor != null) cursors.add(cursor);
    }
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
      await _writeProjectionCursor(
        source: source,
        projection: payload['projection'] as String,
        appliedVersion: payload['appliedVersion'] as int,
      );
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
    final cursor = await _readProjectionCursor(
      ownerId: ownerId,
      projection: projection,
      appliedVersion: appliedVersion,
    );
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
    final idRows = await database
        .customSelect(
          candidateSql,
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
    final eventsById = <String, EventEnvelopeV2>{
      for (final row in rows) row.eventId: _toEvent(row),
    };
    final result = <PendingLearningProjectionEvent>[];
    for (final row in idRows) {
      final event = eventsById[row.read<String>('event_id')]!;
      if (prerequisiteProjection == null) {
        result.add(PendingLearningProjectionEvent(event: event));
        continue;
      }
      try {
        result.add(
          PendingLearningProjectionEvent(
            event: event,
            prerequisiteReceipt: await readProjectionReceipt(
              source: event,
              projection: prerequisiteProjection,
              appliedVersion: appliedVersion,
            ),
          ),
        );
      } on StateError {
        result.add(
          PendingLearningProjectionEvent(
            event: event,
            prerequisiteInvalid: true,
          ),
        );
      }
    }
    return List<PendingLearningProjectionEvent>.unmodifiable(result);
  }

  /// Returns true when the caller must execute the projection. A valid
  /// terminal receipt is recovered by advancing only its cursor and returns
  /// false, so a rewind never repeats the external sink.
  Future<bool> ensureProjectionOutcomeWritable({
    required EventEnvelopeV2 source,
    required String projection,
    required int appliedVersion,
  }) async {
    final receiptKey = _projectionKey(
      sourceEventId: source.eventId,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    return database.transaction(() async {
      final receiptRows = await _rowsForBothIdentities(
        key: receiptKey,
        ownerId: source.ownerIdentity,
      );
      if (receiptRows.isNotEmpty) {
        final existing = await readProjectionReceipt(
          source: source,
          projection: projection,
          appliedVersion: appliedVersion,
        );
        if (existing == null) {
          throw StateError('learning projection receipt identity conflict');
        }
        await _writeProjectionCursor(
          source: source,
          projection: projection,
          appliedVersion: appliedVersion,
        );
        return false;
      }
      await _readProjectionCursor(
        ownerId: source.ownerIdentity,
        projection: projection,
        appliedVersion: appliedVersion,
      );
      return true;
    });
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
    if (!_validReceiptReason(reasonCode, outcome, allowMissingBlocked: false)) {
      throw ArgumentError.value(
        reasonCode,
        'reasonCode',
        'receipt outcome requires a bounded stable reason code',
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
    await database.transaction(() async {
      if (bridgedFromVersion != null) {
        await _requireMatchingBridgeReceipt(
          source: source,
          projection: projection,
          bridgedFromVersion: bridgedFromVersion,
          outcome: outcome,
          result: result,
        );
      }
      final existingReceipts = await _rowsForBothIdentities(
        key: key,
        ownerId: source.ownerIdentity,
      );
      if (existingReceipts.isEmpty) {
        await database
            .into(database.eventsV2)
            .insert(_companion(receipt), mode: InsertMode.insertOrIgnore);
      } else {
        _requireExactStoredEvent(
          rows: existingReceipts,
          expected: receipt,
          conflict: 'learning projection receipt is immutable',
        );
      }
      _requireExactStoredEvent(
        rows: await _rowsForBothIdentities(
          key: key,
          ownerId: source.ownerIdentity,
        ),
        expected: receipt,
        conflict: 'learning projection receipt identity conflict',
      );

      await _writeProjectionCursor(
        source: source,
        projection: projection,
        appliedVersion: appliedVersion,
      );
    });
  }

  Future<LearningProjectionReceipt?> readProjectionReceipt({
    required EventEnvelopeV2 source,
    required String projection,
    required int appliedVersion,
  }) async {
    final key = _projectionKey(
      sourceEventId: source.eventId,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    final rows = await _rowsForBothIdentities(
      key: key,
      ownerId: source.ownerIdentity,
    );
    if (rows.isEmpty) return null;
    if (rows.length != 1) {
      throw StateError('invalid learning projection receipt identity');
    }
    final row = rows.single;
    final outcome = switch (row.eventType) {
      'LearningProjectionApplied' => LearningProjectionOutcome.applied,
      'LearningProjectionSkipped' => LearningProjectionOutcome.notApplicable,
      'LearningProjectionBlocked' => LearningProjectionOutcome.blocked,
      _ => throw StateError('invalid learning projection receipt type'),
    };
    late final Map<String, dynamic> payload;
    late final EventEnvelopeV2 receipt;
    try {
      final decoded = jsonDecode(row.payloadJson);
      if (decoded is! Map) {
        throw const FormatException('receipt payload is not an object');
      }
      payload = decoded.cast<String, dynamic>();
      receipt = _toEvent(row);
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('invalid learning projection receipt payload');
    }
    const requiredKeys = <String>{
      'sourceEventId',
      'projection',
      'appliedVersion',
      'outcome',
      'result',
    };
    const optionalKeys = <String>{
      'reasonCode',
      'bridgedFromVersion',
      'decision',
    };
    if (!payload.keys.toSet().containsAll(requiredKeys) ||
        !payload.keys.every(
          (key) => requiredKeys.contains(key) || optionalKeys.contains(key),
        ) ||
        receipt.eventId != key ||
        receipt.idempotencyKey != key ||
        receipt.eventVersion != 1 ||
        receipt.occurredAtUtc != source.occurredAtUtc ||
        receipt.recordedAtUtc != source.recordedAtUtc ||
        receipt.actorIdentity != source.actorIdentity ||
        receipt.ownerIdentity != source.ownerIdentity ||
        receipt.tenantContext != null ||
        receipt.aggregateType != 'LearningProjection' ||
        receipt.aggregateId != source.eventId ||
        receipt.correlationId != null ||
        receipt.causationId != source.eventId ||
        jsonEncode(receipt.consentContext.toJson()) !=
            jsonEncode(source.consentContext.toJson()) ||
        receipt.experimentContext != null ||
        receipt.contentRevision != null ||
        receipt.policyVersion != null ||
        receipt.appVersion != source.appVersion ||
        receipt.buildId != source.buildId ||
        receipt.providerProvenance != null ||
        receipt.privacyClassification != source.privacyClassification ||
        payload['sourceEventId'] != source.eventId ||
        payload['projection'] != projection ||
        payload['appliedVersion'] != appliedVersion ||
        payload['outcome'] != outcome.name) {
      throw StateError('invalid learning projection receipt identity');
    }
    final result = payload['result'];
    if (result is! Map) {
      throw StateError('invalid learning projection receipt result');
    }
    final reasonCode = payload['reasonCode'];
    final bridgedFromVersion = payload['bridgedFromVersion'];
    final decision = payload['decision'];
    if ((payload.containsKey('reasonCode') && reasonCode == null) ||
        (payload.containsKey('bridgedFromVersion') &&
            bridgedFromVersion == null) ||
        (payload.containsKey('decision') && decision == null) ||
        !_validReceiptReason(
          reasonCode,
          outcome,
          allowMissingBlocked: appliedVersion == 1,
        ) ||
        (bridgedFromVersion != null &&
            (bridgedFromVersion is! int ||
                bridgedFromVersion < 1 ||
                bridgedFromVersion >= appliedVersion)) ||
        (decision != null && decision is! Map)) {
      throw StateError('invalid learning projection receipt metadata');
    }
    final castResult = result.cast<String, dynamic>();
    if (bridgedFromVersion != null) {
      await _requireMatchingBridgeReceipt(
        source: source,
        projection: projection,
        bridgedFromVersion: bridgedFromVersion as int,
        outcome: outcome,
        result: castResult,
      );
    }
    if (projection == 'quest' &&
        !_validQuestReceiptResult(
          outcome: outcome,
          ownerId: source.ownerIdentity,
          appliedVersion: appliedVersion,
          bridgedFromVersion: bridgedFromVersion as int?,
          result: castResult,
        )) {
      throw StateError('invalid quest projection receipt result');
    }
    if (projection == 'coins' &&
        !_validCoinsReceiptResult(outcome: outcome, result: castResult)) {
      throw StateError('invalid coins projection receipt result');
    }
    return LearningProjectionReceipt(
      outcome: outcome,
      result: castResult,
      reasonCode: reasonCode as String?,
      bridgedFromVersion: bridgedFromVersion as int?,
    );
  }

  Future<void> _requireMatchingBridgeReceipt({
    required EventEnvelopeV2 source,
    required String projection,
    required int bridgedFromVersion,
    required LearningProjectionOutcome outcome,
    required Map<String, dynamic> result,
  }) async {
    final earlier = await readProjectionReceipt(
      source: source,
      projection: projection,
      appliedVersion: bridgedFromVersion,
    );
    if (earlier == null ||
        earlier.outcome != outcome ||
        jsonEncode(earlier.result) != jsonEncode(result)) {
      throw StateError('invalid learning projection bridge provenance');
    }
  }

  bool _validReceiptReason(
    Object? reasonCode,
    LearningProjectionOutcome outcome, {
    required bool allowMissingBlocked,
  }) {
    if (outcome == LearningProjectionOutcome.blocked) {
      return (reasonCode == null && allowMissingBlocked) ||
          reasonCode is String &&
              reasonCode.runes.length <= 128 &&
              RegExp(r'^[A-Za-z][A-Za-z0-9._-]*$').hasMatch(reasonCode);
    }
    return reasonCode == null;
  }

  bool _validQuestReceiptResult({
    required LearningProjectionOutcome outcome,
    required String ownerId,
    required int appliedVersion,
    required int? bridgedFromVersion,
    required Map<String, dynamic> result,
  }) {
    if (outcome == LearningProjectionOutcome.blocked) return result.isEmpty;
    const resultKeys = <String>{'eligible', 'rewardGrants'};
    if (result.length != resultKeys.length ||
        !result.keys.every(resultKeys.contains)) {
      return false;
    }
    final eligible = result['eligible'];
    final grants = result['rewardGrants'];
    if (eligible is! bool || grants is! List || grants.length > 64) {
      return false;
    }
    if (outcome == LearningProjectionOutcome.applied && !eligible) {
      return false;
    }
    if (outcome == LearningProjectionOutcome.notApplicable &&
        (eligible || grants.isNotEmpty)) {
      return false;
    }
    final idempotencyKeys = <String>{};
    final sourceEventIds = <String>{};
    for (final rawGrant in grants) {
      if (rawGrant is! Map) return false;
      final grant = rawGrant.cast<String, dynamic>();
      const legacyRequiredGrantKeys = <String>{
        'ownerId',
        'idempotencyKey',
        'xpAmount',
      };
      const durableRequiredGrantKeys = <String>{
        ...legacyRequiredGrantKeys,
        'sourceEventId',
        'occurredAtUtcMs',
      };
      final requiresDurableGrant =
          appliedVersion >= 2 && bridgedFromVersion != 1;
      final requiredGrantKeys = requiresDurableGrant
          ? durableRequiredGrantKeys
          : legacyRequiredGrantKeys;
      const optionalGrantKeys = <String>{'rewardItemId'};
      if (!grant.keys.toSet().containsAll(requiredGrantKeys) ||
          !grant.keys.every(
            (key) =>
                requiredGrantKeys.contains(key) ||
                optionalGrantKeys.contains(key),
          )) {
        return false;
      }
      final grantOwner = grant['ownerId'];
      final idempotencyKey = grant['idempotencyKey'];
      final xpAmount = grant['xpAmount'];
      final sourceEventId = grant['sourceEventId'];
      final occurredAtUtcMs = grant['occurredAtUtcMs'];
      final rewardItemId = grant['rewardItemId'];
      final hasRewardItemId = grant.containsKey('rewardItemId');
      if (grantOwner is! String ||
          grantOwner != ownerId ||
          idempotencyKey is! String ||
          idempotencyKey.trim() != idempotencyKey ||
          idempotencyKey.isEmpty ||
          idempotencyKey.runes.length > 256 ||
          !idempotencyKeys.add(idempotencyKey) ||
          xpAmount is! int ||
          xpAmount < 1 ||
          xpAmount > 9223372036854775807 ||
          (requiresDurableGrant &&
              (sourceEventId is! String ||
                  sourceEventId.trim() != sourceEventId ||
                  sourceEventId.isEmpty ||
                  sourceEventId.runes.length > 256 ||
                  sourceEventId != idempotencyKey ||
                  !sourceEventIds.add(sourceEventId) ||
                  occurredAtUtcMs is! int ||
                  occurredAtUtcMs < 0 ||
                  occurredAtUtcMs > 8640000000000000)) ||
          (hasRewardItemId &&
              (rewardItemId == null ||
                  (rewardItemId is! String ||
                      rewardItemId.trim() != rewardItemId ||
                      rewardItemId.isEmpty ||
                      rewardItemId.runes.length > 256)))) {
        return false;
      }
    }
    return true;
  }

  bool _validCoinsReceiptResult({
    required LearningProjectionOutcome outcome,
    required Map<String, dynamic> result,
  }) {
    return switch (outcome) {
      LearningProjectionOutcome.blocked => result.isEmpty,
      LearningProjectionOutcome.applied =>
        result.length == 1 &&
            (result['status'] == 'inserted' || result['status'] == 'replayed'),
      LearningProjectionOutcome.notApplicable =>
        result.length == 1 &&
            switch (result['reasonCode']) {
              'incorrectAnswer' ||
              'evidenceIneligible' ||
              'capturedByLegacyBackfill' => true,
              _ => false,
            },
    };
  }

  Future<void> _writeProjectionCursor({
    required EventEnvelopeV2 source,
    required String projection,
    required int appliedVersion,
  }) async {
    final key = _cursorKey(
      ownerId: source.ownerIdentity,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    final cursor = _projectionCursorEvent(
      source: source,
      key: key,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    await _readProjectionCursor(
      ownerId: source.ownerIdentity,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    await database
        .into(database.eventsV2)
        .insertOnConflictUpdate(_companion(cursor));
    await _readProjectionCursor(
      ownerId: source.ownerIdentity,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    _requireExactStoredEvent(
      rows: await _rowsForBothIdentities(
        key: key,
        ownerId: source.ownerIdentity,
      ),
      expected: cursor,
      conflict: 'learning projection cursor identity conflict',
    );
  }

  EventEnvelopeV2 _projectionCursorEvent({
    required EventEnvelopeV2 source,
    required String key,
    required String projection,
    required int appliedVersion,
  }) => EventEnvelopeV2(
    eventId: key,
    eventType: 'LearningProjectionCursor',
    eventVersion: 1,
    occurredAtUtc: source.occurredAtUtc,
    recordedAtUtc: source.occurredAtUtc,
    actorIdentity: source.ownerIdentity,
    ownerIdentity: source.ownerIdentity,
    aggregateType: 'LearningProjectionCursor',
    aggregateId: source.eventId,
    causationId: source.eventId,
    idempotencyKey: key,
    consentContext: const ConsentContext.none(),
    appVersion: _projectionCursorAppVersion,
    buildId: _projectionCursorBuildId,
    privacyClassification: PrivacyClassification.anonymized,
    payload: <String, dynamic>{
      'sourceEventId': source.eventId,
      'projection': projection,
      'appliedVersion': appliedVersion,
    },
  );

  Future<List<db.EventsV2Data>> _rowsForBothIdentities({
    required String key,
    required String ownerId,
  }) =>
      (database.select(database.eventsV2)..where(
            (row) =>
                row.eventId.equals(key) |
                (row.ownerId.equals(ownerId) & row.idempotencyKey.equals(key)),
          ))
          .get();

  Future<db.EventsV2Data?> _readProjectionCursor({
    required String ownerId,
    required String projection,
    required int appliedVersion,
  }) async {
    final key = _cursorKey(
      ownerId: ownerId,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    final rows = await _rowsForBothIdentities(key: key, ownerId: ownerId);
    _requireCanonicalCursorRows(
      rows: rows,
      key: key,
      ownerId: ownerId,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    if (rows.isEmpty) return null;
    await _requireProjectionCursorProvenance(
      cursorRow: rows.single,
      ownerId: ownerId,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    return rows.single;
  }

  Future<void> _requireProjectionCursorProvenance({
    required db.EventsV2Data cursorRow,
    required String ownerId,
    required String projection,
    required int appliedVersion,
  }) async {
    late final EventEnvelopeV2 cursor;
    late final EventEnvelopeV2 source;
    try {
      cursor = _toEvent(cursorRow);
      final sourceRow =
          await (database.select(database.eventsV2)
                ..where((row) => row.eventId.equals(cursor.aggregateId)))
              .getSingleOrNull();
      if (sourceRow == null) {
        throw StateError('learning projection cursor source is missing');
      }
      source = _toEvent(sourceRow);
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('invalid learning projection cursor source');
    }
    if (source.eventId != cursor.aggregateId ||
        source.ownerIdentity != ownerId ||
        source.occurredAtUtc != cursor.occurredAtUtc ||
        !source.idempotencyKey.startsWith('learning-attempt:')) {
      throw StateError('invalid learning projection cursor provenance');
    }
    final receipt = await readProjectionReceipt(
      source: source,
      projection: projection,
      appliedVersion: appliedVersion,
    );
    if (receipt == null) {
      throw StateError('learning projection cursor receipt is missing');
    }
  }

  void _requireCanonicalCursorRows({
    required List<db.EventsV2Data> rows,
    required String key,
    required String ownerId,
    required String projection,
    required int appliedVersion,
  }) {
    if (rows.isEmpty) return;
    if (rows.length != 1 ||
        !_isCanonicalCursorRow(
          row: rows.single,
          key: key,
          ownerId: ownerId,
          projection: projection,
          appliedVersion: appliedVersion,
        )) {
      throw StateError('learning projection cursor identity conflict');
    }
  }

  bool _isCanonicalCursorRow({
    required db.EventsV2Data row,
    required String key,
    required String ownerId,
    required String projection,
    required int appliedVersion,
  }) {
    try {
      final event = _toEvent(row);
      final payload = event.payload;
      const payloadKeys = <String>{
        'sourceEventId',
        'projection',
        'appliedVersion',
      };
      return event.eventId == key &&
          event.idempotencyKey == key &&
          event.eventType == 'LearningProjectionCursor' &&
          event.eventVersion == 1 &&
          event.occurredAtUtc == event.recordedAtUtc &&
          LearningEvidenceContract.isCanonicalEventUtcSecond(
            event.occurredAtUtc,
          ) &&
          event.ownerIdentity == ownerId &&
          event.actorIdentity == ownerId &&
          event.tenantContext == null &&
          event.aggregateType == 'LearningProjectionCursor' &&
          event.aggregateId == payload['sourceEventId'] &&
          event.correlationId == null &&
          event.causationId == event.aggregateId &&
          event.experimentContext == null &&
          event.contentRevision == null &&
          event.policyVersion == null &&
          event.providerProvenance == null &&
          jsonEncode(event.consentContext.toJson()) ==
              jsonEncode(const ConsentContext.none().toJson()) &&
          event.appVersion == _projectionCursorAppVersion &&
          event.buildId == _projectionCursorBuildId &&
          event.privacyClassification == PrivacyClassification.anonymized &&
          payload.length == payloadKeys.length &&
          payload.keys.every(payloadKeys.contains) &&
          payload['sourceEventId'] is String &&
          payload['projection'] == projection &&
          payload['appliedVersion'] == appliedVersion;
    } catch (_) {
      return false;
    }
  }

  void _requireExactStoredEvent({
    required List<db.EventsV2Data> rows,
    required EventEnvelopeV2 expected,
    required String conflict,
  }) {
    if (rows.length != 1 || !_isExactStoredEvent(rows.single, expected)) {
      throw StateError(conflict);
    }
  }

  bool _isExactStoredEvent(db.EventsV2Data row, EventEnvelopeV2 expected) {
    try {
      return _sameEvent(row, expected);
    } catch (_) {
      return false;
    }
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
