/// EventV1ToV2Adapter — reads a [LearningEvent] (schema 1) and wraps it in
/// an [EventEnvelopeV2] without data loss.
///
/// The V1 payload is preserved verbatim inside [EventEnvelopeV2.payload] so
/// that existing analytics pipelines can continue to consume the original
/// fields while new consumers use the V2 envelope metadata.
///
/// **Idempotency guarantee:** Given the same [LearningEvent], the adapter
/// always produces the same [idempotencyKey], making replay-safe.
library;

import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/learning/learning_event.dart';

/// Adapts a legacy [LearningEvent] (schema version 1) to [EventEnvelopeV2].
final class EventV1ToV2Adapter {
  const EventV1ToV2Adapter({
    required this.appVersion,
    required this.buildId,
    this.consentContext = const ConsentContext.none(),
  });

  /// LexiQuest app version string (e.g. `'1.0.0+1'`).
  final String appVersion;

  /// Git commit SHA used at build time (e.g. `'abc1234'`).
  final String buildId;

  /// Consent context applied to all adapted events.
  ///
  /// Production code should resolve real consent from the consent repository.
  /// Defaults to [ConsentContext.none] so that Phase -1 scaffolding is safe.
  final ConsentContext consentContext;

  /// Adapt [v1] into an [EventEnvelopeV2].
  ///
  /// - [EventEnvelopeV2.eventId] is set to `v1.eventId` (already a UUID).
  /// - [EventEnvelopeV2.payload] contains the full [v1.toMap()] output,
  ///   preserving every V1 field for backward-compatible consumers.
  /// - [EventEnvelopeV2.idempotencyKey] is deterministic — calling this method
  ///   twice with the same [v1] produces the same key.
  EventEnvelopeV2 adapt(LearningEvent v1) {
    return EventEnvelopeV2(
      // Field 1 — reuse the V1 event ID (already unique UUID)
      eventId: v1.eventId,
      // Field 2 — map V1 activity name to V2 event type
      eventType: _mapActivity(v1.activity),
      // Field 3 — payload is V1 format, so version = 1
      eventVersion: 1,
      // Field 4
      occurredAtUtc: v1.occurredAtUtc,
      // Field 5 — adapter records "now"; callers may override in tests
      recordedAtUtc: DateTime.now().toUtc(),
      // Field 6 — V1 had a single user identity
      actorIdentity: v1.pseudonymousUserId,
      // Field 7 — same in V1 (actor == owner)
      ownerIdentity: v1.pseudonymousUserId,
      // Field 8 — V1 had no tenant concept
      tenantContext: null,
      // Field 9
      aggregateType: 'LearningSession',
      // Field 10 — V1 has no session ID field; use a stable surrogate
      aggregateId: _aggregateId(v1),
      // Field 11-12 — V1 had no correlation/causation IDs
      correlationId: null,
      causationId: null,
      // Field 13 — deterministic from V1 content
      idempotencyKey: _idempotencyKey(v1),
      // Field 14
      consentContext: consentContext,
      // Field 15 — V1 had no experiment tracking
      experimentContext: null,
      // Field 16-17 — V1 had no catalog revision or policy version
      contentRevision: null,
      policyVersion: null,
      // Fields 18-19
      appVersion: appVersion,
      buildId: buildId,
      // Field 20 — V1 had no provider provenance
      providerProvenance: null,
      // Field 21 — V1 events are pseudonymised research data
      privacyClassification: PrivacyClassification.anonymized,
      // Field 22 — wrap the full V1 map as payload
      payload: v1.toMap(),
    );
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  /// Maps a [LearningActivity] to its V2 event type name.
  String _mapActivity(LearningActivity activity) => switch (activity) {
    LearningActivity.multipleChoiceQuiz => 'QuizCompleted',
  };

  /// Generates a stable aggregate ID from V1 fields.
  ///
  /// V1 [LearningEvent] has no session ID.  The pseudonym + UTC millis gives
  /// a stable surrogate that is unique per event (since eventId is UUID).
  String _aggregateId(LearningEvent v1) =>
      'v1-session-${v1.pseudonymousUserId}';

  /// Idempotency key from V1 content.
  String _idempotencyKey(LearningEvent v1) =>
      'v1_${v1.pseudonymousUserId}_${v1.occurredAtUtc.millisecondsSinceEpoch}';

  /// Convenience method that builds an [EventEnvelopeV2] directly from the
  /// raw parameters of [LearningUseCases.recordAnswer], bypassing the
  /// intermediate [LearningEvent] DTO.
  ///
  /// Used exclusively by the shadow reward orchestrator hook so that the
  /// shadow path does not need to reconstruct a [LearningEvent] externally.
  EventEnvelopeV2 adaptFromCommand({
    required String sourceEventId,
    required String ownerId,
    required String sessionId,
    required String wordId,
    required String promptMode,
    required bool isCorrect,
    required int? responseTimeMs,
    required int attemptNumber,
    required DateTime occurredAtUtc,
    required String appVersion,
    required String buildId,
    String? providerProvenance,
  }) {
    final now = occurredAtUtc.isUtc ? occurredAtUtc : occurredAtUtc.toUtc();
    final eventId = 'learning-event:$sourceEventId';
    final idemKey = 'learning-attempt:$sourceEventId:v1';

    return EventEnvelopeV2(
      eventId: eventId,
      eventType: isCorrect ? 'QuizCompleted' : 'QuizAttempted',
      eventVersion: 1,
      occurredAtUtc: now,
      recordedAtUtc: now,
      actorIdentity: ownerId,
      ownerIdentity: ownerId,
      aggregateType: 'LearningSession',
      aggregateId: sessionId,
      idempotencyKey: idemKey,
      consentContext: consentContext,
      appVersion: appVersion,
      buildId: buildId,
      privacyClassification: PrivacyClassification.anonymized,
      payload: {
        'attemptId': sourceEventId,
        'wordId': wordId,
        'promptMode': promptMode,
        'correct': isCorrect,
        'score': isCorrect ? 100 : 0,
        // ignore: use_null_aware_elements, map key is non-null literal
        if (responseTimeMs != null) 'responseTimeMs': responseTimeMs,
        'attemptNumber': attemptNumber,
        // ignore: use_null_aware_elements, map key is non-null literal
        if (providerProvenance != null)
          'providerProvenance': providerProvenance,
      },
    );
  }
}
