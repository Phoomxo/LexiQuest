import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';

final _time = DateTime.utc(2026, 8, 4, 10);

class _Owners implements LocalOwnerRepository {
  _Owners(this.owner);
  LocalOwner owner;
  LocalOwner? switchAfterFirst;
  int reads = 0;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    reads++;
    final result = owner;
    if (reads == 1 && switchAfterFirst != null) owner = switchAfterFirst!;
    return result;
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) async => owner;
}

void main() {
  setUpAll(tz.initializeTimeZones);
  late AppDatabase db;
  late _Owners owners;
  late DateTime clock;
  late StreakUseCases useCases;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES ('a',1,1),('b',1,0)",
    );
    owners = _Owners(
      LocalOwner(
        id: 'a',
        createdAtUtc: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
      ),
    );
    clock = _time;
    useCases = StreakUseCases(
      repository: DriftStreakRepository(db, calendarVisible: () => true),
      owners: owners,
      nowUtc: () => clock,
    );
  });
  tearDown(() => db.close());

  test('calendar load is owner bound, UTC by default, and read-only', () async {
    final view = await useCases.loadCalendar();
    expect(view.ownerId, 'a');
    expect(view.current.ianaId, 'UTC');
    expect(view.pending, isNull);
    expect(await db.select(db.ownerCalendarEpochs).get(), isEmpty);
  });

  test(
    'calendar selection retains current rule and shows pending region',
    () async {
      final selected = await useCases.selectHomeTimezone(
        expectedOwnerId: 'a',
        ianaId: 'Asia/Bangkok',
      );
      final view = await useCases.loadCalendar();
      expect(view.current.ianaId, 'UTC');
      expect(view.pending?.ianaId, 'Asia/Bangkok');
      expect(view.pending?.ruleId, selected.ruleId);
      expect(
        view.pending!.effectiveUtcUs,
        greaterThan(clock.microsecondsSinceEpoch),
      );
    },
  );

  test(
    'wrong owner and invalid local clock fail before calendar writes',
    () async {
      await expectLater(
        useCases.selectHomeTimezone(
          expectedOwnerId: 'b',
          ianaId: 'Asia/Bangkok',
        ),
        throwsStateError,
      );
      expect(await db.select(db.ownerCalendarEpochs).get(), isEmpty);
      clock = DateTime(2026, 8, 4);
      await expectLater(
        useCases.selectHomeTimezone(
          expectedOwnerId: 'a',
          ianaId: 'Asia/Bangkok',
        ),
        throwsArgumentError,
      );
      expect(await db.select(db.ownerCalendarEpochs).get(), isEmpty);
    },
  );

  test('owner change while loading calendar suppresses stale result', () async {
    owners.switchAfterFirst = LocalOwner(
      id: 'b',
      createdAtUtc: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
    );
    await expectLater(useCases.loadCalendar(), throwsStateError);
    expect(await db.select(db.ownerCalendarEpochs).get(), isEmpty);
  });

  test(
    'manual debit checks owner, replays after clock changes and cannot underflow',
    () async {
      await db.customStatement(
        'INSERT INTO streak_baselines(origin_owner_id,owner_id,cutoff_utc_ms,current_streak_days,longest_streak_days,freeze_count,last_learned_at_utc_ms,updated_at_utc_ms,controls_continuity) VALUES (?,?,?,?,?,?,?,?,?)',
        ['a', 'a', 1, 0, 0, 1, null, 1, 1],
      );
      expect(
        await useCases.useFreezeToken(
          expectedOwnerId: 'a',
          commandId: 'synthetic-debit',
        ),
        isTrue,
      );
      clock = clock.add(const Duration(days: 1));
      expect(
        await useCases.useFreezeToken(
          expectedOwnerId: 'a',
          commandId: 'synthetic-debit',
        ),
        isTrue,
      );
      expect(
        await useCases.useFreezeToken(
          expectedOwnerId: 'a',
          commandId: 'synthetic-debit-2',
        ),
        isFalse,
      );
      final rows = await db.select(db.streakTokenAdjustments).get();
      expect(rows, hasLength(1));
      expect(rows.single.kind, 'manualDebit');
      expect(rows.single.occurredAtUtcMs, _time.millisecondsSinceEpoch);
    },
  );

  test(
    'settlement and answer notification reject stale owner before writes',
    () async {
      await expectLater(
        useCases.settle(expectedOwnerId: 'b'),
        throwsStateError,
      );
      await expectLater(
        useCases.afterAnswerCommitted(
          ownerId: 'b',
          attemptId: 'fake',
          occurredAtUtcMs: _time.millisecondsSinceEpoch,
        ),
        throwsStateError,
      );
      expect(await db.select(db.learningDayLog).get(), isEmpty);
      expect(await db.select(db.streakTokenAdjustments).get(), isEmpty);
    },
  );
}
