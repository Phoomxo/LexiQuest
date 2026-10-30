import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

final _assigned = DateTime.utc(2026, 10, 30, 9);
final _answered = DateTime.utc(2026, 10, 30, 10);

EventEnvelopeV2 _event({
  String id = 'attempt-a',
  String owner = 'owner-a',
  String? actor,
  DateTime? at,
}) => EventEnvelopeV2(
  eventId: id,
  eventType: 'QuizCompleted',
  eventVersion: 1,
  occurredAtUtc: at ?? _answered,
  recordedAtUtc: at ?? _answered,
  actorIdentity: actor ?? owner,
  ownerIdentity: owner,
  aggregateType: 'LearningSession',
  aggregateId: 'session-a',
  idempotencyKey: 'answer-attempt:$id',
  consentContext: const ConsentContext.none(),
  appVersion: 'synthetic',
  buildId: 'quest-domain',
  privacyClassification: PrivacyClassification.ownerOnly,
  payload: const {'correct': true},
);

QuestObjective _objective(String id, {int target = 3}) => QuestObjective(
  objectiveId: id,
  description: 'Synthetic correct answer objective',
  targetCount: target,
  criteria: ObjectiveCriteria(
    eventType: 'QuizCompleted',
    filters: {'correct': true},
  ),
);

ObjectiveProgress _progress(
  String id, {
  int count = 0,
  int target = 3,
  List<String> sources = const [],
}) => ObjectiveProgress(
  objectiveId: id,
  currentCount: count,
  targetCount: target,
  sourceEventIds: sources,
);

QuestInstance _instance({
  QuestInstanceState state = QuestInstanceState.active,
  List<ObjectiveProgress>? progress,
  DateTime? completedAt,
}) => QuestInstance(
  instanceId: 'quest-instance-a',
  questId: 'quest-definition-a',
  ownerId: 'owner-a',
  catalogVersion: 1,
  assignedAtUtc: _assigned,
  state: state,
  progress: progress ?? [_progress('objective-a')],
  completedAtUtc: completedAt,
);

QuestDefinition _definition({
  List<QuestObjective>? objectives,
  List<String> tags = const [],
}) => QuestDefinition(
  questId: 'quest-definition-a',
  catalogVersion: 1,
  title: 'Synthetic immutable definition',
  description: 'Synthetic',
  type: QuestType.daily,
  objectives: objectives ?? [_objective('objective-a')],
  reward: const RewardSpec(xpAmount: 0),
  tags: tags,
);

