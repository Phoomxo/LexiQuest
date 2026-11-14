import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_motivation_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/timezone_policy.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_progress_reader.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';

final _at = DateTime.utc(2026, 10, 20, 12);
final _boundary = DateTime.utc(2026, 10, 26);
final _rejected = throwsA(anyOf(isA<StateError>(), isA<ArgumentError>()));

void main() {
  setUpAll(tz.initializeTimeZones);

  test(
    'schedule preview is virtual UTC, owner-bound and never creates epochs',
    () async {
      final f = await _Fixture.memory();
      final before = await _snapshot(f.db);
      for (var i = 0; i < 2; i++) {
        final view = await f.repository.previewCalendarSchedule(
          ownerId: 'a',
          asOfUtc: _at,
        );
        expect(view.current.ruleId, 'calendar:utc-default:a');
        expect(view.current.ianaId, 'UTC');
        expect(view.current.effectiveUtcUs, 1000000);
        expect(view.pending, isNull);
      }
      expect(await _snapshot(f.db), before);
    },
  );

  test(
    'explicit UTC setting persists the default once without a second epoch',
    () async {
      final f = await _Fixture.memory(installCatalog: false);
      final rule = await f.select('UTC');
      expect(rule.ruleId, 'calendar:utc-default:a');
      expect(rule.effectiveUtcUs, 1000000);
      expect(rule.expiresUtcUs, isNull);
      expect(await f.db.select(f.db.ownerCalendarEpochs).get(), hasLength(1));
      final before = await _snapshot(f.db);
      final again = await f.select('UTC');
      expect(_identity(again), _identity(rule));
      expect(await _snapshot(f.db), before);
      await _expectNoQuestOrResearch(f.db);
    },
  );

  test(
    'inactive retained guest epoch never selects the target home calendar',
    () async {
      final f = await _Fixture.memory();
      await _epoch(
        f.db,
        id: 'calendar:utc-default:b',
        zone: 'Europe/London',
        origin: 'b',
        selected: false,
      );
      final guest = (await f.db.select(f.db.ownerCalendarEpochs).getSingle())
          .toJson();
      final chosen = await f.select('Asia/Bangkok');
      expect(
        (chosen.originOwnerId, chosen.effectiveUtcUs),
        ('a', _boundary.microsecondsSinceEpoch),
      );
      final rows = await f.db.select(f.db.ownerCalendarEpochs).get();
      expect(rows, hasLength(3));
      expect(rows.singleWhere((r) => r.originOwnerId == 'b').toJson(), guest);
      expect(
        rows.where((r) => r.isSelected).every((r) => r.originOwnerId == 'a'),
        isTrue,
      );
      final preview = await f.repository.previewCalendarSchedule(
        ownerId: 'a',
        asOfUtc: _at,
      );
      expect(preview.current.ianaId, 'UTC');
      expect(preview.pending!.ruleId, chosen.ruleId);
    },
  );

  test(
    'UTC to Bangkok is prospective and fresh-zone first day and week are clipped',
    () async {
      final f = await _Fixture.memory(installCatalog: false);
      await f.answer('before', _at, questEnabled: false);
      final before = await _snapshotExceptEpochs(f.db);
      final oldAnswer = await _answer(f.db, 'before');
      final oldStamp =
          decodeCalendarEvidence(oldAnswer.calendarEvidence!)
              as CapturedCalendarEvidence;
      final selected = await f.select('Asia/Bangkok');
      expect(
        (
          selected.originOwnerId,
          selected.ianaId,
          selected.tzdbRevision,
          selected.effectiveUtcUs,
        ),
        (
          'a',
          'Asia/Bangkok',
          bundledTzdbRevision,
          _boundary.microsecondsSinceEpoch,
        ),
      );
      final old = await f.repository.calendarRuleAt(
        ownerId: 'a',
        occurredAtUtcMs: _at.millisecondsSinceEpoch,
      );
      expect(
        (old.ruleId, old.ianaId, old.expiresUtcUs),
        (oldStamp.rule.ruleId, 'UTC', _boundary.microsecondsSinceEpoch),
      );
      expect(await _snapshotExceptEpochs(f.db), before);
      final previewRows = await _snapshot(f.db);
      final view = await f.repository.previewCalendarSchedule(
        ownerId: 'a',
        asOfUtc: _at,
      );
      expect(
        (view.current.ianaId, view.pending!.ruleId),
        ('UTC', selected.ruleId),
      );
      expect(await _snapshot(f.db), previewRows);
      await f.answer(
        'last-old',
        _boundary.subtract(const Duration(milliseconds: 1)),
        questEnabled: false,
      );
      await f.answer('first-new', _boundary, questEnabled: false);
      final last =
          decodeCalendarEvidence(
                (await _answer(f.db, 'last-old')).calendarEvidence!,
              )
              as CapturedCalendarEvidence;
      final next =
          decodeCalendarEvidence(
                (await _answer(f.db, 'first-new')).calendarEvidence!,
              )
              as CapturedCalendarEvidence;
      expect(last.rule.ruleId, old.ruleId);
      expect(last.weekSegments.last.$2, _boundary.microsecondsSinceEpoch);
      expect(next.rule.ruleId, selected.ruleId);
      expect((next.civilDay, next.weekMonday), ('2026-10-26', '2026-10-26'));
      expect(next.daySegments.first.$1, _boundary.microsecondsSinceEpoch);
      expect(next.weekSegments.first.$1, _boundary.microsecondsSinceEpoch);
      expect(
        next.daySegments.last.$2,
        DateTime.utc(2026, 10, 26, 17).microsecondsSinceEpoch,
      );
      expect((await _answer(f.db, 'before')).toJson(), oldAnswer.toJson());
      await f.answer('before', _at, questEnabled: false);
      expect((await _answer(f.db, 'before')).toJson(), oldAnswer.toJson());
      await _expectNoQuestOrResearch(f.db);
    },
  );

  test(
    'same desired retry is unchanged and an unused pending zone replaces the same slot',
    () async {
      final f = await _Fixture.memory();
      final first = await f.select('Asia/Bangkok');
      final snapshot = await _snapshot(f.db);
      expect(_identity(await f.select('Asia/Bangkok')), _identity(first));
      expect(await _snapshot(f.db), snapshot);
      final changed = await f.select('America/New_York');
      expect(changed.ruleId, first.ruleId);
      expect(changed.effectiveUtcUs, first.effectiveUtcUs);
      expect(changed.ianaId, 'America/New_York');
      final rows = await f.db.select(f.db.ownerCalendarEpochs).get();
      expect(rows, hasLength(2));
      expect(
        rows.where((r) => r.effectiveUtcUs == first.effectiveUtcUs),
        hasLength(1),
      );
      expect(
        rows
            .singleWhere((r) => r.ruleId == 'calendar:utc-default:a')
            .expiresUtcUs,
        first.effectiveUtcUs,
      );
      final beforePreview = await _snapshot(f.db);
      final view = await f.repository.previewCalendarSchedule(
        ownerId: 'a',
        asOfUtc: _at,
      );
      expect(view.pending!.ianaId, 'America/New_York');
      expect(await _snapshot(f.db), beforePreview);
    },
  );

  test(
    'requesting current IANA replaces unused pending without unexpiring captured authority',
    () async {
      final f = await _Fixture.memory();
      final pending = await f.select('Asia/Bangkok');
      await f.answer('finite', _at);
      final original = await _answer(f.db, 'finite');
      final desired = await f.select('UTC');
      expect(
        (desired.ruleId, desired.effectiveUtcUs, desired.ianaId),
        (pending.ruleId, pending.effectiveUtcUs, 'UTC'),
      );
      final old = await f.repository.calendarRuleAt(
        ownerId: 'a',
        occurredAtUtcMs: _at.millisecondsSinceEpoch,
      );
      expect(old.expiresUtcUs, _boundary.microsecondsSinceEpoch);
      expect((await _answer(f.db, 'finite')).toJson(), original.toJson());
      final rows = await f.db.select(f.db.ownerCalendarEpochs).get();
      expect(rows, hasLength(2));
    },
  );

  for (final pendingEvidence in [false, true]) {
    test(
      'referenced pending epoch cannot be replaced, unavailable capture=$pendingEvidence',
      () async {
        final f = await _Fixture.memory();
        final pending = await f.select('Asia/Bangkok');
        await f.answer(
          'future-pending',
          _boundary.add(const Duration(seconds: 1)),
          unavailableCapture: pendingEvidence,
        );
        final attempt = await _answer(f.db, 'future-pending');
        if (pendingEvidence) {
          expect(
            decodeQuestIntent(attempt.questIntent!),
            isA<PendingQuestIntent>(),
          );
        }
        final before = await _snapshot(f.db);
        await expectLater(f.select('America/New_York'), _rejected);
        expect(await _snapshot(f.db), before);
        expect(
          (await f.db.select(f.db.ownerCalendarEpochs).get())
              .singleWhere((r) => r.ruleId == pending.ruleId)
              .ianaId,
          'Asia/Bangkok',
        );
      },
    );
  }

  test(
    'future captured week crossing cutover refuses selection and preserves original bytes',
    () async {
      final f = await _Fixture.memory();
      await f.answer(
        'future-original',
        _boundary.add(const Duration(hours: 12)),
      );
      final original = await _answer(f.db, 'future-original');
      final captured =
          decodeCalendarEvidence(original.calendarEvidence!)
              as CapturedCalendarEvidence;
      expect(
        captured.weekSegments.last.$2,
        greaterThan(_boundary.microsecondsSinceEpoch),
      );
      final before = await _snapshot(f.db);
      await expectLater(f.select('Asia/Bangkok'), _rejected);
      expect(await _snapshot(f.db), before);
      expect(
        (await _answer(f.db, 'future-original')).toJson(),
        original.toJson(),
      );
    },
  );

  test(
    'paid captured week remains byte-identical and its receipt validates after safe scheduling',
    () async {
      final f = await _Fixture.memory();
      for (var i = 0; i < 5; i++) {
        await f.answer('paid-$i', _at.add(Duration(seconds: i)));
      }
      final original = await _answer(f.db, 'paid-0');
      final period =
          (decodeQuestIntent(original.questIntent!) as CapturedQuestIntent)
              .dailyPeriodId;
      final receipt = await DriftRewardRepository(
        f.db,
        questCatalog: f.catalog,
        questVisible: () => true,
        nowUtc: () => _at.add(const Duration(minutes: 1)),
      ).claimQuest(expectedOwnerId: 'a', instanceId: period);
      final before = await _snapshotExceptEpochs(f.db);
      await f.select('Asia/Bangkok', at: _at.add(const Duration(minutes: 2)));
      expect(await _snapshotExceptEpochs(f.db), before);
      final verified = await DriftQuestProgressReader(
        f.db,
        catalog: f.catalog,
      ).validatedReceipts(ownerId: 'a');
      expect(verified.single.id, receipt.receiptId);
      expect((await _answer(f.db, 'paid-0')).toJson(), original.toJson());
    },
  );

  for (final sample in [
    (
      'Asia/Bangkok',
      DateTime.utc(2026, 8, 2, 9),
      DateTime.utc(2026, 8, 2, 17),
      'America/New_York',
    ),
    (
      'America/New_York',
      DateTime.utc(2026, 3, 8, 12),
      DateTime.utc(2026, 3, 9, 4),
      'Asia/Bangkok',
    ),
    (
      'America/New_York',
      DateTime.utc(2026, 11, 1, 12),
      DateTime.utc(2026, 11, 2, 5),
      'Asia/Bangkok',
    ),
  ]) {
    test(
      'travel/DST cutover follows LAST old-zone week end: ${sample.$1} ${sample.$2}',
      () async {
        final f = await _Fixture.memory();
        await _epoch(f.db, id: 'synthetic-home', zone: sample.$1);
        final selected = await f.select(sample.$4, at: sample.$2);
        expect(selected.effectiveUtcUs, sample.$3.microsecondsSinceEpoch);
        final last = await f.repository.calendarRuleAt(
          ownerId: 'a',
          occurredAtUtcMs: sample.$3
              .subtract(const Duration(milliseconds: 1))
              .millisecondsSinceEpoch,
        );
        final next = await f.repository.calendarRuleAt(
          ownerId: 'a',
          occurredAtUtcMs: sample.$3.millisecondsSinceEpoch,
        );
        expect(
          (last.ianaId, last.expiresUtcUs),
          (sample.$1, sample.$3.microsecondsSinceEpoch),
        );
        expect((next.ruleId, next.ianaId), (selected.ruleId, sample.$4));
        final clip = TimezonePolicy.captureWindow(
          sample.$3,
          next.ianaId,
          epochEffectiveAtUtc: sample.$3,
        );
        expect(clip.daySegments.first.startUtc, sample.$3);
        expect(clip.weekSegments.first.startUtc, sample.$3);
      },
    );
  }

  test(
    'St Johns returning Saturday fragments never shorten the selected week cutover',
    () async {
      final f = await _Fixture.memory();
      await _epoch(f.db, id: 'synthetic-st-johns', zone: 'America/St_Johns');
      final ends = DateTime.utc(2009, 11, 2, 3, 30);
      OwnerCalendarRule? selected;
      for (final instant in [
        DateTime.utc(2009, 11, 1, 2, 30),
        DateTime.utc(2009, 11, 1, 2, 31),
        DateTime.utc(2009, 11, 1, 3, 30),
      ]) {
        await f.answer('st-johns-${instant.millisecondsSinceEpoch}', instant);
        final again = await f.select('Asia/Bangkok', at: instant);
        expect(again.effectiveUtcUs, ends.microsecondsSinceEpoch);
        if (selected != null) expect(_identity(again), _identity(selected));
        selected = again;
      }
      final answers = await f.db.select(f.db.answerAttempts).get();
      final days = answers
          .map(
            (r) =>
                (decodeCalendarEvidence(r.calendarEvidence!)
                        as CapturedCalendarEvidence)
                    .civilDay,
          )
          .toList();
      expect(days, ['2009-11-01', '2009-10-31', '2009-11-01']);
      expect(await f.db.select(f.db.ownerCalendarEpochs).get(), hasLength(2));
    },
  );

  for (final failure in [
    'default-deny',
    'hidden',
    'stale owner',
    'two active',
    'unknown zone',
    'local time',
    'old bundle',
    'wrong origin',
    'overlap',
    'retired',
  ]) {
    test('selection fails closed with no mutation: $failure', () async {
      final f = await _Fixture.memory();
      var repository = f.repository;
      var owner = 'a';
      var zone = 'Asia/Bangkok';
      var at = _at;
      switch (failure) {
        case 'default-deny':
          repository = DriftStreakRepository(f.db);
        case 'hidden':
          repository = DriftStreakRepository(
            f.db,
            calendarVisible: () => false,
          );
        case 'stale owner':
          owner = 'b';
        case 'two active':
          await f.db.customStatement("UPDATE local_owners SET is_active=1");
        case 'unknown zone':
          zone = 'Invalid/Not_An_IANA_Zone';
        case 'local time':
          at = DateTime(2026, 10, 20, 12);
        case 'old bundle':
          await _epoch(
            f.db,
            id: 'unsupported-bundle',
            zone: 'UTC',
            revision: 'synthetic-unavailable-tzdb',
          );
        case 'wrong origin':
          await _epoch(f.db, id: 'wrong-origin', zone: 'UTC', origin: 'b');
        case 'overlap':
          await _epoch(f.db, id: 'left', zone: 'UTC');
          await _epoch(f.db, id: 'right', zone: 'UTC', effectiveUs: 2000000);
        case 'retired':
          await _epoch(f.db, id: 'retired', zone: 'UTC', selected: false);
      }
      final before = await _snapshot(f.db);
      await expectLater(
        repository.selectHomeTimezone(
          expectedOwnerId: owner,
          ianaId: zone,
          occurredAtUtc: at,
        ),
        _rejected,
      );
      expect(await _snapshot(f.db), before);
    });
  }

  test(
    'trigger failure rolls back default installation and future scheduling together',
    () async {
      final f = await _Fixture.memory();
      await f.db.customStatement(
        "CREATE TRIGGER synthetic_pending_failure BEFORE INSERT ON owner_calendar_epochs WHEN NEW.effective_utc_us > 1000000 BEGIN SELECT RAISE(ABORT,'synthetic schedule failure'); END",
      );
      final before = await _snapshot(f.db);
      await expectLater(f.select('Asia/Bangkok'), throwsA(isA<Exception>()));
      expect(await _snapshot(f.db), before);
      await f.db.customStatement('DROP TRIGGER synthetic_pending_failure');
      expect((await f.select('Asia/Bangkok')).ianaId, 'Asia/Bangkok');
    },
  );

  test(
    'file reopen and independent connections retry the same desired slot without duplication',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'synthetic-home-calendar-',
      );
      final file = File('${directory.path}/calendar.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      AppDatabase? other;
      try {
        final f = await _Fixture.create(db);
        final first = await f.select('Asia/Bangkok');
        final initial = await _snapshot(db);
        await db.close();
        db = AppDatabase(NativeDatabase(file));
        other = AppDatabase(NativeDatabase(file));
        final one = DriftStreakRepository(db, calendarVisible: () => true);
        final two = DriftStreakRepository(other, calendarVisible: () => true);
        final results = await Future.wait([
          one.selectHomeTimezone(
            expectedOwnerId: 'a',
            ianaId: 'Asia/Bangkok',
            occurredAtUtc: _at,
          ),
          two.selectHomeTimezone(
            expectedOwnerId: 'a',
            ianaId: 'Asia/Bangkok',
            occurredAtUtc: _at,
          ),
        ]);
        expect(results.map(_identity), everyElement(_identity(first)));
        expect(await _snapshot(db), initial);
        final active = await one.selectHomeTimezone(
          expectedOwnerId: 'a',
          ianaId: 'Asia/Bangkok',
          occurredAtUtc: _boundary.add(const Duration(hours: 1)),
        );
        expect(_identity(active), _identity(first));
        expect(await _snapshot(db), initial);
        final beforeView = await _snapshot(db);
        final view = await one.previewCalendarSchedule(
          ownerId: 'a',
          asOfUtc: _boundary,
        );
        expect((view.current.ruleId, view.pending), (first.ruleId, null));
        expect(await _snapshot(db), beforeView);
        expect(
          await db.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await other?.close();
        await db.close();
        final temp = Directory.systemTemp.absolute.path;
        expect(
          directory.absolute.path.startsWith('$temp${Platform.pathSeparator}'),
          isTrue,
        );
        await directory.delete(recursive: true);
      }
    },
  );
}

