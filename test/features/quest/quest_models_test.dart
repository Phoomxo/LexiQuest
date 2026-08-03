import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

// ── Helpers ──────────────────────────────────────────────────────────────────

EventEnvelopeV2 _makeEvent({
  required String eventId,
  required String eventType,
  Map<String, dynamic> payload = const {},
}) => EventEnvelopeV2(
  eventId: eventId,
  eventType: eventType,
  eventVersion: 1,
  occurredAtUtc: DateTime.utc(2026, 8, 4, 10, 0),
  recordedAtUtc: DateTime.utc(2026, 8, 4, 10, 0, 1),
  actorIdentity: 'owner-1',
  ownerIdentity: 'owner-1',
  aggregateType: 'LearningSession',
  aggregateId: 'sess-1',
  idempotencyKey: 'idem-$eventId',
  consentContext: const ConsentContext.none(),
  appVersion: '1.0',
  buildId: 'sha',
  privacyClassification: PrivacyClassification.ownerOnly,
  payload: payload,
);

QuestDefinition _makeQuestDef({int targetCount = 3}) => QuestDefinition(
  questId: 'quest-daily-quiz',
  catalogVersion: 1,
  title: 'Quiz 3 Times',
  description: 'Complete 3 correct quizzes today',
  type: QuestType.daily,
  objectives: [
    QuestObjective(
      objectiveId: 'obj-1',
      description: 'Complete correct quizzes',
      targetCount: targetCount,
      criteria: const ObjectiveCriteria(
        eventType: 'QuizCompleted',
        filters: {'correct': true},
      ),
    ),
  ],
  reward: const RewardSpec(xpAmount: 50),
);

QuestInstance _makeInstance(QuestDefinition def) => QuestInstance(
  instanceId: 'inst-001',
  questId: def.questId,
  ownerId: 'owner-1',
  catalogVersion: def.catalogVersion,
  assignedAtUtc: DateTime.utc(2026, 8, 4),
  state: QuestInstanceState.active,
  progress: def.objectives
      .map(
        (o) => ObjectiveProgress(
          objectiveId: o.objectiveId,
          currentCount: 0,
          targetCount: o.targetCount,
        ),
      )
      .toList(),
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ObjectiveCriteria — matching', () {
    const criteria = ObjectiveCriteria(
      eventType: 'QuizCompleted',
      filters: {'correct': true},
    );

    test('matches event with correct type and matching payload', () {
      final event = _makeEvent(
        eventId: 'e1',
        eventType: 'QuizCompleted',
        payload: {'correct': true, 'score': 100},
      );
      expect(criteria.matches(event), isTrue);
    });

    test('does not match event with wrong type', () {
      final event = _makeEvent(eventId: 'e2', eventType: 'SrsReviewCompleted');
      expect(criteria.matches(event), isFalse);
    });

    test('does not match event with filter mismatch', () {
      final event = _makeEvent(
        eventId: 'e3',
        eventType: 'QuizCompleted',
        payload: {'correct': false, 'score': 0},
      );
      expect(criteria.matches(event), isFalse);
    });

    test('criteria with no filters matches any event of the right type', () {
      const noFilter = ObjectiveCriteria(eventType: 'SrsReviewCompleted');
      final event = _makeEvent(
        eventId: 'e4',
        eventType: 'SrsReviewCompleted',
        payload: {'words': 5},
      );
      expect(noFilter.matches(event), isTrue);
    });
  });

  group('QuestInstance — progress tracking', () {
    test('advanceIfMatches increments progress on matching event', () {
      final def = _makeQuestDef();
      final instance = _makeInstance(def);

      final event = _makeEvent(
        eventId: 'ev-1',
        eventType: 'QuizCompleted',
        payload: {'correct': true},
      );
      final updated = instance.advanceIfMatches(event, def.objectives);

      expect(updated.progress.first.currentCount, 1);
      expect(updated.progress.first.sourceEventIds, ['ev-1']);
    });

    test('advanceIfMatches returns same instance when no event matches', () {
      final def = _makeQuestDef();
      final instance = _makeInstance(def);
      final event = _makeEvent(
        eventId: 'ev-x',
        eventType: 'SrsReviewCompleted',
      );
      final updated = instance.advanceIfMatches(event, def.objectives);
      expect(identical(updated, instance), isTrue);
    });

    test('quest tracks full evidence chain across multiple events', () {
      final def = _makeQuestDef(targetCount: 3);
      var inst = _makeInstance(def);

      for (var i = 1; i <= 3; i++) {
        inst = inst.advanceIfMatches(
          _makeEvent(
            eventId: 'ev-$i',
            eventType: 'QuizCompleted',
            payload: {'correct': true},
          ),
          def.objectives,
        );
      }
      expect(inst.isAllObjectivesComplete, isTrue);
      expect(inst.allSourceEventIds, ['ev-1', 'ev-2', 'ev-3']);
    });

    test('completed objective does not advance further', () {
      final def = _makeQuestDef(targetCount: 1);
      var inst = _makeInstance(def);
      inst = inst.advanceIfMatches(
        _makeEvent(
          eventId: 'ev-done',
          eventType: 'QuizCompleted',
          payload: {'correct': true},
        ),
        def.objectives,
      );
      expect(inst.progress.first.isComplete, isTrue);

      // Second matching event should NOT advance the already-completed objective.
      final before = inst.progress.first.currentCount;
      final afterInst = inst.advanceIfMatches(
        _makeEvent(
          eventId: 'ev-extra',
          eventType: 'QuizCompleted',
          payload: {'correct': true},
        ),
        def.objectives,
      );
      expect(afterInst.progress.first.currentCount, before);
    });
  });

  group('QuestInstance — completion', () {
    test('quest completion is idempotent — same key on two calls', () {
      final def = _makeQuestDef(targetCount: 1);
      var inst = _makeInstance(def);
      inst = inst.advanceIfMatches(
        _makeEvent(
          eventId: 'ev-fin',
          eventType: 'QuizCompleted',
          payload: {'correct': true},
        ),
        def.objectives,
      );
      final key1 = inst.complete().idempotencyKey;
      final key2 = inst.complete().idempotencyKey;
      expect(key1, key2);
    });

    test('QuestCompletedEvent contains full evidence chain', () {
      final def = _makeQuestDef(targetCount: 2);
      var inst = _makeInstance(def);
      for (final id in ['ev-a', 'ev-b']) {
        inst = inst.advanceIfMatches(
          _makeEvent(
            eventId: id,
            eventType: 'QuizCompleted',
            payload: {'correct': true},
          ),
          def.objectives,
        );
      }
      final completion = inst.complete();
      expect(completion.objectiveEventIds, containsAll(['ev-a', 'ev-b']));
      expect(completion.ownerId, 'owner-1');
    });
  });

  group('QuestDefinition constraints', () {
    test('definition requires at least one objective', () {
      expect(
        () => QuestDefinition(
          questId: 'q',
          catalogVersion: 1,
          title: 'T',
          description: 'D',
          type: QuestType.daily,
          objectives: const [], // ← empty
          reward: const RewardSpec(xpAmount: 10),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('all QuestType values are usable', () {
      for (final type in QuestType.values) {
        final def = QuestDefinition(
          questId: 'q-$type',
          catalogVersion: 1,
          title: type.name,
          description: '',
          type: type,
          objectives: const [
            QuestObjective(
              objectiveId: 'o1',
              description: 'd',
              targetCount: 1,
              criteria: ObjectiveCriteria(eventType: 'X'),
            ),
          ],
          reward: const RewardSpec(xpAmount: 0),
        );
        expect(def.type, type);
      }
    });
  });
}
