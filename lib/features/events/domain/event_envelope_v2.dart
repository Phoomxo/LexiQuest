/// EventEnvelopeV2 — immutable metadata envelope for all V2 domain events.
///
/// Every event produced by LexiQuest V2 is wrapped in this envelope so that
/// consent, identity, experiment assignment, and privacy classification travel
/// with the event payload regardless of transport or storage mechanism.
///
/// **Contract freeze:** Fields and their semantics are frozen after Week 5-6.
/// Additive changes (new nullable fields) require a version bump of
/// [schemaVersion].
library;

// ─── Supporting value types ──────────────────────────────────────────────────

/// Tenant (school / organisation) context.
///
/// `null` for personal-mode learners who are not affiliated with any tenant.
final class TenantContext {
  const TenantContext({required this.tenantId, required this.role});

  /// Opaque tenant identifier.
  final String tenantId;

  /// Learner's role inside this tenant (e.g. `'student'`, `'teacher'`).
  final String role;

  Map<String, dynamic> toJson() => {'tenantId': tenantId, 'role': role};

  factory TenantContext.fromJson(Map<String, dynamic> j) =>
      TenantContext(tenantId: j['tenantId'] as String, role: j['role'] as String);
}

/// Consent grants that were active at the moment the event was recorded.
///
/// Stored inline so that consent withdrawal can be reconstructed historically.
final class ConsentContext {
  const ConsentContext({
    required this.researchConsentVersion,
    required this.aiConsentGranted,
    required this.voiceConsentGranted,
    required this.socialConsentGranted,
  });

  /// Version of the research consent form the learner agreed to (0 = none).
  final int researchConsentVersion;

  /// `true` when the learner allowed data to be sent to an AI provider.
  final bool aiConsentGranted;

  /// `true` when the learner allowed voice recordings to leave the device.
  final bool voiceConsentGranted;

  /// `true` when the learner allowed social / leaderboard participation.
  final bool socialConsentGranted;

  /// Convenience: no consents granted, version 0.
  const ConsentContext.none()
    : researchConsentVersion = 0,
      aiConsentGranted = false,
      voiceConsentGranted = false,
      socialConsentGranted = false;

  Map<String, dynamic> toJson() => {
    'researchConsentVersion': researchConsentVersion,
    'aiConsentGranted': aiConsentGranted,
    'voiceConsentGranted': voiceConsentGranted,
    'socialConsentGranted': socialConsentGranted,
  };

  factory ConsentContext.fromJson(Map<String, dynamic> j) => ConsentContext(
    researchConsentVersion: j['researchConsentVersion'] as int,
    aiConsentGranted: j['aiConsentGranted'] as bool,
    voiceConsentGranted: j['voiceConsentGranted'] as bool,
    socialConsentGranted: j['socialConsentGranted'] as bool,
  );
}

/// A/B experiment cohort that was active when the event occurred.
final class ExperimentContext {
  const ExperimentContext({
    required this.experimentId,
    required this.variantId,
    required this.assignedAtUtc,
  });

  final String experimentId;
  final String variantId;
  final DateTime assignedAtUtc;

  Map<String, dynamic> toJson() => {
    'experimentId': experimentId,
    'variantId': variantId,
    'assignedAtUtc': assignedAtUtc.toIso8601String(),
  };

  factory ExperimentContext.fromJson(Map<String, dynamic> j) => ExperimentContext(
    experimentId: j['experimentId'] as String,
    variantId: j['variantId'] as String,
    assignedAtUtc: DateTime.parse(j['assignedAtUtc'] as String),
  );
}

/// Which AI or voice provider produced the output that this event records.
final class ProviderProvenance {
  const ProviderProvenance({
    required this.providerId,
    required this.modelVersion,
    this.requestId,
  });

  /// Opaque provider identifier (e.g. `'gemini'`, `'flutter_tts'`).
  final String providerId;

  /// Model / engine version string.
  final String modelVersion;

  /// Provider-assigned request trace ID for debugging.
  final String? requestId;

  Map<String, dynamic> toJson() => {
    'providerId': providerId,
    'modelVersion': modelVersion,
    if (requestId != null) 'requestId': requestId,
  };

  factory ProviderProvenance.fromJson(Map<String, dynamic> j) =>
      ProviderProvenance(
        providerId: j['providerId'] as String,
        modelVersion: j['modelVersion'] as String,
        requestId: j['requestId'] as String?,
      );
}

/// PII classification of the event payload.
enum PrivacyClassification {
  /// No personal data — can be shown to anyone.
  public,

  /// Contains identifiers visible only to the learner.
  ownerOnly,

  /// Research data pseudonymized per consent agreement.
  anonymized,

  /// Requires explicit separate consent before any processing.
  restricted,
}

// ─── Envelope ────────────────────────────────────────────────────────────────

/// Immutable event envelope — 22 required fields (V2 spec §11.1).
///
/// All [DateTime] fields are UTC. [payload] carries the domain-specific data;
/// the envelope fields provide routing, consent, and compliance context.
final class EventEnvelopeV2 {
  /// Schema version of the *envelope* (not the payload).  Currently `2`.
  static const int schemaVersion = 2;

  const EventEnvelopeV2({
    required this.eventId,
    required this.eventType,
    required this.eventVersion,
    required this.occurredAtUtc,
    required this.recordedAtUtc,
    required this.actorIdentity,
    required this.ownerIdentity,
    this.tenantContext,
    required this.aggregateType,
    required this.aggregateId,
    this.correlationId,
    this.causationId,
    required this.idempotencyKey,
    required this.consentContext,
    this.experimentContext,
    this.contentRevision,
    this.policyVersion,
    required this.appVersion,
    required this.buildId,
    this.providerProvenance,
    required this.privacyClassification,
    required this.payload,
  }) : assert(idempotencyKey.length > 0, 'idempotencyKey must not be empty'),
       assert(eventId.length > 0, 'eventId must not be empty'),
       assert(actorIdentity.length > 0, 'actorIdentity must not be empty'),
       assert(ownerIdentity.length > 0, 'ownerIdentity must not be empty'),
       assert(appVersion.length > 0, 'appVersion must not be empty'),
       assert(buildId.length > 0, 'buildId must not be empty');

