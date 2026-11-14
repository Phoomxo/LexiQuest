import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/motivation/application/focus_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_focus_repository.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/focus_models.dart';
import 'package:vocab_learning_app/features/motivation/domain/timezone_policy.dart';

final _at = DateTime.utc(2026, 11, 13, 9);
final _monday = DateTime.utc(2026, 11, 9);

void main() {
  setUpAll(tz.initializeTimeZones);

  test(
    'two measured active ranges exclude the three-minute pause everywhere',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seed(database);
        final unrelated = await _rows(database, excludeFocus: true);
        final repository = DriftFocusRepository(database);
        var focus = await _start(repository);
        expect(focus.revision, 1);
        expect(focus.state, FocusState.running);
        expect(focus.startRuleId, 'calendar:utc-default:owner-a');
        expect(focus.startCivilWeek, '2026-11-09');
        focus = await _step(repository, focus, FocusStep.pause, _sample(60));
        expect(focus.activeMs, 60000);
        expect(focus.state, FocusState.paused);
        focus = await _step(repository, focus, FocusStep.resume, _sample(240));
        expect(focus.activeMs, 60000);
        expect(focus.pausedMs, 180000);
        focus = await _step(repository, focus, FocusStep.finish, _sample(300));
        expect(focus.state, FocusState.completed);
        expect(focus.activeMs, 120000);
        expect(focus.measuredActiveMs, 120000);
        expect(focus.pausedMs, 180000);
        expect(focus.hasUnknownGap, isFalse);
        expect(focus.spans.map((span) => span.kind), [
          FocusSpanKind.active,
          FocusSpanKind.paused,
          FocusSpanKind.active,
        ]);
        expect(focus.spans.map((span) => span.elapsedUs), [
          60000000,
          180000000,
          60000000,
        ]);
        expect(
          focus.spans.map(
            (span) => (span.observedStartUtcMs, span.observedEndUtcMs),
          ),
          [
            (_sample(0).utcMs, _sample(60).utcMs),
            (_sample(60).utcMs, _sample(240).utcMs),
            (_sample(240).utcMs, _sample(300).utcMs),
          ],
        );
        expect(() => focus.spans.clear(), throwsUnsupportedError);
        final beforeRead = await _rows(database);
        final week = await repository.week(
          ownerId: 'owner-a',
          civilMonday: _monday,
        );
        expect(week.completedActiveMs, 120000);
        expect(week.sessions.map((row) => row.id), ['focus-1']);
        expect(week.unattributed, isEmpty);
        expect(await repository.findOpen(ownerId: 'owner-a'), isNull);
        expect(
          (await repository.load(ownerId: 'owner-a', id: 'focus-1'))!.activeMs,
          120000,
        );
        expect(await _rows(database), beforeRead);
        expect(await _rows(database, excludeFocus: true), unrelated);
      } finally {
        await database.close();
      }
    },
  );

  test(
    'wall rollback cannot inflate time and repeated finish cannot count it twice',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seed(database);
        final repository = DriftFocusRepository(database);
        final initial = await _start(repository, targetMs: 60000);
        final sample = FocusSample(
          utcMs: _at
              .subtract(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
          monotonicUs: 90000000,
          continuityId: 'boot-a',
        );
        final finished = await _step(
          repository,
          initial,
          FocusStep.finish,
          sample,
        );
        expect(finished.state, FocusState.completed);
        expect(finished.activeMs, 60000);
        expect(finished.measuredActiveMs, 90000);
        expect(finished.endedAtUtcMs, lessThan(finished.startedAtUtcMs));
        expect(finished.spans.single.elapsedUs, 90000000);
        final after = await _rows(database);
        final replay = await _step(
          repository,
          initial,
          FocusStep.finish,
          sample,
        );
        expect(replay.revision, finished.revision);
        expect(await _rows(database), after);
        await expectLater(
          _step(repository, initial, FocusStep.finish, _sample(91)),
          throwsStateError,
        );
        expect(await _rows(database), after);
        expect(
          (await repository.week(
            ownerId: 'owner-a',
            civilMonday: _monday,
          )).completedActiveMs,
          60000,
        );
      } finally {
        await database.close();
      }
    },
  );

  test(
    'one open round, immutable start and owner-revision checks are atomic',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seed(database);
        final repository = DriftFocusRepository(database);
        final initial = await _start(repository);
        var before = await _rows(database);
        expect((await _start(repository)).revision, initial.revision);
        await expectLater(
          _start(repository, targetMs: 60000),
          throwsStateError,
        );
        await expectLater(_start(repository, id: 'focus-2'), throwsStateError);
        expect(await _rows(database), before);
        final paused = await _step(
          repository,
          initial,
          FocusStep.pause,
          _sample(60),
        );
        before = await _rows(database);
        expect(
          (await _step(
            repository,
            initial,
            FocusStep.pause,
            _sample(60),
          )).revision,
          paused.revision,
        );
        await expectLater(
          _step(repository, initial, FocusStep.resume, _sample(70)),
          throwsStateError,
        );
        expect(await _rows(database), before);
        await database.customStatement(
          "UPDATE local_owners SET is_active=0 WHERE id='owner-a'",
        );
        await database.customStatement(
          "INSERT INTO local_owners (id,created_at_utc_ms,is_active) VALUES ('owner-b',1,1)",
        );
        before = await _rows(database);
        expect(
          await repository.load(ownerId: 'owner-b', id: initial.id),
          isNull,
        );
        expect(await repository.findOpen(ownerId: 'owner-b'), isNull);
        for (final owner in ['owner-a', 'owner-b']) {
          await expectLater(
            repository.transition(
              expectedOwnerId: owner,
              id: paused.id,
              expectedRevision: paused.revision,
              step: FocusStep.resume,
              sample: _sample(100),
            ),
            throwsStateError,
          );
        }
        expect(await _rows(database), before);
      } finally {
        await database.close();
      }
    },
  );

  test(
    'file restart preserves measured spans and never estimates a lost clock tail',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-focus-clock-',
      );
      final original = await directory.resolveSymbolicLinks();
      final file = File('${directory.path}/focus.sqlite');
      var database = AppDatabase(NativeDatabase(file));
      try {
        await _seed(database);
        var repository = DriftFocusRepository(database);
        var paused = await _start(repository);
        paused = await _step(repository, paused, FocusStep.pause, _sample(60));
        await database.close();
        database = AppDatabase(NativeDatabase(file));
        repository = DriftFocusRepository(database);
        paused = (await repository.findOpen(ownerId: 'owner-a'))!;
        expect(paused.activeMs, 60000);
        final restarted = FocusSample(
          utcMs: _at.add(const Duration(days: 1)).millisecondsSinceEpoch,
          monotonicUs: 0,
          continuityId: 'boot-b',
        );
        paused = await _step(repository, paused, FocusStep.resume, restarted);
        expect(paused.hasUnknownGap, isTrue);
        expect(paused.pausedMs, 0);
        expect(paused.spans.last.kind, FocusSpanKind.paused);
        expect(paused.spans.last.elapsedUs, isNull);
        paused = await _step(
          repository,
          paused,
          FocusStep.finish,
          FocusSample(
            utcMs: restarted.utcMs + 10000,
            monotonicUs: 10000000,
            continuityId: 'boot-b',
          ),
        );
        expect(paused.activeMs, 70000);

        var running = await repository.start(
          expectedOwnerId: 'owner-a',
          id: 'crashed',
          targetMs: 300000,
          sample: FocusSample(
            utcMs: restarted.utcMs + 20000,
            monotonicUs: 20000000,
            continuityId: 'boot-b',
          ),
        );
        running = await _step(
          repository,
          running,
          FocusStep.pause,
          FocusSample(
            utcMs: restarted.utcMs + 80000,
            monotonicUs: 80000000,
            continuityId: 'boot-b',
          ),
        );
        running = await _step(
          repository,
          running,
          FocusStep.resume,
          FocusSample(
            utcMs: restarted.utcMs + 90000,
            monotonicUs: 90000000,
            continuityId: 'boot-b',
          ),
        );
        final stored = await _rows(database);
        await database.close();
        database = AppDatabase(NativeDatabase(file));
        repository = DriftFocusRepository(database);
        running = (await repository.load(ownerId: 'owner-a', id: 'crashed'))!;
        expect(await _rows(database), stored);
        final recovery = FocusSample(
          utcMs: restarted.utcMs + 86400000,
          monotonicUs: 0,
          continuityId: 'boot-c',
        );
        final interrupted = await _step(
          repository,
          running,
          FocusStep.recoverInterrupted,
          recovery,
        );
        expect(interrupted.state, FocusState.interrupted);
        expect(interrupted.activeMs, 60000);
        expect(interrupted.endedAtUtcMs, isNull);
        expect(interrupted.hasUnknownGap, isTrue);
        expect(interrupted.spans, hasLength(2));
        final afterRecovery = await _rows(database);
        await _step(
          repository,
          running,
          FocusStep.recoverInterrupted,
          recovery,
        );
        expect(await _rows(database), afterRecovery);
        expect(await repository.findOpen(ownerId: 'owner-a'), isNull);
        final week = await repository.week(
          ownerId: 'owner-a',
          civilMonday: _monday,
        );
        expect(week.completedActiveMs, 70000);
        expect(
          week.sessions
              .where((row) => row.state == FocusState.interrupted)
              .single
              .activeMs,
          60000,
        );
      } finally {
        await database.close();
        final resolved = Directory(await directory.resolveSymbolicLinks());
        expect(resolved.path, original);
        expect(
          resolved.parent.path,
          await Directory.systemTemp.resolveSymbolicLinks(),
        );
        expect(
          resolved.uri.pathSegments.where((part) => part.isNotEmpty).last,
          startsWith('lexiquest-focus-clock-'),
        );
        await resolved.delete(recursive: true);
      }
    },
  );

  test(
    'weekly attribution uses the original home week across midnight and timezone change',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seed(database);
        await database.customStatement(
          'INSERT INTO owner_calendar_epochs (rule_id,owner_id,origin_owner_id,effective_utc_us,iana_id,tzdb_revision,is_selected) '
          "VALUES ('home-a','owner-a','owner-a',1000,'Asia/Bangkok',?,1)",
          [bundledTzdbRevision],
        );
        final calendar = DriftStreakRepository(
          database,
          calendarVisible: () => true,
        );
        final repository = DriftFocusRepository(database, calendar: calendar);
        final start = DateTime.utc(2026, 11, 15, 16, 59);
        var focus = await repository.start(
          expectedOwnerId: 'owner-a',
          id: 'boundary',
          targetMs: 300000,
          sample: FocusSample(
            utcMs: start.millisecondsSinceEpoch,
            monotonicUs: 0,
            continuityId: 'boot-a',
          ),
        );
        focus = await _step(
          repository,
          focus,
          FocusStep.finish,
          FocusSample(
            utcMs: start.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
            monotonicUs: 120000000,
            continuityId: 'boot-a',
          ),
        );
        expect(focus.startRuleId, 'home-a');
        expect(focus.startCivilWeek, '2026-11-09');
        await calendar.selectHomeTimezone(
          expectedOwnerId: 'owner-a',
          ianaId: 'America/New_York',
          occurredAtUtc: start.add(const Duration(minutes: 3)),
        );
        expect(
          (await repository.week(
            ownerId: 'owner-a',
            civilMonday: _monday,
          )).completedActiveMs,
          120000,
        );
        expect(
          (await repository.week(
            ownerId: 'owner-a',
            civilMonday: DateTime.utc(2026, 11, 16),
          )).sessions,
          isEmpty,
        );
        expect(
          (await repository.load(
            ownerId: 'owner-a',
            id: 'boundary',
          ))!.startCivilWeek,
          '2026-11-09',
        );
      } finally {
        await database.close();
      }
    },
  );

  test(
    'unavailable calendar keeps measured time explicitly unattributed',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seed(database);
        await database.customStatement(
          'INSERT INTO owner_calendar_epochs (rule_id,owner_id,origin_owner_id,effective_utc_us,iana_id,tzdb_revision,is_selected) '
          "VALUES ('unknown-a','owner-a','owner-a',1000,'Unknown/Synthetic','unavailable',1)",
        );
        final repository = DriftFocusRepository(database);
        var focus = await _start(repository);
        expect(focus.startRuleId, isNull);
        expect(focus.startCivilWeek, isNull);
        focus = await _step(repository, focus, FocusStep.finish, _sample(60));
        expect(focus.activeMs, 60000);
        final week = await repository.week(
          ownerId: 'owner-a',
          civilMonday: _monday,
        );
        expect(week.sessions, isEmpty);
        expect(week.completedActiveMs, 0);
        expect(week.unattributed.single.activeMs, 60000);
      } finally {
        await database.close();
      }
    },
  );

  test(
    'owner merge retains measured guest history and interrupts its running lease',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seed(database);
        await database.customStatement(
          "UPDATE local_owners SET is_active=0 WHERE id='owner-a'",
        );
        await database.customStatement(
          "INSERT INTO local_owners (id,firebase_uid,created_at_utc_ms,is_active) VALUES ('owner-b','firebase-b',1,1)",
        );
        final repository = DriftFocusRepository(database);
        var target = await repository.start(
          expectedOwnerId: 'owner-b',
          id: 'target-focus',
          targetMs: 300000,
          sample: _sample(0),
        );
        target = await repository.transition(
          expectedOwnerId: 'owner-b',
          id: target.id,
          expectedRevision: target.revision,
          step: FocusStep.pause,
          sample: _sample(60),
        );
        await database.customStatement(
          "UPDATE local_owners SET is_active=CASE WHEN id='owner-a' THEN 1 ELSE 0 END",
        );
        var guest = await _start(repository);
        guest = await _step(repository, guest, FocusStep.pause, _sample(60));
        guest = await _step(repository, guest, FocusStep.resume, _sample(240));
        final guestRow =
            (await database
                    .customSelect(
                      "SELECT * FROM focus_sessions WHERE id='focus-1'",
                    )
                    .getSingle())
                .data;
        var conflictId = 0;
        final merger = DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => _at.add(const Duration(minutes: 5)),
          generateConflictId: () => 'focus-conflict-${conflictId++}',
          generateOwnerId: () => 'unused',
        );
        await merger.upgrade(
          activeOwnerId: 'owner-a',
          firebaseUid: 'firebase-b',
        );
        final moved = (await repository.load(
          ownerId: 'owner-b',
          id: guest.id,
        ))!;
        expect(moved.originOwnerId, 'owner-a');
        expect(moved.startRuleId, guest.startRuleId);
        expect(moved.startCivilWeek, guest.startCivilWeek);
        expect(moved.state, FocusState.interrupted);
        expect(moved.activeMs, 60000);
        expect(moved.pausedMs, 180000);
        expect(moved.endedAtUtcMs, isNull);
        expect(moved.hasUnknownGap, isTrue);
        final movedRow =
            (await database
                    .customSelect(
                      "SELECT * FROM focus_sessions WHERE id='focus-1'",
                    )
                    .getSingle())
                .data;
        expect(movedRow['spans_json'], guestRow['spans_json']);
        final retained = (await repository.findOpen(ownerId: 'owner-b'))!;
        expect(retained.id, target.id);
        expect(retained.state, FocusState.paused);
        expect(retained.revision, target.revision);
        final merged = await _rows(database);
        await expectLater(
          _step(repository, guest, FocusStep.finish, _sample(300)),
          throwsStateError,
        );
        await merger.upgrade(
          activeOwnerId: 'owner-b',
          firebaseUid: 'firebase-b',
        );
        expect(await _rows(database), merged);
        expect(await database.select(database.answerAttempts).get(), isEmpty);
        expect(
          await database.select(database.pointsLedgerEntries).get(),
          isEmpty,
        );
        expect(
          await database.select(database.rewardTransactions).get(),
          isEmpty,
        );
        expect(
          await database.select(database.achievementUnlocks).get(),
          isEmpty,
        );
      } finally {
        await database.close();
      }
    },
  );

  test(
    'malformed stored spans are unavailable without repair writes',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seed(database);
        final repository = DriftFocusRepository(database);
        await _start(repository);
        for (final bad in ['{"v":99}', '{broken', '{}']) {
          await database.customStatement(
            "UPDATE focus_sessions SET spans_json=? WHERE id='focus-1'",
            [bad],
          );
          final before = await _rows(database);
          await expectLater(
            repository.load(ownerId: 'owner-a', id: 'focus-1'),
            throwsFormatException,
          );
          await expectLater(
            repository.week(ownerId: 'owner-a', civilMonday: _monday),
            throwsFormatException,
          );
          expect(await _rows(database), before);
        }
      } finally {
        await database.close();
      }
    },
  );

  test(
    'facade samples foreground before background, fences owners and notifies only mutations',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seed(database);
        final clock = _Clock(_sample(0));
        var changed = 0;
        final useCases = FocusUseCases(
          repository: DriftFocusRepository(database),
          owners: DriftLocalOwnerRepository(
            database,
            generateId: () => 'unused',
            nowUtc: () => _at,
          ),
          clock: clock,
          generateId: () => 'facade-focus',
          onChanged: () => changed++,
        );
        var focus = await useCases.start(
          expectedOwnerId: 'owner-a',
          targetMs: 300000,
        );
        expect(changed, 1);
        clock.value = _sample(60);
        expect(useCases.remainingMs(focus), 240000);
        clock.value = _sample(75);
        focus = (await useCases.background(
          expectedOwnerId: 'owner-a',
          sample: _sample(60),
        ))!;
        expect(focus.state, FocusState.paused);
        expect(focus.activeMs, 60000);
        expect(focus.hasUnknownGap, isTrue);
        final afterPause = await _rows(database);
        await useCases.background(expectedOwnerId: 'owner-a');
        expect(changed, 2);
        expect(await _rows(database), afterPause);
        clock.value = _sample(240);
        expect(useCases.remainingMs(focus), 240000);
        focus = await useCases.resume(
          expectedOwnerId: 'owner-a',
          id: focus.id,
          expectedRevision: focus.revision,
        );
        clock.value = _sample(300);
        focus = await useCases.finish(
          expectedOwnerId: 'owner-a',
          id: focus.id,
          expectedRevision: focus.revision,
        );
        expect(focus.activeMs, 120000);
        expect(focus.pausedMs, 0);
        expect(focus.hasUnknownGap, isTrue);
        expect(changed, 4);
        await useCases.week(expectedOwnerId: 'owner-a', civilMonday: _monday);
        await useCases.loadOpen(expectedOwnerId: 'owner-a');
        await useCases.recover(expectedOwnerId: 'owner-a');
        expect(changed, 4);
        await database.customStatement(
          "UPDATE local_owners SET is_active=0 WHERE id='owner-a'",
        );
        await database.customStatement(
          "INSERT INTO local_owners (id,created_at_utc_ms,is_active) VALUES ('owner-b',1,1)",
        );
        final switched = await _rows(database);
        await expectLater(
          useCases.start(expectedOwnerId: 'owner-a', targetMs: 300000),
          throwsStateError,
        );
        expect(changed, 4);
        expect(await _rows(database), switched);
        await useCases.dispose();
        await expectLater(
          useCases.start(expectedOwnerId: 'owner-b', targetMs: 300000),
          throwsStateError,
        );
        expect(await _rows(database), switched);
      } finally {
        await database.close();
      }
    },
  );
}

