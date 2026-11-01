import 'dart:io';

import 'package:drift/drift.dart'
    show Value, Variable, QueryInterceptor, QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LearningProfile;
import 'package:vocab_learning_app/features/learning_profile/application/learning_profile_use_cases.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning_profile/data/drift_learning_profile_repository.dart';
import 'package:vocab_learning_app/features/learning_profile/domain/learning_profile.dart';

void main() {
  test(
    'timezone is owner-scoped durable preference with exact retry and explicit clearing',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final draft = LearningProfileDraft(
        onboardingState: LearningOnboardingState.completed,
        learningTimezoneId: 'America/New_York',
      );
      final change = h.change(draft: draft);
      await h.repository.save(change);
      final after = await _snapshot(h.database);
      final replay = await h.repository.save(change);
      expect(replay.draft.learningTimezoneId, 'America/New_York');
      expect(await _snapshot(h.database), after);
      final read = await h.repository.read(
        expectedOwnerId: 'a',
        stillCurrent: () => true,
      );
      expect(read.profile!.draft.learningTimezoneId, 'America/New_York');
      expect(after['learning_profiles']!.single['owner_id'], 'a');
      await h.repository.save(
        h.change(
          revision: 1,
          draft: LearningProfileDraft(
            onboardingState: LearningOnboardingState.completed,
          ),
        ),
      );
      expect(
        (await h.repository.read(
          expectedOwnerId: 'a',
          stillCurrent: () => true,
        )).profile!.draft.learningTimezoneId,
        isNull,
      );
    },
  );
  test('inactive owner cannot save a profile or mutate any table', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    for (final id in ['a', 'b']) {
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: id,
              createdAtUtcMs: 1,
              isActive: Value(id == 'a'),
            ),
          );
    }
    final repository = DriftLearningProfileRepository(
      database: database,
      ownerWrites: DriftOwnerWriteCoordinator(
        database,
        nowUtc: () => DateTime.utc(2026, 11, 1),
      ),
    );
    final before = await _snapshot(database);
    await expectLater(
      () => repository.save(
        LearningProfileChange(
          expectedOwnerId: 'b',
          expectedRevision: 0,
          draft: LearningProfileDraft(
            onboardingState: LearningOnboardingState.completed,
            goalText: 'Synthetic exam goal',
            dailyMinutes: 25,
          ),
          updatedAtUtc: DateTime.utc(2026, 11, 1),
          stillCurrent: () => true,
        ),
      ),
      throwsA(
        isA<LearningProfileException>().having(
          (error) => error.code,
          'code',
          LearningProfileFailureCode.ownerChanged,
        ),
      ),
    );
    expect(await _snapshot(database), before);
  });

  test(
    'absent profile reads do not create data and acknowledged writes replay exactly',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final before = await _snapshot(h.database);
      final absent = await h.repository.read(
        expectedOwnerId: 'a',
        stillCurrent: () => true,
      );
      expect(absent.revision, 0);
      expect(absent.profile, isNull);
      expect(await _snapshot(h.database), before);
      final change = h.change();
      final saved = await h.repository.save(change);
      final acknowledged = await _snapshot(h.database);
      final replay = await h.repository.save(change);
      expect(saved.revision, 1);
      expect(replay.revision, 1);
      expect(replay.draft.goalText, 'Synthetic goal');
      expect(replay.draft.targetDate, LearningCivilDate(2026, 12, 31));
      expect(replay.draft.interestCodes, ['exam', 'travel']);
      expect(await _snapshot(h.database), acknowledged);
      for (final table in before.keys.where(
        (name) => name != 'learning_profiles',
      )) {
        expect(
          acknowledged[table],
          before[table],
          reason: '$table must be unchanged',
        );
      }
    },
  );

  test(
    'a stale edit conflicts and clearing is an explicit acknowledged update',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await h.repository.save(h.change());
      final before = await _snapshot(h.database);
      await expectLater(
        () => h.repository.save(h.change(goal: 'Different goal')),
        throwsA(
          isA<LearningProfileException>().having(
            (error) => error.code,
            'code',
            LearningProfileFailureCode.conflict,
          ),
        ),
      );
      expect(await _snapshot(h.database), before);
      final cleared = await h.repository.save(
        h.change(
          revision: 1,
          draft: LearningProfileDraft(
            onboardingState: LearningOnboardingState.skipped,
          ),
        ),
      );
      expect(cleared.revision, 2);
      expect(cleared.draft.onboardingState, LearningOnboardingState.skipped);
      expect(cleared.draft.goalText, isNull);
      expect(cleared.draft.targetDate, isNull);
      expect(cleared.draft.dailyMinutes, isNull);
      expect(cleared.draft.interestCodes, isEmpty);
    },
  );

  test(
    'an expired command cannot read or save despite the same active owner',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final before = await _snapshot(h.database);
      await expectLater(
        () => h.repository.save(h.change(current: () => false)),
        throwsA(
          isA<LearningProfileException>().having(
            (error) => error.code,
            'code',
            LearningProfileFailureCode.ownerChanged,
          ),
        ),
      );
      await expectLater(
        () =>
            h.repository.read(expectedOwnerId: 'a', stillCurrent: () => false),
        throwsA(isA<LearningProfileException>()),
      );
      expect(await _snapshot(h.database), before);
    },
  );

  test(
    'deletion fence rejects reads and writes without changing rows',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      await (h.database.update(
        h.database.localOwners,
      )..where((owner) => owner.id.equals('a'))).write(
        const LocalOwnersCompanion(firebaseUid: Value('synthetic-uid-a')),
      );
      await h.ownerWrites.beginDeletion(
        ownerId: 'a',
        firebaseUid: 'synthetic-uid-a',
        idempotencyKey: 'synthetic-profile-delete',
      );
      final before = await _snapshot(h.database);
      await expectLater(
        () => h.repository.save(h.change()),
        throwsA(isA<LearningProfileException>()),
      );
      await expectLater(
        () => h.repository.read(expectedOwnerId: 'a', stillCurrent: () => true),
        throwsA(isA<LearningProfileException>()),
      );
      expect(await _snapshot(h.database), before);
    },
  );

  test('owner A-B-A retires a prepared use-case command', () async {
    final h = await _Harness.open();
    addTearDown(h.close);
    final useCases = LearningProfileUseCases(
      repository: h.repository,
      nowUtc: () => DateTime.utc(2026, 11, 1),
    );
    addTearDown(useCases.dispose);
    await useCases.watchActiveOwnerId().firstWhere((owner) => owner == 'a');
    final snapshot = await useCases.load(
      expectedOwnerId: 'a',
      stillCurrent: () => true,
    );
    final command = useCases.prepareChange(
      snapshot: snapshot,
      draft: LearningProfileDraft(
        onboardingState: LearningOnboardingState.completed,
      ),
      stillCurrent: () => true,
    );
    final seenB = useCases.watchActiveOwnerId().firstWhere(
      (owner) => owner == 'b',
    );
    await h.database.customUpdate(
      'UPDATE local_owners SET is_active = (id = ?)',
      variables: [Variable<String>('b')],
      updates: {h.database.localOwners},
    );
    await seenB;
    final seenA = useCases.watchActiveOwnerId().firstWhere(
      (owner) => owner == 'a',
    );
    await h.database.customUpdate(
      'UPDATE local_owners SET is_active = (id = ?)',
      variables: [Variable<String>('a')],
      updates: {h.database.localOwners},
    );
    await seenA;
    final before = await _snapshot(h.database);
    await expectLater(
      () => useCases.save(command),
      throwsA(
        isA<LearningProfileException>().having(
          (error) => error.code,
          'code',
          LearningProfileFailureCode.ownerChanged,
        ),
      ),
    );
    expect(await _snapshot(h.database), before);
  });

  test('profile survives a real database connection reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-profile-test-',
    );
    final file = File('${directory.path}/profile.sqlite');
    final first = AppDatabase(NativeDatabase(file));
    await first
        .into(first.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'a',
            createdAtUtcMs: 1,
            isActive: const Value(true),
          ),
        );
    final repository = DriftLearningProfileRepository(
      database: first,
      ownerWrites: DriftOwnerWriteCoordinator(
        first,
        nowUtc: () => DateTime.utc(2026, 11, 1),
      ),
    );
    await repository.save(
      LearningProfileChange(
        expectedOwnerId: 'a',
        expectedRevision: 0,
        draft: LearningProfileDraft(
          onboardingState: LearningOnboardingState.completed,
          goalText: 'Retained',
          learningTimezoneId: 'Asia/Bangkok',
        ),
        updatedAtUtc: DateTime.utc(2026, 11, 1),
        stillCurrent: () => true,
      ),
    );
    await first.close();
    final reopened = AppDatabase(NativeDatabase(file));
    try {
      final reader = DriftLearningProfileRepository(
        database: reopened,
        ownerWrites: DriftOwnerWriteCoordinator(
          reopened,
          nowUtc: () => DateTime.utc(2026, 11, 1),
        ),
      );
      final loaded = await reader.read(
        expectedOwnerId: 'a',
        stillCurrent: () => true,
      );
      expect(loaded.profile!.draft.goalText, 'Retained');
      expect(loaded.profile!.draft.learningTimezoneId, 'Asia/Bangkok');
      expect(loaded.revision, 1);
    } finally {
      await reopened.close();
      await file.delete();
      await directory.delete();
    }
  });

  test(
    'owner interference after profile insertion rolls back the entire transaction',
    () async {
      final h = await _Harness.open();
      addTearDown(h.close);
      final before = await _snapshot(h.database);
      final interference = _AfterProfileInsert();
      await expectLater(
        () => h.database.runWithInterceptor(
          () => h.repository.save(h.change()),
          interceptor: interference,
        ),
        throwsA(isA<LearningProfileException>()),
      );
      expect(interference.fired, isTrue);
      expect(await _snapshot(h.database), before);
    },
  );
}

Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  AppDatabase database,
) async {
  final result = <String, List<Map<String, Object?>>>{};
  for (final table in database.allTables) {
    final rows = await database
        .customSelect('SELECT * FROM "${table.actualTableName}" ORDER BY rowid')
        .get();
    result[table.actualTableName] = rows.map((row) => row.data).toList();
  }
  return result;
}

