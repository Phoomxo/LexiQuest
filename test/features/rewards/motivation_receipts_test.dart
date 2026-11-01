import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide QuestDefinition;
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_profile/data/drift_learning_profile_repository.dart';
import 'package:vocab_learning_app/features/learning_profile/domain/learning_profile.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/motivation_snapshot.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_motivation_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/motivation_rewards.dart';

import '../quest/support/quest_repository_harness.dart';

void main() {
  late QuestHarness h;
  late StreakUseCases streak;
  var nextId = 0;

  void compose() {
    streak = StreakUseCases(
      repository: DriftStreakRepository(
        h.database,
        ownerWrites: h.storage.ownerWrites,
        quests: h.repository,
        nowUtc: () => h.now,
      ),
      nowUtc: () => h.now,
      generateId: () => 'synthetic-freeze-${++nextId}',
    );
  }

  setUp(() async {
    h = await QuestHarness.open();
    h.now = DateTime.utc(2026, 10, 29, 12);
    nextId = 0;
    compose();
  });
  tearDown(() => h.close());

  Future<MotivationSnapshot> read() =>
      streak.load(expectedOwnerId: configuredOwnerId, stillCurrent: () => true);
  Future<void> reconcile() => streak.reconcileRewards(
    expectedOwnerId: configuredOwnerId,
    stillCurrent: () => true,
  );

  Future<QuestDefinition> completeWeekly() async {
    final base = questDefinition(id: 'synthetic-weekly-reward', target: 1);
    final weekly = QuestDefinition(
      questId: base.questId,
      catalogVersion: base.catalogVersion,
      title: base.title,
      description: base.description,
      type: QuestType.weekly,
      objectives: base.objectives,
      reward: const RewardSpec(xpAmount: 200),
    );
    await h.useCases.startQuest(weekly);
    final answer = await h.answer();
    expect(await h.apply(answer, weekly), hasLength(1));
    return weekly;
  }

  test(
    'grant authority rejects a Quest reader backed by another database before writes',
    () async {
      final other = await QuestHarness.open();
      addTearDown(other.close);
      final before = await h.storage.snapshot();
      final otherBefore = await other.storage.snapshot();
      expect(
        () => DriftMotivationRewardRepository(
          h.database,
          ownerWrites: h.storage.ownerWrites,
          quests: other.repository,
          nowUtc: () => h.now,
        ),
        throwsArgumentError,
      );
      expect(await h.storage.snapshot(), before);
      expect(await other.storage.snapshot(), otherBefore);
    },
  );

  test(
    'grant authority rejects a different coordinator on the same database before writes',
    () async {
      final before = await h.storage.snapshot();
      final different = DriftOwnerWriteCoordinator(
        h.database,
        nowUtc: () => h.now,
      );
      expect(
        () => DriftMotivationRewardRepository(
          h.database,
          ownerWrites: different,
          quests: h.repository,
          nowUtc: () => h.now,
        ),
        throwsArgumentError,
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'canonical weekly completion grants XP and one freeze without coins or research',
    () async {
      await completeWeekly();
      final shop = DriftRewardRepository(h.database);
      final coins = (await shop.load(configuredOwnerId)).balance;
      final before = await h.storage.snapshot();
      await reconcile();
      final result = await read();
      expect(result.questXp, 200);
      expect(result.state.freezeCount, 1);
      expect((await shop.load(configuredOwnerId)).balance, coins);
      final rows = await h.database.select(h.database.rewardTransactions).get();
      expect(
        rows
            .where(
              (row) => row.transactionType == MotivationRewardPolicy.questXp,
            )
            .single
            .amount,
        200,
      );
      expect(
        rows
            .where(
              (row) =>
                  row.transactionType == MotivationRewardPolicy.weeklyFreeze,
            )
            .single
            .amount,
        1,
      );
      final after = await h.storage.snapshot();
      after['reward_transactions'] = before['reward_transactions']!;
      expect(after, before);
      expect((await h.storage.researchCounts()).values, everyElement(0));
      expect(
        (await h.database.select(h.database.outboxOperations).get()).where(
          (row) => row.entityType == 'rewardTransaction',
        ),
        isEmpty,
      );
    },
  );

  test(
    'pure projections read an inactive owner without weakening guarded operations',
    () async {
      await completeWeekly();
      await reconcile();
      h.now = DateTime.utc(2026, 10, 31, 12);
      final original = await read();
      final intent = streak.prepareProtection(
        snapshot: original,
        protectedDay: '2026-10-30',
        stillCurrent: () => true,
      );
      await h.storage.switchOwner(configuredOtherOwnerId);
      final before = await h.storage.snapshot();
      final projected = await streak.repository.readForProjection(
        ownerId: configuredOwnerId,
        nowUtc: h.now,
      );
      expect(
        projected.state.currentStreakDays,
        original.state.currentStreakDays,
      );
      expect(
        projected.learningDays.map((day) => day.sourceAttemptId),
        original.learningDays.map((day) => day.sourceAttemptId),
      );
      expect(projected.questXp, 200);
      expect(projected.state.freezeCount, 1);
      expect(
        await h.repository.readValidatedCompletionsForProjection(
          ownerId: configuredOwnerId,
          nowUtc: h.now,
        ),
        hasLength(1),
      );
      final rewards = await streak.repository.rewards.readForProjection(
        ownerId: configuredOwnerId,
        atUtc: h.now,
      );
      expect(rewards.questXp, 200);
      expect(rewards.freezeCount, 1);
      await expectLater(read(), throwsA(anything));
      await expectLater(
        streak.repository.rewards.read(
          expectedOwnerId: configuredOwnerId,
          atUtc: h.now,
          stillCurrent: () => true,
        ),
        throwsA(anything),
      );
      await expectLater(
        h.repository.readValidatedCompletions(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsA(anything),
      );
      await expectLater(reconcile(), throwsA(anything));
      await expectLater(streak.protect(intent), throwsA(anything));
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'pure absent-owner projections return zero without creating any row',
    () async {
      await completeWeekly();
      await reconcile();
      final before = await h.storage.snapshot();
      const absent = 'synthetic-absent-owner';
      final projected = await streak.repository.readForProjection(
        ownerId: absent,
        nowUtc: h.now,
      );
      expect(projected.ownerId, absent);
      expect(projected.state.currentStreakDays, 0);
      expect(projected.state.longestStreakDays, 0);
      expect(projected.state.freezeCount, 0);
      expect(projected.questXp, 0);
      expect(projected.learningDays, isEmpty);
      expect(projected.protectedDays, isEmpty);
      expect(
        await h.repository.readValidatedCompletionsForProjection(
          ownerId: absent,
          nowUtc: h.now,
        ),
        isEmpty,
      );
      final rewards = await streak.repository.rewards.readForProjection(
        ownerId: absent,
        atUtc: h.now,
      );
      expect(rewards.questXp, 0);
      expect(rewards.freezeCount, 0);
      await expectLater(
        streak.load(expectedOwnerId: absent, stillCurrent: () => true),
        throwsA(anything),
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'a weekly freeze earned now can protect yesterday at the same millisecond',
    () async {
      final base = questDefinition(id: 'synthetic-weekly-tied-time', target: 2);
      final weekly = QuestDefinition(
        questId: base.questId,
        catalogVersion: base.catalogVersion,
        title: base.title,
        description: base.description,
        type: QuestType.weekly,
        objectives: base.objectives,
        reward: const RewardSpec(xpAmount: 200),
      );
      await h.useCases.startQuest(weekly);
      final first = await h.answer(
        id: 'synthetic-tie-first',
        sessionId: 'synthetic-tie-first-session',
      );
      expect(await h.apply(first, weekly), isEmpty);
      h.now = DateTime.utc(2026, 10, 31, 12);
      final last = await h.answer(
        id: 'synthetic-tie-last',
        sessionId: 'synthetic-tie-last-session',
      );
      expect(await h.apply(last, weekly), hasLength(1));
      await reconcile();
      final intent = streak.prepareProtection(
        snapshot: await read(),
        protectedDay: '2026-10-30',
        stillCurrent: () => true,
      );
      final protected = await streak.protect(intent);
      expect(protected.questXp, 200);
      expect(protected.state.freezeCount, 0);
      expect(protected.state.currentStreakDays, 2);
      expect(protected.protectedDays, {'2026-10-30'});
      final receipts = await h.database
          .select(h.database.rewardTransactions)
          .get();
      expect(
        receipts
            .where(
              (row) =>
                  row.transactionType == MotivationRewardPolicy.weeklyFreeze,
            )
            .single
            .occurredAtUtcMs,
        intent.occurredAtUtc.millisecondsSinceEpoch,
      );
      expect(
        receipts
            .where(
              (row) => row.transactionType == MotivationRewardPolicy.protection,
            )
            .single
            .occurredAtUtcMs,
        intent.occurredAtUtc.millisecondsSinceEpoch,
      );
      final once = await h.storage.snapshot();
      await streak.protect(intent);
      expect(await h.storage.snapshot(), once);
    },
  );

  test(
    'grant replay preserves exact receipt IDs and original completion time',
    () async {
      await completeWeekly();
      await reconcile();
      final original = await h.storage.snapshot();
      h.now = h.now.add(const Duration(days: 3));
      await reconcile();
      await reconcile();
      expect(await h.storage.snapshot(), original);
      final rows = await h.database.select(h.database.rewardTransactions).get();
      expect(
        rows
            .where(
              (row) =>
                  row.transactionType == MotivationRewardPolicy.weeklyFreeze,
            )
            .single
            .occurredAtUtcMs,
        DateTime.utc(2026, 10, 29, 12).millisecondsSinceEpoch,
      );
    },
  );

  test(
    'a missing callback is repaired after file restart exactly once',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-motivation-restart-',
      );
      final file = File('${directory.path}/synthetic.sqlite');
      await h.close();
      h = await QuestHarness.open(file: file);
      h.now = DateTime.utc(2026, 10, 29, 12);
      compose();
      await completeWeekly();
      expect((await read()).questXp, 0);
      final rawBefore = await h.storage.snapshot();
      await h.close();
      h = await QuestHarness.open(file: file, seed: false);
      h.now = DateTime.utc(2026, 10, 30, 12);
      compose();
      await reconcile();
      final once = await h.storage.snapshot();
      await reconcile();
      expect(await h.storage.snapshot(), once);
      expect((await read()).questXp, 200);
      final withoutRewards = await h.storage.snapshot();
      withoutRewards['reward_transactions'] = rawBefore['reward_transactions']!;
      expect(withoutRewards, rawBefore);
      await h.close();
      final resolved = await directory.resolveSymbolicLinks();
      final temp = await Directory.systemTemp.resolveSymbolicLinks();
      expect(
        resolved,
        startsWith(
          '$temp${Platform.pathSeparator}lexiquest-motivation-restart-',
        ),
      );
      expect(file.parent.absolute.path, directory.absolute.path);
      await directory.delete(recursive: true);
    },
  );

  test(
    'explicit missing-day protection spends once and never becomes a learned day',
    () async {
      await completeWeekly();
      await reconcile();
      h.now = DateTime.utc(2026, 10, 31, 12);
      final intent = streak.prepareProtection(
        snapshot: await read(),
        protectedDay: '2026-10-30',
        stillCurrent: () => true,
      );
      final beforeAnswers = await h.database
          .select(h.database.answerAttempts)
          .get();
      final protected = await streak.protect(intent);
      expect(protected.state.freezeCount, 0);
      expect(protected.state.currentStreakDays, 1);
      expect(protected.protectedDays, {'2026-10-30'});
      expect(protected.learningDays.map((day) => day.learningDay), [
        '2026-10-29',
      ]);
      final original = await h.storage.snapshot();
      await streak.protect(intent);
      expect(await h.storage.snapshot(), original);
      expect(
        (await h.database.select(h.database.answerAttempts).get()).map(
          (row) => row.toJson(),
        ),
        beforeAnswers.map((row) => row.toJson()),
      );
      await h.answer(
        id: 'synthetic-after-freeze',
        sessionId: 'synthetic-after-freeze-session',
      );
      expect((await read()).state.currentStreakDays, 2);
      expect((await read()).state.longestStreakDays, 2);
    },
  );

  test(
    'two concurrent protections cannot spend one earned freeze twice',
    () async {
      await completeWeekly();
      await reconcile();
      h.now = DateTime.utc(2026, 10, 31, 12);
      final snapshot = await read();
      final first = streak.prepareProtection(
        snapshot: snapshot,
        protectedDay: '2026-10-30',
        stillCurrent: () => true,
      );
      final second = streak.prepareProtection(
        snapshot: snapshot,
        protectedDay: '2026-10-30',
        stillCurrent: () => true,
      );
      final results = await Future.wait([
        streak
            .protect(first)
            .then<Object>((_) => true)
            .catchError((Object error) => error),
        streak
            .protect(second)
            .then<Object>((_) => true)
            .catchError((Object error) => error),
      ]);
      expect(results.where((result) => result == true), hasLength(1));
      expect(results.whereType<MotivationException>(), hasLength(1));
      expect((await read()).state.freezeCount, 0);
      expect(
        (await h.database.select(h.database.rewardTransactions).get()).where(
          (row) => row.transactionType == MotivationRewardPolicy.protection,
        ),
        hasLength(1),
      );
    },
  );

  test(
    'a forged unsupported grant or consumption cannot create XP or freeze balance',
    () async {
      await h.answer();
      for (final type in [
        MotivationRewardPolicy.questXp,
        MotivationRewardPolicy.weeklyFreeze,
        MotivationRewardPolicy.protection,
      ]) {
        await h.database
            .into(h.database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: 'synthetic-forged-$type',
                ownerId: configuredOwnerId,
                idempotencyKey: 'synthetic-forged-$type',
                transactionType: type,
                amount: 999999,
                catalogVersion: 1,
                sourceEventId: const Value('synthetic-no-completion'),
                occurredAtUtcMs: h.now.millisecondsSinceEpoch,
              ),
            );
      }
      final before = await h.storage.snapshot();
      final result = await read();
      expect(result.questXp, 0);
      expect(result.state.freezeCount, 0);
      expect(result.protectedDays, isEmpty);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'changed grant replay is rejected and cannot inflate the existing receipt',
    () async {
      await completeWeekly();
      await reconcile();
      await h.sql(
        'UPDATE reward_transactions SET amount=999 WHERE transaction_type=?',
        [MotivationRewardPolicy.questXp],
      );
      final before = await h.storage.snapshot();
      await expectLater(reconcile(), throwsA(isA<MotivationException>()));
      expect(await h.storage.snapshot(), before);
      expect((await read()).questXp, 0);
      expect((await read()).state.freezeCount, 1);
    },
  );

  test(
    'protection rejects unavailable balance, older days, learned days and owner retirement',
    () async {
      await h.answer();
      h.now = DateTime.utc(2026, 10, 31, 12);
      final noBalance = streak.prepareProtection(
        snapshot: await read(),
        protectedDay: '2026-10-30',
        stillCurrent: () => true,
      );
      final before = await h.storage.snapshot();
      await expectLater(
        streak.protect(noBalance),
        throwsA(isA<MotivationException>()),
      );
      expect(await h.storage.snapshot(), before);
      final snapshot = await read();
      expect(
        () => streak.prepareProtection(
          snapshot: snapshot,
          protectedDay: '2026-10-29',
          stillCurrent: () => true,
        ),
        throwsA(isA<MotivationException>()),
      );
      final stale = FreezeProtectionIntent(
        id: 'synthetic-stale',
        ownerId: configuredOwnerId,
        protectedDay: noBalance.protectedDay,
        timezoneId: noBalance.timezoneId,
        sourceAttemptId: noBalance.sourceAttemptId,
        occurredAtUtc: noBalance.occurredAtUtc,
        stillCurrent: () => false,
      );
      await expectLater(streak.protect(stale), throwsA(anything));
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'raw false receipts remain byte-identical after reading or rejection',
    () async {
      await h.database
          .into(h.database.rewardTransactions)
          .insert(
            RewardTransactionsCompanion.insert(
              id: 'synthetic-invalid-json',
              ownerId: configuredOwnerId,
              idempotencyKey: 'consumeFreezeProtectionV1:2026-10-30',
              transactionType: MotivationRewardPolicy.protection,
              amount: -1,
              itemId: const Value('{invalid'),
              catalogVersion: 1,
              sourceEventId: const Value('synthetic-invalid-source'),
              occurredAtUtcMs: h.now.millisecondsSinceEpoch,
            ),
          );
      final before = jsonEncode(
        (await h.database.select(h.database.rewardTransactions).get())
            .map((row) => row.toJson())
            .toList(),
      );
      final result = await read();
      expect(result.protectedDays, isEmpty);
      expect(
        jsonEncode(
          (await h.database.select(h.database.rewardTransactions).get())
              .map((row) => row.toJson())
              .toList(),
        ),
        before,
      );
    },
  );

  test(
    'owner merge preserves a non-UTC spent freeze and its original learned day',
    () async {
      final profiles = DriftLearningProfileRepository(
        database: h.database,
        ownerWrites: h.storage.ownerWrites,
      );
      Future<void> setZone(String owner) => profiles.save(
        LearningProfileChange(
          expectedOwnerId: owner,
          expectedRevision: 0,
          draft: LearningProfileDraft(
            onboardingState: LearningOnboardingState.completed,
            learningTimezoneId: 'Asia/Bangkok',
          ),
          updatedAtUtc: h.now,
          stillCurrent: () => true,
        ),
      );
      await h.sql(
        'UPDATE local_owners SET firebase_uid=NULL,account_state=? WHERE id=?',
        ['localGuest', configuredOwnerId],
      );
      h.now = DateTime.utc(2026, 10, 29, 17, 1);
      await setZone(configuredOwnerId);
      await completeWeekly();
      await reconcile();
      h.now = DateTime.utc(2026, 11, 1, 12);
      final intent = streak.prepareProtection(
        snapshot: await read(),
        protectedDay: '2026-10-31',
        stillCurrent: () => true,
      );
      expect((await streak.protect(intent)).state.freezeCount, 0);
      final sourceReceipts =
          (await h.database.select(h.database.rewardTransactions).get())
              .where(
                (row) => [
                  MotivationRewardPolicy.questXp,
                  MotivationRewardPolicy.weeklyFreeze,
                  MotivationRewardPolicy.protection,
                ].contains(row.transactionType),
              )
              .map((row) => row.toJson())
              .toList();
      final sourceAttempt =
          (await h.database.select(h.database.answerAttempts).getSingle())
              .toJson();
      final shop = DriftRewardRepository(h.database);
      final guestCoins = (await shop.load(configuredOwnerId)).balance;

      await h.storage.switchOwner(configuredOtherOwnerId);
      h.now = DateTime.utc(2026, 10, 30, 1);
      await setZone(configuredOtherOwnerId);
      await h.learning.startSession(
        LearningSessionDraft(
          id: 'synthetic-target-civil-session',
          ownerId: configuredOtherOwnerId,
          activityType: 'quiz',
          startedAtUtc: h.now,
          appVersion: 'synthetic-1',
          buildId: 'synthetic-owner-merge',
        ),
      );
      await h.learning.recordAnswer(
        RecordAnswerCommand(
          id: 'synthetic-target-civil-answer',
          ownerId: configuredOtherOwnerId,
          sessionId: 'synthetic-target-civil-session',
          wordId: 'synthetic-configured-other-word',
          promptMode: 'multipleChoice',
          isCorrect: true,
          responseTimeMs: 500,
          attemptNumber: 1,
          occurredAtUtc: h.now,
        ),
      );
      final targetCoins = (await shop.load(configuredOtherOwnerId)).balance;
      expect(
        (await h.database.select(h.database.learningDayLog).get()).map(
          (row) => row.learningDay,
        ),
        everyElement('2026-10-30'),
      );

      await h.storage.switchOwner(configuredOwnerId);
      h.now = DateTime.utc(2026, 11, 1, 12);
      var conflictId = 0;
      final upgrade = DriftOwnerUpgradeRepository(
        h.database,
        nowUtc: () => h.now,
        generateConflictId: () =>
            'synthetic-motivation-conflict-${++conflictId}',
        generateOwnerId: () => 'synthetic-unused-guest',
      );
      final result = await upgrade.upgrade(
        activeOwnerId: configuredOwnerId,
        firebaseUid: 'synthetic-configured-uid-b',
      );
      expect(result.targetOwnerId, configuredOtherOwnerId);
      final merged = await streak.load(
        expectedOwnerId: configuredOtherOwnerId,
        stillCurrent: () => true,
      );
      expect(
        {
          'freezes': merged.state.freezeCount,
          'current': merged.state.currentStreakDays,
          'longest': merged.state.longestStreakDays,
          'learnedDays': merged.learningDays
              .map((day) => day.learningDay)
              .toSet(),
          'protectedDays': merged.protectedDays,
          'questXp': merged.questXp,
        },
        {
          'freezes': 0,
          'current': 1,
          'longest': 1,
          'learnedDays': {'2026-10-30'},
          'protectedDays': {'2026-10-31'},
          'questXp': 200,
        },
      );
      final mergedRows = await h.database
          .select(h.database.rewardTransactions)
          .get();
      for (final original in sourceReceipts) {
        final current = mergedRows
            .singleWhere((row) => row.id == original['id'])
            .toJson();
        expect({...current, 'ownerId': configuredOwnerId}, original);
      }
      final movedAttempt =
          await (h.database.select(h.database.answerAttempts)
                ..where((row) => row.id.equals(sourceAttempt['id'] as String)))
              .getSingle();
      expect({
        ...movedAttempt.toJson(),
        'ownerId': configuredOwnerId,
      }, sourceAttempt);
      expect(
        (await shop.load(configuredOtherOwnerId)).balance,
        guestCoins + targetCoins,
      );
      final once = await h.storage.snapshot();
      await upgrade.upgrade(
        activeOwnerId: configuredOtherOwnerId,
        firebaseUid: 'synthetic-configured-uid-b',
      );
      await streak.load(
        expectedOwnerId: configuredOtherOwnerId,
        stillCurrent: () => true,
      );
      expect(await h.storage.snapshot(), once);
      expect((await h.storage.researchCounts()).values, everyElement(0));
    },
  );
}
