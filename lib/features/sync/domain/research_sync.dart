import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../adventure/domain/adventure_entry.dart';
import '../../events/domain/event_envelope_v2.dart';
import '../../events/domain/today_experience_event_payload_policy.dart';
import '../../research/domain/research_participation_permit.dart';
import '../../research/domain/research_event_identity.dart';
import '../../research/domain/research_session_proof.dart';
import 'sync_entity.dart';
import 'sync_failure.dart';

// Keep revision metadata available to existing callers without making pure
// Dart build tools depend on the runtime proof-validation graph.
export 'sync_entity.dart' show researchMeasurementV1RulesRevision;

/// No production constructor: real enrollment/deployment is a separate release.
final class ResearchMeasurementSyncRollout {
  const ResearchMeasurementSyncRollout.off()
    : enabled = false,
      deployedRulesRevision = '';
  const ResearchMeasurementSyncRollout.localEmulatorV1({
    required this.deployedRulesRevision,
  }) : enabled = true;
  final bool enabled;
  final String deployedRulesRevision;
  bool get allowsSync =>
      enabled && deployedRulesRevision == researchMeasurementV1RulesRevision;
}

enum ResearchSyncPhase { enqueue, claim, push, pull }

/// Validation must reload current owner/consent/assignment and validate the
/// signed permit, receipts, issuer/revision/revocation and instrument pins.
/// Validate the supplied sync lease token and deny an actual owner-transition
/// fence. A global sync lease alone is not an owner fence. Never acquire a
/// competing lease from this read-only callback. This request is not uploaded.
final class ResearchSyncRequest {
  ResearchSyncRequest({
    required this.phase,
    required this.ownerId,
    required this.firebaseUid,
    required this.collection,
    required this.entityId,
    required Map<String, Object?> payload,
    required DateTime evaluatedAtUtc,
    this.ownerGateToken,
    this.serverReadProvenance,
  }) : payload = _freezeMap(payload),
       // This timestamp is process-local clock context, not signed evidence.
       // Invalid UTC/negative values remain invalid for the authorizer to deny.
       evaluatedAtUtc =
           evaluatedAtUtc.isUtc && evaluatedAtUtc.microsecondsSinceEpoch >= 0
           ? DateTime.fromMillisecondsSinceEpoch(
               evaluatedAtUtc.millisecondsSinceEpoch,
               isUtc: true,
             )
           : evaluatedAtUtc;
  final ResearchSyncPhase phase;
  final String ownerId;
  final String firebaseUid;
  final SyncCollection collection;
  final String entityId;
  final Map<String, Object?> payload;
  final DateTime evaluatedAtUtc;
  final String? ownerGateToken;

  /// Forward only from a validated server SyncEntity on pull, never from JSON.
  final SyncServerReadProvenance? serverReadProvenance;
}

typedef ResearchSyncAuthorizer =
    Future<bool> Function(ResearchSyncRequest request);

Future<bool> authorizeResearchSync(
  ResearchSyncAuthorizer? authorizer,
  ResearchSyncRequest request,
) async {
  if (authorizer == null) return false;
  try {
    return await authorizer(request);
  } on Object {
    return false;
  }
}

abstract final class ResearchSyncContract {
  static const collections = <SyncCollection>[
    SyncCollection.researchParticipationPermits,
    SyncCollection.motivationMeasurementRuns,
    SyncCollection.motivationResponses,
    SyncCollection.researchSessionProofs,
    SyncCollection.measurementOpportunities,
    SyncCollection.neutralEventsV2,
  ];
  static const eventTypes = <String>{
    'TodayExperiencePresented',
    'TodayExperiencePresentationChanged',
    'TodayExperienceMissionStarted',
    'TodayExperienceMissionCompleted',
  };
  static SyncCollection? collectionForEntityType(String type) {
    if (type == 'researchWithdrawal') return SyncCollection.researchWithdrawals;
    if (eventTypes.contains(type)) return SyncCollection.neutralEventsV2;
    for (final c in collections) {
      if (c != SyncCollection.neutralEventsV2 && c.entityType == type) return c;
    }
    return null;
  }

