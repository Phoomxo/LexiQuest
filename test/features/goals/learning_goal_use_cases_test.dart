import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/goals/application/learning_goal_use_cases.dart';
import 'package:vocab_learning_app/features/goals/data/drift_learning_goal_repository.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  late AppDatabase database;
  late DriftLearningGoalRepository repository;
  late LearningGoalUseCases useCases;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'goals-owner',
      nowUtc: () => DateTime.utc(2026, 8, 25),
    );
    await owners.getOrCreateActiveOwner();
    repository = DriftLearningGoalRepository(database, owners: owners);
    useCases = LearningGoalUseCases(
      activeOwnerId: () async =>
          (await database.select(database.localOwners).get())
              .singleWhere((owner) => owner.isActive)
              .id,
      repository: repository,
      nowUtc: () => DateTime.utc(2026, 8, 25, 12),
      generateId: () => 'goal:ielts',
    );
  });

  tearDown(() => database.close());

  test('prepared owner A command cannot retry into active owner B', () async {
    final command = await useCases.prepareCreate(
      kind: LearningGoalKind.personal,
      title: 'Synthetic owner A draft',
      deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
      timezone: const LearningGoalTimezoneContext(
        timezoneId: 'Asia/Bangkok',
        utcOffsetMinutes: 420,
      ),
    );
    await expectLater(
      useCases.executeCreate(command, mutationAllowed: () => false),
      throwsA(isA<LearningGoalMutationUnavailable>()),
    );
    await database.transaction(() async {
      await database.customUpdate('UPDATE local_owners SET is_active = 0');
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'synthetic-owner-b',
              createdAtUtcMs: DateTime.utc(2026, 8, 25).millisecondsSinceEpoch,
            ),
          );
    });
    Object? rejection;
    try {
      await useCases.executeCreate(command, mutationAllowed: () => true);
    } catch (error) {
      rejection = error;
    }
    expect(
      await database.select(database.learningGoals).get(),
      isEmpty,
      reason: 'An A draft must never become a new B goal on retry.',
    );
    expect(await database.select(database.outboxOperations).get(), isEmpty);
    expect(rejection, isNotNull);
    await expectLater(
      useCases.executeCreate(command),
      throwsA(isA<LearningGoalOwnerChanged>()),
    );
    final fresh = await useCases.prepareCreate(
      kind: LearningGoalKind.personal,
      title: 'Synthetic owner B draft',
      deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
      timezone: command.goal.timezone,
    );
    expect(fresh.expectedOwnerId, 'synthetic-owner-b');
    await useCases.executeCreate(fresh);
    expect(
      (await database.select(database.learningGoals).get()).single.ownerId,
      'synthetic-owner-b',
    );
    expect(
      await database.select(database.outboxOperations).get(),
      hasLength(1),
    );
  });

  test(
    'owner change after repository preflight is rejected inside transaction',
    () async {
      final command = await useCases.prepareCreate(
        kind: LearningGoalKind.personal,
        title: 'Synthetic transaction race',
        deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
        timezone: const LearningGoalTimezoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
      );
      final switchingOwners = _AfterEnsureOwners(
        DriftLocalOwnerRepository(
          database,
          generateId: () => 'unused-owner',
          nowUtc: () => DateTime.utc(2026, 8, 25),
        ),
        afterEnsure: () async {
          await database.transaction(() async {
            await database.customUpdate(
              'UPDATE local_owners SET is_active = 0',
            );
            await database
                .into(database.localOwners)
                .insert(
                  LocalOwnersCompanion.insert(
                    id: 'synthetic-race-owner-b',
                    createdAtUtcMs: DateTime.utc(
                      2026,
                      8,
                      25,
                    ).millisecondsSinceEpoch,
                  ),
                );
          });
        },
      );
      final raced = LearningGoalUseCases(
        repository: DriftLearningGoalRepository(
          database,
          owners: switchingOwners,
        ),
        activeOwnerId: useCases.activeOwnerId,
        nowUtc: useCases.nowUtc,
        generateId: () => 'unused-goal',
      );
      await expectLater(
        raced.executeCreate(command),
        throwsA(isA<LearningGoalOwnerChanged>()),
      );
      expect(await database.select(database.learningGoals).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test('future and past countdowns use the pinned timezone', () async {
    final future = await useCases.create(
      kind: LearningGoalKind.languageTest,
      title: 'IELTS practice target',
      deadlineAtUtc: DateTime.utc(2026, 8, 28, 16, 59),
      timezone: const LearningGoalTimezoneContext(
        timezoneId: 'Asia/Bangkok',
        utcOffsetMinutes: 420,
      ),
    );
    expect(useCases.countdown(future).state, LearningGoalDeadlineState.future);
    expect(useCases.countdown(future).days, 3);

    final past = LearningGoal(
      id: 'goal:past',
      kind: LearningGoalKind.course,
      title: 'Finish language course',
      deadlineAtUtc: DateTime.utc(2026, 8, 20),
      timezone: const LearningGoalTimezoneContext(
        timezoneId: 'Asia/Bangkok',
        utcOffsetMinutes: 420,
      ),
      status: LearningGoalStatus.active,
      createdAtUtc: DateTime.utc(2026, 8, 1),
      updatedAtUtc: DateTime.utc(2026, 8, 1),
    );
    expect(useCases.countdown(past).state, LearningGoalDeadlineState.past);
  });

  test('calendar countdown treats DST-adjacent local dates as one day', () {
    final location = timezone.getLocation('America/New_York');
    final cases = <(DateTime, DateTime)>[
      (
        timezone.TZDateTime(location, 2026, 3, 8),
        timezone.TZDateTime(location, 2026, 3, 9),
      ),
      (
        timezone.TZDateTime(location, 2026, 11, 1),
        timezone.TZDateTime(location, 2026, 11, 2),
      ),
    ];
    for (var index = 0; index < cases.length; index++) {
      final nowUtc = DateTime.utc(2026, 1, 1, 0, 0, index);
      final deadlineAtUtc = DateTime.utc(2026, 1, 2, 0, 0, index);
      final localDays = cases[index];
      final subject = LearningGoalUseCases(
        repository: repository,
        nowUtc: () => nowUtc,
        generateId: () => 'unused-dst-goal',
        activeOwnerId: () async => 'goals-owner',
        learningDay: (instant, timezoneId) {
          expect(timezoneId, 'America/New_York');
          return instant == nowUtc ? localDays.$1 : localDays.$2;
        },
      );
      final goal = LearningGoal(
        id: 'goal:dst-$index',
        kind: LearningGoalKind.personal,
        title: 'DST calendar target $index',
        deadlineAtUtc: deadlineAtUtc,
        timezone: LearningGoalUseCases.timezoneContext(
          'America/New_York',
          deadlineAtUtc,
        ),
        status: LearningGoalStatus.active,
        createdAtUtc: DateTime.utc(2026, 1, 1),
        updatedAtUtc: DateTime.utc(2026, 1, 1),
      );

      final countdown = subject.countdown(goal);

      expect(countdown.state, LearningGoalDeadlineState.future);
      expect(countdown.days, 1);
    }
  });

  test('calendar countdown preserves reverse date order across DST', () {
    final location = timezone.getLocation('America/New_York');
    final nowUtc = DateTime.utc(2026, 1, 2);
    final deadlineAtUtc = DateTime.utc(2026, 1, 1);
    final today = timezone.TZDateTime(location, 2026, 11, 2);
    final deadlineDay = timezone.TZDateTime(location, 2026, 11, 1);
    final subject = LearningGoalUseCases(
      repository: repository,
      nowUtc: () => nowUtc,
      generateId: () => 'unused-reverse-goal',
      activeOwnerId: () async => 'goals-owner',
      learningDay: (instant, _) => instant == nowUtc ? today : deadlineDay,
    );
    final goal = LearningGoal(
      id: 'goal:reverse-dst',
      kind: LearningGoalKind.personal,
      title: 'Reverse DST calendar target',
      deadlineAtUtc: deadlineAtUtc,
      timezone: LearningGoalUseCases.timezoneContext(
        'America/New_York',
        deadlineAtUtc,
      ),
      status: LearningGoalStatus.active,
      createdAtUtc: DateTime.utc(2026, 1, 1),
      updatedAtUtc: DateTime.utc(2026, 1, 1),
    );

    final countdown = subject.countdown(goal);

    expect(countdown.state, LearningGoalDeadlineState.past);
    expect(countdown.days, 1);
  });

  test('identical create and update replays persist exactly once', () async {
    final goal = LearningGoal(
      id: 'goal:ielts',
      kind: LearningGoalKind.languageTest,
      title: 'IELTS practice target',
      deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
      timezone: const LearningGoalTimezoneContext(
        timezoneId: 'Asia/Bangkok',
        utcOffsetMinutes: 420,
      ),
      status: LearningGoalStatus.active,
      createdAtUtc: DateTime.utc(2026, 8, 25),
      updatedAtUtc: DateTime.utc(2026, 8, 25),
    );
    await repository.save(goal);
    await repository.save(goal);

    expect(await database.select(database.learningGoals).get(), hasLength(1));
    expect(
      await database.select(database.outboxOperations).get(),
      hasLength(1),
    );

    final completed = goal.copyWith(
      status: LearningGoalStatus.completed,
      updatedAtUtc: DateTime.utc(2026, 8, 26),
    );
    await repository.save(completed);
    await repository.save(completed);
    final rows = await database.select(database.learningGoals).get();
    expect(rows.single.status, 'completed');
    expect(rows.single.localRevision, 2);
    expect(
      await database.select(database.outboxOperations).get(),
      hasLength(2),
    );
  });

  test('same-clock-tick status update advances the durable revision', () async {
    final goal = await useCases.create(
      kind: LearningGoalKind.course,
      title: 'Finish language course',
      deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
      timezone: const LearningGoalTimezoneContext(
        timezoneId: 'Asia/Bangkok',
        utcOffsetMinutes: 420,
      ),
    );

    final completed = await useCases.updateStatus(
      goal,
      LearningGoalStatus.completed,
    );

    expect(
      completed.updatedAtUtc,
      goal.updatedAtUtc.add(const Duration(milliseconds: 1)),
    );
    final row = await database.select(database.learningGoals).getSingle();
    expect(row.status, 'completed');
    expect(row.localRevision, 2);
  });

  test(
    'one prepared create survives concurrency and a lost acknowledgement',
    () async {
      var generatedIds = 0;
      var notifications = 0;
      final durableRepository = DriftLearningGoalRepository(
        database,
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'unused-owner',
          nowUtc: () => DateTime.utc(2026, 8, 25),
        ),
        onLocalMutation: () async {
          notifications += 1;
          if (notifications == 1) throw StateError('lost acknowledgement');
        },
      );
      final durableUseCases = LearningGoalUseCases(
        activeOwnerId: () async =>
            (await database.select(database.localOwners).get())
                .singleWhere((owner) => owner.isActive)
                .id,
        repository: durableRepository,
        nowUtc: () => DateTime.utc(2026, 8, 25, 12),
        generateId: () => 'goal:stable-${++generatedIds}',
      );
      final command = await durableUseCases.prepareCreate(
        kind: LearningGoalKind.languageTest,
        title: 'IELTS practice target',
        deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
        timezone: const LearningGoalTimezoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
      );

      await expectLater(
        durableUseCases.executeCreate(command),
        throwsStateError,
      );
      final retries = await Future.wait([
        durableUseCases.executeCreate(command),
        durableUseCases.executeCreate(command),
      ]);

      expect(generatedIds, 1);
      expect(retries.map((goal) => goal.id), everyElement('goal:stable-1'));
      expect(await database.select(database.learningGoals).get(), hasLength(1));
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(1),
      );
      expect(notifications, 1);
    },
  );

  test(
    'current status and lost-ack semantic retries do not add revisions',
    () async {
      var clock = DateTime.utc(2026, 8, 25, 12);
      var notifications = 0;
      final durableRepository = DriftLearningGoalRepository(
        database,
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'unused-owner',
          nowUtc: () => DateTime.utc(2026, 8, 25),
        ),
        onLocalMutation: () async {
          notifications += 1;
          if (notifications == 2) throw StateError('lost acknowledgement');
        },
      );
      final durableUseCases = LearningGoalUseCases(
        activeOwnerId: () async =>
            (await database.select(database.localOwners).get())
                .singleWhere((owner) => owner.isActive)
                .id,
        repository: durableRepository,
        nowUtc: () => clock,
        generateId: () => 'goal:status-replay',
      );
      final goal = await durableUseCases.create(
        kind: LearningGoalKind.course,
        title: 'Finish language course',
        deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
        timezone: const LearningGoalTimezoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
      );

      final unchanged = await durableUseCases.updateStatus(
        goal,
        LearningGoalStatus.active,
      );
      expect(identical(unchanged, goal), isTrue);

      clock = DateTime.utc(2026, 8, 26);
      await expectLater(
        durableUseCases.updateStatus(goal, LearningGoalStatus.completed),
        throwsStateError,
      );
      clock = DateTime.utc(2026, 8, 27);
      final replayed = await durableUseCases.updateStatus(
        goal,
        LearningGoalStatus.completed,
      );
      await durableUseCases.updateStatus(
        replayed,
        LearningGoalStatus.completed,
      );

      final row = await database.select(database.learningGoals).getSingle();
      expect(row.status, 'completed');
      expect(row.localRevision, 2);
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(2),
      );
      expect(notifications, 2);
    },
  );

  test('rechecks the live mutation guard after owner preflight', () async {
    var allowed = true;
    final guardedOwners = _AfterEnsureOwners(
      DriftLocalOwnerRepository(
        database,
        generateId: () => 'unused-owner',
        nowUtc: () => DateTime.utc(2026, 8, 25),
      ),
      afterEnsure: () => allowed = false,
    );
    final guardedUseCases = LearningGoalUseCases(
      activeOwnerId: () async =>
          (await database.select(database.localOwners).get())
              .singleWhere((owner) => owner.isActive)
              .id,
      repository: DriftLearningGoalRepository(database, owners: guardedOwners),
      nowUtc: () => DateTime.utc(2026, 8, 25, 12),
      generateId: () => 'goal:guarded',
    );
    final command = await guardedUseCases.prepareCreate(
      kind: LearningGoalKind.languageTest,
      title: 'IELTS practice target',
      deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
      timezone: const LearningGoalTimezoneContext(
        timezoneId: 'Asia/Bangkok',
        utcOffsetMinutes: 420,
      ),
    );

    await expectLater(
      guardedUseCases.executeCreate(command, mutationAllowed: () => allowed),
      throwsA(isA<LearningGoalMutationUnavailable>()),
    );

    expect(await database.select(database.learningGoals).get(), isEmpty);
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  });

  test('invalid timezone and admission-shaped values fail closed', () {
    expect(
      () => LearningGoal(
        id: 'goal:invalid',
        kind: LearningGoalKind.personal,
        title: 'Personal vocabulary target',
        deadlineAtUtc: DateTime.utc(2026, 9, 1),
        timezone: const LearningGoalTimezoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 0,
        ),
        status: LearningGoalStatus.active,
        createdAtUtc: DateTime.utc(2026, 8, 25),
        updatedAtUtc: DateTime.utc(2026, 8, 25),
      ),
      throwsArgumentError,
    );
    expect(
      () => LearningGoalKindCodec.parse('universityAdmissionScore'),
      throwsArgumentError,
    );
    expect(
      () => LearningGoal(
        id: 'goal:c1',
        kind: LearningGoalKind.personal,
        title: 'Vocabulary\u0085target',
        deadlineAtUtc: DateTime.utc(2026, 9, 1),
        timezone: const LearningGoalTimezoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
        status: LearningGoalStatus.active,
        createdAtUtc: DateTime.utc(2026, 8, 25),
        updatedAtUtc: DateTime.utc(2026, 8, 25),
      ),
      throwsArgumentError,
    );
  });
}

final class _AfterEnsureOwners implements LocalOwnerRepository {
  const _AfterEnsureOwners(this.delegate, {required this.afterEnsure});

  final LocalOwnerRepository delegate;
  final FutureOr<void> Function() afterEnsure;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    final owner = await delegate.getOrCreateActiveOwner();
    await afterEnsure();
    return owner;
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => delegate.bindFirebaseUid(ownerId, firebaseUid);
}
