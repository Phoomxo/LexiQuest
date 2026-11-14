import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_motivation_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

final _day = DateTime.utc(2026, 10, 20, 12);
final _claimTime = _day.add(const Duration(hours: 1));
final _claimRejected = throwsA(
  anyOf(isA<StateError>(), isA<RewardException>()),
);

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test(
    'real daily claim grants XP50 and no coins, survives lost ACK and reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'synthetic-quest-claim-',
      );
      final file = File('${directory.path}/claims.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      try {
        var fixture = await _Fixture.create(db);
        await fixture.answers(5);
        final period = await fixture.period();
        await _expectEconomy(db, 'a', xp: 5, coins: 5);
        final ordinaryOutbox = await _rows(db, 'outbox_operations');
        final answerBytes = await _rows(db, 'answer_attempts');
        final result = await fixture.rewards().claimQuest(
          expectedOwnerId: 'a',
          instanceId: period,
        );
        expect(
          (
            result.ownerId,
            result.canonicalInstanceId,
            result.xpAmount,
            result.replayed,
          ),
          ('a', period, 50, false),
        );
        expect(result.issuedAtUtc, _claimTime);
        expect(result.receiptId, isNotEmpty);
        await _expectEconomy(db, 'a', xp: 55, coins: 5);
        await _expectEconomy(db, 'b', xp: 0, coins: 0);
        final receipts = await _rows(db, 'quest_claim_receipts');
        final points = await _rows(db, 'points_ledger_entries');
        expect(receipts, hasLength(1));
        expect(receipts.single['id'], result.receiptId);
        expect(
          receipts.single['completed_at_utc_ms'],
          _day.add(const Duration(seconds: 4)).millisecondsSinceEpoch,
        );
        expect(await _rows(db, 'outbox_operations'), ordinaryOutbox);
        expect(await _rows(db, 'answer_attempts'), answerBytes);
        await _expectNoResearch(db);
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        fixture = await _Fixture.attach(db);
        fixture.now = _claimTime.add(const Duration(days: 30));
        final replay = await fixture.rewards().claimQuest(
          expectedOwnerId: 'a',
          instanceId: period,
        );
        expect(
          (
            replay.receiptId,
            replay.canonicalInstanceId,
            replay.xpAmount,
            replay.issuedAtUtc,
            replay.replayed,
          ),
          (
            result.receiptId,
            result.canonicalInstanceId,
            50,
            result.issuedAtUtc,
            true,
          ),
        );
        await fixture.rewards().projections.rebuild('a');
        await _expectEconomy(db, 'a', xp: 55, coins: 5);
        expect(await _rows(db, 'quest_claim_receipts'), receipts);
        expect(await _rows(db, 'points_ledger_entries'), points);
        expect(await _rows(db, 'outbox_operations'), ordinaryOutbox);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        await _expectNoResearch(db);
      } finally {
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test('weekly twenty real correct answers grant XP200 only once', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final fixture = await _Fixture.create(db);
    await fixture.answers(20);
    final period = await fixture.period(weekly: true);
    final result = await fixture.rewards().claimQuest(
      expectedOwnerId: 'a',
      instanceId: period,
    );
    expect(result.xpAmount, 200);
    await _expectEconomy(db, 'a', xp: 220, coins: 20);
    expect(
      (await fixture.rewards().claimQuest(
        expectedOwnerId: 'a',
        instanceId: period,
      )).replayed,
      isTrue,
    );
    expect(await _rows(db, 'quest_claim_receipts'), hasLength(1));
    expect(await _rows(db, 'quest_instances'), hasLength(1));
    await _expectNoResearch(db);
  });

  test(
    'same-ms distinct attempts count, exact answer replay counts once',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final fixture = await _Fixture.create(db);
      for (var i = 0; i < 4; i++) {
        await fixture.answer(i, at: _day);
      }
      await fixture.answer(0, at: _day);
      await fixture.answer(4, correct: false, at: _day);
      final period = await fixture.period();
      final before = await _snapshot(db);
      await expectLater(
        fixture.rewards().claimQuest(expectedOwnerId: 'a', instanceId: period),
        _claimRejected,
      );
      expect(await _snapshot(db), before);
      await fixture.answer(5, at: _day);
      await fixture.rewards().claimQuest(
        expectedOwnerId: 'a',
        instanceId: period,
      );
      expect(
        (await db.select(db.questClaimReceipts).getSingle()).completedAtUtcMs,
        _day.millisecondsSinceEpoch,
      );
      await _expectEconomy(db, 'a', xp: 55, coins: 5);
    },
  );

  test(
    'closed completed period stays claimable while incomplete period expires',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final fixture = await _Fixture.create(db);
      await fixture.answers(5);
      final complete = await fixture.period();
      await fixture.answer(5, at: _day.add(const Duration(days: 1)));
      final incomplete = await fixture.period(answerId: 'a-answer-5');
      fixture.now = _day.add(const Duration(days: 8));
      final before = await _snapshot(db);
      await expectLater(
        fixture.rewards().claimQuest(
          expectedOwnerId: 'a',
          instanceId: incomplete,
        ),
        _claimRejected,
      );
      expect(await _snapshot(db), before);
      expect(
        (await fixture.rewards().claimQuest(
          expectedOwnerId: 'a',
          instanceId: complete,
        )).xpAmount,
        50,
      );
      await _expectEconomy(db, 'a', xp: 56, coins: 6);
    },
  );

  for (final failure in [
    'hidden',
    'absent catalog',
    'stale owner',
    'malformed intent',
    'tampered archive',
    'future answer',
  ]) {
    test('claim fails closed without writes: $failure', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final fixture = await _Fixture.create(db);
      await fixture.answers(5);
      final period = await fixture.period();
      var repository = fixture.rewards();
      switch (failure) {
        case 'hidden':
          repository = fixture.rewards(visible: () => false);
        case 'absent catalog':
          repository = DriftRewardRepository(
            db,
            questVisible: () => true,
            nowUtc: () => fixture.now,
          );
        case 'stale owner':
          await db.customStatement(
            "UPDATE local_owners SET is_active=CASE WHEN id='b' THEN 1 ELSE 0 END",
          );
        case 'malformed intent':
          await db.customStatement(
            "UPDATE answer_attempts SET quest_intent='{}' WHERE id='a-answer-4'",
          );
        case 'tampered archive':
          await db.customStatement(
            "UPDATE quest_definition_revisions SET canonical_definition='{}'",
          );
        case 'future answer':
          fixture.now = _day.add(const Duration(seconds: 2));
      }
      final before = await _snapshot(db);
      await expectLater(
        repository.claimQuest(expectedOwnerId: 'a', instanceId: period),
        _claimRejected,
      );
      expect(await _snapshot(db), before);
    });
  }

  for (final table in [
    'quest_instances',
    'quest_claim_receipts',
    'points_ledger_entries',
  ]) {
    test(
      'SQLite failure inserting $table rolls back the complete claim',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final fixture = await _Fixture.create(db);
        await fixture.answers(5);
        final period = await fixture.period();
        await db.customStatement(
          "CREATE TRIGGER synthetic_claim_failure BEFORE INSERT ON $table BEGIN SELECT RAISE(ABORT,'synthetic claim failure'); END",
        );
        final before = await _snapshot(db);
        await expectLater(
          fixture.rewards().claimQuest(
            expectedOwnerId: 'a',
            instanceId: period,
          ),
          throwsA(isA<Exception>()),
        );
        expect(await _snapshot(db), before);
        await db.customStatement('DROP TRIGGER synthetic_claim_failure');
        expect(
          (await fixture.rewards().claimQuest(
            expectedOwnerId: 'a',
            instanceId: period,
          )).replayed,
          isFalse,
        );
        await _expectEconomy(db, 'a', xp: 55, coins: 5);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  }

  test(
    'two independent file connections converge on one receipt and one XP grant',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'synthetic-quest-race-',
      );
      final file = File('${directory.path}/claims.sqlite');
      final db = AppDatabase(NativeDatabase(file));
      AppDatabase? second;
      try {
        final fixture = await _Fixture.create(db);
        await fixture.answers(5);
        final period = await fixture.period();
        second = AppDatabase(NativeDatabase(file));
        final other = await _Fixture.attach(second);
        final results = await Future.wait([
          fixture.rewards().claimQuest(
            expectedOwnerId: 'a',
            instanceId: period,
          ),
          other.rewards().claimQuest(expectedOwnerId: 'a', instanceId: period),
        ]);
        expect(results.map((r) => r.receiptId).toSet(), hasLength(1));
        expect(results.where((r) => !r.replayed), hasLength(1));
        expect(await _rows(db, 'quest_claim_receipts'), hasLength(1));
        expect(
          (await _rows(
            db,
            'points_ledger_entries',
          )).where((r) => r['entry_type'] == 'questClaimXpV1'),
          hasLength(1),
        );
        await _expectEconomy(db, 'a', xp: 55, coins: 5);
      } finally {
        await second?.close();
        await db.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'existing XP issuer reconstructs exactly one validated receipt projection',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final fixture = await _Fixture.create(db);
      await fixture.answers(5);
      await fixture.rewards().claimQuest(
        expectedOwnerId: 'a',
        instanceId: await fixture.period(),
      );
      final issued = (await _rows(
        db,
        'points_ledger_entries',
      )).where((r) => r['entry_type'] == 'questClaimXpV1').single;
      await db.customStatement(
        "DELETE FROM points_ledger_entries WHERE entry_type='questClaimXpV1'",
      );
      final issuer = DriftLearningProjectionRebuilder(
        db,
        questCatalog: fixture.catalog,
      );
      await issuer.rebuildQuestXp('a');
      await issuer.rebuildQuestXp('a');
      expect(
        (await _rows(
          db,
          'points_ledger_entries',
        )).where((r) => r['entry_type'] == 'questClaimXpV1'),
        [issued],
      );
      await _expectEconomy(db, 'a', xp: 55, coins: 5);
      await db.customStatement("UPDATE quest_claim_receipts SET xp_amount=51");
      final before = await _snapshot(db);
      await expectLater(issuer.rebuildQuestXp('a'), throwsStateError);
      expect(await _snapshot(db), before);
    },
  );

  test(
    'claim replay rejects a mismatched existing receipt XP projection',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final fixture = await _Fixture.create(db);
      await fixture.answers(5);
      final period = await fixture.period();
      await fixture.rewards().claimQuest(
        expectedOwnerId: 'a',
        instanceId: period,
      );
      await db.customStatement(
        "UPDATE points_ledger_entries SET amount=51 WHERE entry_type='questClaimXpV1'",
      );
      final before = await _snapshot(db);
      await expectLater(
        fixture.rewards().claimQuest(expectedOwnerId: 'a', instanceId: period),
        _claimRejected,
      );
      expect(await _snapshot(db), before);
    },
  );

  group('issued Quest provenance', () {
    late AppDatabase db;
    late _Fixture fixture;
    late String period;
    late QuestClaimResult original;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      fixture = await _Fixture.create(db);
      await fixture.answers(5);
      period = await fixture.period();
      original = await fixture.rewards().claimQuest(
        expectedOwnerId: 'a',
        instanceId: period,
      );
      expect(original.replayed, isFalse);
    });
    tearDown(() => db.close());

    test('rejects a changed receipt issue time before restoring XP', () async {
      await db.customStatement(
        "DELETE FROM points_ledger_entries WHERE entry_type='questClaimXpV1' AND source_event_id=?",
        [original.receiptId],
      );
      await db.customStatement(
        'UPDATE quest_claim_receipts SET issued_at_utc_ms=? WHERE id=?',
        [original.issuedAtUtc.millisecondsSinceEpoch + 1, original.receiptId],
      );
      final before = await _snapshot(db);
      final issuer = DriftLearningProjectionRebuilder(
        db,
        questCatalog: fixture.catalog,
      );
      await expectLater(issuer.rebuildQuestXp('a'), throwsStateError);
      expect(await _snapshot(db), before);
      final xp = await db.select(db.pointsLedgerEntries).get();
      expect(xp.where((r) => r.entryType == 'questClaimXpV1'), isEmpty);
      expect(xp.fold<int>(0, (sum, r) => sum + r.amount), 5);
    });

    test('replays the original receipt after the clock moves backward', () async {
      // All five answers have occurred. Only the prior issuance is now in the future.
      fixture.now = original.issuedAtUtc.subtract(
        const Duration(milliseconds: 1),
      );
      final before = await _snapshot(db);
      final replay = await fixture.rewards().claimQuest(
        expectedOwnerId: 'a',
        instanceId: period,
      );
      expect(replay.replayed, isTrue);
      expect(replay.receiptId, original.receiptId);
      expect(replay.canonicalInstanceId, original.canonicalInstanceId);
      expect(replay.issuedAtUtc, original.issuedAtUtc);
      expect(replay.xpAmount, original.xpAmount);
      expect(await _snapshot(db), before);
    });

    test('an answer ID may equal an issued receipt ID', () async {
      await fixture.answer(
        5,
        id: original.receiptId,
        at: original.issuedAtUtc.add(const Duration(seconds: 1)),
      );
      final before = await _snapshot(db);
      fixture.now = _day.subtract(const Duration(milliseconds: 1));
      final replay = await fixture.rewards().claimQuest(
        expectedOwnerId: 'a',
        instanceId: period,
      );
      expect(replay.replayed, isTrue);
      expect(replay.receiptId, original.receiptId);
      expect(replay.issuedAtUtc, original.issuedAtUtc);
      expect(replay.xpAmount, 50);
      expect(await _snapshot(db), before);
      final xp = await db.select(db.pointsLedgerEntries).get();
      expect(xp.where((r) => r.entryType == 'questClaimXpV1'), hasLength(1));
      expect(
        xp
            .where((r) => r.sourceEventId == original.receiptId)
            .map((r) => r.entryType),
        unorderedEquals(['quizCorrect', 'questClaimXpV1']),
      );
      await _expectEconomy(db, 'a', xp: 56, coins: 6);
    });

    test(
      'rejects a renamed XP identity that still refers to the receipt',
      () async {
        await db.customStatement(
          "UPDATE points_ledger_entries SET id='renamed-entry', idempotency_key='renamed-key' "
          "WHERE entry_type='questClaimXpV1' AND source_event_id=?",
          [original.receiptId],
        );
        final before = await _snapshot(db);
        final issuer = DriftLearningProjectionRebuilder(
          db,
          questCatalog: fixture.catalog,
        );
        await expectLater(issuer.rebuildQuestXp('a'), throwsStateError);
        expect(await _snapshot(db), before);
        final xp = await db.select(db.pointsLedgerEntries).get();
        final grant = xp.singleWhere(
          (r) => r.sourceEventId == original.receiptId,
        );
        expect(
          (grant.id, grant.idempotencyKey, grant.amount),
          ('renamed-entry', 'renamed-key', 50),
        );
        expect(xp.fold<int>(0, (sum, r) => sum + r.amount), 55);
      },
    );
  });

  for (final bothPaid in [false, true]) {
    test(
      'actual claims survive owner merge with no third grant, both paid=$bothPaid',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final fixture = await _Fixture.create(db);
        await fixture.answers(5);
        final aPeriod = await fixture.period();
        final aReceipt = await fixture.rewards().claimQuest(
          expectedOwnerId: 'a',
          instanceId: aPeriod,
        );
        await fixture.activate('b');
        await fixture.answers(5, owner: 'b');
        final bPeriod = await fixture.period(answerId: 'b-answer-0');
        if (bothPaid) {
          await fixture.rewards().claimQuest(
            expectedOwnerId: 'b',
            instanceId: bPeriod,
          );
        }
        await fixture.activate('a');
        final rawReceiptIds = (await _rows(
          db,
          'quest_claim_receipts',
        )).map((r) => r['id']).toSet();
        final rawXpIds = (await _rows(
          db,
          'points_ledger_entries',
        )).map((r) => r['id']).toSet();
        await fixture.mergeAIntoB();
        final first = await fixture.rewards().claimQuest(
          expectedOwnerId: 'b',
          instanceId: aPeriod,
        );
        final second = await fixture.rewards().claimQuest(
          expectedOwnerId: 'b',
          instanceId: bPeriod,
        );
        expect(first.replayed, isTrue);
        expect(second.replayed, isTrue);
        if (!bothPaid) expect(first.receiptId, aReceipt.receiptId);
        expect(
          (await _rows(db, 'quest_claim_receipts')).map((r) => r['id']).toSet(),
          rawReceiptIds,
        );
        expect(
          (await _rows(
            db,
            'points_ledger_entries',
          )).map((r) => r['id']).toSet(),
          rawXpIds,
        );
        await _expectEconomy(db, 'b', xp: bothPaid ? 110 : 60, coins: 10);
        await _expectNoResearch(db);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  }

  test(
    'compatible real three-plus-two facts merge then claim once through either member',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final fixture = await _Fixture.create(db);
      await fixture.answers(3);
      final aPeriod = await fixture.period();
      await fixture.activate('b');
      await fixture.answers(2, owner: 'b');
      final bPeriod = await fixture.period(answerId: 'b-answer-0');
      await fixture.activate('a');
      await fixture.mergeAIntoB();
      final result = await fixture.rewards().claimQuest(
        expectedOwnerId: 'b',
        instanceId: aPeriod,
      );
      expect(result.replayed, isFalse);
      final replay = await fixture.rewards().claimQuest(
        expectedOwnerId: 'b',
        instanceId: bPeriod,
      );
      expect((replay.receiptId, replay.replayed), (result.receiptId, true));
      expect(await _rows(db, 'quest_claim_receipts'), hasLength(1));
      final instances = await db.select(db.questInstances).get();
      expect(instances.where((r) => r.recordKind == 'canonical'), hasLength(1));
      expect(instances.where((r) => r.recordKind == 'alias'), hasLength(1));
      await _expectEconomy(db, 'b', xp: 55, coins: 5);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    },
  );
}

