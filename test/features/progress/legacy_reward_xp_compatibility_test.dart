import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

final _now = DateTime.utc(2026, 10, 20, 10);

void main() {
  test(
    'legacy purchase preserves coins and rights without spending XP',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seed(database, 'a', 200);
      await _seed(database, 'b', 10);
      final rewards = DriftRewardRepository(database);

      final before = await _progress(database, 'a');
      await _purchase(rewards, 'a');
      await rewards.equip(
        ownerId: 'a',
        item: RewardCatalog.byId('theme_ocean')!,
        idempotencyKey: 'equip-a',
        transactionId: 'equip-a',
        occurredAtUtc: _now,
      );
      final account = await rewards.load('a');
      final after = await _progress(database, 'a');

      expect(account.balance, 120);
      expect(account.ownedItemIds, {'theme_ocean'});
      expect(account.equippedBySlot, {'theme': 'theme_ocean'});
      expect(after.totalXp, before.totalXp);
      expect(after.gameLevel, before.gameLevel);
      expect(after.totalXp, 200);
      expect(after.gameLevel, 11);
      expect((await _progress(database, 'b')).totalXp, 10);
      expect((await rewards.load('b')).balance, 10);
      expect((await rewards.load('b')).ownedItemIds, isEmpty);
    },
  );

  test(
    'reopen rebuild and purchase replay preserve legacy raw evidence',
    () async {
      final directory = await Directory.systemTemp.createTemp('lq04-xp-');
      var database = AppDatabase(
        NativeDatabase(File('${directory.path}/test.db')),
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      await _seed(database, 'a', 200);
      final rewards = DriftRewardRepository(database);
      await _purchase(rewards, 'a');
      await rewards.equip(
        ownerId: 'a',
        item: RewardCatalog.byId('theme_ocean')!,
        idempotencyKey: 'equip-a',
        transactionId: 'equip-a',
        occurredAtUtc: _now,
      );
      final evidence = await _rawEvidence(database);
      await database.close();
      database = AppDatabase(NativeDatabase(File('${directory.path}/test.db')));
      final reopened = DriftRewardRepository(database);
      await database.transaction(() => reopened.projections.rebuild('a'));
      await database.transaction(() => reopened.projections.rebuild('a'));
      final replay = await _purchase(reopened, 'a');

      expect(replay.status, PurchaseStatus.replayed);
      expect(replay.account.balance, 120);
      expect(replay.account.ownedItemIds, {'theme_ocean'});
      expect(replay.account.equippedBySlot, {'theme': 'theme_ocean'});
      expect(await _rawEvidence(database), evidence);
      expect((await _progress(database, 'a')).totalXp, 200);
      expect((await _progress(database, 'a')).gameLevel, 11);
    },
  );

  test(
    'legacy duplicate and unaffordable purchases retain old treatment',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seed(database, 'a', 200);
      await _seed(database, 'b', 10);
      final rewards = DriftRewardRepository(database);
      await _purchase(rewards, 'a');
      for (final owner in ['a', 'b']) {
        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: 'legacy-$owner',
                ownerId: owner,
                idempotencyKey: 'legacy-$owner',
                transactionType: 'purchase',
                amount: -80,
                itemId: const Value('theme_ocean'),
                catalogVersion: RewardCatalog.version,
                occurredAtUtcMs: _now.millisecondsSinceEpoch + 1,
              ),
            );
        await database.transaction(() => rewards.projections.rebuild(owner));
      }
      expect((await rewards.load('a')).balance, 120);
      expect((await rewards.load('a')).ownedItemIds, {'theme_ocean'});
      expect((await rewards.load('b')).balance, 10);
      expect((await rewards.load('b')).ownedItemIds, isEmpty);
      expect((await _progress(database, 'a')).totalXp, 200);
      expect((await _progress(database, 'b')).totalXp, 10);
      // Direct transaction SUM would break the old accepted-debit semantics.
      final sum = database.rewardTransactions.amount.sum();
      final row =
          await (database.selectOnly(database.rewardTransactions)
                ..addColumns([sum])
                ..where(database.rewardTransactions.ownerId.equals('a')))
              .getSingle();
      expect(row.read(sum), 40);
    },
  );

  test(
    'conflicting replay rejects and invalid legacy transaction has zero effect',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seed(database, 'a', 200);
      final rewards = DriftRewardRepository(database);
      await _purchase(rewards, 'a');
      final evidence = await _rawEvidence(database);
      await expectLater(
        rewards.purchase(
          ownerId: 'a',
          item: RewardCatalog.byId('wallpaper_focus')!,
          idempotencyKey: 'buy-a',
          transactionId: 'conflict',
          occurredAtUtc: _now,
        ),
        throwsA(
          isA<RewardException>().having(
            (e) => e.code,
            'code',
            RewardFailureCode.invalidIdempotencyKey,
          ),
        ),
      );
      expect(await _rawEvidence(database), evidence);
      await database
          .into(database.rewardTransactions)
          .insert(
            RewardTransactionsCompanion.insert(
              id: 'invalid',
              ownerId: 'a',
              idempotencyKey: 'invalid',
              transactionType: 'purchase',
              amount: -1,
              itemId: const Value('theme_ocean'),
              catalogVersion: RewardCatalog.version,
              occurredAtUtcMs: _now.millisecondsSinceEpoch + 1,
            ),
          );
      await database.transaction(() => rewards.projections.rebuild('a'));
      final accounting = await rewards.projections.readLedger('a');
      final invalid = accounting.effects.singleWhere(
        (e) => e.entry.id == 'invalid',
      );
      expect(invalid.effectiveAmount, 0);
      expect(invalid.status.name, 'invalid');
      expect((await rewards.load('a')).balance, 120);
      expect((await rewards.load('a')).ownedItemIds, {'theme_ocean'});
      expect((await _progress(database, 'a')).totalXp, 200);
    },
  );
}

