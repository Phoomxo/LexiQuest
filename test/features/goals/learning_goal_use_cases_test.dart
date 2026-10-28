import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
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
      repository: repository,
      nowUtc: () => DateTime.utc(2026, 8, 25, 12),
      generateId: () => 'goal:ielts',
    );
  });

  tearDown(() => database.close());

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
        repository: durableRepository,
        nowUtc: () => DateTime.utc(2026, 8, 25, 12),
        generateId: () => 'goal:stable-${++generatedIds}',
      );
      final command = durableUseCases.prepareCreate(
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
      repository: DriftLearningGoalRepository(database, owners: guardedOwners),
      nowUtc: () => DateTime.utc(2026, 8, 25, 12),
      generateId: () => 'goal:guarded',
    );
    final command = guardedUseCases.prepareCreate(
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
  final void Function() afterEnsure;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    final owner = await delegate.getOrCreateActiveOwner();
    afterEnsure();
    return owner;
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => delegate.bindFirebaseUid(ownerId, firebaseUid);
}
