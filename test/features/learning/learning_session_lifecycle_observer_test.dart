import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/learning_session_lifecycle_observer.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

const _owner = 'synthetic-lifecycle-owner';
const _otherOwner = 'synthetic-lifecycle-other';
const _sessionId = 'synthetic-lifecycle-session';
final _start = DateTime.utc(2026, 10, 29, 12, 0, 0, 123);
final _end = _start.add(const Duration(minutes: 5));

void main() {
  late db.AppDatabase database;
  late _Observer observer;
  late DriftLearningRepository repository;

  setUp(() async {
    database = await _openDatabase();
    observer = _Observer(database);
    repository = DriftLearningRepository(database, lifecycleObserver: observer);
  });
  tearDown(() => database.close());

  test('constructor rejects an observer using another database', () async {
    final other = await _openDatabase();
    addTearDown(other.close);

    expect(
      () => DriftLearningRepository(
        database,
        lifecycleObserver: _Observer(other),
      ),
      throwsArgumentError,
    );
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  test('accepted observes the exact newly persisted canonical tuple', () async {
    await repository.startSession(_draft());

    final fact = observer.acceptedFacts.single;
    final row = await _session(database);
    expect(_factMap(fact), {
      'id': row.id,
      'ownerId': row.ownerId,
      'activityType': row.activityType,
      'startedAtUtcMs': row.startedAtUtcMs,
      'appVersion': row.appVersion,
      'buildId': row.buildId,
      'state': row.state,
      'endedAtUtcMs': row.endedAtUtcMs,
    });
    expect(fact.state, 'active');
    expect(fact.endedAtUtcMs, isNull);
    expect(fact.startedAtUtcMs, _start.millisecondsSinceEpoch);
    expect(_factMap(observer.persistedFacts.single), _factMap(fact));
    expect(await _markerCount(database, 'accepted'), 1);
    await _expectResearchEmpty(database);
  });

  test(
    'matching start replay preserves the row without repeating acceptance',
    () async {
      await repository.startSession(_draft());
      final before = (await _session(database)).toJson();

      await repository.startSession(_draft());

      expect((await _session(database)).toJson(), before);
      expect(observer.acceptedFacts, hasLength(1));
      expect(observer.authorityCalls, 1);
      expect(await _markerCount(database, 'accepted'), 1);
    },
  );

  test(
    'start replay cannot reopen a completed session or refresh its end',
    () async {
      await repository.startSession(_draft());
      await _finish(repository, _end);
      final before = await _canonicalSnapshot(database);

      await repository.startSession(_draft());

      expect(await _canonicalSnapshot(database), before);
      expect(observer.acceptedFacts, hasLength(1));
      expect(observer.completedFacts.single.state, 'completed');
      expect(
        observer.completedFacts.single.endedAtUtcMs,
        _end.millisecondsSinceEpoch,
      );
    },
  );

  for (final change in ['owner', 'activity', 'start', 'app', 'build']) {
    test(
      'a conflicting $change start cannot overwrite the global session ID',
      () async {
        await repository.startSession(_draft());
        final before = await _canonicalSnapshot(database);
        final conflicting = LearningSessionDraft(
          id: _sessionId,
          ownerId: change == 'owner' ? _otherOwner : _owner,
          activityType: change == 'activity' ? 'srsReview' : 'quiz',
          startedAtUtc: change == 'start'
              ? _start.add(const Duration(milliseconds: 1))
              : _start,
          appVersion: change == 'app' ? 'synthetic-v2' : 'synthetic-v1',
          buildId: change == 'build'
              ? 'synthetic-build-2'
              : 'synthetic-build-1',
        );

        await expectLater(
          repository.startSession(conflicting),
          throwsStateError,
        );

        expect(await _canonicalSnapshot(database), before);
        expect(observer.acceptedFacts, hasLength(1));
        expect(await _markerCount(database, 'accepted'), 1);
      },
    );
  }

  test(
    'denied acceptance rolls back its sidecar while the session commits',
    () async {
      observer.failAccepted = true;

      await repository.startSession(_draft());

      expect((await _session(database)).state, 'active');
      expect(await _markerCount(database, 'accepted'), 0);
      observer.failAccepted = false;
      await repository.startSession(_draft());
      expect(observer.acceptedFacts, hasLength(1));
      expect(await _markerCount(database, 'accepted'), 0);
      await _expectResearchEmpty(database);
    },
  );

  test(
    'completion retry repairs a sidecar with the original end and rewards',
    () async {
      await repository.startSession(_draft());
      observer.failCompleted = true;

      final completed = await _finish(repository, _end);

      expect(completed.state, 'completed');
      expect(
        (await _session(database)).endedAtUtcMs,
        _end.millisecondsSinceEpoch,
      );
      expect(await _markerCount(database, 'completed'), 0);
      final before = await _canonicalSnapshot(database);
      observer.failCompleted = false;
      await _finish(repository, _end.add(const Duration(hours: 1)));

      expect(await _canonicalSnapshot(database), before);
      expect(observer.completedFacts, hasLength(2));
      expect(observer.completedFacts.map((fact) => fact.endedAtUtcMs).toSet(), {
        _end.millisecondsSinceEpoch,
      });
      expect(await _markerCount(database, 'completed'), 1);
      expect(
        await database.select(database.achievementUnlocks).get(),
        hasLength(1),
      );
    },
  );

  test(
    'an observer SQL failure rolls back all of its partial writes',
    () async {
      observer.constraintFailure = true;

      await repository.startSession(_draft());

      expect((await _session(database)).state, 'active');
      expect(await _markerCount(database, 'accepted'), 0);
      expect(
        await database.select(database.vocabularyCategories).get(),
        hasLength(1),
      );
      await _expectResearchEmpty(database);
    },
  );

  test(
    'the default ordinary path has no research observer or research facts',
    () async {
      final ordinary = DriftLearningRepository(database);

      await ordinary.startSession(_draft());
      await _finish(ordinary, _end);

      expect((await _session(database)).state, 'completed');
      expect(observer.authorityCalls, 0);
      expect(await database.select(database.runtimeFlags).get(), isEmpty);
      final queue = await database.select(database.outboxOperations).get();
      expect(queue.single.entityType, 'achievementUnlock');
      await _expectResearchEmpty(database, includesLearningOutbox: true);
    },
  );

  test(
    'an uninterested observer performs no authority call for ordinary learning',
    () async {
      observer.hasOpportunity = false;

      await repository.startSession(_draft());
      await _finish(repository, _end);

      expect(observer.acceptedFacts, hasLength(1));
      expect(observer.completedFacts, hasLength(1));
      expect(observer.authorityCalls, 0);
      expect(await database.select(database.runtimeFlags).get(), isEmpty);
      final queue = await database.select(database.outboxOperations).get();
      expect(queue.single.entityType, 'achievementUnlock');
      await _expectResearchEmpty(database, includesLearningOutbox: true);
    },
  );

  test('a canonical start FK failure cannot invoke the observer', () async {
    await expectLater(
      repository.startSession(_draft(owner: 'synthetic-missing-owner')),
      throwsException,
    );

    expect(await database.select(database.learningSessions).get(), isEmpty);
    expect(observer.acceptedFacts, isEmpty);
    expect(await database.select(database.runtimeFlags).get(), isEmpty);
  });

  test(
    'a later canonical transaction failure rolls back start and sidecar',
    () async {
      final failure = StateError(
        'synthetic canonical failure after acceptance',
      );

      await expectLater(
        database.transaction(() async {
          await repository.startSession(_draft());
          expect(await _markerCount(database, 'accepted'), 1);
          throw failure;
        }),
        throwsA(same(failure)),
      );

      expect(observer.acceptedFacts, hasLength(1));
      expect(await database.select(database.learningSessions).get(), isEmpty);
      expect(await database.select(database.runtimeFlags).get(), isEmpty);
    },
  );

  test(
    'canonical achievement failure rolls back completion before observation',
    () async {
      await repository.startSession(_draft());
      final before = await _canonicalSnapshot(database);
      await database.customStatement('''
      CREATE TRIGGER synthetic_lifecycle_achievement_failure
      BEFORE INSERT ON achievement_unlocks
      BEGIN
        SELECT RAISE(ABORT, 'synthetic canonical achievement failure');
      END
    ''');

      await expectLater(_finish(repository, _end), throwsException);

      expect(await _canonicalSnapshot(database), before);
      expect(observer.completedFacts, isEmpty);
      expect(await _markerCount(database, 'completed'), 0);
      expect(await _markerCount(database, 'accepted'), 1);
    },
  );

  test(
    'a later canonical failure rolls back completion and its sidecar',
    () async {
      await repository.startSession(_draft());
      final before = await _canonicalSnapshot(database);
      final failure = StateError(
        'synthetic canonical failure after completion',
      );

      await expectLater(
        database.transaction(() async {
          await _finish(repository, _end);
          expect(await _markerCount(database, 'completed'), 1);
          throw failure;
        }),
        throwsA(same(failure)),
      );

      expect(await _canonicalSnapshot(database), before);
      expect(observer.completedFacts, hasLength(1));
      expect(await _markerCount(database, 'completed'), 0);
      expect(await _markerCount(database, 'accepted'), 1);
    },
  );

  test(
    'failing research leaves answer, SRS, reward and outbox results unchanged',
    () async {
      final ordinaryDatabase = await _openDatabase();
      addTearDown(ordinaryDatabase.close);
      observer.failAccepted = true;
      observer.failCompleted = true;

      await _exercise(repository);
      await _exercise(DriftLearningRepository(ordinaryDatabase));

      expect(
        await _canonicalSnapshot(database),
        await _canonicalSnapshot(ordinaryDatabase),
      );
      expect(await database.select(database.runtimeFlags).get(), isEmpty);
      await _expectResearchEmpty(database, includesLearningOutbox: true);
    },
  );

  for (final wrongTarget in ['wrong-owner', 'missing-session']) {
    test('$wrongTarget completion cannot invoke the observer', () async {
      await repository.startSession(_draft());
      final before = await _canonicalSnapshot(database);

      await expectLater(
        repository.finishSession(
          ownerId: wrongTarget == 'wrong-owner' ? _otherOwner : _owner,
          sessionId: wrongTarget == 'missing-session' ? 'missing' : _sessionId,
          endedAtUtc: _end,
        ),
        throwsStateError,
      );

      expect(await _canonicalSnapshot(database), before);
      expect(observer.completedFacts, isEmpty);
    });
  }
}

LearningSessionDraft _draft({String owner = _owner}) => LearningSessionDraft(
  id: _sessionId,
  ownerId: owner,
  activityType: 'quiz',
  startedAtUtc: _start,
  appVersion: 'synthetic-v1',
  buildId: 'synthetic-build-1',
);

Future<LearningSessionSummary> _finish(
  DriftLearningRepository repository,
  DateTime end,
) => repository.finishSession(
  ownerId: _owner,
  sessionId: _sessionId,
  endedAtUtc: end,
);

Future<db.LearningSession> _session(db.AppDatabase database) =>
    (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals(_sessionId))).getSingle();

Future<db.AppDatabase> _openDatabase() async {
  final database = db.AppDatabase(NativeDatabase.memory());
  await database.customStatement('PRAGMA foreign_keys = ON');
  await database.customStatement(
    'INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES (?, 1, 1), (?, 1, 0)',
    [_owner, _otherOwner],
  );
  await database.customStatement(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
    "VALUES ('synthetic-category', ?, 'Synthetic', 'synthetic', 1, 1)",
    [_owner],
  );
  await database.customStatement(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, '
    'part_of_speech, created_at_utc_ms, updated_at_utc_ms) '
    "VALUES ('synthetic-word', ?, 'synthetic-category', 'station', 'station', 'synthetic meaning', 'synthetic meaning', 'noun', 1, 1)",
    [_owner],
  );
  return database;
}

Future<void> _exercise(DriftLearningRepository repository) async {
  await repository.startSession(_draft());
  await repository.recordAnswer(
    RecordAnswerCommand(
      id: 'synthetic-lifecycle-answer',
      ownerId: _owner,
      sessionId: _sessionId,
      wordId: 'synthetic-word',
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 250,
      attemptNumber: 1,
      occurredAtUtc: _start.add(const Duration(minutes: 1)),
    ),
  );
  await _finish(repository, _end);
}

Future<int> _markerCount(db.AppDatabase database, String stage) async =>
    (await database
            .customSelect(
              "SELECT COUNT(*) AS count FROM runtime_flags WHERE key = 'synthetic-research:$stage:$_sessionId'",
            )
            .getSingle())
        .read<int>('count');

Future<void> _expectResearchEmpty(
  db.AppDatabase database, {
  bool includesLearningOutbox = false,
}) async {
  for (final table in [
    'experiment_assignments',
    'research_participation_permits',
    'motivation_measurement_runs',
    'motivation_responses',
    'events_v2',
    if (!includesLearningOutbox) 'outbox_operations',
  ]) {
    expect(
      (await database
              .customSelect('SELECT COUNT(*) AS count FROM $table')
              .getSingle())
          .read<int>('count'),
      0,
      reason: table,
    );
  }
}

Future<Map<String, List<String>>> _canonicalSnapshot(
  db.AppDatabase database,
) async {
  final result = <String, List<String>>{};
  for (final table in [
    'local_owners',
    'vocabulary_categories',
    'vocabulary_words',
    'learning_sessions',
    'answer_attempts',
    'srs_states',
    'points_ledger_entries',
    'achievement_unlocks',
    'reward_transactions',
    'owned_reward_items',
    'equipped_reward_items',
    'outbox_operations',
    'events_v2',
  ]) {
    final rows = await database.customSelect('SELECT * FROM $table').get();
    result[table] = rows.map((row) => jsonEncode(row.data)).toList()..sort();
  }
  return result;
}

Map<String, Object?> _factMap(LearningSessionLifecycleFact fact) => {
  'id': fact.id,
  'ownerId': fact.ownerId,
  'activityType': fact.activityType,
  'startedAtUtcMs': fact.startedAtUtcMs,
  'appVersion': fact.appVersion,
  'buildId': fact.buildId,
  'state': fact.state,
  'endedAtUtcMs': fact.endedAtUtcMs,
};

final class _Observer implements LearningSessionLifecycleObserver {
  _Observer(this.database);

  @override
  final db.AppDatabase database;
  final acceptedFacts = <LearningSessionLifecycleFact>[];
  final completedFacts = <LearningSessionLifecycleFact>[];
  final persistedFacts = <LearningSessionLifecycleFact>[];
  bool hasOpportunity = true;
  bool failAccepted = false;
  bool failCompleted = false;
  bool constraintFailure = false;
  int authorityCalls = 0;

  @override
  Future<void> accepted(LearningSessionLifecycleFact fact) async {
    acceptedFacts.add(fact);
    await _write('accepted', fact, failAccepted);
  }

  @override
  Future<void> completed(LearningSessionLifecycleFact fact) async {
    completedFacts.add(fact);
    await _write('completed', fact, failCompleted);
  }

  Future<void> _write(
    String stage,
    LearningSessionLifecycleFact fact,
    bool fail,
  ) async {
    if (!hasOpportunity) return;
    authorityCalls++;
    final row = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals(fact.id))).getSingle();
    persistedFacts.add(LearningSessionLifecycleFact.fromRow(row));
    await database.customStatement(
      'INSERT INTO runtime_flags (key, bool_value, source, updated_at_utc_ms) VALUES (?, 1, ?, 1) '
      'ON CONFLICT(key) DO UPDATE SET source = excluded.source',
      ['synthetic-research:$stage:${fact.id}', jsonEncode(_factMap(fact))],
    );
    if (constraintFailure) {
      await database.customStatement(
        'INSERT INTO vocabulary_categories '
        '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
        "VALUES ('synthetic-invalid-sidecar', 'synthetic-missing-owner', 'Invalid', 'invalid', 1, 1)",
      );
    }
    if (fail) throw StateError('synthetic research unavailable');
  }
}