Future<void> _seed(AppDatabase db, String owner, int credits) async {
  await db
      .into(db.localOwners)
      .insert(LocalOwnersCompanion.insert(id: owner, createdAtUtcMs: 1));
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category-$owner',
          ownerId: owner,
          name: 'Synthetic',
          normalizedName: 'synthetic',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await db
      .into(db.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word-$owner',
          ownerId: owner,
          categoryId: 'category-$owner',
          spelling: 'synthetic',
          normalizedSpelling: 'synthetic',
          meaning: 'test',
          normalizedMeaning: 'test',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  final learning = DriftLearningRepository(db);
  await learning.startSession(
    LearningSessionDraft(
      id: 'session-$owner',
      ownerId: owner,
      activityType: 'quiz',
      startedAtUtc: _now,
      appVersion: 'test',
      buildId: 'test',
    ),
  );
  await learning.recordAnswer(
    RecordAnswerCommand(
      id: 'answer-$owner',
      ownerId: owner,
      sessionId: 'session-$owner',
      wordId: 'word-$owner',
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 100,
      attemptNumber: 1,
      occurredAtUtc: _now,
    ),
  );
  await db
      .into(db.pointsLedgerEntries)
      .insert(
        PointsLedgerEntriesCompanion.insert(
          id: 'legacy-credit-$owner',
          ownerId: owner,
          idempotencyKey: 'legacy-credit-$owner',
          entryType: 'learning',
          amount: credits - 1,
          occurredAtUtcMs: 1,
        ),
      );
}

Future<PurchaseResult> _purchase(DriftRewardRepository repo, String owner) =>
    repo.purchase(
      ownerId: owner,
      item: RewardCatalog.byId('theme_ocean')!,
      idempotencyKey: 'buy-$owner',
      transactionId: 'purchase-$owner',
      occurredAtUtc: _now,
    );

Future<ProgressSnapshot> _progress(AppDatabase db, String owner) =>
    DriftProgressQueries(db).load(ownerId: owner, nowUtc: _now);

Future<List<Object?>> _rawEvidence(AppDatabase db) async => [
  (await db.select(db.answerAttempts).get()).map((r) => r.toJson()).toList(),
  (await db.select(db.rewardTransactions).get())
      .map((r) => r.toJson())
      .toList(),
  (await db.select(db.pointsLedgerEntries).get())
      .map((r) => r.toJson())
      .toList(),
  (await db.select(db.outboxOperations).get()).map((r) => r.toJson()).toList(),
];
