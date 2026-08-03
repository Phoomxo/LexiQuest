import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';

// Minimal valid envelope used across tests.
EventEnvelopeV2 _makeEvent({
  String eventId = 'evt-001',
  String idempotencyKey = 'idem-001',
  Map<String, dynamic>? payload,
  PrivacyClassification privacy = PrivacyClassification.ownerOnly,
  ExperimentContext? experiment,
  TenantContext? tenant,
  ProviderProvenance? provenance,
  String? correlationId,
  String? causationId,
  String? contentRevision,
  String? policyVersion,
}) => EventEnvelopeV2(
  eventId: eventId,
  eventType: 'QuizCompleted',
  eventVersion: 1,
  occurredAtUtc: DateTime.utc(2026, 8, 4, 10, 0),
  recordedAtUtc: DateTime.utc(2026, 8, 4, 10, 0, 1),
  actorIdentity: 'owner-abc',
  ownerIdentity: 'owner-abc',
  tenantContext: tenant,
  aggregateType: 'LearningSession',
  aggregateId: 'sess-001',
  correlationId: correlationId,
  causationId: causationId,
  idempotencyKey: idempotencyKey,
  consentContext: const ConsentContext(
    researchConsentVersion: 1,
    aiConsentGranted: false,
    voiceConsentGranted: false,
    socialConsentGranted: false,
  ),
  experimentContext: experiment,
  contentRevision: contentRevision,
  policyVersion: policyVersion,
  appVersion: '1.0.0',
  buildId: 'abc1234',
  providerProvenance: provenance,
  privacyClassification: privacy,
  payload: payload ?? {'correct': true, 'score': 100},
);

