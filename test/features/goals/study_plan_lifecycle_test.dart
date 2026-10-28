import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/goals/domain/study_plan.dart';
import 'package:vocab_learning_app/features/goals/data/drift_study_plan_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  late AppDatabase db;
  final now = DateTime.utc(2026, 9, 20);
  Future<void> seed(String owner, String op) async {
    final p = StudyPlanRevision.propose(
      operationId: op,
      expectedPriorRevision: 0,
      createdAtUtc: now,
      timezoneId: 'Asia/Bangkok',
      availableMinutes: 10,
      authorityHash: 'fixture',
      goalId: null,
      deadlineAtUtc: null,
      dueItemIds: [],
      newItemIds: [],
    );
    await db
        .into(db.studyPlanRevisions)
        .insert(
          StudyPlanRevisionsCompanion.insert(
            ownerId: owner,
            operationId: op,
            revision: 1,
            payloadHash: p.payloadHash,
            payloadJson: jsonEncode(p.toJson()),
          ),
        );
    await db
        .into(db.activePlanPointers)
        .insert(
          ActivePlanPointersCompanion.insert(ownerId: owner, operationId: op),
        );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO local_owners(id,firebase_uid,account_state,created_at_utc_ms,is_active) VALUES('guest',NULL,'localGuest',1,1),('account','firebase-user','firebaseBound',2,0)",
    );
  });
  tearDown(() => db.close());
  test(
    'guest merge preserves both histories and the target active pointer',
    () async {
      await seed('guest', 'guest-plan');
      await seed('account', 'account-plan');
      final upgrade = DriftOwnerUpgradeRepository(
        db,
        nowUtc: () => now,
        generateConflictId: () => 'conflict',
        generateOwnerId: () => 'new-guest',
        generateOwnerOperationToken: () => 'upgrade-lease',
        deleteOwnerSecrets: (_) async {},
      );
      await upgrade.upgrade(
        activeOwnerId: 'guest',
        firebaseUid: 'firebase-user',
      );
      final repo = DriftStudyPlanRepository(db, nowUtc: () => now);
      expect(
        (await repo.history('account')).map((p) => p.operationId).toSet(),
        {'guest-plan', 'account-plan'},
      );
      expect((await repo.active('account'))!.operationId, 'account-plan');
      expect(await repo.history('guest'), isEmpty);
    },
  );
  test(
    'guest merge without target plan rebinds pointer and retains exact payload',
    () async {
      await seed('guest', 'guest-plan');
      final repo = DriftStudyPlanRepository(db, nowUtc: () => now);
      final hash = (await repo.active('guest'))!.payloadHash;
      final upgrade = DriftOwnerUpgradeRepository(
        db,
        nowUtc: () => now,
        generateConflictId: () => 'conflict',
        generateOwnerId: () => 'new-guest',
        generateOwnerOperationToken: () => 'upgrade-lease',
        deleteOwnerSecrets: (_) async {},
      );
      await upgrade.upgrade(
        activeOwnerId: 'guest',
        firebaseUid: 'firebase-user',
      );
      expect((await repo.active('account'))!.payloadHash, hash);
    },
  );
  test(
    'canonical export includes plan and erasure removes only target owner',
    () async {
      await seed('guest', 'guest-plan');
      await seed('account', 'account-plan');
      final artifact = await OwnerLifecycleArchiveExporter(
        database: db,
        nowUtc: () => now,
      ).prepareActive();
      final json = jsonDecode(utf8.decode(artifact.bytes)) as Map;
      final tables = (json['content'] as Map)['tables'] as List;
      final plans = tables.cast<Map>().singleWhere(
        (t) => t['alias'] == 'studyPlanRevisions',
      );
      expect((plans['records'] as List).length, 1);
      await LocalDataDeletion(
        db,
        deleteOwnerSecrets: (_) async {},
      ).eraseAll(ownerId: 'guest');
      final repo = DriftStudyPlanRepository(db, nowUtc: () => now);
      expect(await repo.history('guest'), isEmpty);
      expect((await repo.active('account'))!.operationId, 'account-plan');
    },
  );
}