void main() {
  test(
    'criteria copies caller filters before an owner await can mutate them',
    () {
      final filters = <String, dynamic>{'correct': true};
      final criteria = ObjectiveCriteria(
        eventType: 'QuizCompleted',
        filters: filters,
      );
      filters['correct'] = false;
      expect(criteria.filters, {'correct': true});
      expect(criteria.matches(_event()), isTrue);
    },
  );

  test(
    'definition copies caller objectives before an owner await can remove them',
    () {
      final objective = _objective('objective-a');
      final objectives = [objective];
      final definition = _definition(objectives: objectives);
      objectives.clear();
      expect(definition.objectives, [objective]);
    },
  );

  test(
    'definition copies caller tags before an owner await can rewrite them',
    () {
      final tags = ['synthetic-original'];
      final definition = _definition(tags: tags);
      tags[0] = 'synthetic-rewritten';
      expect(definition.tags, ['synthetic-original']);
    },
  );

  test('criteria filters and definition objectives and tags are read-only', () {
    final criteria = ObjectiveCriteria(
      eventType: 'QuizCompleted',
      filters: {'correct': true},
    );
    final definition = _definition(tags: ['synthetic-original']);
    expect(() => criteria.filters!['correct'] = false, throwsUnsupportedError);
    expect(() => definition.objectives.clear(), throwsUnsupportedError);
    expect(() => definition.tags.clear(), throwsUnsupportedError);
    expect(ObjectiveCriteria(eventType: 'QuizCompleted').filters, isNull);
  });

  test(
    'objective replay returns the same progress without adding evidence',
    () {
      final progress = _progress(
        'objective-a',
        count: 1,
        sources: ['attempt-a'],
      );
      final replayed = progress.advance('attempt-a');
      expect(identical(replayed, progress), isTrue);
      expect(replayed.currentCount, 1);
      expect(replayed.sourceEventIds, ['attempt-a']);
    },
  );

  test('direct objective advancement cannot overshoot a completed target', () {
    final progress = _progress(
      'objective-a',
      count: 1,
      target: 1,
      sources: ['attempt-a'],
    );
    expect(identical(progress.advance('attempt-b'), progress), isTrue);
    expect(progress.sourceEventIds, ['attempt-a']);
  });

  test(
    'one source counts once per matching objective rather than once per callback',
    () {
      final instance = _instance(
        progress: [
          _progress('objective-a', count: 1, sources: ['attempt-a']),
          _progress('objective-b'),
        ],
      );
      final objectives = [_objective('objective-a'), _objective('objective-b')];
      final updated = instance.advanceIfMatches(_event(), objectives);
      expect(updated.progress.map((progress) => progress.currentCount), [1, 1]);
      expect(
        updated.progress.every(
          (progress) => progress.sourceEventIds.single == 'attempt-a',
        ),
        isTrue,
      );
      expect(
        identical(updated.advanceIfMatches(_event(), objectives), updated),
        isTrue,
      );
    },
  );

  test(
    'distinct canonical IDs at the same timestamp remain distinct evidence',
    () {
      final objectives = [_objective('objective-a')];
      final first = _instance().advanceIfMatches(_event(), objectives);
      final second = first.advanceIfMatches(
        _event(id: 'attempt-b'),
        objectives,
      );
      expect(second.progress.single.currentCount, 2);
      expect(second.progress.single.sourceEventIds, ['attempt-a', 'attempt-b']);
    },
  );

  for (final foreignActor in [false, true]) {
    test(
      'foreign ${foreignActor ? 'actor' : 'owner'} does not advance the instance',
      () {
        final instance = _instance();
        final event = foreignActor
            ? _event(actor: 'owner-b')
            : _event(owner: 'owner-b');
        expect(
          identical(
            instance.advanceIfMatches(event, [_objective('objective-a')]),
            instance,
          ),
          isTrue,
        );
        expect(instance.progress.single.currentCount, 0);
      },
    );
  }

  for (final state in [
    QuestInstanceState.completed,
    QuestInstanceState.expired,
    QuestInstanceState.abandoned,
  ]) {
    test('$state instance cannot receive another source', () {
      final instance = _instance(state: state);
      expect(
        identical(
          instance.advanceIfMatches(_event(), [_objective('objective-a')]),
          instance,
        ),
        isTrue,
      );
      expect(instance.progress.single.sourceEventIds, isEmpty);
    });
  }

  test('answer before assignment does not become objective evidence', () {
    final instance = _instance();
    final event = _event(
      at: _assigned.subtract(const Duration(milliseconds: 1)),
    );
    expect(
      identical(
        instance.advanceIfMatches(event, [_objective('objective-a')]),
        instance,
      ),
      isTrue,
    );
  });

  test(
    'answer exactly at assignment remains eligible for objective matching',
    () {
      final updated = _instance().advanceIfMatches(_event(at: _assigned), [
        _objective('objective-a'),
      ]);
      expect(updated.progress.single.currentCount, 1);
    },
  );

  test('source IDs are copied and exposed as immutable values', () {
    final source = ['attempt-a'];
    final progress = _progress('objective-a', count: 1, sources: source);
    source[0] = 'rewritten-external-source';
    expect(progress.sourceEventIds, ['attempt-a']);
    expect(
      () => progress.sourceEventIds.add('attempt-b'),
      throwsUnsupportedError,
    );
  });

  test(
    'instance progress is copied and cannot be rewritten through a caller list',
    () {
      final source = [_progress('objective-a')];
      final instance = _instance(progress: source);
      source.clear();
      expect(instance.progress, hasLength(1));
      expect(() => instance.progress.clear(), throwsUnsupportedError);
    },
  );

  test('advanced progress and derived source views are immutable', () {
    final updated = _instance().advanceIfMatches(_event(), [
      _objective('objective-a'),
    ]);
    expect(() => updated.progress.clear(), throwsUnsupportedError);
    expect(
      () => updated.progress.single.sourceEventIds[0] = 'rewritten',
      throwsUnsupportedError,
    );
    expect(
      () => updated.allSourceEventIds[0] = 'rewritten',
      throwsUnsupportedError,
    );
    expect(updated.progress.single.sourceEventIds, ['attempt-a']);
  });

  test('an empty objective list is not a completed quest', () {
    final empty = _instance(progress: []);
    expect(empty.isAllObjectivesComplete, isFalse);
    expect(() => empty.complete(now: _answered), throwsStateError);
  });

  test('incomplete objective cannot produce a completion proof', () {
    expect(() => _instance().complete(now: _answered), throwsStateError);
  });

  for (final state in [
    QuestInstanceState.expired,
    QuestInstanceState.abandoned,
  ]) {
    test('$state cannot produce a completion even when counters are full', () {
      final instance = _instance(
        state: state,
        progress: [
          _progress('objective-a', count: 1, target: 1, sources: ['attempt-a']),
        ],
      );
      expect(() => instance.complete(now: _answered), throwsStateError);
    });
  }

  test('completed replay preserves the stored original completion time', () {
    final instance = _instance(
      state: QuestInstanceState.completed,
      progress: [
        _progress('objective-a', count: 1, target: 1, sources: ['attempt-a']),
      ],
      completedAt: _answered,
    );
    final replayed = instance.complete(
      now: _answered.add(const Duration(days: 1)),
    );
    expect(replayed.completedAtUtc, _answered);
    expect(
      replayed.idempotencyKey,
      'quest_complete_quest-instance-a_quest-definition-a',
    );
    expect(replayed.objectiveEventIds, ['attempt-a']);
  });

  test('completed state without its original completion time fails closed', () {
    final instance = _instance(
      state: QuestInstanceState.completed,
      progress: [
        _progress('objective-a', count: 1, target: 1, sources: ['attempt-a']),
      ],
    );
    expect(() => instance.complete(now: _answered), throwsStateError);
  });

  test('completion source IDs are copied and immutable', () {
    final sources = ['attempt-a'];
    final completion = QuestCompletedEvent(
      eventId: 'qcomplete-quest-instance-a',
      questInstanceId: 'quest-instance-a',
      ownerId: 'owner-a',
      completedAtUtc: _answered,
      objectiveEventIds: sources,
      idempotencyKey: 'quest_complete_quest-instance-a_quest-definition-a',
    );
    sources.clear();
    expect(completion.objectiveEventIds, ['attempt-a']);
    expect(() => completion.objectiveEventIds.clear(), throwsUnsupportedError);
  });
}