final class _Fixture {
  _Fixture(this.db, this.catalog);
  final AppDatabase db;
  final TrustedQuestAnswerCatalog catalog;
  DateTime now = _claimTime;

  static Future<_Fixture> create(AppDatabase db) async {
    await _seed(db, 'a', active: true);
    await _seed(db, 'b', active: false);
    return attach(db);
  }

  static Future<_Fixture> attach(AppDatabase db) async =>
      _Fixture(db, await DriftQuestRepository(db).installAnswerCatalog());

  DriftRewardRepository rewards({bool Function()? visible}) =>
      DriftRewardRepository(
        db,
        questCatalog: catalog,
        questVisible: visible ?? () => true,
        nowUtc: () => now,
      );

  Future<void> answers(int count, {String owner = 'a'}) async {
    for (var i = 0; i < count; i++) {
      await answer(i, owner: owner);
    }
  }

  Future<void> answer(
    int index, {
    String? id,
    String owner = 'a',
    bool correct = true,
    DateTime? at,
  }) =>
      DriftLearningRepository(
            db,
            questCatalog: catalog,
            questVisible: () => true,
          )
          .recordAnswer(
            RecordAnswerCommand(
              id: id ?? '$owner-answer-$index',
              ownerId: owner,
              sessionId: 'session-$owner',
              wordId: 'word-$owner',
              promptMode: 'meaningChoice',
              isCorrect: correct,
              responseTimeMs: 100,
              attemptNumber: index + 1,
              occurredAtUtc: at ?? _day.add(Duration(seconds: index)),
            ),
          )
          .then((_) {});

