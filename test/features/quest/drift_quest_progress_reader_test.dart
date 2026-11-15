import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_motivation_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/motivation/domain/timezone_policy.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_progress_reader.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart'
    as quest;
import 'package:vocab_learning_app/features/quest/domain/quest_progress_models.dart';

void main() {
  late AppDatabase db;
  late TrustedQuestAnswerCatalog catalog;
  late DriftQuestProgressReader reader;
  final now = DateTime.utc(2027, 1, 5, 12);
  setUpAll(tz.initializeTimeZones);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    catalog = await DriftQuestRepository(db).installAnswerCatalog();
    reader = DriftQuestProgressReader(db, catalog: catalog);
    await _owner(db, 'A', active: true);
  });
  tearDown(() => db.close());

  Future<RecordAnswerCommand> answer(
    String owner,
    String id,
    DateTime at, {
    bool correct = true,
    bool visible = true,
    bool pending = false,
  }) async {
    final cmd = RecordAnswerCommand(
      id: id,
      ownerId: owner,
      sessionId: 's-$owner',
      wordId: 'w-$owner',
      promptMode: 'meaningChoice',
      isCorrect: correct,
      responseTimeMs: 100,
      attemptNumber: 1,
      occurredAtUtc: at,
    );
    final learning = DriftLearningRepository(
      db,
      questCatalog: catalog,
      questVisible: () => visible,
      captureCalendarWindow: pending
          ? _unavailable
          : TimezonePolicy.captureWindow,
    );
    await learning.recordAnswer(cmd);
    return cmd;
  }

  Future<QuestSummary> load(DateTime asOf, {String owner = 'A'}) =>
      reader.load(ownerId: owner, asOfUtc: asOf);
  QuestProgressCard card(QuestSummary summary, quest.QuestType cadence) =>
      summary.current.singleWhere((c) => c.cadence == cadence);

  test(
    'empty current periods are virtual, with stable IDs and no mutations',
    () async {
      final before = await _snapshot(db);
      final summary = await load(now);
      expect(summary.history, isEmpty);
      expect(summary.issues, isEmpty);
      final daily = card(summary, quest.QuestType.daily),
          weekly = card(summary, quest.QuestType.weekly);
      expect(
        (daily.targetCount, daily.xpAmount, daily.correctCount),
        (5, 50, 0),
      );
      expect(
        (weekly.targetCount, weekly.xpAmount, weekly.correctCount),
        (20, 200, 0),
      );
      expect(daily.state, QuestProgressState.active);
      expect(daily.civilLabel, '2027-01-05');
      expect(weekly.civilLabel, '2027-01-04');
      expect(daily.lastEndUtc, DateTime.utc(2027, 1, 6));
      expect(
        card(await load(now), quest.QuestType.daily).instanceId,
        daily.instanceId,
      );
      await expectLater(
        reader.qualify(
          ownerId: 'A',
          instanceId: daily.instanceId,
          asOfUtc: now,
        ),
        throwsStateError,
      );
      expect(await reader.validatedReceipts(ownerId: 'A'), isEmpty);
      expect(await _snapshot(db), before);
    },
  );

  test(
    'distinct correct facts determine completion independent of replay and word deletion',
    () async {
      await answer('A', 'wrong', now, correct: false);
      for (final id in ['e', 'd', 'c', 'b']) {
        await answer('A', id, now);
      }
      await answer('A', 'd', now);
      final last = now.add(const Duration(milliseconds: 1));
      await answer('A', 'f', last);
      await answer('A', 'later', last.add(const Duration(seconds: 1)));
      await db.customStatement(
        "UPDATE vocabulary_words SET is_deleted=1 WHERE owner_id='A'",
      );
      final before = await _snapshot(db);
      expect(card(await load(now), quest.QuestType.daily).correctCount, 4);
      final summary = await load(last);
      final daily = card(summary, quest.QuestType.daily);
      expect(daily.state, QuestProgressState.completedUnclaimed);
      expect(daily.completedAtUtc, last);
      expect(card(summary, quest.QuestType.weekly).correctCount, 5);
      final qualified = await reader.qualify(
        ownerId: 'A',
        instanceId: daily.instanceId,
        asOfUtc: last,
      );
      expect(qualified.completedAtUtcMs, last.millisecondsSinceEpoch);
      expect(qualified.receipts, isEmpty);
      expect(qualified.xpAmount, 50);
      final later = await load(DateTime.utc(2027, 1, 6));
      final history = later.history.singleWhere(
        (c) => c.instanceId == daily.instanceId,
      );
      expect(
        (history.state, history.completedAtUtc),
        (QuestProgressState.completedUnclaimed, last),
      );
      expect(await _snapshot(db), before);
    },
  );

  test('segment gaps do not expire returning St Johns Saturday', () async {
    await _rule(db, 'A', 'America/St_Johns');
    final a = DateTime.utc(2009, 11, 1, 2, 29);
    final gap = DateTime.utc(2009, 11, 1, 2, 30);
    final back = DateTime.utc(2009, 11, 1, 3);
    await answer('A', 'sat1', a);
    await answer('A', 'sun', gap);
    await answer('A', 'sat2', back);
    final first = card(await load(a), quest.QuestType.daily);
    final interim = await load(gap);
    expect(card(interim, quest.QuestType.daily).civilLabel, '2009-11-01');
    final saturday = interim.history.singleWhere(
      (c) => c.instanceId == first.instanceId,
    );
    expect(
      (saturday.state, saturday.correctCount),
      (QuestProgressState.active, 1),
    );
    final returned = card(await load(back), quest.QuestType.daily);
    expect((returned.instanceId, returned.correctCount), (first.instanceId, 2));
    expect(returned.lastEndUtc, DateTime.utc(2009, 11, 1, 3, 30));
    final closed = await load(DateTime.utc(2009, 11, 1, 3, 30));
    expect(
      closed.history.singleWhere((c) => c.instanceId == first.instanceId).state,
      QuestProgressState.expired,
    );
  });

  test(
    'repair uses original rule and archived pins while NULL eligibility stays NULL',
    () async {
      for (var i = 0; i < 5; i++) {
        await answer('A', 'pending-$i', now, pending: true);
      }
      await answer('A', 'hidden', now, visible: false);
      final rows = await db.select(db.answerAttempts).get();
      expect(
        decodeQuestIntent(
          rows.firstWhere((r) => r.id == 'pending-0').questIntent!,
        ),
        isA<PendingQuestIntent>(),
      );
      await db.customStatement(
        "UPDATE owner_calendar_epochs SET is_selected=0 WHERE owner_id='A'",
      );
      await _rule(
        db,
        'A',
        'Asia/Bangkok',
        startUs: now.add(const Duration(days: 1)).microsecondsSinceEpoch,
      );
      final before = await _snapshot(db);
      final asOf = now.add(const Duration(days: 2));
      final summary = await load(asOf);
      final historical = summary.history.singleWhere(
        (r) => r.cadence == quest.QuestType.daily,
      );
      expect(
        (historical.correctCount, historical.state),
        (5, QuestProgressState.completedUnclaimed),
      );
      final proof = await reader.qualify(
        ownerId: 'A',
        instanceId: historical.instanceId,
        asOfUtc: asOf,
      );
      expect(proof.calendarRuleId, 'calendar:utc-default:A');
      expect(await _snapshot(db), before);
    },
  );

  test('archive body substitution makes affected card unclaimable', () async {
    for (var i = 0; i < 5; i++) {
      await answer('A', 'p-$i', now);
    }
    final paidCandidate = card(await load(now), quest.QuestType.daily);
    await db.customStatement(
      "UPDATE quest_definition_revisions SET canonical_definition='{}' WHERE quest_id=?",
      [
        (await reader.qualify(
          ownerId: 'A',
          instanceId: paidCandidate.instanceId,
          asOfUtc: now,
        )).pin.questId,
      ],
    );
    final damaged = await load(now);
    expect(
      damaged.current.where(
        (r) =>
            r.cadence == quest.QuestType.daily &&
            r.state == QuestProgressState.completedUnclaimed,
      ),
      isEmpty,
    );
    expect(card(damaged, quest.QuestType.weekly).correctCount, 5);
    await expectLater(
      reader.qualify(
        ownerId: 'A',
        instanceId: paidCandidate.instanceId,
        asOfUtc: now,
      ),
      throwsStateError,
    );
  });

  test(
    '3 plus 2 across merged owners qualifies both original IDs without materializing an instance',
    () async {
      await _owner(db, 'B', active: false);
      for (var i = 0; i < 3; i++) {
        await answer('A', 'a-$i', now);
      }
      await _active(db, 'B');
      for (var i = 0; i < 2; i++) {
        await answer('B', 'b-$i', now);
      }
      await _active(db, 'A');
      await _merge(db, now);
      final row = (await db.select(db.answerAttempts).get()).singleWhere(
        (r) => r.id == 'a-0',
      );
      final original =
          decodeQuestIntent(row.questIntent!) as CapturedQuestIntent;
      final before = await _snapshot(db);
      final daily = card(await load(now, owner: 'B'), quest.QuestType.daily);
      expect(
        (daily.state, daily.correctCount),
        (QuestProgressState.completedUnclaimed, 5),
      );
      final joined = await reader.qualify(
        ownerId: 'B',
        instanceId: original.dailyPeriodId,
        asOfUtc: now,
      );
      expect(joined.instanceId, daily.instanceId);
      expect(joined.originOwnerId, 'B');
      expect(joined.members.map((m) => m.originOwnerId).toSet(), {'A', 'B'});
      expect(joined.receipts, isEmpty);
      expect(await db.select(db.questInstances).get(), isEmpty);
      expect(await _snapshot(db), before);
    },
  );

  test('one guest period straddling two target days is a conflict', () async {
    await _owner(db, 'B', active: false);
    await _rule(db, 'B', 'Asia/Bangkok');
    final late = DateTime.utc(2027, 1, 5, 18);
    for (var i = 0; i < 3; i++) {
      await answer('A', 'a-$i', now);
    }
    await _active(db, 'B');
    await answer('B', 'b1', now);
    await answer('B', 'b2', late);
    await _active(db, 'A');
    await _merge(db, late);
    final summary = await load(late, owner: 'B');
    final daily = [
      ...summary.current,
      ...summary.history,
    ].where((c) => c.cadence == quest.QuestType.daily);
    expect(daily, isNotEmpty);
    expect(daily.every((r) => r.state == QuestProgressState.conflict), isTrue);
    for (final c in daily) {
      await expectLater(
        reader.qualify(ownerId: 'B', instanceId: c.instanceId, asOfUtc: late),
        throwsStateError,
      );
    }
  });

  test(
    'two already-paid originals survive a merge and late evidence without a third grant',
    () async {
      await _owner(db, 'B', active: false);
      final paid = <String>{};
      final issued = now.add(const Duration(minutes: 1));
      for (final owner in ['A', 'B']) {
        await _active(db, owner);
        for (var i = 0; i < 5; i++) {
          await answer(owner, '$owner-$i', now);
        }
        final daily = card(
          await load(now, owner: owner),
          quest.QuestType.daily,
        );
        final result = await reader.qualify(
          ownerId: owner,
          instanceId: daily.instanceId,
          asOfUtc: issued,
        );
        await _persistIssuedProof(db, owner, result, issued);
        paid.add(result.receiptId);
        await answer(
          owner,
          'late-$owner',
          now.subtract(const Duration(minutes: 5)),
        );
      }
      await _active(db, 'A');
      await _merge(db, issued);
      final before = await _snapshot(db);
      final daily = card(await load(issued, owner: 'B'), quest.QuestType.daily);
      expect(daily.state, QuestProgressState.claimed);
      expect(daily.receiptIds.toSet(), paid);
      final receipts = await reader.validatedReceipts(ownerId: 'B');
      expect(receipts.map((r) => r.id).toSet(), paid);
      expect(receipts.map((r) => r.originOwnerId).toSet(), {'A', 'B'});
      expect(
        receipts.every(
          (r) =>
              r.completedAtUtcMs == now.millisecondsSinceEpoch &&
              r.issuedAtUtcMs == issued.millisecondsSinceEpoch &&
              r.xpAmount == 50,
        ),
        isTrue,
      );
      final replay = await reader.qualify(
        ownerId: 'B',
        instanceId: daily.instanceId,
        asOfUtc: issued,
      );
      expect(replay.receipts.map((r) => r.id).toSet(), paid);
      expect(await _snapshot(db), before);
      await db.customStatement(
        'UPDATE quest_claim_receipts SET xp_amount=500 WHERE id=?',
        [paid.first],
      );
      await expectLater(
        reader.validatedReceipts(ownerId: 'B'),
        throwsStateError,
      );
    },
  );
}

