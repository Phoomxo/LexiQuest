import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

final _time = DateTime.utc(2026, 10, 20, 12);

void main() {
  late AppDatabase db;
  late DriftRewardRepository rewards;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    rewards = DriftRewardRepository(db);
    await _seedOwner(db, 'a');
    await _seedOwner(db, 'b');
  });
  tearDown(() => db.close());

  test(
    'correct immutable attempt creates one provenance-bound coin across replay',
    () async {
      final learning = DriftLearningRepository(db);
      final command = RecordAnswerCommand(
        id: 'answer-a',
        ownerId: 'a',
        sessionId: 'session-a',
        wordId: 'word-a',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 100,
        attemptNumber: 1,
        occurredAtUtc: _time,
      );
      await learning.recordAnswer(command);
      await learning.recordAnswer(command);
      await rewards.projections.rebuild('a');
      final credits = await (db.select(
        db.rewardTransactions,
      )..where((r) => r.transactionType.equals('creditQuizCorrectV1'))).get();
      expect(credits, hasLength(1));
      expect(credits.single.amount, 1);
      expect(credits.single.catalogVersion, 0);
      expect(credits.single.ownerId, 'a');
      expect(credits.single.sourceEventId, command.id);
      expect(
        credits.single.occurredAtUtcMs,
        command.occurredAtUtc.millisecondsSinceEpoch,
      );
      expect((await rewards.load('a')).balance, 1);
      expect((await rewards.load('b')).balance, 0);
      final outbox = await db.select(db.outboxOperations).get();
      expect(outbox.where((r) => r.entityType == 'rewardTransaction'), isEmpty);
    },
  );

  test(
    'Quest XP preserves five quiz coins across load rebuild and file reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'quest-xp-coins-',
      );
      final file = File('${directory.path}/economy.sqlite');
      var fileDb = AppDatabase(NativeDatabase(file));
      try {
        await _seedOwner(fileDb, 'a');
        await _seedOwner(fileDb, 'b');
        final learning = DriftLearningRepository(fileDb);
        for (var index = 0; index < 5; index++) {
          await learning.recordAnswer(
            RecordAnswerCommand(
              id: 'answer-a-$index',
              ownerId: 'a',
              sessionId: 'session-a',
              wordId: 'word-a',
              promptMode: 'meaningChoice',
              isCorrect: true,
              responseTimeMs: 100,
              attemptNumber: index + 1,
              occurredAtUtc: _time.add(Duration(seconds: index)),
            ),
          );
        }
        expect(
          (await DriftProgressQueries(
            fileDb,
          ).load(ownerId: 'a', nowUtc: _time)).totalXp,
          5,
        );
        expect((await DriftRewardRepository(fileDb).load('a')).balance, 5);
        await _questXp(fileDb, id: 'quest-xp-a');

        Future<void> expectEconomy() async {
          final progress = DriftProgressQueries(fileDb);
          final rewards = DriftRewardRepository(fileDb);
          expect(
            (await progress.load(ownerId: 'a', nowUtc: _time)).totalXp,
            55,
          );
          expect((await rewards.load('a')).balance, 5);
          expect((await progress.load(ownerId: 'b', nowUtc: _time)).totalXp, 0);
          expect((await rewards.load('b')).balance, 0);
          expect(
            await (fileDb.select(
              fileDb.pointsLedgerEntries,
            )..where((row) => row.ownerId.equals('b'))).get(),
            isEmpty,
          );
          expect(
            await (fileDb.select(
              fileDb.rewardTransactions,
            )..where((row) => row.ownerId.equals('b'))).get(),
            isEmpty,
          );
        }

        await expectEconomy();
        await DriftRewardRepository(fileDb).projections.rebuild('a');
        await expectEconomy();
        await fileDb.close();
        fileDb = AppDatabase(NativeDatabase(file));
        await expectEconomy();
        await DriftRewardRepository(fileDb).projections.rebuild('a');
        await expectEconomy();
      } finally {
        await fileDb.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'Quest XP cannot consume correct source backing for legitimate legacy carry',
    () async {
      await DriftLearningRepository(db).recordAnswer(
        RecordAnswerCommand(
          id: 'answer-a',
          ownerId: 'a',
          sessionId: 'session-a',
          wordId: 'word-a',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 100,
          attemptNumber: 1,
          occurredAtUtc: _time,
        ),
      );
      await _legacyCredit(db, 'a', 200, sourceEventId: 'answer-a');
      await _questXp(db, id: 'a-quest-xp', sourceEventId: 'answer-a');
      await rewards.projections.rebuild('a');
      final carry = await (db.select(
        db.rewardTransactions,
      )..where((row) => row.id.equals('coin:legacy:legacy-a'))).getSingle();
      expect(
        carry.amount,
        199,
        reason: 'the quiz coin backs the legacy carry, never the XP-only row',
      );
      expect((await rewards.load('a')).balance, 200);
      expect(
        (await DriftProgressQueries(
          db,
        ).load(ownerId: 'a', nowUtc: _time)).totalXp,
        251,
      );
      expect((await rewards.load('b')).balance, 0);
      final legacy = await (db.select(
        db.pointsLedgerEntries,
      )..where((row) => row.id.equals('legacy-a'))).getSingle();
      expect(legacy.amount, 200);
      expect(legacy.sourceEventId, 'answer-a');
    },
  );

  test(
    'legacy carry preserves balance and raw history without credit outbox',
    () async {
      await _legacyCredit(db, 'a', 200);
      final raw = await db.select(db.pointsLedgerEntries).get();
      final purchase = await rewards.purchase(
        ownerId: 'a',
        item: RewardCatalog.byId('theme_ocean')!,
        idempotencyKey: 'buy',
        transactionId: 'buy',
        occurredAtUtc: _time,
      );
      await rewards.equip(
        ownerId: 'a',
        item: RewardCatalog.byId('theme_ocean')!,
        idempotencyKey: 'equip-intent',
        transactionId: 'equip',
        occurredAtUtc: _time.add(const Duration(seconds: 1)),
      );
      await rewards.projections.rebuild('a');
      final ledger = await db.select(db.pointsLedgerEntries).get();
      expect(ledger.map((r) => r.toJson()), raw.map((r) => r.toJson()));
      expect(purchase.account.balance, 120);
      expect((await rewards.load('a')).equippedBySlot, {
        'theme': 'theme_ocean',
      });
      final carries = await (db.select(
        db.rewardTransactions,
      )..where((r) => r.transactionType.equals('creditLegacyCarryV1'))).get();
      expect(carries, hasLength(1));
      expect(carries.single.amount, 200);
      expect(carries.single.catalogVersion, 0);
      expect(
        ledger.fold<int>(0, (sum, r) => sum + r.amount),
        200,
        reason:
            'same-database downgrade to an old mixed-ledger client is unsupported',
      );
      expect(carries.single.sourceEventId, 'legacy-a');
      final outbox = await db.select(db.outboxOperations).get();
      expect(outbox.map((r) => r.entityId).toSet(), {'buy', 'equip'});
    },
  );

  test(
    'invalid purchase remains raw with zero effect and does not block learning',
    () async {
      await _legacyCredit(db, 'a', 200);
      await db
          .into(db.rewardTransactions)
          .insert(
            RewardTransactionsCompanion.insert(
              id: 'invalid',
              ownerId: 'a',
              idempotencyKey: 'invalid',
              transactionType: 'purchase',
              amount: -1,
              itemId: const Value('theme_ocean'),
              catalogVersion: 1,
              occurredAtUtcMs: 1,
            ),
          );
      await rewards.projections.rebuild('a');
      expect((await rewards.load('a')).balance, 200);
      expect((await rewards.load('a')).ownedItemIds, isEmpty);
      await DriftLearningRepository(db).recordAnswer(
        RecordAnswerCommand(
          id: 'answer-a',
          ownerId: 'a',
          sessionId: 'session-a',
          wordId: 'word-a',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 100,
          attemptNumber: 1,
          occurredAtUtc: _time,
        ),
      );
      expect((await rewards.load('a')).balance, 201);
      final raw = await (db.select(
        db.rewardTransactions,
      )..where((r) => r.id.equals('invalid'))).getSingle();
      expect(raw.amount, -1);
    },
  );

  test(
    'repository admission rejects forged catalog items and conflicting operation types',
    () async {
      await _legacyCredit(db, 'a', 200);
      const forged = RewardCatalogItem(
        id: 'theme_ocean',
        catalogVersion: 1,
        kind: RewardItemKind.theme,
        name: 'fake',
        description: '',
        price: 1,
      );
      await expectLater(
        rewards.purchase(
          ownerId: 'a',
          item: forged,
          idempotencyKey: 'forged',
          transactionId: 'forged',
          occurredAtUtc: _time,
        ),
        throwsA(isA<RewardException>()),
      );
      await rewards.equip(
        ownerId: 'a',
        item: RewardCatalog.byId('theme_default')!,
        idempotencyKey: 'equip:free',
        transactionId: 'free',
        occurredAtUtc: _time,
      );
      await expectLater(
        rewards.purchase(
          ownerId: 'a',
          item: RewardCatalog.byId('theme_default')!,
          idempotencyKey: 'equip:free',
          transactionId: 'conflict',
          occurredAtUtc: _time,
        ),
        throwsA(isA<RewardException>()),
      );
      expect((await rewards.load('a')).balance, 200);
    },
  );

  test(
    'provenance conflict rolls back reward materialization while learning survives',
    () async {
      await _legacyCredit(db, 'a', 200);
      await db
          .into(db.rewardTransactions)
          .insert(
            RewardTransactionsCompanion.insert(
              id: 'coin:legacy:legacy-a',
              ownerId: 'a',
              idempotencyKey: 'creditLegacyCarryV1:legacy-a',
              transactionType: 'creditLegacyCarryV1',
              amount: 999,
              sourceEventId: const Value('legacy-a'),
              catalogVersion: 1,
              occurredAtUtcMs: 1,
            ),
          );
      final command = RecordAnswerCommand(
        id: 'answer-a',
        ownerId: 'a',
        sessionId: 'session-a',
        wordId: 'word-a',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 100,
        attemptNumber: 1,
        occurredAtUtc: _time,
      );
      await expectLater(
        DriftLearningRepository(db).recordAnswer(command),
        completes,
      );
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
      expect(await db.select(db.srsStates).get(), hasLength(1));
      await expectLater(rewards.projections.readLedger('a'), throwsStateError);
      final raw = await db.select(db.rewardTransactions).get();
      expect(
        raw,
        hasLength(1),
        reason:
            'the earlier quiz insert must roll back with the conflicting carry',
      );
      expect(raw.single.amount, 999);
      expect(await db.select(db.pointsLedgerEntries).get(), hasLength(2));
    },
  );

  test('incorrect and cross-owner sources cannot mint a quiz credit', () async {
    await DriftLearningRepository(db).recordAnswer(
      RecordAnswerCommand(
        id: 'wrong-a',
        ownerId: 'a',
        sessionId: 'session-a',
        wordId: 'word-a',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 100,
        attemptNumber: 1,
        occurredAtUtc: _time,
      ),
    );
    await DriftLearningRepository(db).recordAnswer(
      RecordAnswerCommand(
        id: 'correct-b',
        ownerId: 'b',
        sessionId: 'session-b',
        wordId: 'word-b',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 100,
        attemptNumber: 1,
        occurredAtUtc: _time,
      ),
    );
    for (final source in ['wrong-a', 'correct-b']) {
      await db
          .into(db.rewardTransactions)
          .insert(
            RewardTransactionsCompanion.insert(
              id: 'forged-$source',
              ownerId: 'a',
              idempotencyKey: 'forged-$source',
              transactionType: 'creditQuizCorrectV1',
              amount: 100,
              sourceEventId: Value(source),
              catalogVersion: 1,
              occurredAtUtcMs: _time.millisecondsSinceEpoch,
            ),
          );
    }
    final ledger = await rewards.projections.readLedger('a');
    expect(ledger.balance, 0);
    expect(ledger.effects.every((e) => e.effectiveAmount == 0), isTrue);
    expect((await rewards.load('b')).balance, 1);
  });
}