  static const referenceKeys = <String>{
    'permitId',
    'permitPayloadSha256',
    'permitRevision',
  };
  static const runKeys = <String>{
    ...referenceKeys,
    'id',
    'ownerId',
    'assignmentId',
    'consentVersion',
    'consentDecidedAtUtcMs',
    'protocolId',
    'protocolVersion',
    'treatment',
    'instrumentId',
    'instrumentVersion',
    'formId',
    'formVersion',
    'appVersion',
    'buildId',
    'databaseSchemaVersion',
    'contentRevision',
    'evidencePolicyVersion',
    'state',
    'startedAtUtcMs',
    'closedAtUtcMs',
  };
  static const responseKeys = <String>{
    ...referenceKeys,
    'id',
    'ownerId',
    'runId',
    'itemId',
    'itemCatalogVersion',
    'responseCode',
    'ordinalValue',
    'answeredAtUtcMs',
  };
  static const opportunityKeys = <String>{
    ...referenceKeys,
    'id',
    'ownerId',
    'measurementRunId',
    'entryAttemptId',
    'assignedTreatment',
    'effectivePresentation',
    'presentedEventId',
    'learningSessionId',
    'startedEventId',
    'completedEventId',
    'lastSwitchOrdinal',
    'suppressedSwitchCount',
    'openedAtUtcMs',
    'closedAtUtcMs',
  };
  static const permitKeys = <String>{
    'schema',
    'id',
    'ownerId',
    'participantClass',
    'ageBandCode',
    'assignmentId',
    'assignedTreatment',
    'consentReceiptId',
    'guardianPermissionReceiptRef',
    'learnerAssentReceiptRef',
    'protocolId',
    'protocolVersion',
    'issuedAtUtc',
    'expiresAtUtc',
    'revokedAtUtc',
    'issuerKeyId',
    'localRevision',
    'cloudRevision',
    'isDeleted',
    'payloadSha256',
    'signature',
  };
  static const eventKeys = <String>{...referenceKeys, 'envelope'};

  static Map<String, Object?> permitPayload(ResearchParticipationPermit p) => {
    ...jsonDecode(p.canonicalPayload()) as Map<String, dynamic>,
    'payloadSha256': p.payloadSha256,
    'signature': p.signature,
  };

