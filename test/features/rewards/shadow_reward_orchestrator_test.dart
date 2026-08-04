import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/rewards/application/shadow_reward_orchestrator.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_eligibility.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

int _seq = 0;

EventEnvelopeV2 _makeEvent({
  String eventType = 'QuizCompleted',
  Map<String, dynamic> payload = const {'correct': true},
  String idempotencyKey = 'idem-shadow',
  String ownerId = 'owner-shadow',
}) => EventEnvelopeV2(
  eventId: 'evt-shadow-${++_seq}',
  eventType: eventType,
  eventVersion: 1,
  occurredAtUtc: DateTime.utc(2026, 8, 4, 10, 0),
  recordedAtUtc: DateTime.utc(2026, 8, 4, 10, 0, 1),
  actorIdentity: ownerId,
  ownerIdentity: ownerId,
  aggregateType: 'LearningSession',
  aggregateId: 'sess-shadow',
  idempotencyKey: idempotencyKey,
  consentContext: const ConsentContext.none(),
  appVersion: '1.0',
  buildId: 'sha',
  privacyClassification: PrivacyClassification.anonymized,
  payload: payload,
);

ShadowRewardOrchestrator _makeOrchestrator({
  required InMemoryShadowLogger logger,
  bool canGrantResult = true,
}) => ShadowRewardOrchestrator(
  logger: logger,
  canGrant: (_, __) async => canGrantResult,
  generateId: () => 'req-${DateTime.now().millisecondsSinceEpoch}',
  nowUtc: () => DateTime.utc(2026, 8, 4, 10, 1),
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() => _seq = 0);

  group('ShadowRewardOrchestrator', () {
    test('logs decision for eligible event without granting reward', () async {
      final logger = InMemoryShadowLogger();
      final orch = _makeOrchestrator(logger: logger);

      await orch.processShadow(_makeEvent(payload: {'correct': true}));

      expect(logger.entries, hasLength(1));
      expect(logger.entries.first.decision.result, EligibilityResult.eligible);
      expect(logger.entries.first.wouldSucceed, isTrue);
      expect(logger.entries.first.request, isNotNull);
      expect(logger.errors, isEmpty);
    });

    test('logs skipped entry for non-eligible event', () async {
      final logger = InMemoryShadowLogger();
      final orch = _makeOrchestrator(logger: logger);

      await orch.processShadow(
        _makeEvent(eventType: 'SrsReviewCompleted', payload: {}),
      );

      expect(logger.entries, hasLength(1));
      expect(
        logger.entries.first.decision.result,
        EligibilityResult.notEligible,
      );
      expect(logger.entries.first.request, isNull);
      expect(logger.entries.first.wouldSucceed, isFalse);
    });

    test(
      'idempotency check: wouldSucceed=false when already granted',
      () async {
        final logger = InMemoryShadowLogger();
        final orch = _makeOrchestrator(
          logger: logger,
          canGrantResult: false, // already granted
        );

        await orch.processShadow(
          _makeEvent(
            payload: {'correct': true},
            idempotencyKey: 'already_used',
          ),
        );

        expect(logger.entries.first.wouldSucceed, isFalse);
        expect(
          logger.entries.first.decision.result,
          EligibilityResult.eligible,
        );
      },
    );

    test('shadow errors are swallowed — never propagate to caller', () async {
      final logger = InMemoryShadowLogger();
      final throwingOrch = ShadowRewardOrchestrator(
        logger: logger,
        canGrant: (_, __) async => throw Exception('canGrant failed'),
        generateId: () => 'req-id',
        nowUtc: () => DateTime.utc(2026, 8, 4),
      );

      // Must not throw
      await throwingOrch.processShadow(_makeEvent(payload: {'correct': true}));

      expect(logger.errors, hasLength(1));
    });

    test('shadow mode produces log entries with all required fields', () async {
      final logger = InMemoryShadowLogger();
      final orch = _makeOrchestrator(logger: logger);
      final event = _makeEvent(
        ownerId: 'owner-abc',
        idempotencyKey: 'key-abc',
        payload: {'correct': true},
      );

      await orch.processShadow(event);

      final entry = logger.entries.first;
      expect(entry.eventId, event.eventId);
      expect(entry.eventType, 'QuizCompleted');
      expect(entry.ownerId, 'owner-abc');
      expect(entry.decision.coinAmount, 10);
      expect(entry.request!.idempotencyKey, 'key-abc');
      expect(entry.request!.ownerId, 'owner-abc');
    });

    test('log entry serialises to JSON without error', () async {
      final logger = InMemoryShadowLogger();
      await _makeOrchestrator(
        logger: logger,
      ).processShadow(_makeEvent(payload: {'correct': true}));
      expect(() => logger.entries.first.toJson(), returnsNormally);
    });

    test('multiple events accumulate in log', () async {
      final logger = InMemoryShadowLogger();
      final orch = _makeOrchestrator(logger: logger);

      for (var i = 0; i < 5; i++) {
        await orch.processShadow(_makeEvent(payload: {'correct': true}));
      }

      expect(logger.entries, hasLength(5));
    });
  });
}
