import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/identity/application/owner_generation.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_generation.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/personal_sets_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_personal_set_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/packaged_sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/vocabulary/data/packaged_starter_catalog.dart';
import 'package:vocab_learning_app/features/adventure/application/dialogue_mission_use_cases.dart';
import 'package:vocab_learning_app/features/adventure/domain/dialogue_mission.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_session_plan.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/features/adventure/presentation/dialogue_mission_screen.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';

void main() {
  late AppDatabase db;
  late Directory directory;
  late File databaseFile;
  late PersonalSetsUseCases sets;

  var enabled = true;
  var missing = false;
  String? missingId;
  Future<void> Function()? duringAdmission;
  var serial = 0;
  final now = DateTime.utc(2026, 9, 20);
  Future<void> wire() async {
    Future<Uint8List?> load(ContentIdentity identity) async {
      await duringAdmission?.call();
      if (missing || identity.id == missingId) return null;
      if (identity == PackagedSenseCrosswalk.identity) {
        return File(PackagedSenseCrosswalk.assetPath).readAsBytes();
      }
      return File(
        'assets/content/lexical_metadata/${identity.id.substring(5)}/r${identity.revision}.json',
      ).readAsBytes();
    }

    final manifests = DriftContentManifestRepository(
      db,
      loadArtifactBytes: load,
    );
    await PackagedStarterCatalog.provision(db, manifests, load);
    await manifests.provisionPackagedArtifact(
      PackagedSenseCrosswalk.verify(
        (await load(PackagedSenseCrosswalk.identity))!,
      ),
    );
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'unused',
      nowUtc: () => now,
    );
    Future<String> activeOwner() async =>
        (await owners.getOrCreateActiveOwner()).id;
    sets = PersonalSetsUseCases(
      repository: DriftPersonalSetRepository(
        db,
        SenseCrosswalkRepository(manifests),
        nowUtc: () => now,
      ),
      ownerGeneration: OwnerGeneration(
        activeOwnerId: activeOwner,
        readDurableStamp: DriftOwnerGeneration(db).read,
      ),
      ownerOperations: OwnerOperationCoordinator(
        gate: DriftOwnerOperationGate(db),
        activeOwnerId: activeOwner,
        nowUtc: () => now,
      ),
    );
  }

  late LearningUseCases learning;
  late DialogueMissionUseCases service;
  DialogueMissionUseCases createService() => DialogueMissionUseCases(
    sets: sets,
    learning: learning,
    evidence: CurrentActivityEvidenceAdapter(learning: learning),
    isAvailable: () => enabled,
  );
  void wireLearning() {
    learning = LearningUseCases(
      owners: DriftLocalOwnerRepository(
        db,
        generateId: () => 'unused',
        nowUtc: () => now,
      ),
      repository: DriftLearningRepository(db),
      generateId: () => 'dialogue-${++serial}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'dialogue'),
    );
    service = createService();
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('dialogue-test-');
    databaseFile = File('${directory.path}/data.sqlite');
    db = AppDatabase(NativeDatabase(databaseFile));
    await db.customStatement(
      "INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES ('a', 1, 1)",
    );
    enabled = true;
    missing = false;
    missingId = null;
    duringAdmission = null;
    await wire();
    learning = LearningUseCases(
      owners: DriftLocalOwnerRepository(
        db,
        generateId: () => 'unused',
        nowUtc: () => now,
      ),
      repository: DriftLearningRepository(db),
      generateId: () => 'dialogue-${++serial}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'dialogue'),
    );
    service = createService();
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });
  AdventureSessionPlanV1 plan([DialogueMission? selected]) {
    final m = selected ?? DialogueMissionInventory.missions.first;
    final config = SessionConfiguration.validated(
      schemaVersion: sessionConfigurationSchemaVersion,
      policyVersion: sessionConfigurationPolicyVersion,
      ownerId: 'a',
      mode: LessonMode.cloze,
      itemCount: 1,
      direction: SessionDirection.forward,
      difficulty: SessionDifficulty.standard,
      hintBudget: 0,
      timing: const SessionTiming.untimedAlternative(
        maximumActiveEffort: Duration(minutes: 5),
      ),
      packIdentity: null,
      protocolId: 'protocol:local',
      protocolVersion: '1',
      protocolLimitsIdentity: 'limits:dialogue',
    );
    return AdventureSessionPlanV1(
      planId: 'adventure-plan:test',
      ownerId: 'a',
      createdAtUtc: now,
      sourceEvaluatedAtUtc: now,
      content: [
        ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: m.wordId,
          revision: m.contentRevision,
        ),
      ],
      contentChecksumsSha256: {
        m.wordId:
            ((jsonDecode(
                              File(
                                PackagedSenseCrosswalk.assetPath,
                              ).readAsStringSync(),
                            )
                            as Map)['entries']
                        as List)
                    .firstWhere(
                      (e) => e['ref']['wordId'] == m.wordId,
                    )['wordChecksumSha256']
                as String,
      },
      mode: LessonMode.cloze,
      configuration: config,
      recommendationPolicyVersion: 'f14-v1',
      sourceReasonCode: 'learnerOverride',
      learnerOverrideApplied: true,
      origin: const AdventureOriginContextV1(
        planId: 'adventure-plan:test',
        nodeId: 'today-mission',
        catalogId: 'test',
        catalogVersion: '1',
        catalogSchemaVersion: 1,
        presentation: TodayExperiencePresentation.adventure,
      ),
    );
  }

  Future<DialogueRun> start() async => service.start(
    await sets.begin(),
    plan: plan(),
    mission: DialogueMissionInventory.missions.first,
    operationId: 'launch-1',
  );
  for (final mission in DialogueMissionInventory.missions) {
    for (final path in [
      ['target'],
      ['alternative', 'target'],
      ['alternative', 'alternative'],
    ]) {
      test(
        'admitted ${mission.id} path ${path.join("/")} terminates with one receipt per choice',
        () async {
          var run = await service.start(
            await sets.begin(),
            plan: plan(mission),
            mission: mission,
            operationId: 'all-branches',
          );
          for (final choice in path) {
            run = await service.choose(
              run,
              nodeId: run.node.id,
              choiceId: choice,
              operationId: 'turn-${run.decisions.length}',
            );
          }
          expect(run.node.terminal, isTrue);
          final result = await service.complete(run);
          expect(
            result.summary!.correctCount,
            path.where((c) => c == 'target').length,
          );
          expect(
            result.summary!.wrongCount,
            path.where((c) => c == 'alternative').length,
          );
          expect(
            await db.select(db.answerAttempts).get(),
            hasLength(path.length),
          );
          expect(await db.select(db.rewardTransactions).get(), isEmpty);
        },
      );
    }
  }
  test(
    'LOST-ACK restart and replay retain one canonical choice and receipt',
    () async {
      final first = await start();
      Future<void> loseAcknowledgement() async {
        await service.choose(
          first,
          nodeId: 'request',
          choiceId: 'alternative',
          operationId: 'choice-1',
        );
        throw const SocketException(
          'Injected lost acknowledgement after commit',
        );
      }

      await expectLater(loseAcknowledgement(), throwsA(isA<SocketException>()));
      service.dispose();
      await db.close();
      db = AppDatabase(NativeDatabase(databaseFile));
      await wire();
      wireLearning();
      final reopened = await service.resume(
        await sets.begin(),
        first.session.id,
      );
      expect(reopened.decisions.length, 1);
      expect(reopened.node.id, 'repair');
      final replay = await service.choose(
        reopened,
        nodeId: 'request',
        choiceId: 'alternative',
        operationId: 'choice-1',
      );
      expect(replay.decisions.length, 1);
      await expectLater(
        service.choose(
          replay,
          nodeId: 'request',
          choiceId: 'target',
          operationId: 'choice-1',
        ),
        throwsStateError,
      );
      final done = await service.choose(
        replay,
        nodeId: 'repair',
        choiceId: 'target',
        operationId: 'choice-2',
      );
      expect(done.node.terminal, isTrue);
      expect(done.decisions.last['assisted'], isTrue);
      expect(
        (await learning.loadExactActivityRecovery(
          ownerId: 'a',
          sessionId: first.session.id,
          activityType: dialogueActivityType,
        ))!.attempts.length,
        2,
      );
      final closed = await service.complete(done);
      expect(closed.summary!.state, 'completed');
      expect((await service.complete(done)).summary!.id, closed.summary!.id);
      expect((await start()).session.id, first.session.id);
      expect(await db.select(db.learningSessions).get(), hasLength(1));
    },
  );
  test(
    'withdrawn content and disabled entry still allow idempotent abandonment',
    () async {
      final first = await start();
      final chosen = await service.choose(
        first,
        nodeId: 'request',
        choiceId: 'alternative',
        operationId: 'before-withdrawal',
      );
      missing = true;
      enabled = false;
      final ended = await service.abandon(chosen.owner, chosen.session.id);
      expect(ended.state, 'abandoned');
      expect(
        (await service.abandon(chosen.owner, chosen.session.id)).endedAtUtc,
        ended.endedAtUtc,
      );
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
      expect(await db.select(db.rewardTransactions).get(), isEmpty);
    },
  );
  test(
    'stale backtracking and parallel taps never create another attempt',
    () async {
      final first = await start();
      final both = await Future.wait([
        service.choose(
          first,
          nodeId: 'request',
          choiceId: 'target',
          operationId: 'tap',
        ),
        service.choose(
          first,
          nodeId: 'request',
          choiceId: 'target',
          operationId: 'tap',
        ),
      ]);
      expect(both.last.decisions.length, 1);
      await expectLater(
        service.choose(
          first,
          nodeId: 'request',
          choiceId: 'alternative',
          operationId: 'backtrack',
        ),
        throwsStateError,
      );
      expect(
        (await learning.loadExactActivityRecovery(
          ownerId: 'a',
          sessionId: first.session.id,
          activityType: dialogueActivityType,
        ))!.attempts.length,
        1,
      );
    },
  );
  test(
    'feature retirement and owner change fence old handles without writes',
    () async {
      final first = await start();
      enabled = false;
      await expectLater(
        service.choose(
          first,
          nodeId: 'request',
          choiceId: 'target',
          operationId: 'late',
        ),
        throwsStateError,
      );
      enabled = true;
      await db.customStatement(
        "UPDATE local_owners SET is_active=0 WHERE id='a'",
      );
      await db.customStatement(
        "INSERT INTO local_owners (id,created_at_utc_ms,is_active) VALUES ('b',2,1)",
      );
      await expectLater(
        service.choose(
          first,
          nodeId: 'request',
          choiceId: 'target',
          operationId: 'late',
        ),
        throwsStateError,
      );
      await expectLater(
        service.resume(await sets.begin(), first.session.id),
        throwsStateError,
      );
      expect((await db.select(db.answerAttempts).get()), isEmpty);
    },
  );
  test(
    'withdrawn exact content denies progression and does not substitute',
    () async {
      final first = await start();
      missing = true;
      await expectLater(
        service.choose(
          first,
          nodeId: 'request',
          choiceId: 'target',
          operationId: 'withdrawn',
        ),
        throwsA(
          isA<ContentQualityFailure>().having(
            (e) => e.code,
            'code',
            ContentQualityFailureCode.missingReference,
          ),
        ),
      );
      expect((await db.select(db.answerAttempts).get()), isEmpty);
    },
  );
  test('retiring and re-enabling requires a fresh handle', () async {
    final first = await start();
    service.retire();
    await expectLater(
      service.choose(
        first,
        nodeId: 'request',
        choiceId: 'target',
        operationId: 'old-handle',
      ),
      throwsStateError,
    );
    final fresh = await service.resume(await sets.begin(), first.session.id);
    expect(
      (await service.choose(
        fresh,
        nodeId: 'request',
        choiceId: 'target',
        operationId: 'fresh',
      )).decisions.length,
      1,
    );
  });
  for (final boundary in ['retire', 'feature', 'owner']) {
    test(
      'in-flight $boundary change rolls back evidence and branch together',
      () async {
        final first = await start();
        duringAdmission = () async {
          duringAdmission = null;
          if (boundary == 'retire') service.retire();
          if (boundary == 'feature') enabled = false;
          if (boundary == 'owner') await DriftOwnerGeneration(db).advance();
        };
        await expectLater(
          service.choose(
            first,
            nodeId: 'request',
            choiceId: 'target',
            operationId: 'late',
          ),
          throwsStateError,
        );
        expect(await db.select(db.answerAttempts).get(), isEmpty);
        enabled = true;
        final recovered = await service.resume(
          await sets.begin(),
          first.session.id,
        );
        expect(recovered.decisions, isEmpty);
        expect(recovered.checkpointRevision, 1);
      },
    );
  }
  test(
    'checkpoint failure rolls back evidence; exact retry succeeds once',
    () async {
      final first = await start();
      await db.customStatement(
        "CREATE TRIGGER dialogue_injected_failure BEFORE INSERT ON events_v2 WHEN NEW.event_type='LearningActivityCheckpoint' BEGIN SELECT RAISE(ABORT, 'injected checkpoint failure'); END",
      );
      await expectLater(
        service.choose(
          first,
          nodeId: 'request',
          choiceId: 'target',
          operationId: 'retry',
        ),
        throwsA(anything),
      );
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      expect(
        (await service.resume(await sets.begin(), first.session.id)).decisions,
        isEmpty,
      );
      await db.customStatement('DROP TRIGGER dialogue_injected_failure');
      final result = await service.choose(
        first,
        nodeId: 'request',
        choiceId: 'target',
        operationId: 'retry',
      );
      expect(result.decisions, hasLength(1));
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
    },
  );
  test(
    'RESEARCH-OFF both branches leave SRS and research/reward storage untouched',
    () async {
      var run = await start();
      run = await service.choose(
        run,
        nodeId: 'request',
        choiceId: 'alternative',
        operationId: 'wrong',
      );
      run = await service.choose(
        run,
        nodeId: 'repair',
        choiceId: 'target',
        operationId: 'repair',
      );
      await service.complete(run);
      expect(await db.select(db.answerAttempts).get(), hasLength(2));
      for (final table in [
        'srs_states',
        'reward_transactions',
        'research_session_proofs',
        'motivation_responses',
      ]) {
        expect(
          (await db
                  .customSelect('SELECT COUNT(*) AS n FROM $table')
                  .getSingle())
              .read<int>('n'),
          0,
          reason: table,
        );
      }
    },
  );
  test(
    'guest upgrade preserves immutable decisions; export redacts and delete fences',
    () async {
      var run = await start();
      run = await service.choose(
        run,
        nodeId: 'request',
        choiceId: 'alternative',
        operationId: 'choice',
      );
      final before = jsonEncode(run.state());
      await db.customStatement(
        "INSERT INTO local_owners(id,firebase_uid,account_state,created_at_utc_ms,is_active) VALUES('account','dialogue-user','firebaseBound',1,0)",
      );
      await DriftOwnerUpgradeRepository(
        db,
        nowUtc: () => now,
        generateConflictId: () => 'conflict-${serial++}',
        generateOwnerId: () => 'unused',
        generateOwnerOperationToken: () => 'merge-${serial++}',
        deleteOwnerSecrets: (_) async {},
      ).upgrade(activeOwnerId: 'a', firebaseUid: 'dialogue-user');
      final fresh = await service.resume(await sets.begin(), run.session.id);
      expect(jsonEncode(fresh.state()), before);
      await expectLater(
        service.choose(
          run,
          nodeId: 'repair',
          choiceId: 'target',
          operationId: 'old-owner',
        ),
        throwsStateError,
      );
      final export = await OwnerLifecycleArchiveExporter(
        database: db,
        nowUtc: () => now,
      ).prepareActive();
      expect(utf8.decode(export.bytes), isNot(contains('Mira')));
      await LocalDataDeletion(
        db,
        deleteOwnerSecrets: (_) async {},
      ).eraseAll(ownerId: 'account');
      expect(await db.select(db.answerAttempts).get(), isEmpty);
      await expectLater(
        service.resume(fresh.owner, run.session.id),
        throwsStateError,
      );
    },
  );
  test(
    'RESTORE-OLDER canonical events reject an older checkpoint projection',
    () async {
      var run = await start();
      run = await service.choose(
        run,
        nodeId: 'request',
        choiceId: 'target',
        operationId: 'saved',
      );
      // Simulate a partial older restore: the new attempt survives but its
      // immutable decision event is absent. This must never permit resubmission.
      await db.customStatement(
        r"DELETE FROM events_v2 WHERE event_type='LearningActivityCheckpoint' AND json_extract(payload_json, '$.revision')=2",
      );
      await expectLater(
        service.resume(await sets.begin(), run.session.id),
        throwsStateError,
      );
      expect(await db.select(db.answerAttempts).get(), hasLength(1));
    },
  );
  test(
    'RESTORE-OLDER future dialogue state rejects before recovery writes',
    () async {
      final run = await start();
      await db.customStatement(
        r"UPDATE events_v2 SET payload_json=json_set(payload_json, '$.state.schemaVersion', 2) WHERE event_type='LearningActivityCheckpoint'",
      );
      final before = await db
          .customSelect('SELECT payload_json FROM events_v2 ORDER BY event_id')
          .get();
      await expectLater(
        service.resume(await sets.begin(), run.session.id),
        throwsStateError,
      );
      final after = await db
          .customSelect('SELECT payload_json FROM events_v2 ORDER BY event_id')
          .get();
      expect(
        after.map((r) => r.data).toList(),
        before.map((r) => r.data).toList(),
      );
      expect(await db.select(db.answerAttempts).get(), isEmpty);
    },
  );
  testWidgets('320px text200 scene, consequence, repair and saved exit', (
    tester,
  ) async {
    final run = (await tester.runAsync(start))!;
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> settle() async {
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      }
    }

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: DialogueMissionScreen(useCases: service, run: run),
      ),
    );
    await settle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('dialogue-choice-alternative')),
      200,
    );
    await tester.tap(find.byKey(const ValueKey('dialogue-choice-alternative')));
    await settle();
    expect(find.textContaining('That does not fit'), findsOneWidget);
    await tester.ensureVisible(find.text('Continue'));
    await tester.tap(find.text('Continue'));
    await settle();
    expect(find.text('Assisted repair'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Save and exit'), 200);
    expect(find.text('Save and exit'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle();
  });
}
