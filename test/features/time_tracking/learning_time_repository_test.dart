import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/data/drift_learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';

void main() {
  late AppDatabase database;
  late DriftLearningTimeRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner-1',
      nowUtc: () => DateTime.utc(2026, 8, 24),
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: 'session-1',
            ownerId: owner.id,
            activityType: 'meaning-quiz',
            state: 'active',
            startedAtUtcMs: DateTime.utc(2026, 8, 24, 9).millisecondsSinceEpoch,
            appVersion: 'test',
            buildId: 'test',
          ),
        );
    repository = DriftLearningTimeRepository(database, owners: owners);
  });

  tearDown(() => database.close());

  test(
    'append is atomic idempotent and never mutates learning projections',
    () async {
      final segment = _segment();

      await repository.append(segment);
      await repository.append(segment);

      expect(
        await database.select(database.learningTimeSegments).get(),
        hasLength(1),
      );
      final outbox = await database.select(database.outboxOperations).get();
      expect(outbox, hasLength(1));
      expect(outbox.single.entityType, 'learningTimeSegment');
      expect(outbox.single.entityId, segment.id);
      expect(
        await repository.activeDuration('session-1'),
        const Duration(seconds: 30),
      );
      expect(await database.select(database.srsStates).get(), isEmpty);
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        isEmpty,
      );
      expect(
        await database.select(database.questObjectiveProgress).get(),
        isEmpty,
      );
    },
  );

  test('same identity with different duration fails closed', () async {
    final segment = _segment();
    await repository.append(segment);
    final mismatch = LearningTimeSegment(
      sessionId: segment.sessionId,
      activeStartOffset: segment.activeStartOffset,
      activeDuration: const Duration(seconds: 31),
      startedAtUtc: segment.startedAtUtc,
      endedAtUtc: segment.endedAtUtc,
      timezone: segment.timezone,
      captureSource: segment.captureSource,
    );

    await expectLater(repository.append(mismatch), throwsStateError);
    expect(
      await database.select(database.learningTimeSegments).get(),
      hasLength(1),
    );
  });

  test('negative and overlapping active ranges are rejected', () async {
    expect(
      () => LearningTimeSegment(
        sessionId: 'session-1',
        activeStartOffset: const Duration(milliseconds: -1),
        activeDuration: const Duration(seconds: 1),
        startedAtUtc: DateTime.utc(2026, 8, 24, 9),
        endedAtUtc: DateTime.utc(2026, 8, 24, 9, 0, 1),
        timezone: const LearningTimeZoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
        captureSource: LearningTimeCaptureSource.automaticLesson,
      ),
      throwsArgumentError,
    );

    await repository.append(_segment());
    final overlap = LearningTimeSegment(
      sessionId: 'session-1',
      activeStartOffset: const Duration(seconds: 15),
      activeDuration: const Duration(seconds: 10),
      startedAtUtc: DateTime.utc(2026, 8, 24, 9, 1),
      endedAtUtc: DateTime.utc(2026, 8, 24, 9, 1, 10),
      timezone: const LearningTimeZoneContext(
        timezoneId: 'Asia/Bangkok',
        utcOffsetMinutes: 420,
      ),
      captureSource: LearningTimeCaptureSource.automaticLesson,
    );

    await expectLater(repository.append(overlap), throwsStateError);
    expect(
      await repository.activeDuration('session-1'),
      const Duration(seconds: 30),
    );
  });

  test('timezone context must exist and match its historical UTC offset', () {
    LearningTimeSegment segment(LearningTimeZoneContext timezone) =>
        LearningTimeSegment(
          sessionId: 'session-1',
          activeStartOffset: Duration.zero,
          activeDuration: const Duration(seconds: 1),
          startedAtUtc: DateTime.utc(2026, 8, 24, 9),
          endedAtUtc: DateTime.utc(2026, 8, 24, 9, 0, 1),
          timezone: timezone,
          captureSource: LearningTimeCaptureSource.automaticLesson,
        );

    expect(
      () => segment(
        const LearningTimeZoneContext(
          timezoneId: 'Mars/Olympus',
          utcOffsetMinutes: 0,
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => segment(
        const LearningTimeZoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 0,
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'restart fails closed on a remote gap until earlier offsets arrive',
    () async {
      final owner = await database.select(database.localOwners).getSingle();
      Future<void> insert(LearningTimeSegment segment) => database
          .into(database.learningTimeSegments)
          .insert(
            LearningTimeSegmentsCompanion.insert(
              id: segment.id,
              ownerId: owner.id,
              sessionId: segment.sessionId,
              activeStartOffsetMs: segment.activeStartOffset.inMilliseconds,
              activeDurationMs: segment.activeDuration.inMilliseconds,
              startedAtUtcMs: segment.startedAtUtc.millisecondsSinceEpoch,
              endedAtUtcMs: segment.endedAtUtc.millisecondsSinceEpoch,
              timezoneId: segment.timezone.timezoneId,
              timezoneOffsetMinutes: segment.timezone.utcOffsetMinutes,
              captureSource: segment.captureSource.name,
            ),
          );
      LearningTimeSegment remote({
        required int offset,
        required int duration,
      }) => LearningTimeSegment(
        sessionId: 'session-1',
        activeStartOffset: Duration(milliseconds: offset),
        activeDuration: Duration(milliseconds: duration),
        startedAtUtc: DateTime.utc(2026, 8, 24, 9),
        endedAtUtc: DateTime.utc(2026, 8, 24, 9),
        timezone: const LearningTimeZoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
        captureSource: LearningTimeCaptureSource.automaticLesson,
      );

      await insert(remote(offset: 10000, duration: 5000));
      await expectLater(
        repository.activeDuration('session-1'),
        throwsStateError,
      );
      await insert(remote(offset: 0, duration: 10000));
      expect(
        await repository.activeDuration('session-1'),
        const Duration(seconds: 15),
      );
      await repository.append(remote(offset: 15000, duration: 1000));
      expect(
        await repository.activeDuration('session-1'),
        const Duration(seconds: 16),
      );
    },
  );

  test('active duration never crosses an owner switch', () async {
    await repository.append(_segment());
    await database.transaction(() async {
      await database.customUpdate(
        'UPDATE local_owners SET is_active = 0 WHERE is_active = 1',
      );
      await database.customInsert(
        'INSERT INTO local_owners('
        'id, account_state, created_at_utc_ms, is_active'
        ") VALUES ('owner-2', 'localGuest', 2, 1)",
      );
    });

    await expectLater(repository.activeDuration('session-1'), throwsStateError);
  });
}

LearningTimeSegment _segment() => LearningTimeSegment(
  sessionId: 'session-1',
  activeStartOffset: Duration.zero,
  activeDuration: const Duration(seconds: 30),
  startedAtUtc: DateTime.utc(2026, 8, 24, 9),
  // Wall time is audit context only; rollback must not alter active duration.
  endedAtUtc: DateTime.utc(2026, 8, 24, 8, 59, 55),
  timezone: const LearningTimeZoneContext(
    timezoneId: 'Asia/Bangkok',
    utcOffsetMinutes: 420,
  ),
  captureSource: LearningTimeCaptureSource.automaticLesson,
);