  // Field 1 — UUID v7 (time-ordered, generated by caller)
  final String eventId;
  // Field 2 — e.g. 'QuizCompleted', 'SrsReviewCompleted'
  final String eventType;
  // Field 3 — payload schema version (1 for legacy-wrapped V1 events)
  final int eventVersion;
  // Field 4 — when the domain action happened
  final DateTime occurredAtUtc;
  // Field 5 — when the event was written to the envelope
  final DateTime recordedAtUtc;
  // Field 6 — identity of the agent that caused the event
  final String actorIdentity;
  // Field 7 — identity of the account that owns the data
  final String ownerIdentity;
  // Field 8 — school/class context; null for personal-mode learners
  final TenantContext? tenantContext;
  // Field 9 — aggregate root type (e.g. 'LearningSession')
  final String aggregateType;
  // Field 10 — aggregate root ID
  final String aggregateId;
  // Field 11 — optional distributed trace ID
  final String? correlationId;
  // Field 12 — optional ID of the event that caused this one
  final String? causationId;
  // Field 13 — replay-protection key; unique per (owner, idempotencyKey)
  final String idempotencyKey;
  // Field 14 — consent grants at recording time
  final ConsentContext consentContext;
  // Field 15 — A/B experiment context; null when not in any experiment
  final ExperimentContext? experimentContext;
  // Field 16 — content catalog revision (for reproducibility)
  final String? contentRevision;
  // Field 17 — privacy/data-handling policy version applied
  final String? policyVersion;
  // Field 18 — LexiQuest app version string
  final String appVersion;
  // Field 19 — git commit SHA at build time
  final String buildId;
  // Field 20 — AI/voice provider that contributed to the output
  final ProviderProvenance? providerProvenance;
  // Field 21 — PII classification of payload contents
  final PrivacyClassification privacyClassification;
  // Field 22 — domain-specific event data
  final Map<String, dynamic> payload;

  // ── Serialization ──────────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'eventId': eventId,
    'eventType': eventType,
    'eventVersion': eventVersion,
    'occurredAtUtc': occurredAtUtc.toIso8601String(),
    'recordedAtUtc': recordedAtUtc.toIso8601String(),
    'actorIdentity': actorIdentity,
    'ownerIdentity': ownerIdentity,
    if (tenantContext != null) 'tenantContext': tenantContext!.toJson(),
    'aggregateType': aggregateType,
    'aggregateId': aggregateId,
    if (correlationId != null) 'correlationId': correlationId,
    if (causationId != null) 'causationId': causationId,
    'idempotencyKey': idempotencyKey,
    'consentContext': consentContext.toJson(),
    if (experimentContext != null)
      'experimentContext': experimentContext!.toJson(),
    if (contentRevision != null) 'contentRevision': contentRevision,
    if (policyVersion != null) 'policyVersion': policyVersion,
    'appVersion': appVersion,
    'buildId': buildId,
    if (providerProvenance != null)
      'providerProvenance': providerProvenance!.toJson(),
    'privacyClassification': privacyClassification.name,
    'payload': payload,
  };

  factory EventEnvelopeV2.fromJson(Map<String, dynamic> j) {
    // Validate idempotencyKey before constructing to throw ArgumentError.
    final idem = j['idempotencyKey'] as String? ?? '';
    if (idem.isEmpty) {
      throw ArgumentError.value(idem, 'idempotencyKey', 'must not be empty');
    }
    final tenantJson = j['tenantContext'] as Map<String, dynamic>?;
    final expJson = j['experimentContext'] as Map<String, dynamic>?;
    final provJson = j['providerProvenance'] as Map<String, dynamic>?;
    return EventEnvelopeV2(
      eventId: j['eventId'] as String,
      eventType: j['eventType'] as String,
      eventVersion: j['eventVersion'] as int,
      occurredAtUtc: DateTime.parse(j['occurredAtUtc'] as String),
      recordedAtUtc: DateTime.parse(j['recordedAtUtc'] as String),
      actorIdentity: j['actorIdentity'] as String,
      ownerIdentity: j['ownerIdentity'] as String,
      tenantContext:
          tenantJson != null ? TenantContext.fromJson(tenantJson) : null,
      aggregateType: j['aggregateType'] as String,
      aggregateId: j['aggregateId'] as String,
      correlationId: j['correlationId'] as String?,
      causationId: j['causationId'] as String?,
      idempotencyKey: idem,
      consentContext: ConsentContext.fromJson(
        j['consentContext'] as Map<String, dynamic>,
      ),
      experimentContext:
          expJson != null ? ExperimentContext.fromJson(expJson) : null,
      contentRevision: j['contentRevision'] as String?,
      policyVersion: j['policyVersion'] as String?,
      appVersion: j['appVersion'] as String,
      buildId: j['buildId'] as String,
      providerProvenance:
          provJson != null ? ProviderProvenance.fromJson(provJson) : null,
      privacyClassification: PrivacyClassification.values.byName(
        j['privacyClassification'] as String,
      ),
      payload: Map<String, dynamic>.from(j['payload'] as Map),
    );
  }

  @override
  String toString() =>
      'EventEnvelopeV2(id=$eventId, type=$eventType, owner=$ownerIdentity)';
}
