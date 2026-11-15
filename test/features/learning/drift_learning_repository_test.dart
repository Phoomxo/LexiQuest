import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_motivation_evidence.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/motivation/domain/timezone_policy.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/quest/application/quest_catalog_provider.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart'
    as quest;
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart'
    as sync;
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  late AppDatabase database;
  late DriftLearningRepository repository;

  Future<void> seedVocabulary(AppDatabase database) async {
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-1',
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in const [
      ('word-1', 'station', 'สถานี'),
      ('word-2', 'ticket', 'ตั๋ว'),
    ]) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.$1,
              ownerId: 'owner-1',
              categoryId: 'category-1',
              spelling: word.$2,
              normalizedSpelling: word.$2,
              meaning: word.$3,
              normalizedMeaning: word.$3,
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
  }

  setUpAll(tz.initializeTimeZones);
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLearningRepository(database);
    await seedVocabulary(database);
  });

  tearDown(() => database.close());

  test('inactive learning owner cannot start a session', () async {
    await database.customUpdate(
      "UPDATE local_owners SET is_active=0 WHERE id='owner-1'",
    );
    await expectLater(
      _start(repository, DateTime.utc(2026, 11, 14)),
      throwsStateError,
    );
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  test(
    'inactive exact replay cannot repair projections after owner switch',
    () async {
      final at = DateTime.utc(2026, 11, 14);
      await _start(repository, at);
      final answer = _answer('synthetic-ack-retry', at);
      await repository.recordAnswer(answer);
      await database.delete(database.srsStates).go();
      await database.customUpdate(
        "UPDATE local_owners SET is_active=0 WHERE id='owner-1'",
      );
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'owner-2',
              createdAtUtcMs: at.millisecondsSinceEpoch,
            ),
          );
      await expectLater(repository.recordAnswer(answer), throwsStateError);
      expect(await database.select(database.srsStates).get(), isEmpty);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        hasLength(1),
      );
    },
  );

  test(
    'inactive learning owner cannot complete a session or unlock rewards',
    () async {
      final at = DateTime.utc(2026, 11, 14);
      await _start(repository, at);
      final session = await database
          .select(database.learningSessions)
          .getSingle();
      await database.customUpdate(
        "UPDATE local_owners SET is_active=0 WHERE id='owner-1'",
      );
      await expectLater(
        repository.finishSession(
          ownerId: 'owner-1',
          sessionId: session.id,
          endedAtUtc: at,
        ),
        throwsStateError,
      );
      expect(
        (await database.select(database.learningSessions).getSingle()).state,
        'active',
      );
      expect(await database.select(database.achievementUnlocks).get(), isEmpty);
    },
  );

  group('original local answer motivation evidence', () {
    final at = DateTime.utc(2027, 1, 5, 10);
    late TrustedQuestAnswerCatalog catalog;
    var visible = true;

    setUp(() async {
      visible = true;
      catalog = await DriftQuestRepository(database).installAnswerCatalog();
      repository = DriftLearningRepository(
        database,
        questCatalog: catalog,
        questVisible: () => visible,
      );
      await _start(repository, at);
    });

    test(
      'first commit pins the actual day, week and both archived digests',
      () async {
        await repository.recordAnswer(_answer('first', at));
        final row = await _read(database, 'first');
        final calendar =
            decodeCalendarEvidence(row.calendarEvidence!)
                as CapturedCalendarEvidence;
        final intent =
            decodeQuestIntent(row.questIntent!) as CapturedQuestIntent;
        expect(
          OriginalAnswerMetadata(calendar: calendar, quest: intent).quest,
          intent,
        );
        expect(
          (calendar.originOwnerId, calendar.occurredAtUtcMs),
          ('owner-1', at.millisecondsSinceEpoch),
        );
        expect(
          (
            calendar.rule.ruleId,
            calendar.rule.ianaId,
            calendar.rule.tzdbRevision,
          ),
          ('calendar:utc-default:owner-1', 'UTC', bundledTzdbRevision),
        );
        expect(
          (calendar.civilDay, calendar.weekMonday, calendar.offsetSeconds),
          ('2027-01-05', '2027-01-04', 0),
        );
        expect(calendar.daySegments, [
          (
            DateTime.utc(2027, 1, 5).microsecondsSinceEpoch,
            DateTime.utc(2027, 1, 6).microsecondsSinceEpoch,
          ),
        ]);
        expect(calendar.weekSegments, [
          (
            DateTime.utc(2027, 1, 4).microsecondsSinceEpoch,
            DateTime.utc(2027, 1, 11).microsecondsSinceEpoch,
          ),
        ]);
        final archive = await database
            .select(database.questDefinitionRevisions)
            .get();
        expect(archive, hasLength(2));
        for (final (pin, id) in [
          (intent.daily, QuestCatalogProvider.dailyCorrectAnswers.questId),
          (intent.weekly, QuestCatalogProvider.weeklyCorrectAnswers.questId),
        ]) {
          expect(pin.questId, id);
          final stored = archive.singleWhere((r) => r.questId == id);
          expect(
            (pin.catalogVersion, pin.definitionDigest),
            (stored.catalogVersion, stored.definitionDigest),
          );
        }
        await _expectOrdinaryCorrectAnswer(database, 'first');
      },
    );

    test(
      'enabling Quest affects only the next original answer in the same session',
      () async {
        visible = false;
        final hidden = _answer('hidden', at);
        await repository.recordAnswer(hidden);
        final before = await _read(database, hidden.id);
        expect(before.questIntent, isNull);
        visible = true;
        expect((await repository.recordAnswer(hidden)).inserted, isFalse);
        expect(await _read(database, hidden.id), before);
        await repository.recordAnswer(_answer('enabled', at));
        expect(
          decodeQuestIntent((await _read(database, 'enabled')).questIntent!),
          isA<CapturedQuestIntent>(),
        );
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(2),
        );
      },
    );

    test(
      'replay keeps original bytes after gate, catalog and selected zone change',
      () async {
        final first = _answer('stable', at);
        await repository.recordAnswer(first);
        final raw = await _read(database, first.id);
        expect(raw.questIntent, isNotNull);
        final updated = await _installDailyRevision(database, at);
        await database.customStatement(
          'UPDATE owner_calendar_epochs SET is_selected=0',
        );
        await _epoch(
          database,
          'new-rule',
          'Asia/Bangkok',
          at.microsecondsSinceEpoch,
          null,
        );
        var captures = 0, checks = 0;
        repository = DriftLearningRepository(
          database,
          questCatalog: updated,
          questVisible: () {
            checks++;
            return visible;
          },
          captureCalendarWindow:
              (time, zone, {epochEffectiveAtUtc, epochExpiresAtUtc}) {
                captures++;
                return TimezonePolicy.captureWindow(
                  time,
                  zone,
                  epochEffectiveAtUtc: epochEffectiveAtUtc,
                  epochExpiresAtUtc: epochExpiresAtUtc,
                );
              },
        );
        visible = false;
        expect((await repository.recordAnswer(first)).inserted, isFalse);
        expect(await _read(database, first.id), raw);
        expect((checks, captures), (0, 0));
        visible = true;
        await repository.recordAnswer(
          _answer('next', at.add(const Duration(days: 1))),
        );
        final next = await _read(database, 'next');
        final nextCalendar =
            decodeCalendarEvidence(next.calendarEvidence!)
                as CapturedCalendarEvidence;
        final pins =
            decodeQuestIntent(next.questIntent!) as CapturedQuestIntent;
        expect(nextCalendar.rule.ruleId, 'new-rule');
        expect((pins.daily.catalogVersion, pins.weekly.catalogVersion), (2, 1));
      },
    );

    test(
      'calendar uses stored millisecond at a sub-millisecond epoch boundary',
      () async {
        final boundary = at.microsecondsSinceEpoch + 500;
        await _epoch(database, 'before', 'UTC', 1000, boundary);
        await _epoch(database, 'after', 'Asia/Bangkok', boundary, null);
        await repository.recordAnswer(
          _answer('edge', at.add(const Duration(microseconds: 900))),
        );
        final row = await _read(database, 'edge');
        final c =
            decodeCalendarEvidence(row.calendarEvidence!)
                as CapturedCalendarEvidence;
        expect(row.occurredAtUtcMs, at.millisecondsSinceEpoch);
        expect(c.occurredAtUtcMs, row.occurredAtUtcMs);
        expect(c.rule.ruleId, 'before');
        expect(c.daySegments.single.$2, boundary);
        expect(c.weekSegments.single.$2, boundary);
        expect(
          (await repository.recordAnswer(
            _answer('edge', at.add(const Duration(microseconds: 100))),
          )).inserted,
          isFalse,
        );
        expect(await _read(database, 'edge'), row);
        await repository.recordAnswer(
          _answer('later', at.add(const Duration(milliseconds: 1))),
        );
        final next =
            decodeCalendarEvidence(
                  (await _read(database, 'later')).calendarEvidence!,
                )
                as CapturedCalendarEvidence;
        expect(next.rule.ruleId, 'after');
        expect(next.daySegments.single.$1, boundary);
      },
    );

    test(
      'inactive original owner cannot create a fact or select either owner calendar',
      () async {
        await database.customStatement(
          "UPDATE local_owners SET is_active=0 WHERE id='owner-1'",
        );
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 1),
            );
        await expectLater(
          repository.recordAnswer(_answer('stale', at)),
          throwsStateError,
        );
        for (final table in [
          'answer_attempts',
          'owner_calendar_epochs',
          'srs_states',
          'points_ledger_entries',
          'reward_transactions',
          'outbox_operations',
        ]) {
          expect(
            await database.customSelect('SELECT * FROM $table').get(),
            isEmpty,
            reason: table,
          );
        }
      },
    );

    test(
      'same-zone window for another day preserves learning with unavailable metadata',
      () async {
        repository = DriftLearningRepository(
          database,
          questCatalog: catalog,
          questVisible: () => true,
          captureCalendarWindow:
              (time, zone, {epochEffectiveAtUtc, epochExpiresAtUtc}) {
                expect(zone, 'UTC');
                return TimezonePolicy.captureWindow(
                  time.add(const Duration(days: 1)),
                  zone,
                  epochEffectiveAtUtc: epochEffectiveAtUtc,
                  epochExpiresAtUtc: epochExpiresAtUtc,
                );
              },
        );
        final result = await repository.recordAnswer(
          _answer('wrong-window', at),
        );
        expect(result.inserted, isTrue);
        await _expectOrdinaryCorrectAnswer(database, 'wrong-window');
        final row = await _read(database, 'wrong-window');
        expect(
          row.calendarEvidence,
          isNotNull,
          reason:
              'invalid optional capture must retain explicit unavailable state',
        );
        expect(
          row.questIntent,
          isNotNull,
          reason:
              'the original visible decision must not become hidden or legacy',
        );
        final calendar = decodeCalendarEvidence(row.calendarEvidence!);
        final intent = decodeQuestIntent(row.questIntent!);
        expect(calendar, isA<UnavailableCalendarEvidence>());
        expect(intent, isA<UnavailableQuestIntent>());
        expect(intent, isNot(isA<PendingQuestIntent>()));
        expect(
          (calendar.originOwnerId, calendar.occurredAtUtcMs),
          ('owner-1', at.millisecondsSinceEpoch),
        );
        expect(
          (intent.originOwnerId, intent.occurredAtUtcMs),
          ('owner-1', at.millisecondsSinceEpoch),
        );
        expect(
          OriginalAnswerMetadata(calendar: calendar, quest: intent).quest,
          intent,
        );
      },
    );

    test(
      'unavailable calendar saves original rule and two unambiguous pins with the answer',
      () async {
        repository = DriftLearningRepository(
          database,
          questCatalog: catalog,
          questVisible: () => true,
          captureCalendarWindow: _failedCapture,
        );
        await repository.recordAnswer(_answer('pending', at));
        final raw = await _read(database, 'pending');
        final c =
            decodeCalendarEvidence(raw.calendarEvidence!)
                as UnavailableCalendarEvidence;
        final q = decodeQuestIntent(raw.questIntent!) as PendingQuestIntent;
        final rule = await database
            .select(database.ownerCalendarEpochs)
            .getSingle();
        expect(
          (
            q.rule.ruleId,
            q.rule.originOwnerId,
            q.rule.effectiveUtcUs,
            q.rule.tzdbRevision,
          ),
          (
            rule.ruleId,
            rule.originOwnerId,
            rule.effectiveUtcUs,
            rule.tzdbRevision,
          ),
        );
        expect(
          (q.daily.questId, q.weekly.questId),
          (
            QuestCatalogProvider.dailyCorrectAnswers.questId,
            QuestCatalogProvider.weeklyCorrectAnswers.questId,
          ),
        );
        final pins = await database
            .select(database.questDefinitionRevisions)
            .get();
        for (final pin in [q.daily, q.weekly]) {
          final archive = pins.singleWhere((r) => r.questId == pin.questId);
          expect(
            (pin.catalogVersion, pin.definitionDigest),
            (archive.catalogVersion, archive.definitionDigest),
          );
        }
        expect(OriginalAnswerMetadata(calendar: c, quest: q).quest, q);
        await _expectOrdinaryCorrectAnswer(database, 'pending');
      },
    );

    test(
      'unavailable calendar and ambiguous revisions cannot become retryable',
      () async {
        final multiple = await _installDailyRevision(database, at);
        repository = DriftLearningRepository(
          database,
          questCatalog: multiple,
          questVisible: () => true,
          captureCalendarWindow: _failedCapture,
        );
        await repository.recordAnswer(_answer('unavailable', at));
        final row = await _read(database, 'unavailable');
        expect(
          decodeCalendarEvidence(row.calendarEvidence!),
          isA<UnavailableCalendarEvidence>(),
        );
        expect(
          decodeQuestIntent(row.questIntent!),
          isA<UnavailableQuestIntent>(),
        );
        await _expectOrdinaryCorrectAnswer(database, 'unavailable');
      },
    );

    test(
      'core SRS failure rolls back original answer, default epoch and learning writes',
      () async {
        await database.customStatement("""
        CREATE TRIGGER fail_srs BEFORE INSERT ON srs_states
        BEGIN SELECT RAISE(ABORT,'synthetic core SRS failure'); END
      """);
        final command = _answer('rollback', at);
        await expectLater(
          repository.recordAnswer(command),
          throwsA(
            predicate(
              (e) => e.toString().contains('synthetic core SRS failure'),
            ),
          ),
        );
        for (final table in [
          'answer_attempts',
          'srs_states',
          'owner_calendar_epochs',
          'points_ledger_entries',
          'reward_transactions',
          'outbox_operations',
        ]) {
          expect(
            await database.customSelect('SELECT * FROM $table').get(),
            isEmpty,
            reason: table,
          );
        }
        await database.customStatement('DROP TRIGGER fail_srs');
        expect((await repository.recordAnswer(command)).inserted, isTrue);
        expect(
          decodeQuestIntent((await _read(database, command.id)).questIntent!),
          isA<CapturedQuestIntent>(),
        );
      },
    );

    test(
      'reopen with no catalog replays the durable answer and original evidence once',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'lexiquest-answer-evidence-',
        );
        final originalDir = await dir.resolveSymbolicLinks();
        final file = File('${dir.path}/answer.sqlite');
        final command = _answer('committed', at);
        try {
          final writer = AppDatabase(NativeDatabase(file));
          late AnswerAttempt original;
          try {
            await seedVocabulary(writer);
            final installed = await DriftQuestRepository(
              writer,
            ).installAnswerCatalog();
            final repo = DriftLearningRepository(
              writer,
              questCatalog: installed,
              questVisible: () => true,
            );
            await _start(repo, at);
            await repo.recordAnswer(command);
            original = await _read(writer, command.id);
            expect(
              decodeQuestIntent(original.questIntent!),
              isA<CapturedQuestIntent>(),
            );
            expect(
              decodeCalendarEvidence(original.calendarEvidence!),
              isA<CapturedCalendarEvidence>(),
            );
          } finally {
            await writer.close();
          }
          final reader = AppDatabase(NativeDatabase(file));
          try {
            final replay = DriftLearningRepository(reader);
            expect((await replay.recordAnswer(command)).inserted, isFalse);
            expect(
              await reader.select(reader.answerAttempts).getSingle(),
              original,
            );
            await _expectOrdinaryCorrectAnswer(reader, command.id);
          } finally {
            await reader.close();
          }
        } finally {
          final resolved = Directory(await dir.resolveSymbolicLinks());
          final root = await Directory.systemTemp.resolveSymbolicLinks();
          expect(resolved.path, originalDir);
          expect(resolved.parent.path, root);
          expect(
            resolved.uri.pathSegments.where((p) => p.isNotEmpty).last,
            startsWith('lexiquest-answer-evidence-'),
          );
          await resolved.delete(recursive: true);
        }
      },
    );
  });

  group('immutable achievement evidence', () {
    final start = DateTime.utc(2026, 11, 14, 8);
    DateTime minute(int n) => start.add(Duration(minutes: n));

    Future<void> startRound(DriftLearningRepository repo, String id, int n) =>
        repo.startSession(
          LearningSessionDraft(
            id: id,
            ownerId: 'owner-1',
            activityType: 'quiz',
            startedAtUtc: minute(n),
            appVersion: 'test',
            buildId: 'synthetic',
          ),
        );

    RecordAnswerCommand answer(
      String id,
      String round,
      int n,
      int number, {
      bool correct = true,
    }) => RecordAnswerCommand(
      id: id,
      ownerId: 'owner-1',
      sessionId: round,
      wordId: 'word-1',
      promptMode: 'meaningChoice',
      isCorrect: correct,
      responseTimeMs: 200,
      attemptNumber: number,
      occurredAtUtc: minute(n),
    );

    Future<LearningSessionSummary> finish(
      DriftLearningRepository repo,
      String id,
      int n,
    ) => repo.finishSession(
      ownerId: 'owner-1',
      sessionId: id,
      endedAtUtc: minute(n),
    );

    Future<List<Map<String, Object?>>> badgeOps(AppDatabase db) async =>
        (await db
                .customSelect(
                  "SELECT * FROM outbox_operations WHERE entity_type='achievementUnlock' "
                  'ORDER BY operation_id',
                )
                .get())
            .map((row) => row.data)
            .toList();

    Future<void> expectRewards(AppDatabase db, Set<String> answerIds) async {
      final xp = await db.select(db.pointsLedgerEntries).get();
      final coins = await db.select(db.rewardTransactions).get();
      expect(
        xp.map((e) => (e.entryType, e.amount, e.sourceEventId)),
        unorderedEquals(answerIds.map((id) => ('quizCorrect', 1, id))),
      );
      expect(
        coins.map((e) => (e.transactionType, e.amount, e.sourceEventId)),
        unorderedEquals(answerIds.map((id) => ('creditQuizCorrectV1', 1, id))),
      );
    }

    test(
      'finishing an empty round grants no achievement or currency',
      () async {
        await startRound(repository, 'empty', 0);
        final result = await finish(repository, 'empty', 1);
        expect(
          (result.state, result.correctCount, result.wrongCount),
          ('completed', 0, 0),
        );
        await finish(repository, 'empty', 2);
        await DriftLearningProjectionRebuilder(
          database,
        ).rebuildAchievements('owner-1');
        expect(
          await database.select(database.achievementUnlocks).get(),
          isEmpty,
        );
        expect(await badgeOps(database), isEmpty);
        await expectRewards(database, {});
      },
    );

    test(
      'five badges use original facts and rounds once, including intentional retries',
      () async {
        await startRound(repository, 'mixed', 5);
        await repository.recordAnswer(
          answer('wrong', 'mixed', 6, 1, correct: false),
        );
        final retry = answer('retry', 'mixed', 7, 2);
        await repository.recordAnswer(retry);
        final mixed = await finish(repository, 'mixed', 8);
        expect((mixed.wrongCount, mixed.correctCount), (1, 1));
        expect(
          (await database.select(database.achievementUnlocks).get()).map(
            (r) => r.achievementId,
          ),
          unorderedEquals(['first_answer', 'first_correct', 'first_session']),
        );
        await startRound(repository, 'perfect', 9);
        final earnedAnswers = {'retry'};
        for (var i = 1; i <= 9; i++) {
          final command = answer('correct-$i', 'perfect', 9 + i, i);
          await repository.recordAnswer(command);
          earnedAnswers.add(command.id);
        }
        await finish(repository, 'perfect', 19);
        final earned = await database.select(database.achievementUnlocks).get();
        expect(
          earned.map(
            (r) => (
              r.achievementId,
              r.definitionVersion,
              r.sourceEventId,
              r.unlockedAtUtcMs,
            ),
          ),
          unorderedEquals([
            ('first_answer', 1, 'wrong', minute(6).millisecondsSinceEpoch),
            ('first_correct', 1, 'retry', minute(7).millisecondsSinceEpoch),
            ('ten_correct', 1, 'correct-9', minute(18).millisecondsSinceEpoch),
            ('first_session', 1, 'mixed', minute(8).millisecondsSinceEpoch),
            (
              'perfect_session',
              1,
              'perfect',
              minute(19).millisecondsSinceEpoch,
            ),
          ]),
        );
        final operations = await badgeOps(database);
        expect(
          operations.map((op) => op['entity_id']),
          unorderedEquals(earned.map((r) => r.id)),
        );
        await expectRewards(database, earnedAnswers);

        await startRound(repository, 'late-arrival', 0);
        final lateAnswer = answer('early-correct', 'late-arrival', 1, 1);
        await repository.recordAnswer(lateAnswer);
        earnedAnswers.add(lateAnswer.id);
        expect((await repository.recordAnswer(retry)).inserted, isFalse);
        await finish(repository, 'perfect', 30);
        await DriftLearningProjectionRebuilder(
          database,
        ).rebuildAchievements('owner-1');
        await DriftProgressQueries(
          database,
        ).load(ownerId: 'owner-1', nowUtc: minute(31));
        expect(
          await database.select(database.achievementUnlocks).get(),
          unorderedEquals(earned),
        );
        expect(await badgeOps(database), operations);
        await expectRewards(database, earnedAnswers);
      },
    );

    for (final canonicalOperation in [true, false]) {
      test(
        'retired achievement delivery identity survives reopen with canonicalOperation=$canonicalOperation',
        () async {
          const retiredId = 'achievement:owner-1:first_answer:1';
          final oldOperationId = canonicalOperation
              ? 'achievementUnlock:$retiredId:1'
              : 'opaque-delivered-operation';
          final file = await _temporaryBadgeFile();
          final command = answer('first-wrong', 'round', 4, 1, correct: false);
          late OutboxOperation acknowledgement;
          late AchievementUnlock issued;
          final writer = AppDatabase(NativeDatabase(file));
          try {
            await seedVocabulary(writer);
            // Post-merge history: the retained legacy badge has a different
            // physical ID. Delivery history for its removed duplicate survives.
            await writer
                .into(writer.achievementUnlocks)
                .insert(
                  AchievementUnlocksCompanion.insert(
                    id: 'target-legacy',
                    ownerId: 'owner-1',
                    achievementId: 'legacy_unknown',
                    definitionVersion: 1,
                    sourceEventId: 'legacy-source',
                    unlockedAtUtcMs: minute(0).millisecondsSinceEpoch,
                  ),
                );
            await writer.customStatement(
              'INSERT INTO outbox_operations '
              '(operation_id, owner_id, entity_type, entity_id, operation_kind, state, '
              'attempt_count, last_attempt_at_utc_ms, created_at_utc_ms, acknowledged_at_utc_ms) '
              "VALUES (?, 'owner-1', 'achievementUnlock', ?, 'upsert', 'acknowledged', 2, ?, ?, ?)",
              [
                oldOperationId,
                retiredId,
                minute(1).millisecondsSinceEpoch,
                minute(0).millisecondsSinceEpoch,
                minute(2).millisecondsSinceEpoch,
              ],
            );
            acknowledgement = await writer
                .select(writer.outboxOperations)
                .getSingle();
            final repo = DriftLearningRepository(writer);
            await startRound(repo, 'round', 3);
            expect((await repo.recordAnswer(command)).inserted, isTrue);
            issued =
                await (writer.select(writer.achievementUnlocks)
                      ..where((r) => r.achievementId.equals('first_answer')))
                    .getSingle();
          } finally {
            await writer.close();
          }

          final reopened = AppDatabase(NativeDatabase(file));
          try {
            expect(
              (await DriftLearningRepository(
                reopened,
              ).recordAnswer(command)).inserted,
              isFalse,
            );
            final grants = await reopened
                .select(reopened.achievementUnlocks)
                .get();
            expect(
              grants.map((r) => r.achievementId),
              unorderedEquals(['first_answer', 'legacy_unknown']),
            );
            expect(
              grants.singleWhere((r) => r.achievementId == 'first_answer'),
              issued,
            );
            final fact = await reopened
                .select(reopened.answerAttempts)
                .getSingle();
            expect((fact.id, fact.isCorrect), (command.id, false));
            await expectRewards(reopened, {});
            final store = DriftSyncStore(reopened);
            final claimed = await store.claimPending(
              ownerId: 'owner-1',
              firebaseUid: 'synthetic-user',
              limit: 20,
              leaseToken: 'synthetic-lease',
              leaseDuration: const Duration(minutes: 1),
              nowUtc: minute(5),
            );
            final fresh = claimed
                .map((c) => c.mutation)
                .where(
                  (m) => m.collection == sync.SyncCollection.achievementUnlocks,
                );
            expect(
              fresh,
              hasLength(1),
              reason: 'the old ACK cannot deliver this new grant',
            );
            expect(
              issued.id,
              isNot(retiredId),
              reason: 'an acknowledged entity ID denotes its original award',
            );
            expect(fresh.single.entityId, issued.id);
            expect(
              fresh.single.operationId,
              isNot(acknowledgement.operationId),
            );
            expect(fresh.single.payload, {
              'achievementId': 'first_answer',
              'definitionVersion': 1,
              'sourceEventId': command.id,
              'unlockedAtUtcMs': command.occurredAtUtc.millisecondsSinceEpoch,
            });
            final ops = await (reopened.select(
              reopened.outboxOperations,
            )..where((op) => op.entityType.equals('achievementUnlock'))).get();
            expect(
              ops.map((op) => op.operationId),
              unorderedEquals([oldOperationId, fresh.single.operationId]),
            );
            expect(
              ops.singleWhere((op) => op.operationId == oldOperationId),
              acknowledgement,
            );
          } finally {
            await reopened.close();
          }
        },
      );
    }

    for (final (legacyKey, legacyVersion) in [
      ('legacy_unknown', 1),
      ('first_answer', 7),
    ]) {
      test(
        'opaque achievement ID collision with $legacyKey v$legacyVersion survives replay and reopen',
        () async {
          const occupiedId = 'achievement:owner-1:first_answer:1';
          final file = await _temporaryBadgeFile();
          final command = answer('first-local', 'quiz', 4, 1);
          final writer = AppDatabase(NativeDatabase(file));
          late AchievementUnlock retained;
          late AchievementUnlock issued;
          try {
            await seedVocabulary(writer);
            final archived = sync.SyncEntity(
              collection: sync.SyncCollection.achievementUnlocks,
              entityId: occupiedId,
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: minute(1),
              serverUpdatedAtUtc: minute(2),
              payload: {
                'achievementId': legacyKey,
                'definitionVersion': legacyVersion,
                'sourceEventId': 'archived-source',
                'unlockedAtUtcMs': minute(1).millisecondsSinceEpoch,
              },
            );
            await DriftSyncStore(writer).applyPullPage(
              ownerId: 'owner-1',
              collection: archived.collection,
              page: PullPage(
                changes: [archived],
                nextCursor: sync.SyncCursor(
                  serverUpdatedAtUtc: archived.serverUpdatedAtUtc,
                  documentId: occupiedId,
                ),
                hasMore: false,
              ),
            );
            retained = await writer
                .select(writer.achievementUnlocks)
                .getSingle();
            final repo = DriftLearningRepository(writer);
            await startRound(repo, 'quiz', 3);
            expect((await repo.recordAnswer(command)).inserted, isTrue);
            issued =
                await (writer.select(writer.achievementUnlocks)..where(
                      (r) =>
                          r.achievementId.equals('first_answer') &
                          r.definitionVersion.equals(1),
                    ))
                    .getSingle();
            expect(issued.id, isNot(occupiedId));
            expect(
              (issued.sourceEventId, issued.unlockedAtUtcMs),
              (command.id, command.occurredAtUtc.millisecondsSinceEpoch),
            );
          } finally {
            await writer.close();
          }

          final reopened = AppDatabase(NativeDatabase(file));
          try {
            final repo = DriftLearningRepository(reopened);
            expect((await repo.recordAnswer(command)).inserted, isFalse);
            final rows = await reopened
                .select(reopened.achievementUnlocks)
                .get();
            expect(rows, hasLength(3));
            expect(rows, containsAll([retained, issued]));
            final firstCorrect = rows.singleWhere(
              (r) =>
                  r.achievementId == 'first_correct' &&
                  r.definitionVersion == 1,
            );
            expect(
              (await reopened.select(reopened.answerAttempts).getSingle()).id,
              command.id,
            );
            await expectRewards(reopened, {command.id});
            final operations = await badgeOps(reopened);
            expect(
              operations.map((op) => op['entity_id']),
              unorderedEquals([issued.id, firstCorrect.id]),
            );
            final claimed = await DriftSyncStore(reopened).claimPending(
              ownerId: 'owner-1',
              firebaseUid: 'synthetic-user',
              limit: 20,
              leaseToken: 'synthetic-lease',
              leaseDuration: const Duration(minutes: 1),
              nowUtc: minute(5),
            );
            final mutation = claimed
                .map((op) => op.mutation)
                .singleWhere(
                  (m) =>
                      m.collection == sync.SyncCollection.achievementUnlocks &&
                      m.entityId == issued.id,
                );
            expect(mutation.payload, {
              'achievementId': 'first_answer',
              'definitionVersion': 1,
              'sourceEventId': command.id,
              'unlockedAtUtcMs': command.occurredAtUtc.millisecondsSinceEpoch,
            });
          } finally {
            await reopened.close();
          }
        },
      );
    }

    test(
      'legacy unlock IDs, sources, dates and pending or acknowledged operations survive reopen',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'lexiquest-badge-history-',
        );
        final originalDir = await dir.resolveSymbolicLinks();
        final file = File('${dir.path}/badges.sqlite');
        final correctIds = {for (var i = 1; i <= 10; i++) 'local-$i'};
        final lateAnswer = answer('late-earlier', 'local', 1, 11);
        late List<AchievementUnlock> history;
        late List<Map<String, Object?>> operations;
        try {
          final writer = AppDatabase(NativeDatabase(file));
          try {
            await seedVocabulary(writer);
            for (final key in [
              'first_answer',
              'first_correct',
              'ten_correct',
              'first_session',
              'perfect_session',
              'archived_custom',
            ]) {
              await writer
                  .into(writer.achievementUnlocks)
                  .insert(
                    AchievementUnlocksCompanion.insert(
                      id: 'legacy-$key',
                      ownerId: 'owner-1',
                      achievementId: key,
                      definitionVersion: 1,
                      sourceEventId: 'original-$key',
                      unlockedAtUtcMs: minute(50).millisecondsSinceEpoch,
                    ),
                  );
            }
            // Persist historical operation identities for both sync states. The
            // wire payload comes from the referenced immutable unlock row.
            for (final key in [
              'first_answer',
              'first_correct',
              'ten_correct',
            ]) {
              final acknowledged = key == 'first_correct';
              await writer.customStatement(
                'INSERT INTO outbox_operations (operation_id,owner_id,entity_type,entity_id,'
                'operation_kind,state,created_at_utc_ms,acknowledged_at_utc_ms) '
                "VALUES (?,'owner-1','achievementUnlock',?,'upsert',?,?,?)",
                [
                  'op-$key',
                  'legacy-$key',
                  acknowledged ? 'acknowledged' : 'pending',
                  minute(50).millisecondsSinceEpoch,
                  acknowledged ? minute(52).millisecondsSinceEpoch : null,
                ],
              );
            }
            history = await writer.select(writer.achievementUnlocks).get();
            operations = await badgeOps(writer);
            final repo = DriftLearningRepository(writer);
            await startRound(repo, 'local', 0);
            for (var i = 1; i <= 10; i++) {
              await repo.recordAnswer(answer('local-$i', 'local', 10 + i, i));
            }
            await repo.recordAnswer(lateAnswer);
            await finish(repo, 'local', 25);
          } finally {
            await writer.close();
          }
          final reopened = AppDatabase(NativeDatabase(file));
          try {
            final repo = DriftLearningRepository(reopened);
            expect((await repo.recordAnswer(lateAnswer)).inserted, isFalse);
            await finish(repo, 'local', 60);
            await DriftLearningProjectionRebuilder(
              reopened,
            ).rebuildAchievements('owner-1');
            await DriftProgressQueries(
              reopened,
            ).load(ownerId: 'owner-1', nowUtc: minute(61));
            expect(
              await reopened.select(reopened.achievementUnlocks).get(),
              unorderedEquals(history),
            );
            expect(await badgeOps(reopened), operations);
            await expectRewards(reopened, {...correctIds, lateAnswer.id});
          } finally {
            await reopened.close();
          }
        } finally {
          final resolved = Directory(await dir.resolveSymbolicLinks());
          expect(resolved.path, originalDir);
          expect(
            resolved.parent.path,
            await Directory.systemTemp.resolveSymbolicLinks(),
          );
          expect(
            resolved.uri.pathSegments.where((s) => s.isNotEmpty).last,
            startsWith('lexiquest-badge-history-'),
          );
          await resolved.delete(recursive: true);
        }
      },
    );
  });

  test('quiz words come from active local vocabulary for the owner', () async {
    final words = await repository.listQuizWords(
      ownerId: 'owner-1',
      categoryId: 'category-1',
      limit: 10,
    );

    expect(words.map((word) => word.id), ['word-1', 'word-2']);
    expect(words.first.meaning, 'สถานี');
  });

  test('target filters exclude deleted words and other owners', () async {
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-2',
            ownerId: 'owner-2',
            name: 'Other',
            normalizedName: 'other',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'other-word',
            ownerId: 'owner-2',
            categoryId: 'category-2',
            spelling: 'synthetic',
            normalizedSpelling: 'synthetic',
            meaning: 'อื่น',
            normalizedMeaning: 'อื่น',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database.customStatement(
      "UPDATE vocabulary_words SET is_deleted = 1 WHERE id = 'word-2'",
    );
    final words = await repository.listQuizWords(
      ownerId: 'owner-1',
      limit: 10,
      wordIds: ['word-1', 'word-2', 'other-word'],
    );
    expect(words.map((word) => word.id), ['word-1']);
    expect(
      await repository.listQuizWords(
        ownerId: 'owner-1',
        limit: 10,
        wordIds: [],
      ),
      isEmpty,
    );
  });

  test('answer transaction is idempotent and updates SRS and points', () async {
    const session = LearningSessionDraft(
      id: 'session-1',
      ownerId: 'owner-1',
      activityType: 'quiz',
      startedAtUtc: null,
      appVersion: '1.0.0',
      buildId: 'test',
    );
    await repository.startSession(
      session.copyWith(startedAtUtc: DateTime.utc(2026, 7, 30, 10)),
    );
    final command = RecordAnswerCommand(
      id: 'attempt-1',
      ownerId: 'owner-1',
      sessionId: 'session-1',
      wordId: 'word-1',
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 420,
      attemptNumber: 1,
      occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
    );

    final first = await repository.recordAnswer(command);
    final replay = await repository.recordAnswer(command);

    expect(first.inserted, isTrue);
    expect(replay.inserted, isFalse);
    expect(replay.srs.intervalDays, 1);
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    expect(
      await database.select(database.pointsLedgerEntries).get(),
      hasLength(1),
    );
    final achievements = await database
        .select(database.achievementUnlocks)
        .get();
    expect(achievements.map((row) => row.achievementId).toSet(), {
      'first_answer',
      'first_correct',
    });
    final outbox = await database.select(database.outboxOperations).get();
    expect(outbox.map((row) => row.entityType), contains('attempt'));
    final storedSession = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals('session-1'))).getSingle();
    expect(storedSession.correctCount, 1);
    expect(storedSession.wrongCount, 0);
  });

  test('finishing session stores auditable score and counts', () async {
    await repository.startSession(
      LearningSessionDraft(
        id: 'session-1',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: DateTime.utc(2026, 7, 30, 10),
        appVersion: '1.0.0',
        buildId: 'test',
      ),
    );
    await repository.recordAnswer(
      RecordAnswerCommand(
        id: 'attempt-1',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 800,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      ),
    );

    final result = await repository.finishSession(
      ownerId: 'owner-1',
      sessionId: 'session-1',
      endedAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
    );

    expect(result.state, 'completed');
    expect(result.correctCount, 0);
    expect(result.wrongCount, 1);
    expect(result.score, 0);
  });

  test(
    'out-of-order local attempts rebuild SRS in canonical event order',
    () async {
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-order',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 9),
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );
      final later = DateTime.utc(2026, 7, 30, 10);
      final earlier = DateTime.utc(2026, 7, 30, 9, 30);
      await repository.recordAnswer(
        RecordAnswerCommand(
          id: 'attempt-later',
          ownerId: 'owner-1',
          sessionId: 'session-order',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 200,
          attemptNumber: 2,
          occurredAtUtc: later,
        ),
      );

      final result = await repository.recordAnswer(
        RecordAnswerCommand(
          id: 'attempt-earlier',
          ownerId: 'owner-1',
          sessionId: 'session-order',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: false,
          responseTimeMs: 300,
          attemptNumber: 1,
          occurredAtUtc: earlier,
        ),
      );

      expect(result.srs.lastReviewAtUtc, later);
      expect(result.srs.repetitions, 1);
      expect(result.srs.lapses, 1);
      final firstAnswer = await (database.select(
        database.achievementUnlocks,
      )..where((row) => row.achievementId.equals('first_answer'))).getSingle();
      expect(firstAnswer.sourceEventId, 'attempt-later');
      expect(firstAnswer.unlockedAtUtcMs, later.millisecondsSinceEpoch);
    },
  );

  test('attempt replay compares provider provenance', () async {
    await repository.startSession(
      LearningSessionDraft(
        id: 'session-provenance',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: DateTime.utc(2026, 7, 30, 10),
        appVersion: '1.0.0',
        buildId: 'test',
      ),
    );
    final command = RecordAnswerCommand(
      id: 'attempt-provenance',
      ownerId: 'owner-1',
      sessionId: 'session-provenance',
      wordId: 'word-1',
      promptMode: 'pronunciation',
      isCorrect: true,
      responseTimeMs: 400,
      attemptNumber: 1,
      occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      providerProvenance: 'device-stt',
    );
    await repository.recordAnswer(command);

    await expectLater(
      repository.recordAnswer(
        RecordAnswerCommand(
          id: command.id,
          ownerId: command.ownerId,
          sessionId: command.sessionId,
          wordId: command.wordId,
          promptMode: command.promptMode,
          isCorrect: command.isCorrect,
          responseTimeMs: command.responseTimeMs,
          attemptNumber: command.attemptNumber,
          occurredAtUtc: command.occurredAtUtc,
          providerProvenance: 'cloud-stt',
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'invalid cloud-contract evidence is rejected before local commit',
    () async {
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-limits',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 10),
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );
      final base = RecordAnswerCommand(
        id: 'attempt-limits',
        ownerId: 'owner-1',
        sessionId: 'session-limits',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 400,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      );

      for (final invalid in [
        RecordAnswerCommand(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: 'x' * 61,
          isCorrect: base.isCorrect,
          responseTimeMs: base.responseTimeMs,
          attemptNumber: base.attemptNumber,
          occurredAtUtc: base.occurredAtUtc,
        ),
        RecordAnswerCommand(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: base.promptMode,
          isCorrect: base.isCorrect,
          responseTimeMs: 2147483648,
          attemptNumber: base.attemptNumber,
          occurredAtUtc: base.occurredAtUtc,
        ),
        RecordAnswerCommand(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: base.promptMode,
          isCorrect: base.isCorrect,
          responseTimeMs: base.responseTimeMs,
          attemptNumber: 1000001,
          occurredAtUtc: base.occurredAtUtc,
        ),
        RecordAnswerCommand(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: base.promptMode,
          isCorrect: base.isCorrect,
          responseTimeMs: base.responseTimeMs,
          attemptNumber: base.attemptNumber,
          occurredAtUtc: base.occurredAtUtc,
          providerProvenance: 'p' * 121,
        ),
      ]) {
        expect(() => repository.recordAnswer(invalid), throwsArgumentError);
      }

      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test('reading progress is monotonic and completion is idempotent', () async {
    final first = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-1',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 80,
        isCompleted: false,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10),
      ),
    );
    final rewound = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-2',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 30,
        isCompleted: false,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      ),
    );
    final completed = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-3',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 100,
        isCompleted: true,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
      ),
    );
    final replay = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-3',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 100,
        isCompleted: true,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
      ),
    );

    expect(first.lastPosition, 80);
    expect(rewound.lastPosition, 80);
    expect(completed.isCompleted, isTrue);
    expect(replay, completed);
    expect(await database.select(database.readingEvents).get(), hasLength(3));
    final readingOutbox = await (database.select(
      database.outboxOperations,
    )..where((row) => row.entityType.equals('readingEvent'))).get();
    expect(readingOutbox, hasLength(3));
  });

  test('reading progress rejects an owner that is no longer active', () async {
    await database.customUpdate(
      "UPDATE local_owners SET is_active = 0 WHERE id = 'owner-1'",
      updates: {database.localOwners},
    );
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 2));

    await expectLater(
      repository.saveReadingProgress(
        ReadingProgressCommand(
          eventId: 'reading-stale-owner',
          ownerId: 'owner-1',
          documentId: 'doc-1',
          documentRevision: 1,
          position: 2,
          isCompleted: false,
          occurredAtUtc: DateTime.utc(2026, 10, 21),
        ),
      ),
      throwsStateError,
    );
    expect(await database.select(database.readingEvents).get(), isEmpty);
    expect(
      await database.select(database.readingProgressEntries).get(),
      isEmpty,
    );
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  });
}

