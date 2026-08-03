import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_eligibility.dart';

EventEnvelopeV2 _makeEvent({
  required String eventType,
  Map<String, dynamic> payload = const {},
  String idempotencyKey = 'idem-test',
}) => EventEnvelopeV2(
  eventId: 'evt-elig-001',
  eventType: eventType,
  eventVersion: 1,
  occurredAtUtc: DateTime.utc(2026, 8, 4, 10, 0),
  recordedAtUtc: DateTime.utc(2026, 8, 4, 10, 0, 1),
  actorIdentity: 'owner-1',
  ownerIdentity: 'owner-1',
  aggregateType: 'LearningSession',
  aggregateId: 'sess-1',
  idempotencyKey: idempotencyKey,
  consentContext: const ConsentContext.none(),
  appVersion: '1.0',
  buildId: 'sha',
  privacyClassification: PrivacyClassification.anonymized,
  payload: payload,
);

void main() {
  group('RewardEligibilityDecision.evaluate — policy v1', () {
    test('correct quiz completion grants 10 coins', () {
      final event = _makeEvent(
        eventType: 'QuizCompleted',
        payload: {'correct': true, 'score': 100},
      );
      final d = RewardEligibilityDecision.evaluate(event);
      expect(d.result, EligibilityResult.eligible);
      expect(d.coinAmount, 10);
      expect(d.reason, 'quiz_completed_correctly');
      expect(d.policyVersion, 'v1');
    });

    test('incorrect quiz grants no reward', () {
      final event = _makeEvent(
        eventType: 'QuizCompleted',
        payload: {'correct': false, 'score': 0},
      );
      final d = RewardEligibilityDecision.evaluate(event);
      expect(d.result, EligibilityResult.notEligible);
      expect(d.coinAmount, 0);
    });

    test('QuizCompleted with null correct field grants no reward', () {
      final event = _makeEvent(
        eventType: 'QuizCompleted',
        payload: {'score': 80}, // no 'correct' key
      );
      final d = RewardEligibilityDecision.evaluate(event);
      expect(d.result, EligibilityResult.notEligible);
    });

    test('daily quest completion grants 50 coins', () {
      final d = RewardEligibilityDecision.evaluate(
        _makeEvent(
          eventType: 'QuestCompleted',
          payload: {'questType': 'daily'},
        ),
      );
      expect(d.result, EligibilityResult.eligible);
      expect(d.coinAmount, 50);
      expect(d.reason, 'quest_completed_daily');
    });

    test('weekly quest completion grants 200 coins', () {
      final d = RewardEligibilityDecision.evaluate(
        _makeEvent(
          eventType: 'QuestCompleted',
          payload: {'questType': 'weekly'},
        ),
      );
      expect(d.result, EligibilityResult.eligible);
      expect(d.coinAmount, 200);
    });

    test('milestone quest completion grants 500 coins', () {
      final d = RewardEligibilityDecision.evaluate(
        _makeEvent(
          eventType: 'QuestCompleted',
          payload: {'questType': 'milestone'},
        ),
      );
      expect(d.result, EligibilityResult.eligible);
      expect(d.coinAmount, 500);
    });

    test('unknown quest type grants no reward', () {
      final d = RewardEligibilityDecision.evaluate(
        _makeEvent(
          eventType: 'QuestCompleted',
          payload: {'questType': 'story'}, // not in policy v1
        ),
      );
      expect(d.result, EligibilityResult.notEligible);
      expect(d.coinAmount, 0);
    });

    test('unrecognised event type is not eligible', () {
      final d = RewardEligibilityDecision.evaluate(
        _makeEvent(eventType: 'SrsReviewCompleted'),
      );
      expect(d.result, EligibilityResult.notEligible);
      expect(d.reason, 'no_matching_rule');
    });

    test('all decisions carry policyVersion v1', () {
      for (final eventType in ['QuizCompleted', 'QuestCompleted', 'Other']) {
        final d = RewardEligibilityDecision.evaluate(
          _makeEvent(eventType: eventType),
        );
        expect(d.policyVersion, 'v1');
      }
    });

    test('toJson round-trips result and coinAmount', () {
      final d = RewardEligibilityDecision.evaluate(
        _makeEvent(
          eventType: 'QuizCompleted',
          payload: {'correct': true},
        ),
      );
      final j = d.toJson();
      expect(j['result'], 'eligible');
      expect(j['coinAmount'], 10);
      expect(j['policyVersion'], 'v1');
    });
  });
}
