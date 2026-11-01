import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning_profile/data/drift_learning_profile_repository.dart';
import 'package:vocab_learning_app/features/learning_profile/domain/learning_profile.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_learning_day_recorder.dart';
import 'package:vocab_learning_app/features/motivation/domain/motivation_snapshot.dart';

import '../quest/support/quest_repository_harness.dart';

void main() {
  late QuestHarness h;
  late StreakUseCases streak;
  setUp(() async {
    h = await QuestHarness.open();
    streak = StreakUseCases(
      repository: DriftStreakRepository(
        h.database,
        ownerWrites: h.storage.ownerWrites,
        quests: h.repository,
        nowUtc: () => h.now,
      ),
      nowUtc: () => h.now,
      generateId: () => 'synthetic-protection',
    );
  });
  tearDown(() => h.close());

  Future<void> timezone(String value) async {
    final repository = DriftLearningProfileRepository(
      database: h.database,
      ownerWrites: h.storage.ownerWrites,
    );
    final snapshot = await repository.read(
      expectedOwnerId: configuredOwnerId,
      stillCurrent: () => true,
    );
    await repository.save(
      LearningProfileChange(
        expectedOwnerId: configuredOwnerId,
        expectedRevision: snapshot.revision,
        draft: LearningProfileDraft(
          onboardingState: LearningOnboardingState.completed,
          learningTimezoneId: value,
        ),
        updatedAtUtc: h.now,
        stillCurrent: () => true,
      ),
    );
  }

  Future<MotivationSnapshot> read() =>
      streak.load(expectedOwnerId: configuredOwnerId, stillCurrent: () => true);

  test(
    'actual canonical answers extend one streak without read writes',
    () async {
      await timezone('Asia/Bangkok');
      h.now = DateTime.utc(2026, 10, 29, 16, 59);
      await h.answer(
        id: 'synthetic-first',
        sessionId: 'synthetic-first-session',
      );
      final first = await read();
      expect(first.state.currentStreakDays, 1);
      expect(first.learningDays.single.learningDay, '2026-10-29');
      h.now = DateTime.utc(2026, 10, 29, 17, 1);
      await h.answer(
        id: 'synthetic-second',
        sessionId: 'synthetic-second-session',
      );
      final before = await h.storage.snapshot();
      final second = await read();
      expect(second.state.currentStreakDays, 2);
      expect(second.state.longestStreakDays, 2);
      expect(second.learningDays.map((day) => day.learningDay), [
        '2026-10-29',
        '2026-10-30',
      ]);
      expect(second.usedUtcFallback, isFalse);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'same-day replay creates one pinned day and no extra learning effects',
    () async {
      await timezone('UTC');
      final event = await h.answer();
      final original = await h.storage.snapshot();
      await h.answer();
      final snapshot = await read();
      expect(snapshot.state.currentStreakDays, 1);
      expect(snapshot.learningDays.single.sourceAttemptId, event.eventId);
      expect(await h.storage.count('learning_day_log'), 1);
      expect(await h.storage.snapshot(), original);
      expect((await h.storage.researchCounts()).values, everyElement(0));
    },
  );

  test(
    'missing two days resets current streak and keeps longest run',
    () async {
      await timezone('UTC');
      h.now = DateTime.utc(2026, 10, 26, 12);
      await h.answer(id: 'synthetic-day1', sessionId: 'synthetic-session1');
      h.now = h.now.add(const Duration(days: 1));
      await h.answer(id: 'synthetic-day2', sessionId: 'synthetic-session2');
      h.now = h.now.add(const Duration(days: 3));
      expect((await read()).state.currentStreakDays, 0);
      await h.answer(id: 'synthetic-day5', sessionId: 'synthetic-session5');
      final result = await read();
      expect(result.state.currentStreakDays, 1);
      expect(result.state.longestStreakDays, 2);
      expect(result.state.freezeCount, 0);
    },
  );

  test('legacy day rows alone cannot create learning or freeze evidence', () async {
    await h.sql(
      'INSERT INTO learning_day_log(id,owner_id,learning_day,first_session_at_utc_ms) VALUES(?,?,?,?)',
      [
        'synthetic-legacy-day',
        configuredOwnerId,
        '2026-10-29',
        h.now.millisecondsSinceEpoch,
      ],
    );
    await h.sql(
      'INSERT INTO streak_states(owner_id,current_streak_days,longest_streak_days,freeze_count,updated_at_utc_ms) VALUES(?,?,?,?,?)',
      [configuredOwnerId, 99, 99, 999, h.now.millisecondsSinceEpoch],
    );
    final before = await h.storage.snapshot();
    final snapshot = await read();
    expect(snapshot.state.currentStreakDays, 0);
    expect(snapshot.state.longestStreakDays, 0);
    expect(snapshot.state.freezeCount, 0);
    expect(snapshot.learningDays, isEmpty);
    expect(await h.storage.snapshot(), before);
  });

  test(
    'unreceipted actual ordinary answers retain explicit UTC compatibility',
    () async {
      h.now = DateTime.utc(2026, 10, 28, 12);
      await h.answer(
        id: 'synthetic-legacy1',
        sessionId: 'synthetic-legacy-session1',
      );
      h.now = h.now.add(const Duration(days: 1));
      await h.answer(
        id: 'synthetic-legacy2',
        sessionId: 'synthetic-legacy-session2',
      );
      await h.sql('DELETE FROM learning_day_log');
      await timezone('Asia/Bangkok');
      final before = await h.storage.snapshot();
      final snapshot = await read();
      expect(snapshot.state.currentStreakDays, 2);
      expect(snapshot.usedUtcFallback, isTrue);
      expect(snapshot.learningDays.map((day) => day.timezoneId).toSet(), {
        'UTC',
      });
      expect(snapshot.learningDays.every((day) => !day.pinned), isTrue);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'legacy row coexists with a new canonical day receipt unchanged',
    () async {
      await timezone('UTC');
      await h.sql(
        'INSERT INTO learning_day_log(id,owner_id,learning_day,first_session_at_utc_ms) VALUES(?,?,?,?)',
        ['synthetic-original-legacy', configuredOwnerId, '2026-10-29', 1],
      );
      await h.answer();
      final rows = await h.database
          .customSelect('SELECT * FROM learning_day_log ORDER BY id')
          .get();
      expect(rows, hasLength(2));
      final legacy = rows.singleWhere(
        (row) => row.read<String>('id') == 'synthetic-original-legacy',
      );
      expect(legacy.read<int>('first_session_at_utc_ms'), 1);
      expect(legacy.readNullable<String>('source_attempt_id'), isNull);
      final snapshot = await read();
      expect(snapshot.state.currentStreakDays, 1);
      expect(snapshot.learningDays, hasLength(1));
    },
  );

  test('profile changes do not relabel a retained canonical day', () async {
    await timezone('Asia/Bangkok');
    h.now = DateTime.utc(2026, 10, 29, 17, 1);
    await h.answer();
    final before = await h.database
        .select(h.database.learningDayLog)
        .getSingle();
    await timezone('America/New_York');
    final snapshot = await read();
    expect(snapshot.learningDays.single.learningDay, '2026-10-30');
    expect(snapshot.learningDays.single.timezoneId, 'Asia/Bangkok');
    expect(
      (await h.database.select(h.database.learningDayLog).getSingle()).toJson(),
      before.toJson(),
    );
  });

  test('retired owner callbacks cannot read or mutate the new owner', () async {
    await h.answer();
    final before = await h.storage.snapshot();
    var current = true;
    final pending = streak.load(
      expectedOwnerId: configuredOwnerId,
      stillCurrent: () => current,
    );
    current = false;
    await expectLater(pending, throwsA(anything));
    await h.storage.switchOwner(configuredOtherOwnerId);
    await h.storage.switchOwner(configuredOwnerId);
    await expectLater(
      streak.load(
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => current,
      ),
      throwsA(anything),
    );
    expect((await read()).state.currentStreakDays, 1);
    final after = await h.storage.snapshot();
    after['local_owners'] = before['local_owners']!;
    expect(after, before);
  });

  test(
    'invalid stored timezone keeps ordinary learning available and streak unavailable',
    () async {
      await timezone('UTC');
      await h.sql(
        'UPDATE learning_profiles SET learning_timezone_id=? WHERE owner_id=?',
        ['Synthetic/Unknown', configuredOwnerId],
      );
      await h.answer();
      expect(await h.storage.count('answer_attempts'), 1);
      expect(await h.storage.count('learning_day_log'), 0);
      await expectLater(read(), throwsA(isA<MotivationException>()));
      expect((await h.storage.researchCounts()).values, everyElement(0));
    },
  );

  test('a timezone change waits for the already pinned day boundary', () async {
    await timezone('UTC');
    h.now = DateTime.utc(2026, 10, 29, 23);
    await h.answer(
      id: 'synthetic-before-zone-jump',
      sessionId: 'synthetic-before-zone-session',
    );
    final first = await h.database
        .select(h.database.learningDayLog)
        .getSingle();
    h.now = DateTime.utc(2026, 10, 29, 23, 1);
    await timezone('Pacific/Kiritimati');
    await h.answer(
      id: 'synthetic-inside-pinned-window',
      sessionId: 'synthetic-inside-window-session',
    );
    final inside = await read();
    expect(inside.state.currentStreakDays, 1);
    expect(inside.learningDays.map((day) => day.learningDay).toSet(), {
      '2026-10-29',
    });
    expect(
      (await h.database.select(h.database.learningDayLog).getSingle()).toJson(),
      first.toJson(),
    );
    h.now = DateTime.utc(2026, 10, 30, 0, 1);
    await h.answer(
      id: 'synthetic-after-pinned-boundary',
      sessionId: 'synthetic-after-boundary-session',
    );
    final after = await read();
    expect(after.state.currentStreakDays, 2);
    expect(after.learningDays.map((day) => day.learningDay).toSet(), {
      '2026-10-29',
      '2026-10-30',
    });
    final newDay = (await h.database.select(h.database.learningDayLog).get())
        .singleWhere((day) => day.learningDay == '2026-10-30');
    expect(newDay.timezoneId, 'Pacific/Kiritimati');
    expect(newDay.sourceAttemptId, 'synthetic-after-pinned-boundary');
    expect((await h.storage.researchCounts()).values, everyElement(0));
  });

  test(
    'synced placeholders keep UTC compatibility without accepting local timezone pins',
    () async {
      h.now = DateTime.utc(2026, 10, 29, 12);
      final event = await h.answer(
        id: 'synthetic-synced-fallback',
        sessionId: 'synthetic-synced-session',
      );
      await h.sql('DELETE FROM learning_day_log');
      await h.sql(
        "UPDATE learning_sessions SET activity_type='syncedEvidence',state='syncedEvidence',app_version='unknown',build_id='synced' WHERE id=?",
        ['synthetic-synced-session'],
      );
      await timezone('Pacific/Kiritimati');
      await h.sql(
        'INSERT INTO learning_day_log(id,owner_id,learning_day,first_session_at_utc_ms,source_attempt_id,timezone_id,policy_version) VALUES(?,?,?,?,?,?,?)',
        [
          'synthetic-untrusted-import-pin',
          configuredOwnerId,
          '2026-10-30',
          h.now.millisecondsSinceEpoch,
          event.eventId,
          'Pacific/Kiritimati',
          1,
        ],
      );
      final before = await h.storage.snapshot();
      final snapshot = await read();
      expect(snapshot.learningDays, hasLength(1));
      expect(snapshot.learningDays.single.learningDay, '2026-10-29');
      expect(snapshot.learningDays.single.timezoneId, 'UTC');
      expect(snapshot.learningDays.single.pinned, isFalse);
      expect(snapshot.usedUtcFallback, isTrue);
      await h.database.transaction(
        () => DriftLearningDayRecorder(
          h.database,
          ownerWrites: h.storage.ownerWrites,
        ).recordAnswer(event.eventId),
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test('a single answer cannot support two forged pinned civil labels', () async {
    await timezone('UTC');
    h.now = DateTime.utc(2026, 10, 29, 17, 1);
    final event = await h.answer();
    await h.sql(
      'INSERT INTO learning_day_log(id,owner_id,learning_day,first_session_at_utc_ms,source_attempt_id,timezone_id,policy_version) VALUES(?,?,?,?,?,?,?)',
      [
        'synthetic-forged-second-pin',
        configuredOwnerId,
        '2026-10-30',
        h.now.millisecondsSinceEpoch,
        event.eventId,
        'Asia/Bangkok',
        1,
      ],
    );
    final snapshot = await read();
    expect(snapshot.state.currentStreakDays, 1);
    expect(snapshot.learningDays, hasLength(1));
    expect(snapshot.learningDays.single.timezoneId, 'UTC');
    expect(snapshot.usedUtcFallback, isTrue);
  });
}
