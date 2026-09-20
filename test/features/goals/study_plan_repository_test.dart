import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/goals/domain/study_plan.dart';
import 'package:vocab_learning_app/features/goals/data/drift_study_plan_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  late AppDatabase db;
  late Directory dir;
  late DriftStudyPlanRepository repo;
  final now = DateTime.utc(2026, 9, 20);
  StudyPlanRevision proposal({
    String op = 'op',
    int prior = 0,
    int minutes = 1,
  }) => StudyPlanRevision.propose(
    operationId: op,
    expectedPriorRevision: prior,
    createdAtUtc: now,
    timezoneId: 'Asia/Bangkok',
    availableMinutes: minutes,
    authorityHash: 'current',
    goalId: null,
    deadlineAtUtc: null,
    dueItemIds: ['due1', 'due2'],
    newItemIds: ['new'],
  );
  Future<StudyPlanRevision> accept(
    StudyPlanRevision p, {
    String authority = 'current',
    Future<void> Function()? guard,
  }) => repo.accept(
    ownerId: 'a',
    leaseToken: 'lease',
    proposal: p,
    requireCurrent: guard ?? () async {},
    readAuthorityHash: () async => authority,
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('study-plan-');
    db = AppDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
    repo = DriftStudyPlanRepository(db, nowUtc: () => now);
    await db.customStatement(
      "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES('a',1,1),('b',1,0)",
    );
    await DriftOwnerOperationGate(db).tryAcquire(
      token: 'lease',
      nowUtc: now,
      leaseDuration: const Duration(hours: 1),
    );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });
  test('accept persists one active revision across database restart', () async {
    final p = proposal();
    await accept(p);
    await db.close();
    db = AppDatabase(NativeDatabase(File('${dir.path}/db.sqlite')));
    repo = DriftStudyPlanRepository(db, nowUtc: () => now);
    expect((await repo.active('a'))!.payloadHash, p.payloadHash);
    expect(await repo.active('b'), isNull);
  });
  test(
    'lost ACK replays exact payload even after later revision accepted',
    () async {
      final p = proposal();
      await accept(p);
      await accept(proposal(op: 'second', prior: 1));
      expect(
        (await accept(p, authority: 'changed')).payloadHash,
        p.payloadHash,
      );
      expect((await repo.active('a'))!.revision, 2);
      await expectLater(accept(proposal(minutes: 0)), throwsStateError);
    },
  );
  test('stale revision or authority leaves active plan unchanged', () async {
    await accept(proposal());
    await expectLater(accept(proposal(op: 'stale')), throwsStateError);
    await expectLater(
      accept(proposal(op: 'changed', prior: 1), authority: 'other'),
      throwsStateError,
    );
    expect((await repo.active('a'))!.revision, 1);
    expect((await repo.history('a')).length, 1);
  });
  test(
    'late owner generation failure rolls back revision and pointer',
    () async {
      var checks = 0;
      await expectLater(
        accept(
          proposal(),
          guard: () async {
            if (++checks == 2) throw StateError('retired generation');
          },
        ),
        throwsStateError,
      );
      expect(await repo.active('a'), isNull);
      expect(await repo.history('a'), isEmpty);
    },
  );
  test(
    'immutable SQL guards deny update and replace but permit erasure',
    () async {
      await accept(proposal());
      await expectLater(
        db.customStatement("UPDATE study_plan_revisions SET payload_json='{}'"),
        throwsA(anything),
      );
      await expectLater(
        db.customStatement(
          'INSERT OR REPLACE INTO study_plan_revisions SELECT * FROM study_plan_revisions',
        ),
        throwsA(anything),
      );
      await db.customStatement(
        "DELETE FROM active_plan_pointers WHERE owner_id='a'",
      );
      await db.customStatement(
        "DELETE FROM study_plan_revisions WHERE owner_id='a'",
      );
      expect(await repo.history('a'), isEmpty);
    },
  );
  test(
    'archive restores exact history and older replay cannot rewind active plan',
    () async {
      await accept(proposal());
      final archive = await repo.exportArchive(
        ownerId: 'a',
        leaseToken: 'lease',
      );
      await accept(proposal(op: 'second', prior: 1));
      await repo.restoreArchive(
        ownerId: 'a',
        leaseToken: 'lease',
        envelope: archive,
        requireCurrent: () async {},
      );
      expect((await repo.active('a'))!.revision, 2);
      await db.customStatement(
        "DELETE FROM active_plan_pointers WHERE owner_id='a'",
      );
      await db.customStatement(
        "DELETE FROM study_plan_revisions WHERE owner_id='a'",
      );
      await repo.restoreArchive(
        ownerId: 'a',
        leaseToken: 'lease',
        envelope: archive,
        requireCurrent: () async {},
      );
      expect((await repo.active('a'))!.revision, 1);
      await expectLater(
        repo.restoreArchive(
          ownerId: 'b',
          leaseToken: 'lease',
          envelope: archive,
          requireCurrent: () async {},
        ),
        throwsStateError,
      );
      final corrupt = Map<String, Object?>.from(archive)
        ..['databaseSchemaVersion'] = 999;
      await expectLater(
        repo.restoreArchive(
          ownerId: 'a',
          leaseToken: 'lease',
          envelope: corrupt,
          requireCurrent: () async {},
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'expired lease and inactive owner cannot replay accepted command',
    () async {
      final p = proposal();
      await accept(p);
      await DriftOwnerOperationGate(db).release(token: 'lease');
      await expectLater(accept(p), throwsA(anything));
      await DriftOwnerOperationGate(db).tryAcquire(
        token: 'lease',
        nowUtc: now,
        leaseDuration: const Duration(hours: 1),
      );
      await db.customStatement(
        "UPDATE local_owners SET is_active=CASE WHEN id='b' THEN 1 ELSE 0 END",
      );
      await expectLater(accept(p), throwsStateError);
      expect((await repo.history('a')).length, 1);
    },
  );
}