final class _Fixture {
  _Fixture(this.db, this.catalog);
  final AppDatabase db;
  final TrustedQuestAnswerCatalog? catalog;
  DriftStreakRepository get repository =>
      DriftStreakRepository(db, calendarVisible: () => true);

  static Future<_Fixture> memory({bool installCatalog = true}) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return create(db, installCatalog: installCatalog);
  }

  static Future<_Fixture> create(
    AppDatabase db, {
    bool installCatalog = true,
  }) async {
    await db.customStatement(
      "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES ('a',1000,1),('b',1000,0)",
    );
    await db.customStatement(
      "INSERT INTO vocabulary_categories(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES ('category-a','a','Synthetic','synthetic',1000,1000)",
    );
    await db.customStatement(
      "INSERT INTO vocabulary_words(id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) VALUES ('word-a','a','category-a','synthetic','synthetic','test','test','noun',1000,1000)",
    );
    await db.customStatement(
      "INSERT INTO learning_sessions(id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) VALUES ('session-a','a','quiz','active',1000,'synthetic','synthetic')",
    );
    return _Fixture(
      db,
      installCatalog
          ? await DriftQuestRepository(db).installAnswerCatalog()
          : null,
    );
  }

  Future<OwnerCalendarRule> select(String zone, {DateTime? at}) =>
      repository.selectHomeTimezone(
        expectedOwnerId: 'a',
        ianaId: zone,
        occurredAtUtc: at ?? _at,
      );

  Future<void> answer(
    String id,
    DateTime at, {
    bool questEnabled = true,
    bool unavailableCapture = false,
  }) =>
      DriftLearningRepository(
            db,
            questCatalog: catalog,
            questVisible: () => questEnabled,
            captureCalendarWindow: unavailableCapture
                ? _unavailable
                : TimezonePolicy.captureWindow,
          )
          .recordAnswer(
            RecordAnswerCommand(
              id: id,
              ownerId: 'a',
              sessionId: 'session-a',
              wordId: 'word-a',
              promptMode: 'meaningChoice',
              isCorrect: true,
              responseTimeMs: 100,
              attemptNumber: 1,
              occurredAtUtc: at,
            ),
          )
          .then((_) {});
}