Future<File> _temporaryBadgeFile() async {
  final dir = await Directory.systemTemp.createTemp('lexiquest-opaque-badge-');
  final originalDir = await dir.resolveSymbolicLinks();
  addTearDown(() async {
    final resolved = Directory(await dir.resolveSymbolicLinks());
    expect(resolved.path, originalDir);
    expect(
      resolved.parent.path,
      await Directory.systemTemp.resolveSymbolicLinks(),
    );
    expect(
      resolved.uri.pathSegments.where((s) => s.isNotEmpty).last,
      startsWith('lexiquest-opaque-badge-'),
    );
    await resolved.delete(recursive: true);
  });
  return File('${dir.path}/badges.sqlite');
}

Future<void> _start(DriftLearningRepository repo, DateTime at) =>
    repo.startSession(
      LearningSessionDraft(
        id: 'motivation-session',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: at,
        appVersion: 'test',
        buildId: 'synthetic',
      ),
    );

RecordAnswerCommand _answer(String id, DateTime at) => RecordAnswerCommand(
  id: id,
  ownerId: 'owner-1',
  sessionId: 'motivation-session',
  wordId: 'word-1',
  promptMode: 'meaningChoice',
  isCorrect: true,
  responseTimeMs: 100,
  attemptNumber: 1,
  occurredAtUtc: at,
);