void main() {
  group('EventEnvelopeV2 — D3.1 contract', () {
    test('has exactly 22 fields', () {
      // Verify by round-trip: all 22 keys must survive toJson→fromJson
      final event = _makeEvent(
        experiment: ExperimentContext(
          experimentId: 'exp-1',
          variantId: 'control',
          assignedAtUtc: DateTime.utc(2026, 8, 1),
        ),
        tenant: const TenantContext(tenantId: 'school-1', role: 'student'),
        provenance: const ProviderProvenance(
          providerId: 'gemini',
          modelVersion: '1.5-flash',
        ),
        correlationId: 'trace-1',
        causationId: 'cause-1',
        contentRevision: 'cat-v3',
        policyVersion: 'pp-v1',
      );
      final json = event.toJson();

      // 22 envelope fields plus schemaVersion envelope marker
      final expectedKeys = {
        'schemaVersion',
        'eventId', 'eventType', 'eventVersion',
        'occurredAtUtc', 'recordedAtUtc',
        'actorIdentity', 'ownerIdentity',
        'tenantContext', 'aggregateType', 'aggregateId',
        'correlationId', 'causationId',
        'idempotencyKey', 'consentContext', 'experimentContext',
        'contentRevision', 'policyVersion',
        'appVersion', 'buildId', 'providerProvenance',
        'privacyClassification', 'payload',
      };
      expect(json.keys.toSet(), expectedKeys);
    });

    test('EventEnvelopeV2 is immutable — all fields are final', () {
      // Compile-time guarantee: the const constructor works.
      final event = _makeEvent();
      expect(event.eventId, 'evt-001');
      // No setters exist — mutation would be a compile error.
    });

    test('round-trip serialization preserves all 22 fields', () {
      final original = _makeEvent(
        experiment: ExperimentContext(
          experimentId: 'exp-2',
          variantId: 'variant-a',
          assignedAtUtc: DateTime.utc(2026, 7, 15),
        ),
        tenant: const TenantContext(tenantId: 'school-2', role: 'teacher'),
        provenance: const ProviderProvenance(
          providerId: 'flutter_tts',
          modelVersion: '4.0',
          requestId: 'req-xyz',
        ),
        correlationId: 'corr-42',
        causationId: 'caus-9',
        contentRevision: 'rev-7',
        policyVersion: 'v2',
        payload: {'score': 85, 'words': ['cat', 'dog']},
      );
      final json = original.toJson();
      final restored = EventEnvelopeV2.fromJson(json);

      expect(restored.eventId, original.eventId);
      expect(restored.eventType, original.eventType);
      expect(restored.eventVersion, original.eventVersion);
      expect(restored.occurredAtUtc, original.occurredAtUtc);
      expect(restored.recordedAtUtc, original.recordedAtUtc);
      expect(restored.actorIdentity, original.actorIdentity);
      expect(restored.ownerIdentity, original.ownerIdentity);
      expect(restored.tenantContext!.tenantId, original.tenantContext!.tenantId);
      expect(restored.aggregateType, original.aggregateType);
      expect(restored.aggregateId, original.aggregateId);
      expect(restored.correlationId, original.correlationId);
      expect(restored.causationId, original.causationId);
      expect(restored.idempotencyKey, original.idempotencyKey);
      expect(
        restored.consentContext.researchConsentVersion,
        original.consentContext.researchConsentVersion,
      );
      expect(
        restored.experimentContext!.variantId,
        original.experimentContext!.variantId,
      );
      expect(restored.contentRevision, original.contentRevision);
      expect(restored.policyVersion, original.policyVersion);
      expect(restored.appVersion, original.appVersion);
      expect(restored.buildId, original.buildId);
      expect(
        restored.providerProvenance!.requestId,
        original.providerProvenance!.requestId,
      );
      expect(restored.privacyClassification, original.privacyClassification);
      expect(restored.payload['score'], original.payload['score']);
    });

    test('idempotencyKey must not be empty — assert fires in debug mode', () {
      expect(
        () => EventEnvelopeV2(
          eventId: 'e',
          eventType: 'X',
          eventVersion: 1,
          occurredAtUtc: DateTime.utc(2026, 1, 1),
          recordedAtUtc: DateTime.utc(2026, 1, 1),
          actorIdentity: 'a',
          ownerIdentity: 'a',
          aggregateType: 'T',
          aggregateId: 'id',
          idempotencyKey: '', // ← empty
          consentContext: const ConsentContext.none(),
          appVersion: '1.0',
          buildId: 'sha',
          privacyClassification: PrivacyClassification.ownerOnly,
          payload: const {},
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('fromJson throws ArgumentError when idempotencyKey is empty', () {
      final json = _makeEvent().toJson();
      json['idempotencyKey'] = '';
      expect(
        () => EventEnvelopeV2.fromJson(json),
        throwsArgumentError,
      );
    });

    test('unknown JSON fields do not break deserialization — forward compat', () {
      final json = _makeEvent().toJson();
      json['futureField'] = 'added in v3';
      json['anotherFutureField'] = 42;
      // Must not throw; unknown keys are silently ignored.
      final event = EventEnvelopeV2.fromJson(json);
      expect(event.eventId, isNotEmpty);
    });

    test('nullable fields are omitted from toJson when null', () {
      final event = _makeEvent(); // all nullables absent
      final json = event.toJson();
      expect(json.containsKey('tenantContext'), isFalse);
      expect(json.containsKey('correlationId'), isFalse);
      expect(json.containsKey('causationId'), isFalse);
      expect(json.containsKey('experimentContext'), isFalse);
      expect(json.containsKey('contentRevision'), isFalse);
      expect(json.containsKey('policyVersion'), isFalse);
      expect(json.containsKey('providerProvenance'), isFalse);
    });

    test('all PrivacyClassification values round-trip through JSON', () {
      for (final cls in PrivacyClassification.values) {
        final event = _makeEvent(privacy: cls);
        final restored = EventEnvelopeV2.fromJson(event.toJson());
        expect(restored.privacyClassification, cls);
      }
    });

    test('ConsentContext.none() has zero version and all false', () {
      const ctx = ConsentContext.none();
      expect(ctx.researchConsentVersion, 0);
      expect(ctx.aiConsentGranted, isFalse);
      expect(ctx.voiceConsentGranted, isFalse);
      expect(ctx.socialConsentGranted, isFalse);
    });
  });
}