LearningCalendarWindow _unavailable(
  DateTime instant,
  String zone, {
  DateTime? epochEffectiveAtUtc,
  DateTime? epochExpiresAtUtc,
}) => throw StateError('synthetic unavailable calendar after known rule');

Future<AnswerAttempt> _answer(AppDatabase db, String id) =>
    (db.select(db.answerAttempts)..where((r) => r.id.equals(id))).getSingle();

Object _identity(OwnerCalendarRule r) => (
  r.ruleId,
  r.originOwnerId,
  r.ianaId,
  r.tzdbRevision,
  r.effectiveUtcUs,
  r.expiresUtcUs,
);

Future<void> _epoch(
  AppDatabase db, {
  required String id,
  required String zone,
  String origin = 'a',
  int effectiveUs = 1000000,
  String revision = bundledTzdbRevision,
  bool selected = true,
}) => db.customStatement(
  'INSERT INTO owner_calendar_epochs(rule_id,owner_id,origin_owner_id,effective_utc_us,iana_id,tzdb_revision,is_selected) VALUES (?,?,?,?,?,?,?)',
  [id, 'a', origin, effectiveUs, zone, revision, selected ? 1 : 0],
);

Future<String> _snapshot(AppDatabase db) async {
  final names = db.allTables.map((t) => t.actualTableName).toList()..sort();
  return jsonEncode({
    for (final name in names)
      name: [
        for (final r
            in await db
                .customSelect('SELECT * FROM $name ORDER BY rowid')
                .get())
          r.data,
      ],
  });
}

Future<String> _snapshotExceptEpochs(AppDatabase db) async {
  final all = jsonDecode(await _snapshot(db)) as Map<String, dynamic>;
  all.remove('owner_calendar_epochs');
  return jsonEncode(all);
}

Future<void> _expectNoQuestOrResearch(AppDatabase db) async {
  for (final name in [
    'quest_definitions',
    'quest_definition_revisions',
    'quest_instances',
    'quest_objective_progress',
    'quest_claim_receipts',
    'events_v2',
    'research_consents',
  ]) {
    expect(
      await db.customSelect('SELECT * FROM $name').get(),
      isEmpty,
      reason: name,
    );
  }
}