Future<AnswerAttempt> _read(AppDatabase db, String id) => (db.select(
  db.answerAttempts,
)..where((row) => row.id.equals(id))).getSingle();

Future<void> _epoch(
  AppDatabase db,
  String id,
  String zone,
  int start,
  int? end,
) => db.customStatement(
  'INSERT INTO owner_calendar_epochs '
  '(rule_id,owner_id,origin_owner_id,iana_id,tzdb_revision,effective_utc_us,expires_utc_us,is_selected) '
  "VALUES (?,'owner-1','owner-1',?,?,?,?,1)",
  [id, zone, bundledTzdbRevision, start, end],
);

LearningCalendarWindow _failedCapture(
  DateTime time,
  String zone, {
  DateTime? epochEffectiveAtUtc,
  DateTime? epochExpiresAtUtc,
}) => throw StateError('synthetic failure after calendar authority lookup');

Future<TrustedQuestAnswerCatalog> _installDailyRevision(
  AppDatabase db,
  DateTime activation,
) {
  final daily = QuestCatalogProvider.dailyCorrectAnswers;
  return DriftQuestRepository(db).installAnswerCatalog(
    authoredRevisions: [
      ...QuestCatalogProvider.authoredRevisions,
      QuestCatalogRevision(
        activeFromUtcMs: activation.millisecondsSinceEpoch,
        definition: quest.QuestDefinition(
          questId: daily.questId,
          catalogVersion: 2,
          title: 'Synthetic daily revision',
          description: daily.description,
          type: daily.type,
          objectives: daily.objectives,
          reward: daily.reward,
          expiresIn: daily.expiresIn,
          tags: daily.tags,
        ),
      ),
    ],
  );
}