final class _Clock implements FocusClock {
  _Clock(this.value);
  FocusSample value;
  @override
  FocusSample sample() => value;
}

FocusSample _sample(int seconds) => FocusSample(
  utcMs: _at.add(Duration(seconds: seconds)).millisecondsSinceEpoch,
  monotonicUs: seconds * 1000000,
  continuityId: 'boot-a',
);

Future<FocusSnapshot> _start(
  DriftFocusRepository repository, {
  String id = 'focus-1',
  int targetMs = 300000,
}) => repository.start(
  expectedOwnerId: 'owner-a',
  id: id,
  targetMs: targetMs,
  sample: _sample(0),
);

Future<FocusSnapshot> _step(
  DriftFocusRepository repository,
  FocusSnapshot focus,
  FocusStep step,
  FocusSample sample,
) => repository.transition(
  expectedOwnerId: 'owner-a',
  id: focus.id,
  expectedRevision: focus.revision,
  step: step,
  sample: sample,
);

Future<void> _seed(AppDatabase database) => database.customStatement(
  "INSERT INTO local_owners (id,created_at_utc_ms,is_active) VALUES ('owner-a',1,1)",
);

Future<Map<String, List<Map<String, Object?>>>> _rows(
  AppDatabase database, {
  bool excludeFocus = false,
}) async => {
  for (final table in database.allTables)
    if (!excludeFocus ||
        ![
          'focus_sessions',
          'owner_calendar_epochs',
        ].contains(table.actualTableName))
      table.actualTableName:
          (await database
                  .customSelect(
                    'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
                  )
                  .get())
              .map((row) => row.data)
              .toList(),
};
