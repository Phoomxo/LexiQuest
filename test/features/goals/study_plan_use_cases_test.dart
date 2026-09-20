import 'dart:io';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/goals/application/study_plan_use_cases.dart';
import 'package:vocab_learning_app/features/goals/data/drift_study_plan_repository.dart';
import 'package:vocab_learning_app/features/identity/application/owner_generation.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_generation.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/vocabulary/data/packaged_starter_catalog.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/personal_sets.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/packaged_sense_crosswalk.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  late AppDatabase db;
  late StudyPlanUseCases app;
  late OwnerGeneration generation;
  var now = DateTime.utc(2026, 9, 20);
  var enabled = true;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 9, 20);
    enabled = true;
    await db.customStatement(
      "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES('a',1,1),('b',1,0)",
    );
    await PackagedStarterCatalog.provision(
      db,
      DriftContentManifestRepository(db),
      (identity) => File(
        'assets/content/lexical_metadata/starter-${PackagedStarterCatalog.words.firstWhere((w) => w.identity == identity).key}/r1.json',
      ).readAsBytes(),
    );
    Future<String> owner() async =>
        (await db
                .customSelect('SELECT id FROM local_owners WHERE is_active=1')
                .getSingle())
            .read<String>('id');
    generation = OwnerGeneration(
      activeOwnerId: owner,
      readDurableStamp: DriftOwnerGeneration(db).read,
    );
    app = StudyPlanUseCases(
      repository: DriftStudyPlanRepository(db, nowUtc: () => now),
      ownerGeneration: generation,
      ownerOperations: OwnerOperationCoordinator(
        gate: DriftOwnerOperationGate(db),
        activeOwnerId: owner,
        nowUtc: () => now,
      ),
      nowUtc: () => now,
      timezoneId: 'Asia/Bangkok',
      isAvailable: () => enabled,
    );
    await db.customStatement(
      "INSERT INTO srs_states(id,owner_id,word_id,due_at_utc_ms,algorithm_version) SELECT 'srs:'||id,'a',id,1,1 FROM vocabulary_words LIMIT 2",
    );
  });
  tearDown(() => db.close());
  Future<void> seedSet() async {
    final crosswalk = SenseCrosswalk.fromBytes(
      await File(PackagedSenseCrosswalk.assetPath).readAsBytes(),
      expectedSha256: PackagedSenseCrosswalk.artifactHash,
      corpusManifestHash: PackagedSenseCrosswalk.corpusManifestHash,
      reviewManifest: PackagedSenseCrosswalk.manifest,
    );
    final p = PersonalSetRevision.create(
      setId: 'set',
      operationId: 'save',
      expectedPriorRevision: 0,
      createdAtUtcMs: now.millisecondsSinceEpoch,
      title: 'Starter',
      crosswalkPin: SenseCrosswalkPin.fromJson({
        'corpusManifestHash': PackagedSenseCrosswalk.corpusManifestHash,
        'revision': 1,
        'artifactHash': PackagedSenseCrosswalk.artifactHash,
      }),
      members: crosswalk.entries.map((e) => e.ref).toList(),
    );
    await db
        .into(db.personalSetRevisions)
        .insert(
          PersonalSetRevisionsCompanion.insert(
            ownerId: 'a',
            setId: p.setId,
            revision: 1,
            operationId: p.operationId,
            payloadHash: p.payloadHash,
            payloadJson: jsonEncode(p.toJson()),
            archived: false,
          ),
        );
    for (var i = 0; i < p.members.length; i++) {
      final ref = p.members[i];
      await db
          .into(db.personalSetMembers)
          .insert(
            PersonalSetMembersCompanion.insert(
              ownerId: 'a',
              setId: p.setId,
              revision: 1,
              position: i,
              senseRefHash: ref.stableHash,
              senseRefJson: jsonEncode(ref.toJson()),
            ),
          );
    }
  }

  test(
    'canonical due proposal is read-only and acceptance has no learning side effects',
    () async {
      final token = await app.begin();
      final p = await app.propose(
        token,
        operationId: 'op',
        availableMinutes: 1,
      );
      expect(p.dueItems.length, 1);
      expect(p.carryOver.length, 1);
      expect(await app.active(token), isNull);
      await app.accept(token, p);
      expect((await app.active(token))!.revision, 1);
      expect((await db.select(db.srsStates).get()).length, 2);
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      expect(await db.select(db.rewardTransactions).get(), isEmpty);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    },
  );
  test(
    'changed due authority or learning day rejects stale proposal',
    () async {
      final token = await app.begin();
      final p = await app.propose(
        token,
        operationId: 'op',
        availableMinutes: 1,
      );
      await db.customStatement('UPDATE srs_states SET due_at_utc_ms=2');
      await expectLater(app.accept(token, p), throwsStateError);
      final p2 = await app.propose(
        token,
        operationId: 'op2',
        availableMinutes: 1,
      );
      now = now.add(const Duration(days: 1));
      await expectLater(app.accept(token, p2), throwsStateError);
      expect(await app.active(token), isNull);
    },
  );
  test('generation ABA and disabled entry reject retained commands', () async {
    final token = await app.begin();
    final p = await app.propose(token, operationId: 'op', availableMinutes: 1);
    enabled = false;
    await expectLater(app.accept(token, p), throwsStateError);
    enabled = true;
    await generation.duringTransition(() async {});
    await expectLater(app.accept(token, p), throwsStateError);
    expect(await app.active(await app.begin()), isNull);
  });
  test('goal timezone and changed deadline remain current authority', () async {
    await db.customStatement(
      "INSERT INTO learning_goals(id,owner_id,kind,title,deadline_at_utc_ms,timezone_id,timezone_offset_minutes,status,created_at_utc_ms,updated_at_utc_ms) VALUES('g','a','personal','Goal',1,'America/New_York',-300,'active',1,1)",
    );
    final token = await app.begin();
    final p = await app.propose(
      token,
      operationId: 'goal-plan',
      availableMinutes: 2,
      goalId: 'g',
    );
    expect(p.timezoneId, 'America/New_York');
    expect(p.deadlinePassed, isTrue);
    await db.customStatement(
      "UPDATE learning_goals SET deadline_at_utc_ms=2 WHERE id='g'",
    );
    await expectLater(app.accept(token, p), throwsStateError);
    expect(await app.active(token), isNull);
  });
  test(
    'F01 new words use spare capacity and canonical SRS changes invalidate diff',
    () async {
      await seedSet();
      final token = await app.begin();
      final p = await app.propose(
        token,
        operationId: 'set-plan',
        availableMinutes: 3,
      );
      expect(p.dueItems.length, 2);
      expect(p.newItems.length, 1);
      expect(p.dueItems.toSet().intersection(p.newItems.toSet()), isEmpty);
      final source = (await db.select(db.srsStates).get()).first;
      await db.customStatement(
        "UPDATE srs_states SET due_at_utc_ms=9999999999999 WHERE id='${source.id}'",
      );
      await expectLater(app.accept(token, p), throwsStateError);
      expect(await app.active(token), isNull);
    },
  );
  test('inconsistent F01 normalized membership fails plan admission', () async {
    await seedSet();
    await db.customStatement(
      "DELETE FROM personal_set_members WHERE owner_id='a' AND position=0",
    );
    await expectLater(
      app.propose(
        await app.begin(),
        operationId: 'corrupt-set',
        availableMinutes: 10,
      ),
      throwsStateError,
    );
  });
  test(
    'application exports and restores an owner-fenced history backup',
    () async {
      final owner = await app.begin();
      await app.accept(
        owner,
        await app.propose(owner, operationId: 'backup', availableMinutes: 0),
      );
      final archive = await app.exportArchive(owner);
      await db.customStatement(
        "DELETE FROM active_plan_pointers WHERE owner_id='a'",
      );
      await db.customStatement(
        "DELETE FROM study_plan_revisions WHERE owner_id='a'",
      );
      await app.restoreArchive(owner, archive);
      expect((await app.active(owner))!.operationId, 'backup');
      await generation.duringTransition(() async {});
      await expectLater(app.restoreArchive(owner, archive), throwsStateError);
    },
  );
}