Future<void> _expectOrdinaryCorrectAnswer(AppDatabase db, String id) async {
  final fact = await db.select(db.answerAttempts).getSingle();
  expect((fact.id, fact.ownerId, fact.isCorrect), (id, 'owner-1', true));
  final xp = await db.select(db.pointsLedgerEntries).getSingle();
  expect((xp.entryType, xp.amount, xp.sourceEventId), ('quizCorrect', 1, id));
  final coin = await db.select(db.rewardTransactions).getSingle();
  expect(
    (coin.transactionType, coin.amount, coin.sourceEventId),
    ('creditQuizCorrectV1', 1, id),
  );
  expect((await db.select(db.srsStates).getSingle()).repetitions, 1);
  final session = await db.select(db.learningSessions).getSingle();
  expect((session.correctCount, session.wrongCount), (1, 0));
  final ops = await db.select(db.outboxOperations).get();
  expect(
    ops.where((r) => r.entityType == 'attempt' && r.entityId == id),
    hasLength(1),
  );
  expect(
    ops.where((r) => r.entityType == 'srsState' && r.entityId == 'word-1'),
    hasLength(1),
  );
  expect(
    ops.where(
      (r) =>
          r.entityType.toLowerCase().contains('research') ||
          r.entityType.toLowerCase().contains('quest'),
    ),
    isEmpty,
  );
  for (final table in [
    'quest_definitions',
    'quest_instances',
    'quest_objective_progress',
    'quest_claim_receipts',
    'events_v2',
    'research_consents',
  ]) {
    expect(
      await db.customSelect('SELECT * FROM $table').get(),
      isEmpty,
      reason: table,
    );
  }
}
