import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
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

Future<void> _legacyCredit(AppDatabase db, String owner, int amount) => db
    .into(db.pointsLedgerEntries)
    .insert(
      PointsLedgerEntriesCompanion.insert(
        id: 'legacy-$owner',
        ownerId: owner,
        idempotencyKey: 'legacy-$owner',
        entryType: 'learning',
        amount: amount,
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