  /// Only structural/hash validation here. Signature/receipt trust must come
  /// from the injected authorizer and the read-only server authority.
  static ResearchParticipationPermit permitFromPayload(Map<String, Object?> p) {
    exactKeys(p, permitKeys);
    if (p['schema'] != 'lexiquest.research-participation-permit.v1') _invalid();
    for (final key in [
      'id',
      'ownerId',
      'ageBandCode',
      'assignmentId',
      'consentReceiptId',
      'protocolId',
      'protocolVersion',
      'issuerKeyId',
    ]) {
      code(p[key]);
    }
    for (final key in [
      'guardianPermissionReceiptRef',
      'learnerAssentReceiptRef',
    ]) {
      if (p[key] != null) code(p[key]);
    }
    integer(p['localRevision'], min: 1);
    integer(p['cloudRevision'], min: 1);
    if (p['localRevision'] != p['cloudRevision'] ||
        p['isDeleted'] is! bool ||
        !const ['adult', 'minor'].contains(p['participantClass'])) {
      _invalid();
    }
    presentation(p['assignedTreatment']);
    digest(p['payloadSha256']);
    final signature = p['signature'];
    if (signature is! String ||
        signature.isEmpty ||
        signature.length > 256 ||
        signature != signature.trim()) {
      _invalid();
    }
    final permit = ResearchParticipationPermit(
      id: p['id']! as String,
      ownerId: p['ownerId']! as String,
      participantClass: ResearchParticipantClass.values.byName(
        p['participantClass']! as String,
      ),
      ageBandCode: p['ageBandCode']! as String,
      assignmentId: p['assignmentId']! as String,
      assignedTreatment: TodayExperiencePresentation.values.byName(
        p['assignedTreatment']! as String,
      ),
      consentReceiptId: p['consentReceiptId']! as String,
      guardianPermissionReceiptRef:
          p['guardianPermissionReceiptRef'] as String?,
      learnerAssentReceiptRef: p['learnerAssentReceiptRef'] as String?,
      protocolId: p['protocolId']! as String,
      protocolVersion: p['protocolVersion']! as String,
      issuedAtUtc: utc(p['issuedAtUtc']),
      expiresAtUtc: utc(p['expiresAtUtc']),
      revokedAtUtc: p['revokedAtUtc'] == null ? null : utc(p['revokedAtUtc']),
      issuerKeyId: p['issuerKeyId']! as String,
      payloadSha256: p['payloadSha256']! as String,
      signature: signature,
      localRevision: p['localRevision']! as int,
      cloudRevision: p['cloudRevision']! as int,
      isDeleted: p['isDeleted']! as bool,
    );
    if (!permit.expiresAtUtc.isAfter(permit.issuedAtUtc) ||
        (permit.revokedAtUtc != null &&
            permit.revokedAtUtc!.isBefore(permit.issuedAtUtc)) ||
        (permit.participantClass == ResearchParticipantClass.minor &&
            (permit.guardianPermissionReceiptRef == null ||
                permit.learnerAssentReceiptRef == null)) ||
        sha256.convert(utf8.encode(permit.canonicalPayload())).toString() !=
            permit.payloadSha256) {
      _invalid();
    }
    return permit;
  }

  static Map<String, Object?> reference(ResearchParticipationPermit p) => {
    'permitId': p.id,
    'permitPayloadSha256': p.payloadSha256,
    'permitRevision': p.localRevision,
  };
  static String ownerOf(SyncCollection c, Map<String, Object?> p) =>
      c == SyncCollection.neutralEventsV2
      ? (p['envelope'] as Map)['ownerIdentity'] as String
      : p['ownerId']! as String;

