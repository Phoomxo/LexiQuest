import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/learning/learning_event.dart';

LearningEvent _makeV1({
  String userId = 'user-abc',
  String eventId = 'evt-v1-001',
  DateTime? occurredAt,
}) => LearningEvent(
  eventId: eventId,
  schemaVersion: 1,
  pseudonymousUserId: userId,
  occurredAtUtc: occurredAt ?? DateTime.utc(2026, 1, 1, 12, 0),
  activity: LearningActivity.multipleChoiceQuiz,
  contentId: 'word-cat',
  categoryId: 'animals',
  cefrLevel: 'A1',
  skill: LearningSkill.meaningRecall,
  correct: true,
  score: 100,
  responseTimeMs: 2500,
  attemptNumber: 1,
  appVersion: '1.0.0',
  buildId: 'oldsha',
);

const _adapter = EventV1ToV2Adapter(appVersion: '2.0.0', buildId: 'newsha');

void main() {
  group('EventV1ToV2Adapter — D3.4', () {
    test('V1 event becomes V2 envelope with V1 payload intact', () {
      final v1 = _makeV1();
      final v2 = _adapter.adapt(v1);

      expect(v2.eventType, 'QuizCompleted');
      expect(v2.ownerIdentity, 'user-abc');
      expect(v2.actorIdentity, 'user-abc');
      expect(v2.eventVersion, 1);
      expect(v2.payload['schemaVersion'], 1);
      expect(v2.payload['activity'], 'multiple_choice_quiz');
      expect(v2.payload['correct'], isTrue);
      expect(v2.payload['score'], 100);
      expect(v2.idempotencyKey, isNotEmpty);
    });

    test('V1 adapter generates stable idempotency keys', () {
      final v1 = _makeV1();
      final key1 = _adapter.adapt(v1).idempotencyKey;
      final key2 = _adapter.adapt(v1).idempotencyKey;
      expect(key1, key2, reason: 'idempotency key must be deterministic');
    });

    test('adapter uses new appVersion and buildId, not V1 values', () {
      final v2 = _adapter.adapt(_makeV1());
      expect(v2.appVersion, '2.0.0');
      expect(v2.buildId, 'newsha');
    });

    test('tenantContext is null — V1 had no tenants', () {
      expect(_adapter.adapt(_makeV1()).tenantContext, isNull);
    });

    test('experimentContext is null — V1 had no experiments', () {
      expect(_adapter.adapt(_makeV1()).experimentContext, isNull);
    });

    test('privacyClassification is anonymized for all V1 events', () {
      expect(
        _adapter.adapt(_makeV1()).privacyClassification,
        PrivacyClassification.anonymized,
      );
    });

    test('occurredAtUtc preserved from V1', () {
      final utc = DateTime.utc(2026, 3, 15, 8, 30);
      final v2 = _adapter.adapt(_makeV1(occurredAt: utc));
      expect(v2.occurredAtUtc, utc);
    });

    test('different users produce different idempotency keys', () {
      final v1a = _makeV1(userId: 'user-A');
      final v1b = _makeV1(userId: 'user-B');
      expect(
        _adapter.adapt(v1a).idempotencyKey,
        isNot(_adapter.adapt(v1b).idempotencyKey),
      );
    });

    test('V1 payload survives round-trip through toJson→fromJson', () {
      final v2 = _adapter.adapt(_makeV1());
      final restored = EventEnvelopeV2.fromJson(v2.toJson());
      expect(restored.payload['contentId'], 'word-cat');
      expect(restored.payload['cefrLevel'], 'A1');
    });
  });
}