final class _Harness {
  _Harness(this.database, this.ownerWrites, this.repository);
  final AppDatabase database;
  final DriftOwnerWriteCoordinator ownerWrites;
  final DriftLearningProfileRepository repository;
  static Future<_Harness> open() async {
    final database = AppDatabase(NativeDatabase.memory());
    for (final owner in ['a', 'b']) {
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: owner,
              createdAtUtcMs: 1,
              isActive: Value(owner == 'a'),
            ),
          );
    }
    final writes = DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => DateTime.utc(2026, 11, 1),
    );
    return _Harness(
      database,
      writes,
      DriftLearningProfileRepository(database: database, ownerWrites: writes),
    );
  }

  LearningProfileChange change({
    int revision = 0,
    String goal = 'Synthetic goal',
    LearningProfileDraft? draft,
    bool Function()? current,
  }) => LearningProfileChange(
    expectedOwnerId: 'a',
    expectedRevision: revision,
    draft:
        draft ??
        LearningProfileDraft(
          onboardingState: LearningOnboardingState.completed,
          goalText: goal,
          targetDate: LearningCivilDate(2026, 12, 31),
          dailyMinutes: 25,
          interestCodes: ['travel', 'exam'],
        ),
    updatedAtUtc: DateTime.utc(2026, 11, 1),
    stillCurrent: current ?? () => true,
  );
  Future<void> close() => database.close();
}

final class _AfterProfileInsert extends QueryInterceptor {
  bool fired = false;
  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    if (!fired &&
        statement.toLowerCase().startsWith('insert into learning_profiles')) {
      fired = true;
      await executor.runUpdate('UPDATE local_owners SET is_active = (id = ?)', [
        'b',
      ]);
    }
    return result;
  }
}