  static void validate({
    required SyncCollection collection,
    required String entityId,
    required Map<String, Object?> payload,
    required int revision,
    required bool isDeleted,
    ResearchSyncPhase phase = ResearchSyncPhase.push,
  }) {
    try {
      final p = payload;
      if (collection == SyncCollection.researchWithdrawals) {
        exactKeys(p, {'permitId', 'ownerId'});
        code(entityId);
        code(p['ownerId']);
        if (p['permitId'] != entityId ||
            revision != 1 ||
            isDeleted ||
            phase == ResearchSyncPhase.pull) {
          _invalid();
        }
        return;
      }
      if (!collections.contains(collection) ||
          utf8.encode(jsonEncode(p)).length >
              (collection == SyncCollection.researchSessionProofs
                  ? ResearchSessionProof.maximumPayloadBytes
                  : 16384)) {
        _invalid();
      }
      code(entityId);
      integer(revision, min: 1);
      if (collection == SyncCollection.researchParticipationPermits) {
        final permit = permitFromPayload(p);
        if (permit.id != entityId ||
            permit.localRevision != revision ||
            permit.isDeleted != isDeleted ||
            (phase != ResearchSyncPhase.pull && isDeleted)) {
          _invalid();
        }
        return;
      }
      if (isDeleted) _invalid();
      code(p['permitId']);
      digest(p['permitPayloadSha256']);
      integer(p['permitRevision'], min: 1);
      if (collection == SyncCollection.researchSessionProofs) {
        final proof = ResearchSessionProof.decode(p);
        if (proof.id != entityId || revision != 1) _invalid();
        return;
      }
      if (collection == SyncCollection.neutralEventsV2) {
        exactKeys(p, eventKeys);
        validateEvent(
          Map<String, dynamic>.from(p['envelope']! as Map),
          entityId,
        );
        if (revision != 1) _invalid();
        return;
      }
      code(p['ownerId']);
      if (p['id'] != entityId) _invalid();
      if (collection == SyncCollection.motivationMeasurementRuns) {
        exactKeys(p, runKeys);
        for (final k in [
          'assignmentId',
          'protocolId',
          'protocolVersion',
          'instrumentId',
          'instrumentVersion',
          'formId',
          'formVersion',
          'appVersion',
          'buildId',
          'contentRevision',
          'evidencePolicyVersion',
        ]) {
          code(p[k]);
        }
        integer(p['consentVersion'], min: 1);
        integer(p['consentDecidedAtUtcMs']);
        integer(p['databaseSchemaVersion'], min: 24);
        if (!const <int>{24, 25, 26, 27}.contains(p['databaseSchemaVersion'])) {
          _invalid();
        }
        presentation(p['treatment']);
        if (!const [
          'started',
          'completed',
          'skipped',
          'abandoned',
          'withdrawn',
        ].contains(p['state'])) {
          _invalid();
        }
        integer(p['startedAtUtcMs'], min: p['consentDecidedAtUtcMs']! as int);
        if (p['state'] == 'started') {
          if (p['closedAtUtcMs'] != null) _invalid();
        } else {
          integer(p['closedAtUtcMs'], min: p['startedAtUtcMs']! as int);
        }
      } else if (collection == SyncCollection.motivationResponses) {
        exactKeys(p, responseKeys);
        for (final k in [
          'runId',
          'itemId',
          'itemCatalogVersion',
          'responseCode',
        ]) {
          code(p[k]);
        }
        if (p['ordinalValue'] != null) integer(p['ordinalValue'], max: 100);
        integer(p['answeredAtUtcMs']);
        if (revision != 1) _invalid();
      } else {
        exactKeys(p, opportunityKeys);
        code(p['measurementRunId']);
        if (p['entryAttemptId'] is! String ||
            !RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ).hasMatch(p['entryAttemptId']! as String)) {
          _invalid();
        }
        presentation(p['assignedTreatment']);
        presentation(p['effectivePresentation']);
        for (final k in [
          'presentedEventId',
          'learningSessionId',
          'startedEventId',
          'completedEventId',
        ]) {
          if (p[k] != null) code(p[k]);
        }
        integer(p['lastSwitchOrdinal'], max: 10);
        integer(p['suppressedSwitchCount']);
        integer(p['openedAtUtcMs']);
        if (p['closedAtUtcMs'] != null) {
          integer(p['closedAtUtcMs'], min: p['openedAtUtcMs']! as int);
        }
        if ((p['startedEventId'] != null && p['learningSessionId'] == null) ||
            (p['completedEventId'] != null &&
                (p['startedEventId'] == null || p['closedAtUtcMs'] == null))) {
          _invalid();
        }
      }
    } on SyncFailure {
      rethrow;
    } on Object {
      _invalid();
    }
  }

  static void validateEvent(Map<String, dynamic> p, String id) {
    final envelope = EventEnvelopeV2.fromJson(p);
    // Respect the frozen serializer: schema marker plus its 22 fields; absent
    // optional values stay absent. No transport authority fields enter it.
    if (p['schemaVersion'] != 2 ||
        !same(p, envelope.toJson()) ||
        envelope.eventId != id ||
        envelope.eventVersion != 1 ||
        !eventTypes.contains(envelope.eventType) ||
        envelope.ownerIdentity != envelope.actorIdentity ||
        envelope.privacyClassification != PrivacyClassification.ownerOnly ||
        envelope.tenantContext != null ||
        envelope.providerProvenance != null ||
        envelope.causationId != null ||
        envelope.experimentContext == null ||
        envelope.consentContext.researchConsentVersion < 1 ||
        envelope.consentContext.aiConsentGranted ||
        envelope.consentContext.voiceConsentGranted ||
        envelope.consentContext.socialConsentGranted) {
      _invalid();
    }
    for (final v in [
      envelope.ownerIdentity,
      envelope.aggregateId,
      envelope.correlationId,
      envelope.idempotencyKey,
      envelope.appVersion,
      envelope.buildId,
      envelope.contentRevision,
      envelope.policyVersion,
      envelope.experimentContext!.experimentId,
      envelope.experimentContext!.variantId,
    ]) {
      code(v);
    }
    final occurred = utc(p['occurredAtUtc']);
    if (researchEventOccurrence(id, occurred) != occurred) _invalid();
    if (utc(p['recordedAtUtc']).isBefore(occurred) ||
        utc(
          (p['experimentContext'] as Map)['assignedAtUtc'],
        ).isAfter(occurred)) {
      _invalid();
    }
    exactKeys(Map<String, Object?>.from(p['consentContext'] as Map), {
      'researchConsentVersion',
      'aiConsentGranted',
      'voiceConsentGranted',
      'socialConsentGranted',
    });
    exactKeys(Map<String, Object?>.from(p['experimentContext'] as Map), {
      'experimentId',
      'variantId',
      'assignedAtUtc',
    });
    TodayExperienceEventPayloadPolicy.validate(
      envelope.eventType,
      envelope.payload,
    );
    final mission =
        envelope.eventType == 'TodayExperienceMissionStarted' ||
        envelope.eventType == 'TodayExperienceMissionCompleted';
    if (envelope.aggregateType !=
            (mission ? 'LearningSession' : 'MeasurementOpportunity') ||
        (!mission && envelope.aggregateId != envelope.correlationId) ||
        (mission &&
            envelope.payload['opportunityId'] != envelope.correlationId)) {
      _invalid();
    }
  }

  static String fingerprint(Map<String, Object?> p) =>
      sha256.convert(utf8.encode(jsonEncode(_sorted(p)))).toString();

  /// Shared identity for atomic local intent and its immutable wire snapshot.
  static String operationIdFor({
    required SyncCollection collection,
    required String entityId,
    required Map<String, Object?> payload,
    required int revision,
  }) =>
      'research-sync:${fingerprint({'collection': collection.wireName, 'id': entityId, 'payload': payload})}:$revision';
  static bool same(Object? a, Object? b) =>
      jsonEncode(_sorted(a)) == jsonEncode(_sorted(b));
  static void exactKeys(Map<String, Object?> p, Set<String> keys) {
    if (p.length != keys.length || !p.keys.every(keys.contains)) _invalid();
  }

  static void code(Object? v) {
    if (v is! String || !RegExp(r'^[A-Za-z0-9_.:\-]{1,128}$').hasMatch(v)) {
      _invalid();
    }
  }

  static void digest(Object? v) {
    if (v is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(v)) _invalid();
  }

  static void integer(Object? v, {int min = 0, int max = 9007199254740991}) {
    if (v is! int || v < min || v > max) _invalid();
  }

  static void presentation(Object? v) {
    if (v != 'standard' && v != 'adventure') _invalid();
  }

  static DateTime utc(Object? v) {
    if (v is! String) _invalid();
    final d = DateTime.parse(v);
    if (!d.isUtc ||
        d.millisecondsSinceEpoch < 0 ||
        d.microsecondsSinceEpoch % 1000 != 0 ||
        d.toIso8601String() != v) {
      _invalid();
    }
    return d;
  }
}

Never _invalid() => throw const InvalidSyncPayloadFailure();
Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final k in keys) k: _sorted(value[k])};
  }
  if (value is List) return value.map(_sorted).toList();
  return value;
}

Map<String, Object?> _freezeMap(Map<String, Object?> p) => Map.unmodifiable({
  for (final e in p.entries)
    e.key: e.value is Map
        ? _freezeMap(Map<String, Object?>.from(e.value! as Map))
        : e.value,
});
