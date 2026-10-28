import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_economy_cutover.dart';

void main() {
  late AppDatabase database;
  late DriftEconomyCutover cutover;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    cutover = DriftEconomyCutover(database);
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
  });

  tearDown(() => database.close());

  test(
    'backfills legacy earnings incrementally and preserves point audit',
    () async {
      await _insertPoint(
        database,
        id: 'point:quiz-1',
        type: 'quizCorrect',
        amount: 5,
        sourceEventId: 'legacy-attempt-1',
        occurredAtUtcMs: 10,
      );
      await _insertPoint(
        database,
        id: 'point:purchase-audit',
        type: 'rewardPurchase',
        amount: -3,
        sourceEventId: 'purchase-1',
        occurredAtUtcMs: 11,
      );

      await cutover.ensureSeparated('owner-1');
      await cutover.ensureSeparated('owner-1');

      var transactions = await database
          .select(database.rewardTransactions)
          .get();
      expect(transactions, hasLength(1));
      expect(transactions.single.transactionType, 'legacyEarningBackfill');
      expect(transactions.single.amount, 5);
      expect(transactions.single.itemId, isNull);
      expect(transactions.single.catalogVersion, 0);
      expect(transactions.single.sourceEventId, 'legacy-attempt-1');
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        hasLength(2),
      );
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(1),
      );

      await _insertPoint(
        database,
        id: 'point:quest-1',
        type: 'questCompletion',
        amount: 50,
        sourceEventId: null,
        occurredAtUtcMs: 12,
      );
      await cutover.ensureSeparated('owner-1');

      transactions = await database.select(database.rewardTransactions).get();
      expect(transactions, hasLength(2));
      final quest = transactions.singleWhere((row) => row.amount == 50);
      expect(quest.sourceEventId, 'point:quest-1');
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(2),
      );
    },
  );

  test(
    'leaves v2-correlated quiz earning pending for the coins sink',
    () async {
      const attemptId = 'attempt-v2';
      await _insertPoint(
        database,
        id: 'point:v2',
        type: 'quizCorrect',
        amount: 1,
        sourceEventId: attemptId,
        occurredAtUtcMs: 10,
      );
      final at = DateTime.utc(2026, 8, 21, 10);
      await database
          .into(database.eventsV2)
          .insert(
            EventsV2Companion.insert(
              eventId: LearningEvidenceContract.learningEventId(attemptId),
              eventType: 'LearningAnswerRecorded',
              eventVersion: 2,
              occurredAtUtc: at,
              recordedAtUtc: at,
              actorIdentity: 'owner-1',
              ownerId: 'owner-1',
              aggregateType: 'LearningAttempt',
              aggregateId: attemptId,
              idempotencyKey:
                  LearningEvidenceContract.learningAttemptIdempotencyKey(
                    attemptId,
                  ),
              consentContextJson: '{}',
              appVersion: 'test',
              buildId: 'test',
              privacyClassification: 'anonymized',
              payloadJson: jsonEncode({'attemptId': attemptId}),
            ),
          );

      await cutover.ensureSeparated('owner-1');

      expect(await database.select(database.rewardTransactions).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test('backfills an exact v1-correlated quiz earning', () async {
    const attemptId = 'attempt-v1';
    await _insertPoint(
      database,
      id: 'point:v1',
      type: 'quizCorrect',
      amount: 1,
      sourceEventId: attemptId,
      occurredAtUtcMs: 10,
    );
    final at = DateTime.utc(2026, 8, 21, 9);
    await database
        .into(database.eventsV2)
        .insert(
          EventsV2Companion.insert(
            eventId: LearningEvidenceContract.learningEventId(attemptId),
            eventType: 'LearningAnswerRecorded',
            eventVersion: 1,
            occurredAtUtc: at,
            recordedAtUtc: at,
            actorIdentity: 'owner-1',
            ownerId: 'owner-1',
            aggregateType: 'LearningAttempt',
            aggregateId: attemptId,
            idempotencyKey: 'learning-attempt:$attemptId:v1',
            consentContextJson: '{}',
            appVersion: 'test',
            buildId: 'test',
            privacyClassification: 'anonymized',
            payloadJson: jsonEncode({'attemptId': attemptId}),
          ),
        );

    await cutover.ensureSeparated('owner-1');

    final transaction = await database
        .select(database.rewardTransactions)
        .getSingle();
    expect(transaction.transactionType, 'legacyEarningBackfill');
    expect(transaction.amount, 1);
    expect(transaction.sourceEventId, attemptId);
  });

  test('same source coin evidence suppresses a legacy backfill', () async {
    await _insertPoint(
      database,
      id: 'point:already-coins',
      type: 'quizCorrect',
      amount: 1,
      sourceEventId: 'source-1',
      occurredAtUtcMs: 10,
    );
    await database
        .into(database.rewardTransactions)
        .insert(
          RewardTransactionsCompanion.insert(
            id: 'coins:source-1',
            ownerId: 'owner-1',
            idempotencyKey: 'coins:source-1',
            transactionType: 'coinGrant',
            amount: 1,
            catalogVersion: 0,
            sourceEventId: const Value('source-1'),
            occurredAtUtcMs: 10,
          ),
        );

    await cutover.ensureSeparated('owner-1');

    expect(
      await database.select(database.rewardTransactions).get(),
      hasLength(1),
    );
  });

  for (final mismatch in const [
    (
      name: 'earning amount',
      transactionType: 'coinGrant',
      amount: 2,
      occurredAtUtcMs: 10,
    ),
    (
      name: 'canonical occurrence',
      transactionType: 'legacyEarningBackfill',
      amount: 1,
      occurredAtUtcMs: 11,
    ),
  ]) {
    test(
      'same source evidence with mismatched ${mismatch.name} fails closed',
      () async {
        await _insertPoint(
          database,
          id: 'point:mismatch',
          type: 'quizCorrect',
          amount: 1,
          sourceEventId: 'source-mismatch',
          occurredAtUtcMs: 10,
        );
        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: 'coins:mismatch',
                ownerId: 'owner-1',
                idempotencyKey: 'coins:mismatch',
                transactionType: mismatch.transactionType,
                amount: mismatch.amount,
                catalogVersion: 0,
                sourceEventId: const Value('source-mismatch'),
                occurredAtUtcMs: mismatch.occurredAtUtcMs,
              ),
            );

        await expectLater(
          cutover.ensureSeparated('owner-1'),
          throwsA(isA<StateError>()),
        );
        expect(
          await database.select(database.rewardTransactions).get(),
          hasLength(1),
        );
      },
    );
  }

  test(
    'same deterministic identity with changed payload fails closed',
    () async {
      await _insertPoint(
        database,
        id: 'point:collision',
        type: 'quizCorrect',
        amount: 4,
        sourceEventId: 'legacy-collision',
        occurredAtUtcMs: 10,
      );
      await cutover.ensureSeparated('owner-1');
      await database.customUpdate(
        "UPDATE reward_transactions SET amount = 99 WHERE owner_id = 'owner-1'",
      );

      await expectLater(
        cutover.ensureSeparated('owner-1'),
        throwsA(isA<StateError>()),
      );
      expect(
        await database.select(database.rewardTransactions).get(),
        hasLength(1),
      );
    },
  );

  test(
    'invalid nullable legacy source receives a bounded deterministic identity',
    () async {
      final longPointId = 'point:${'x' * 300}';
      await _insertPoint(
        database,
        id: longPointId,
        type: 'quizCorrect',
        amount: 2,
        sourceEventId: null,
        occurredAtUtcMs: 10,
      );

      await cutover.ensureSeparated('owner-1');
      final transaction = await database
          .select(database.rewardTransactions)
          .getSingle();

      expect(transaction.sourceEventId, startsWith('legacy-point:'));
      expect(transaction.sourceEventId!.runes.length, lessThanOrEqualTo(256));
      await cutover.ensureSeparated('owner-1');
      expect(
        await database.select(database.rewardTransactions).get(),
        hasLength(1),
      );
    },
  );
}

Future<void> _insertPoint(
  AppDatabase database, {
  required String id,
  required String type,
  required int amount,
  required String? sourceEventId,
  required int occurredAtUtcMs,
}) {
  return database
      .into(database.pointsLedgerEntries)
      .insert(
        PointsLedgerEntriesCompanion.insert(
          id: id,
          ownerId: 'owner-1',
          idempotencyKey: 'idem:$id',
          entryType: type,
          amount: amount,
          sourceEventId: Value(sourceEventId),
          occurredAtUtcMs: occurredAtUtcMs,
        ),
      );
}