  Future<String> period({
    bool weekly = false,
    String answerId = 'a-answer-0',
  }) async {
    final attempt = await (db.select(
      db.answerAttempts,
    )..where((r) => r.id.equals(answerId))).getSingle();
    final intent =
        decodeQuestIntent(attempt.questIntent!) as CapturedQuestIntent;
    return weekly ? intent.weeklyPeriodId : intent.dailyPeriodId;
  }

  Future<void> activate(String owner) => db.customStatement(
    'UPDATE local_owners SET is_active=CASE WHEN id=? THEN 1 ELSE 0 END',
    [owner],
  );

  Future<void> mergeAIntoB() async {
    await db.customStatement(
      "UPDATE local_owners SET firebase_uid='synthetic-bound-b',account_state='firebaseBound' WHERE id='b'",
    );
    var conflicts = 0;
    await DriftOwnerUpgradeRepository(
      db,
      nowUtc: () => now,
      generateConflictId: () => 'synthetic-conflict-${conflicts++}',
      generateOwnerId: () => 'unused-owner',
    ).upgrade(activeOwnerId: 'a', firebaseUid: 'synthetic-bound-b');
  }
}

Future<void> _seed(AppDatabase db, String owner, {required bool active}) async {
  await db
      .into(db.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: owner,
          createdAtUtcMs: 1,
          isActive: Value(active),
        ),
      );
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
  await db
      .into(db.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'session-$owner',
          ownerId: owner,
          activityType: 'quiz',
          state: 'active',
          startedAtUtcMs: _day.millisecondsSinceEpoch,
          appVersion: 'synthetic',
          buildId: 'synthetic',
        ),
      );
}

Future<List<Map<String, dynamic>>> _rows(AppDatabase db, String table) async =>
    [
      for (final row
          in await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
        row.data,
    ];

Future<String> _snapshot(AppDatabase db) async {
  final names = db.allTables.map((t) => t.actualTableName).toList()..sort();
  return jsonEncode({for (final name in names) name: await _rows(db, name)});
}

Future<void> _expectEconomy(
  AppDatabase db,
  String owner, {
  required int xp,
  required int coins,
}) async {
  expect(
    (await DriftProgressQueries(
      db,
    ).load(ownerId: owner, nowUtc: _claimTime)).totalXp,
    xp,
  );
  expect((await DriftRewardRepository(db).load(owner)).balance, coins);
}

Future<void> _expectNoResearch(AppDatabase db) async {
  expect(await db.select(db.eventsV2).get(), isEmpty);
  expect(await db.select(db.researchConsents).get(), isEmpty);
  final outbox = await db.select(db.outboxOperations).get();
  expect(
    outbox.where(
      (r) =>
          r.entityType.toLowerCase().contains('quest') ||
          r.entityType.toLowerCase().contains('research'),
    ),
    isEmpty,
  );
}