Future<void> _persistIssuedProof(
  AppDatabase db,
  String owner,
  QualifiedQuestPeriod p,
  DateTime issued,
) async {
  await db.customStatement(
    "INSERT OR IGNORE INTO quest_definitions(quest_id,catalog_version,title,description,type,objectives_json,reward_json) VALUES(?,1,'synthetic','synthetic','daily','[]','{}')",
    [p.pin.questId],
  );
  await db.customStatement(
    "INSERT INTO quest_instances(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,completed_at_utc_ms,origin_owner_id,period_key,calendar_rule_id,civil_label,segments_json,definition_digest,record_kind) VALUES(?,?,?,?,?,'completed',?,?,?,?,?,?,?,'canonical')",
    [
      p.instanceId,
      p.pin.questId,
      owner,
      p.pin.catalogVersion,
      p.assignedAtUtcMs,
      p.completedAtUtcMs,
      p.originOwnerId,
      p.periodKey,
      p.calendarRuleId,
      p.civilLabel,
      p.segmentsJson,
      p.pin.definitionDigest,
    ],
  );
  await db.customStatement(
    'INSERT INTO quest_claim_receipts(id,owner_id,origin_owner_id,instance_id,issued_at_utc_ms,completed_at_utc_ms,xp_amount,evidence_json) VALUES(?,?,?,?,?,?,?,?)',
    [
      p.receiptId,
      owner,
      p.originOwnerId,
      p.instanceId,
      issued.millisecondsSinceEpoch,
      p.completedAtUtcMs,
      p.xpAmount,
      p.evidenceJson,
    ],
  );
}