Future<void> _questXp(
  AppDatabase db, {
  required String id,
  String? sourceEventId,
}) => db
    .into(db.pointsLedgerEntries)
    .insert(
      PointsLedgerEntriesCompanion.insert(
        id: id,
        ownerId: 'a',
        idempotencyKey: 'quest-claim:$id',
        entryType: 'questClaimXpV1',
        amount: 50,
        sourceEventId: Value(sourceEventId),
        occurredAtUtcMs: _time.millisecondsSinceEpoch,
      ),
    )
    .then((_) {});

Future<void> _legacyCredit(
  AppDatabase db,
  String owner,
  int amount, {
  String? sourceEventId,
}) => db
    .into(db.pointsLedgerEntries)
    .insert(
      PointsLedgerEntriesCompanion.insert(
        id: 'legacy-$owner',
        ownerId: owner,
        idempotencyKey: 'legacy-$owner',
        entryType: 'learning',
        amount: amount,
        sourceEventId: Value(sourceEventId),
        occurredAtUtcMs: 1,
      ),
    )
    .then((_) {});

Future<void> _seedOwner(AppDatabase db, String owner) async {
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
  await DriftLearningRepository(db).startSession(
    LearningSessionDraft(
      id: 'session-$owner',
      ownerId: owner,
      activityType: 'quiz',
      startedAtUtc: _time,
      appVersion: 'test',
      buildId: 'test',
    ),
  );
}