Future<void> _owner(AppDatabase db, String id, {required bool active}) async {
  await db.customStatement(
    'INSERT INTO local_owners(id,created_at_utc_ms,is_active,firebase_uid) VALUES(?,0,?,?)',
    [id, active ? 1 : 0, id == 'B' ? 'uid-b' : null],
  );
  await db.customStatement(
    'INSERT INTO vocabulary_categories(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES(?,?,?,?,0,0)',
    ['c-$id', id, id, id],
  );
  await db.customStatement(
    "INSERT INTO vocabulary_words(id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) VALUES(?,?,?,?,?,?,?,'noun',0,0)",
    ['w-$id', id, 'c-$id', id, id, id, id],
  );
  await db.customStatement(
    "INSERT INTO learning_sessions(id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) VALUES(?,?,'quiz','active',0,'synthetic','test')",
    ['s-$id', id],
  );
}

Future<void> _active(AppDatabase db, String owner) =>
    db.customStatement('UPDATE local_owners SET is_active=(id=?)', [owner]);
Future<void> _rule(
  AppDatabase db,
  String owner,
  String zone, {
  int startUs = 0,
}) => db.customStatement(
  'INSERT INTO owner_calendar_epochs(rule_id,owner_id,origin_owner_id,effective_utc_us,iana_id,tzdb_revision,is_selected) VALUES(?,?,?,?,?,?,1)',
  ['rule-$owner-$zone', owner, owner, startUs, zone, bundledTzdbRevision],
);
Future<void> _merge(AppDatabase db, DateTime now) async {
  var seq = 0;
  await DriftOwnerUpgradeRepository(
    db,
    nowUtc: () => now,
    generateConflictId: () => 'case-${seq++}',
    generateOwnerId: () => 'unused',
  ).upgrade(activeOwnerId: 'A', firebaseUid: 'uid-b');
}

LearningCalendarWindow _unavailable(
  DateTime at,
  String zone, {
  DateTime? epochEffectiveAtUtc,
  DateTime? epochExpiresAtUtc,
}) => throw StateError('synthetic capture failure');
Future<Map<String, Object?>> _snapshot(AppDatabase db) async => {
  for (final t in [
    'answer_attempts',
    'owner_calendar_epochs',
    'quest_definitions',
    'quest_definition_revisions',
    'quest_instances',
    'quest_objective_progress',
    'quest_claim_receipts',
    'points_ledger_entries',
    'reward_transactions',
    'events_v2',
    'research_consents',
    'outbox_operations',
  ])
    t: [
      for (final r
          in await db.customSelect('SELECT * FROM $t ORDER BY rowid').get())
        r.data,
    ],
};
