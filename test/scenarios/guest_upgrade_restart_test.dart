import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/export/application/export_use_cases.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/sync/application/sync_backoff.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_mutex.dart';
import 'package:vocab_learning_app/features/sync/application/sync_trigger.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';

void main() {
  test(
    'committed learning retry preserves guest actor after account upgrade',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-learning-owner-upgrade-',
      );
      final path = '${directory.path}${Platform.pathSeparator}upgrade.sqlite';
      final nowUtc = DateTime.utc(2026, 8, 14, 9);
      final occurredAtUtc = nowUtc.add(
        const Duration(seconds: 2, milliseconds: 123),
      );
      const sourceEvidenceId = 'guest-learning-evidence';
      const learningEventId = 'learning-event:$sourceEvidenceId';
      const decisionEventId =
          'learning-evidence-decisions:$sourceEvidenceId:v1';
      const accountOwnerId = 'account-learning-owner';
      const firebaseUid = 'firebase-learning-owner';
      final evidenceContext = EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'meaning-recall',
        hintLevel: 0,
        contentRevision: 'content-r1',
        engagementAllowed: true,
      );

      AppDatabase openDatabase() => AppDatabase(NativeDatabase(File(path)));
      AppDatabase? database;
      try {
        database = openDatabase();
        final guestOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'learning-guest',
          nowUtc: () => nowUtc,
        );
        final guest = await guestOwners.getOrCreateActiveOwner();
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: accountOwnerId,
                firebaseUid: const Value(firebaseUid),
                accountState: const Value('firebaseBound'),
                createdAtUtcMs: nowUtc.millisecondsSinceEpoch - 1,
                isActive: const Value(false),
              ),
            );
        await _seedLearningEvidenceVocabulary(database, guest.id);
        final firstLearning = LearningUseCases(
          owners: guestOwners,
          repository: DriftLearningRepository(database),
          generateId: () => 'learning-session-id',
          nowUtc: () => nowUtc,
          buildInfo: const AppBuildInfo(
            version: '1.0.0',
            buildId: 'guest-upgrade-test',
          ),
        );
        final quiz = await firstLearning.startQuiz(
          categoryId: 'learning-category',
          limit: 1,
        );
        expect(
          (await firstLearning.recordEvidence(
            sourceEvidenceId: sourceEvidenceId,
            occurredAtUtc: occurredAtUtc,
            sessionId: quiz.id,
            wordId: quiz.questions.single.word.id,
            promptMode: 'meaningChoice',
            isCorrect: true,
            responseTimeMs: 700,
            attemptNumber: 1,
            evidenceContext: evidenceContext,
          )).inserted,
          isTrue,
        );
        final firstEvent = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(learningEventId))).getSingle();
        expect(firstEvent.ownerId, guest.id);
        expect(firstEvent.actorIdentity, guest.id);
        expect(
          firstEvent.occurredAtUtc.toUtc(),
          nowUtc.add(const Duration(seconds: 2)),
        );
        expect(
          (await database.select(database.answerAttempts).getSingle())
              .occurredAtUtcMs,
          occurredAtUtc.millisecondsSinceEpoch,
        );

        var conflictSequence = 0;
        final upgraded = await UpgradeGuestOwner(
          DriftOwnerUpgradeRepository(
            database,
            nowUtc: () => nowUtc.add(const Duration(minutes: 1)),
            generateConflictId: () =>
                'learning-upgrade-conflict-${conflictSequence++}',
            generateOwnerId: () => 'unexpected-learning-owner',
            generateOwnerOperationToken: () => 'learning-upgrade-operation',
            deleteOwnerSecrets: (_) async {},
          ),
        )(activeOwnerId: guest.id, firebaseUid: firebaseUid);
        expect(upgraded.mode, OwnerUpgradeMode.mergedExisting);
        expect(upgraded.targetOwnerId, accountOwnerId);

        await database.close();
        database = openDatabase();
        final storedBeforeReplay = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(learningEventId))).getSingle();
        final decisionBeforeReplay = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(decisionEventId))).getSingle();
        expect(storedBeforeReplay.ownerId, accountOwnerId);
        expect(storedBeforeReplay.actorIdentity, guest.id);
        final unavailableProvider = _UnavailableLearningEventContextProvider();
        final reopenedOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner-after-reopen',
          nowUtc: () => nowUtc.add(const Duration(minutes: 2)),
        );
        expect(
          (await reopenedOwners.getOrCreateActiveOwner()).id,
          accountOwnerId,
        );
        final replayLearning = LearningUseCases(
          owners: reopenedOwners,
          repository: DriftLearningRepository(database),
          generateId: () => 'unexpected-learning-id',
          nowUtc: () => nowUtc.add(const Duration(minutes: 2)),
          buildInfo: const AppBuildInfo(
            version: '1.0.0',
            buildId: 'guest-upgrade-test',
          ),
          eventContextProvider: unavailableProvider,
        );

        final replay = await replayLearning.recordEvidence(
          sourceEvidenceId: sourceEvidenceId,
          occurredAtUtc: occurredAtUtc,
          sessionId: quiz.id,
          wordId: quiz.questions.single.word.id,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 700,
          attemptNumber: 1,
          evidenceContext: evidenceContext,
        );
        expect(replay.inserted, isFalse);
        expect(unavailableProvider.calls, 0);
        expect(
          (await (database.select(database.eventsV2)
                    ..where((row) => row.eventId.equals(learningEventId)))
                  .getSingle())
              .toJson(),
          storedBeforeReplay.toJson(),
        );

        for (final changed in <Future<void> Function()>[
          () => replayLearning.recordEvidence(
            sourceEvidenceId: sourceEvidenceId,
            occurredAtUtc: occurredAtUtc.add(const Duration(milliseconds: 1)),
            sessionId: quiz.id,
            wordId: quiz.questions.single.word.id,
            promptMode: 'meaningChoice',
            isCorrect: true,
            responseTimeMs: 700,
            attemptNumber: 1,
            evidenceContext: evidenceContext,
          ),
          () => replayLearning.recordEvidence(
            sourceEvidenceId: sourceEvidenceId,
            occurredAtUtc: occurredAtUtc,
            sessionId: quiz.id,
            wordId: quiz.questions.single.word.id,
            promptMode: 'meaningChoice',
            isCorrect: true,
            responseTimeMs: 700,
            attemptNumber: 1,
            evidenceContext: EvidenceContext.legacyCompatibility(
              evidenceClass: EvidenceClass.independentRecall,
              skillId: 'changed-skill',
              hintLevel: 0,
              contentRevision: 'content-r1',
              engagementAllowed: true,
            ),
          ),
        ]) {
          await expectLater(changed(), throwsStateError);
        }
        expect(unavailableProvider.calls, 0);
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );
        final storedAfterReplay = await database
            .select(database.eventsV2)
            .get();
        expect(
          storedAfterReplay.map((event) => event.eventId).toSet(),
          <String>{learningEventId, decisionEventId},
        );
        expect(
          storedAfterReplay
              .singleWhere((event) => event.eventId == learningEventId)
              .toJson(),
          storedBeforeReplay.toJson(),
        );
        expect(
          storedAfterReplay
              .singleWhere((event) => event.eventId == decisionEventId)
              .toJson(),
          decisionBeforeReplay.toJson(),
        );
      } finally {
        await database?.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );

  test(
    'eventless frozen-v13 audit preserves merged guest provenance after reopen',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-eventless-owner-upgrade-',
      );
      final path = '${directory.path}${Platform.pathSeparator}upgrade.sqlite';
      final nowUtc = DateTime.utc(2026, 8, 14, 10);
      final occurredAtUtc = nowUtc.add(
        const Duration(seconds: 3, milliseconds: 321),
      );
      const sourceEvidenceId = 'guest-eventless-evidence';
      const decisionEventId =
          'learning-evidence-decisions:$sourceEvidenceId:v1';
      const learningEventId = 'learning-event:$sourceEvidenceId';
      const accountOwnerId = 'account-eventless-owner';
      const firebaseUid = 'firebase-eventless-owner';
      final evidenceContext =
          LearningEvidenceContract.frozenV13LegacyEvidenceContext();

      AppDatabase openDatabase() => AppDatabase(NativeDatabase(File(path)));
      AppDatabase? database;
      try {
        database = openDatabase();
        final guestOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'eventless-guest',
          nowUtc: () => nowUtc,
        );
        final guest = await guestOwners.getOrCreateActiveOwner();
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: accountOwnerId,
                firebaseUid: const Value(firebaseUid),
                accountState: const Value('firebaseBound'),
                createdAtUtcMs: nowUtc.millisecondsSinceEpoch - 1,
                isActive: const Value(false),
              ),
            );
        await _seedLearningEvidenceVocabulary(database, guest.id);
        final firstLearning = LearningUseCases(
          owners: guestOwners,
          repository: DriftLearningRepository(database),
          generateId: () => 'eventless-session-id',
          nowUtc: () => nowUtc,
          buildInfo: const AppBuildInfo(
            version: '1.0.0',
            buildId: 'eventless-upgrade-test',
          ),
        );
        final quiz = await firstLearning.startQuiz(
          categoryId: 'learning-category',
          limit: 1,
        );
        final firstCommand = RecordAnswerCommand.frozenV13LegacyIngress(
          id: sourceEvidenceId,
          ownerId: guest.id,
          sessionId: quiz.id,
          wordId: quiz.questions.single.word.id,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 650,
          attemptNumber: 1,
          occurredAtUtc: occurredAtUtc,
          evidenceContext: evidenceContext,
        );
        expect(
          (await DriftLearningRepository(
            database,
          ).recordAnswer(firstCommand)).inserted,
          isTrue,
        );
        final guestAudit = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(decisionEventId))).getSingle();
        expect(guestAudit.ownerId, guest.id);
        expect(guestAudit.actorIdentity, guest.id);
        expect(
          await (database.select(database.eventsV2)
                ..where((row) => row.eventId.equals(learningEventId)))
              .getSingleOrNull(),
          isNull,
        );

        var eventlessConflictSequence = 0;
        final upgraded = await UpgradeGuestOwner(
          DriftOwnerUpgradeRepository(
            database,
            nowUtc: () => nowUtc.add(const Duration(minutes: 1)),
            generateConflictId: () =>
                'eventless-upgrade-conflict-${eventlessConflictSequence++}',
            generateOwnerId: () => 'unexpected-eventless-owner',
            generateOwnerOperationToken: () => 'eventless-upgrade-operation',
            deleteOwnerSecrets: (_) async {},
          ),
        )(activeOwnerId: guest.id, firebaseUid: firebaseUid);
        expect(upgraded.targetOwnerId, accountOwnerId);
        expect(upgraded.mode, OwnerUpgradeMode.mergedExisting);
        final upgradedAudit = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(decisionEventId))).getSingle();
        expect(upgradedAudit.ownerId, accountOwnerId);
        expect(upgradedAudit.actorIdentity, guest.id);
        final upgradedAuditBytes = upgradedAudit.toJson();

        await database.close();
        database = openDatabase();
        final reopenedOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner-after-eventless-reopen',
          nowUtc: () => nowUtc.add(const Duration(minutes: 2)),
        );
        expect(
          (await reopenedOwners.getOrCreateActiveOwner()).id,
          accountOwnerId,
        );
        final retryCommand = RecordAnswerCommand.frozenV13LegacyIngress(
          id: sourceEvidenceId,
          ownerId: accountOwnerId,
          sessionId: quiz.id,
          wordId: quiz.questions.single.word.id,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 650,
          attemptNumber: 1,
          occurredAtUtc: occurredAtUtc,
          evidenceContext: evidenceContext,
        );
        final reopenedRepository = DriftLearningRepository(database);
        expect(
          (await reopenedRepository.recordAnswer(retryCommand)).inserted,
          isFalse,
        );
        final afterRetry = await (database.select(
          database.eventsV2,
        )..where((row) => row.eventId.equals(decisionEventId))).getSingle();
        expect(afterRetry.toJson(), upgradedAuditBytes);
        expect(afterRetry.ownerId, accountOwnerId);
        expect(afterRetry.actorIdentity, guest.id);

        await expectLater(
          reopenedRepository.recordAnswer(
            RecordAnswerCommand.frozenV13LegacyIngress(
              id: sourceEvidenceId,
              ownerId: accountOwnerId,
              sessionId: quiz.id,
              wordId: quiz.questions.single.word.id,
              promptMode: 'meaningChoice',
              isCorrect: true,
              responseTimeMs: 651,
              attemptNumber: 1,
              occurredAtUtc: occurredAtUtc,
              evidenceContext: evidenceContext,
            ),
          ),
          throwsStateError,
        );

        await database.customUpdate(
          'UPDATE events_v2 SET actor_identity = ? WHERE event_id = ?',
          variables: const <Variable<Object>>[
            Variable<String>('unauthorized-eventless-actor'),
            Variable<String>(decisionEventId),
          ],
          updates: {database.eventsV2},
        );
        final unauthorizedBytes =
            (await (database.select(database.eventsV2)
                      ..where((row) => row.eventId.equals(decisionEventId)))
                    .getSingle())
                .toJson();
        await expectLater(
          reopenedRepository.recordAnswer(retryCommand),
          throwsStateError,
        );
        expect(
          (await (database.select(database.eventsV2)
                    ..where((row) => row.eventId.equals(decisionEventId)))
                  .getSingle())
              .toJson(),
          unauthorizedBytes,
        );
      } finally {
        await database?.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );

  test(
    'complete guest inventory upgrades in order and replays stably after reopen',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-guest-upgrade-',
      );
      final path = '${directory.path}${Platform.pathSeparator}upgrade.sqlite';
      final nowUtc = DateTime.utc(2026, 8, 9, 10);
      final gateway = _UpgradeCloud(nowUtc);
      var leaseSequence = 0;

      AppDatabase openDatabase() => AppDatabase(NativeDatabase(File(path)));
      late AppDatabase syncDatabase;
      late AppDatabase upgradeDatabase;
      var syncDatabaseOpen = false;
      var upgradeDatabaseOpen = false;
      try {
        syncDatabase = openDatabase();
        syncDatabaseOpen = true;
        upgradeDatabase = openDatabase();
        upgradeDatabaseOpen = true;
        await syncDatabase.customSelect('SELECT 1').getSingle();
        await _seedCompleteSyncInventory(syncDatabase);
        final guestAssignmentId =
            DriftExperimentAssignmentRepository.canonicalAssignmentId(
              ownerId: 'guest-owner',
              experimentId: 'research-assessment',
              experimentVersion: 1,
            );
        await syncDatabase.customInsert(
          'INSERT INTO experiment_assignments '
          '(id, owner_id, experiment_id, experiment_version, cohort, '
          'protocol_version, assigned_at_utc_ms) VALUES '
          "(?, 'guest-owner', 'research-assessment', 1, 'treatment-a', "
          "'2026.08', 1786449600000)",
          variables: [Variable<String>(guestAssignmentId)],
        );
        await upgradeDatabase.customSelect('SELECT 1').getSingle();

        final owners = DriftLocalOwnerRepository(
          syncDatabase,
          generateId: () => 'unexpected-owner',
          nowUtc: () => nowUtc,
        );
        final syncEngine = SyncEngine(
          owners: owners,
          store: DriftSyncStore(syncDatabase),
          gateway: gateway,
          policyProvider: () async => CloudSyncPolicy(
            enabled: true,
            source: CloudSyncPolicySource.cache,
            fetchedAtUtc: nowUtc,
            expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
          ),
          ownerGate: DriftOwnerOperationGate(syncDatabase),
          mutex: SyncMutex(),
          backoff: const SyncBackoff(jitterFraction: 0),
          nowUtc: () => nowUtc,
          generateLeaseToken: () => 'upgrade-sync-${leaseSequence++}',
        );

        final upgradeWaitEntered = Completer<void>();
        final releaseUpgradeWait = Completer<void>();
        final secretDeletionEntered = Completer<void>();
        final releaseSecretDeletion = Completer<void>();
        final neverHeartbeat = Completer<void>();
        var ownerOperationSequence = 0;
        final ownerUpgrades = DriftOwnerUpgradeRepository(
          upgradeDatabase,
          nowUtc: () => nowUtc,
          generateConflictId: () => 'upgrade-conflict',
          generateOwnerId: () => 'unexpected-guest',
          generateOwnerOperationToken: () =>
              'upgrade-owner-operation-${ownerOperationSequence++}',
          deleteOwnerSecrets: (_) async {
            secretDeletionEntered.complete();
            await releaseSecretDeletion.future;
          },
          ownerGateDelay: (delay) {
            if (delay == const Duration(milliseconds: 50)) {
              if (!upgradeWaitEntered.isCompleted) {
                upgradeWaitEntered.complete();
              }
              return releaseUpgradeWait.future;
            }
            return neverHeartbeat.future;
          },
        );
        final upgradeGuestOwner = UpgradeGuestOwner(ownerUpgrades);

        final oldSync = syncEngine.run();
        await gateway.firstPushEntered.future;
        var upgradeCompleted = false;
        final upgrading = upgradeGuestOwner(
          activeOwnerId: 'guest-owner',
          firebaseUid: 'firebase-new',
        ).whenComplete(() => upgradeCompleted = true);
        await upgradeWaitEntered.future;
        expect(upgradeCompleted, isFalse);
        expect(gateway.pushFirebaseUids, ['anonymous-old']);

        gateway.releaseFirstPush.complete();
        final oldResult = await oldSync;
        expect(oldResult.status, SyncRunStatus.completed);
        expect(gateway.pushFirebaseUids, everyElement('anonymous-old'));
        releaseUpgradeWait.complete();
        await secretDeletionEntered.future;

        final callsWhileUpgradeHeld = gateway.totalProviderCalls;
        final triggerWaitEntered = Completer<void>();
        final releaseTriggerWait = Completer<void>();
        final trigger = SyncTrigger(
          syncEngine.run,
          retryDelay: (_) {
            if (!triggerWaitEntered.isCompleted) {
              triggerWaitEntered.complete();
            }
            return releaseTriggerWait.future;
          },
        );
        final requestedDuringUpgrade = trigger.request(
          SyncTriggerReason.accountBinding,
        );
        await triggerWaitEntered.future;
        expect(gateway.totalProviderCalls, callsWhileUpgradeHeld);

        releaseSecretDeletion.complete();
        final upgradeResult = await upgrading;
        expect(upgradeResult.targetOwnerId, 'account-owner');
        expect(upgradeResult.mode, OwnerUpgradeMode.mergedExisting);
        releaseTriggerWait.complete();
        final newResult = await requestedDuringUpgrade;
        expect(newResult.status, SyncRunStatus.completed);

        final oldNamespaceCalls = gateway.pushFirebaseUids
            .where((uid) => uid == 'anonymous-old')
            .length;
        expect(oldNamespaceCalls, 7);
        expect(gateway.pushFirebaseUids.skip(oldNamespaceCalls), isNotEmpty);
        expect(
          gateway.pushFirebaseUids.skip(oldNamespaceCalls),
          everyElement('firebase-new'),
        );
        const finalCanonicalPointIds = <String>['points-1', 'points:attempt-1'];
        final finalPointIds = await syncDatabase
            .customSelect(
              'SELECT id FROM points_ledger_entries WHERE owner_id = ? '
              'AND entry_type = ? ORDER BY id',
              variables: const [
                Variable<String>('account-owner'),
                Variable<String>('quizCorrect'),
              ],
            )
            .map((row) => row.read<String>('id'))
            .get();
        expect(finalPointIds, finalCanonicalPointIds);
        final canonicalOperationIds = <String>{
          'operation:category',
          'operation:word',
          'operation:attempt',
          'operation:reading',
          'operation:reward',
          'operation:srs',
          'operation:achievement',
        };
        final expectedOperationIdentities = <String>{
          for (final operationId in canonicalOperationIds)
            'anonymous-old:$operationId',
          for (final operationId in canonicalOperationIds)
            'firebase-new:$operationId',
          for (final pointId in finalCanonicalPointIds)
            'firebase-new:${_legacyBackfillOperationId(pointId)}',
        };
        expect(
          gateway.namespaceApplyCounts.keys.toSet(),
          expectedOperationIdentities,
        );
        expect(gateway.namespaceApplyCounts.values, everyElement(1));
        expect(gateway.namespaceApplyCounts, hasLength(16));

        final beforeReopen = await _inventorySnapshot(syncDatabase);
        expect(beforeReopen['activeOwnerId'], 'account-owner');
        expect(beforeReopen['operationTypes'], _sevenEntityTypes);
        expect(beforeReopen['checkpointCount'], 0);
        expect(beforeReopen['guestInventoryCount'], 0);
        final assignmentBeforeReopen = await syncDatabase
            .customSelect(
              'SELECT experiment_id, experiment_version, cohort, protocol_version, '
              'assigned_at_utc_ms FROM experiment_assignments WHERE owner_id = ?',
              variables: [const Variable<String>('account-owner')],
            )
            .getSingle();
        expect(assignmentBeforeReopen.data, {
          'experiment_id': 'research-assessment',
          'experiment_version': 1,
          'cohort': 'treatment-a',
          'protocol_version': '2026.08',
          'assigned_at_utc_ms': 1786449600000,
        });

        await upgradeDatabase.close();
        upgradeDatabaseOpen = false;
        await syncDatabase.close();
        syncDatabaseOpen = false;

        syncDatabase = openDatabase();
        syncDatabaseOpen = true;
        await syncDatabase.customSelect('SELECT 1').getSingle();
        final replayRepository = DriftOwnerUpgradeRepository(
          syncDatabase,
          nowUtc: () => nowUtc.add(const Duration(minutes: 1)),
          generateConflictId: () => 'replay-conflict',
          generateOwnerId: () => 'replay-owner',
          generateOwnerOperationToken: () => 'replay-owner-operation',
          deleteOwnerSecrets: (_) async {
            fail('already-bound replay must not delete secrets');
          },
        );
        final replayed = await UpgradeGuestOwner(replayRepository)(
          activeOwnerId: 'account-owner',
          firebaseUid: 'firebase-new',
        );
        final afterReopen = await _inventorySnapshot(syncDatabase);
        final assignmentAfterReopen = await syncDatabase
            .customSelect(
              'SELECT experiment_id, experiment_version, cohort, protocol_version, '
              'assigned_at_utc_ms FROM experiment_assignments WHERE owner_id = ?',
              variables: [const Variable<String>('account-owner')],
            )
            .getSingle();

        expect(replayed.mode, OwnerUpgradeMode.alreadyBound);
        expect(replayed.targetOwnerId, 'account-owner');
        expect(afterReopen, beforeReopen);
        expect(assignmentAfterReopen.data, assignmentBeforeReopen.data);
        await syncDatabase.close();
        syncDatabaseOpen = false;
      } finally {
        if (upgradeDatabaseOpen) await upgradeDatabase.close();
        if (syncDatabaseOpen) await syncDatabase.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );

  test(
    'anonymous target-absent upgrade preserves assessment lineage after withdrawal and reopen',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-assessment-anonymous-bind-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}assessment-upgrade.sqlite',
      );
      AppDatabase? database;
      try {
        database = AppDatabase(NativeDatabase(file));
        final seeded = await _seedRestartAssessmentGraph(database);
        final runBefore = await _restartAssessmentSnapshot(database);
        final attemptBefore = await _restartAssessmentAttemptSnapshot(database);
        final eventBefore = await _restartAssessmentEventSnapshot(database);
        final outboxBefore = await _restartAssessmentOutboxSnapshot(database);
        await database.customUpdate(
          "UPDATE research_consents SET consent_state = 'withdrawn', "
          'withdrawn_at_utc_ms = 60 WHERE owner_id = ?',
          variables: const [Variable<String>('assessment-guest')],
        );

        var assessmentUpgradeConflictSequence = 0;
        final result =
            await DriftOwnerUpgradeRepository(
              database,
              nowUtc: () => DateTime.utc(2026, 8, 14, 12),
              generateConflictId: () =>
                  'assessment-upgrade-conflict-'
                  '${assessmentUpgradeConflictSequence++}',
              generateOwnerId: () => 'unused-assessment-owner',
              generateOwnerOperationToken: () => 'assessment-upgrade-operation',
              deleteOwnerSecrets: (_) async {},
            ).upgrade(
              activeOwnerId: 'assessment-guest',
              firebaseUid: 'assessment-firebase-user',
            );

        expect(result.mode, OwnerUpgradeMode.anonymousBound);
        expect(result.targetOwnerId, 'assessment-guest');
        await database.close();
        database = AppDatabase(NativeDatabase(file));
        await database.customSelect('SELECT 1').getSingle();

        final runAfter = await _restartAssessmentSnapshot(database);
        expect(runAfter, runBefore);
        expect(runAfter['owner_id'], 'assessment-guest');
        expect(runAfter['learning_session_id'], seeded.sessionId);
        expect(runAfter['assignment_id'], seeded.assignmentId);
        expect(runAfter['state'], 'completed');
        expect(runAfter['completed_at_utc_ms'], 50);
        expect(
          await _restartAssessmentAttemptSnapshot(database),
          attemptBefore,
        );
        expect(await _restartAssessmentEventSnapshot(database), eventBefore);
        expect(await _restartAssessmentOutboxSnapshot(database), outboxBefore);
        final assignmentOutbox = await database
            .customSelect(
              'SELECT entity_id FROM outbox_operations '
              "WHERE entity_type = 'experimentAssignment'",
            )
            .map((row) => row.read<String>('entity_id'))
            .get();
        expect(assignmentOutbox, [
          DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
            firebaseUid: 'assessment-firebase-user',
            experimentId: 'assessment-study',
            experimentVersion: 1,
          ),
        ]);
        expect(assignmentOutbox, isNot(contains(seeded.assignmentId)));
        final consent = await database
            .customSelect(
              'SELECT consent_state, withdrawn_at_utc_ms '
              'FROM research_consents WHERE owner_id = ?',
              variables: const [Variable<String>('assessment-guest')],
            )
            .getSingle();
        expect(consent.data, {
          'consent_state': 'withdrawn',
          'withdrawn_at_utc_ms': 60,
        });
        expect(
          await database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await database?.close();
        if (await directory.exists()) await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );

  test(
    'anonymous bind preserves complete inventory and replays once after reopen',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-anonymous-bind-',
      );
      final path = '${directory.path}${Platform.pathSeparator}upgrade.sqlite';
      var nowUtc = DateTime.utc(2026, 8, 9, 11);
      var leaseSequence = 0;
      var conflictSequence = 0;
      var operationTokenSequence = 0;
      final gateway = _AnonymousBoundCloud(nowUtc);

      AppDatabase openDatabase() => AppDatabase(NativeDatabase(File(path)));
      SyncEngine buildEngine(AppDatabase database) => SyncEngine(
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner',
          nowUtc: () => nowUtc,
        ),
        store: DriftSyncStore(database),
        gateway: gateway,
        policyProvider: () async => CloudSyncPolicy(
          enabled: true,
          source: CloudSyncPolicySource.cache,
          fetchedAtUtc: nowUtc,
          expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
        ),
        ownerGate: DriftOwnerOperationGate(database),
        mutex: SyncMutex(),
        backoff: const SyncBackoff(jitterFraction: 0),
        nowUtc: () => nowUtc,
        generateLeaseToken: () => 'anonymous-bind-${leaseSequence++}',
      );

      AppDatabase? database;
      try {
        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        await _seedAnonymousBoundCompleteInventory(database);
        final seededInventory = await _completeInventoryIdentity(database);
        final seededCounts = await _completeInventoryCounts(database);
        final seededForeign = await _foreignOwnerSnapshot(database);

        expect(seededCounts.keys.toSet(), ownerUpgradeInventory);
        expect(seededCounts.values, everyElement(greaterThanOrEqualTo(1)));
        expect(await _tableCount(database, 'vocabulary_import_rows'), 2);
        expect(await _tableCount(database, 'quest_objective_progress'), 2);
        expect(await _projectionEventCount(database, 'guest-owner'), 2);
        expect(await _projectionEventCount(database, 'foreign-owner'), 2);

        final repository = DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => nowUtc,
          generateConflictId: () => 'bind-${conflictSequence++}',
          generateOwnerId: () => 'unexpected-guest',
          generateOwnerOperationToken: () =>
              'bind-operation-${operationTokenSequence++}',
          deleteOwnerSecrets: (_) async {
            fail('anonymous bind must not delete external owner secrets');
          },
        );
        final bound = await UpgradeGuestOwner(repository)(
          activeOwnerId: 'guest-owner',
          firebaseUid: 'firebase-new',
        );
        final ownerAfterBind = await (database.select(
          database.localOwners,
        )..where((row) => row.isActive.equals(true))).getSingle();
        final resetOperations = await database
            .customSelect(
              'SELECT operation_id, attempt_count, state, failure_code '
              'FROM outbox_operations WHERE owner_id = ? '
              'ORDER BY operation_id',
              variables: [const Variable<String>('guest-owner')],
            )
            .get();
        final boundInventory = await _completeInventoryIdentity(database);
        final boundCounts = await _completeInventoryCounts(database);

        expect(bound.mode, OwnerUpgradeMode.anonymousBound);
        expect(bound.targetOwnerId, 'guest-owner');
        expect(ownerAfterBind.id, 'guest-owner');
        expect(ownerAfterBind.firebaseUid, 'firebase-new');
        expect(ownerAfterBind.isActive, isTrue);
        for (final entry in seededInventory.entries) {
          expect(boundInventory[entry.key], containsAll(entry.value));
        }
        expect(
          boundCounts['reward_transactions'],
          seededCounts['reward_transactions']! + 1,
        );
        expect(
          boundCounts['outbox_operations'],
          seededCounts['outbox_operations']! + 2,
        );
        expect(
          resetOperations
              .map((row) => row.read<String>('operation_id'))
              .toSet(),
          <String>{
            'operation:category',
            'operation:word',
            'operation:attempt',
            'operation:reading',
            'operation:reward',
            'operation:srs',
            'operation:achievement',
            'assessmentRun:assessment-inventory-run:1',
            'assessmentRun:assessment-inventory-run:2',
            // Owner binding requeues its audit operation separately from the
            // deterministic legacy-reward backfill.
            'rehome:bind-0',
            _legacyBackfillOperationId('points-1'),
          },
        );
        for (final entry in seededCounts.entries) {
          if (entry.key == 'reward_transactions' ||
              entry.key == 'outbox_operations') {
            continue;
          }
          expect(boundCounts[entry.key], entry.value);
        }
        expect(await _foreignOwnerSnapshot(database), seededForeign);
        expect(
          resetOperations.map((row) => row.read<int>('attempt_count')),
          everyElement(0),
        );
        expect(
          resetOperations.map((row) => row.read<String>('state')),
          everyElement('pending'),
        );
        expect(
          resetOperations.map(
            (row) => row.readNullable<String>('failure_code'),
          ),
          everyElement(isNull),
        );
        final invariantGate = DriftOwnerOperationGate(database);
        expect(
          await invariantGate.tryAcquire(
            token: 'verify-srs-rehome',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );
        final invariantStore = DriftSyncStore(database);
        final rehomedClaims = await invariantStore.claimPending(
          ownerId: 'guest-owner',
          firebaseUid: 'firebase-new',
          limit: 20,
          leaseToken: 'verify-srs-rehome-lease',
          ownerGateToken: 'verify-srs-rehome',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: nowUtc,
        );
        final rehomedSrs = rehomedClaims.singleWhere(
          (claim) => claim.mutation.collection == SyncCollection.srsStates,
        );
        expect(rehomedSrs.mutation.operationId, 'operation:srs');
        expect(
          rehomedSrs.mutation.localRevision,
          greaterThan(rehomedSrs.mutation.baseRevision),
        );
        for (final claim in rehomedClaims) {
          expect(
            await invariantStore.releaseClaim(
              claim: claim,
              ownerGateToken: 'verify-srs-rehome',
              nowUtc: nowUtc,
            ),
            isTrue,
          );
        }
        await invariantGate.release(token: 'verify-srs-rehome');

        await database.close();
        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        final firstReplay = await buildEngine(database).run();
        final afterReplay = await _completeInventorySnapshot(database);

        expect(firstReplay.status, SyncRunStatus.completed);
        expect(firstReplay.pushed, 9);
        expect(gateway.pushFirebaseUids, everyElement('firebase-new'));
        expect(gateway.namespaceApplyCounts, hasLength(9));
        expect(gateway.namespaceApplyCounts.values, everyElement(1));
        expect(afterReplay['activeOwnerId'], 'guest-owner');
        expect(afterReplay['inventoryIdentity'], boundInventory);
        expect(afterReplay['inventoryCounts'], boundCounts);
        expect(afterReplay['operationTypes'], _completeInventoryEntityTypes);
        expect(await _foreignOwnerSnapshot(database), seededForeign);
        final afterReplayOperationRows =
            afterReplay['operationRows']! as List<String>;
        final assessmentOperationRows = afterReplayOperationRows
            .where((row) => row.startsWith('assessmentRun:'))
            .toList();
        final nonAssessmentOperationRows = afterReplayOperationRows
            .where((row) => !row.startsWith('assessmentRun:'))
            .toList();
        expect(assessmentOperationRows, <String>[
          'assessmentRun:assessment-inventory-run:1|assessmentRun|'
              'assessment-inventory-run|pending|0|null',
          'assessmentRun:assessment-inventory-run:2|assessmentRun|'
              'assessment-inventory-run|pending|0|null',
        ]);
        expect(nonAssessmentOperationRows, hasLength(9));
        expect(
          nonAssessmentOperationRows,
          everyElement(
            allOf(contains('|acknowledged|1|'), isNot(endsWith('|null'))),
          ),
        );
        final pushesAfterReplay = gateway.pushFirebaseUids.length;

        await database.close();
        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        nowUtc = nowUtc.add(const Duration(minutes: 1));
        final replayRepository = DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => nowUtc,
          generateConflictId: () => 'replay-${conflictSequence++}',
          generateOwnerId: () => 'unexpected-replay-owner',
          generateOwnerOperationToken: () =>
              'replay-operation-${operationTokenSequence++}',
          deleteOwnerSecrets: (_) async {
            fail('already-bound replay must not delete external secrets');
          },
        );
        final replayedBinding = await UpgradeGuestOwner(replayRepository)(
          activeOwnerId: 'guest-owner',
          firebaseUid: 'firebase-new',
        );
        final secondReplay = await buildEngine(database).run();
        final stable = await _completeInventorySnapshot(database);

        expect(replayedBinding.mode, OwnerUpgradeMode.alreadyBound);
        expect(replayedBinding.targetOwnerId, 'guest-owner');
        expect(secondReplay.status, SyncRunStatus.completed);
        expect(secondReplay.pushed, 0);
        expect(gateway.pushFirebaseUids, hasLength(pushesAfterReplay));
        expect(gateway.namespaceApplyCounts.values, everyElement(1));
        expect(stable, afterReplay);
        expect(await _foreignOwnerSnapshot(database), seededForeign);
      } finally {
        await database?.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );

  test(
    'merged existing resolves complete overlapping inventory across reopen',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-complete-owner-merge-',
      );
      final path = '${directory.path}${Platform.pathSeparator}upgrade.sqlite';
      var nowUtc = DateTime.utc(2026, 8, 10, 9);
      var leaseSequence = 0;
      var conflictSequence = 0;
      final gateway = _AnonymousBoundCloud(nowUtc);

      AppDatabase openDatabase() => AppDatabase(NativeDatabase(File(path)));
      SyncEngine buildEngine(AppDatabase database) => SyncEngine(
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner',
          nowUtc: () => nowUtc,
        ),
        store: DriftSyncStore(database),
        gateway: gateway,
        policyProvider: () async => CloudSyncPolicy(
          enabled: true,
          source: CloudSyncPolicySource.cache,
          fetchedAtUtc: nowUtc,
          expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
        ),
        ownerGate: DriftOwnerOperationGate(database),
        mutex: SyncMutex(),
        backoff: const SyncBackoff(jitterFraction: 0),
        nowUtc: () => nowUtc,
        generateLeaseToken: () => 'complete-merge-${leaseSequence++}',
      );

      AppDatabase? database;
      try {
        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        await _seedAnonymousBoundCompleteInventory(database);
        await _seedTargetCollisionInventory(database);
        await database.customUpdate(
          "UPDATE research_consents SET consent_state = 'withdrawn', "
          'decided_at_utc_ms = 200, withdrawn_at_utc_ms = 200 '
          'WHERE id = ?',
          variables: const [Variable<String>('consent-1')],
        );
        await database.customUpdate(
          "UPDATE research_consents SET consent_state = 'accepted', "
          'decided_at_utc_ms = 100, withdrawn_at_utc_ms = NULL '
          'WHERE id = ?',
          variables: const [Variable<String>('target:consent-1')],
        );
        await database.customInsert(
          'INSERT INTO events_v2 '
          '(event_id, event_type, event_version, occurred_at_utc, '
          'recorded_at_utc, actor_identity, owner_id, tenant_context_json, '
          'aggregate_type, aggregate_id, correlation_id, causation_id, '
          'idempotency_key, consent_context_json, experiment_context_json, '
          'content_revision, policy_version, app_version, build_id, '
          'provider_provenance_json, privacy_classification, payload_json) '
          "SELECT 'target:event-key-blocker', event_type, event_version, "
          'occurred_at_utc, recorded_at_utc, actor_identity, owner_id, '
          'tenant_context_json, aggregate_type, aggregate_id, correlation_id, '
          "causation_id, 'merged:event-source-1', consent_context_json, "
          'experiment_context_json, content_revision, policy_version, '
          'app_version, build_id, provider_provenance_json, '
          'privacy_classification, payload_json FROM events_v2 '
          'WHERE event_id = ?',
          variables: const [Variable<String>('target:event-source-1')],
        );
        await database.customInsert(
          'INSERT INTO vocabulary_imports '
          '(id, owner_id, category_id, source_type, source_name, source_hash, '
          'status, accepted_count, duplicate_count, rejected_count, '
          'created_at_utc_ms, completed_at_utc_ms) VALUES '
          "('target:import-key-blocker', 'account-owner', "
          "'target:category-1', 'csv', 'blocker.csv', "
          "'hash-1:merged:import-1', 'complete', 0, 0, 0, 12, 12)",
        );
        await database.customInsert(
          'INSERT INTO reward_transactions '
          '(id, owner_id, idempotency_key, transaction_type, amount, '
          'item_id, catalog_version, source_event_id, occurred_at_utc_ms) '
          "VALUES ('target:reward-key-blocker', 'account-owner', "
          "'merged:reward-1', 'coinGrant', 1, NULL, 0, "
          "'reward-key-blocker-source', 12)",
        );
        await database.customInsert(
          'INSERT INTO quest_objective_progress '
          '(id, instance_id, objective_id, current_count, target_count, '
          'source_event_ids_json) VALUES '
          "('guest-only-objective', 'quest-instance-1', 'guest-only', "
          "2, 3, '[\"guest-only-event\"]')",
        );
        await database.customUpdate(
          'UPDATE streak_states SET current_streak_days = 7, '
          'longest_streak_days = 9, freeze_count = 2, '
          'last_learned_at_utc_ms = 100, updated_at_utc_ms = 100 '
          'WHERE owner_id = ?',
          variables: const [Variable<String>('guest-owner')],
        );
        await database.customUpdate(
          'UPDATE streak_states SET current_streak_days = 3, '
          'longest_streak_days = 12, freeze_count = 5, '
          'last_learned_at_utc_ms = 200, updated_at_utc_ms = 200 '
          'WHERE owner_id = ?',
          variables: const [Variable<String>('account-owner')],
        );
        await database.customUpdate(
          'UPDATE learning_day_log SET first_session_at_utc_ms = 30 '
          'WHERE owner_id = ?',
          variables: const [Variable<String>('account-owner')],
        );
        await database.customUpdate(
          "UPDATE association_records SET content = 'account-newer', "
          'created_at_utc_ms = 30 WHERE owner_id = ?',
          variables: const [Variable<String>('account-owner')],
        );
        await database.customUpdate(
          'UPDATE associative_memory_states SET stability = 9, '
          'last_reviewed_at_utc_ms = 200, next_due_at_utc_ms = 300 '
          'WHERE owner_id = ?',
          variables: const [Variable<String>('account-owner')],
        );
        await database.customUpdate(
          "UPDATE quest_instances SET catalog_version = 2, state = 'expired', "
          'expired_at_utc_ms = 200 WHERE owner_id = ?',
          variables: const [Variable<String>('account-owner')],
        );
        await database.customUpdate(
          'UPDATE events_v2 SET payload_json = ? '
          'WHERE event_type = ? AND owner_id IN (?, ?)',
          variables: const [
            Variable<String>('{"projection":"quest","appliedVersion":1}'),
            Variable<String>('LearningProjectionCursor'),
            Variable<String>('guest-owner'),
            Variable<String>('account-owner'),
          ],
        );
        final foreignBefore = await _foreignOwnerSnapshot(database);

        final result = await UpgradeGuestOwner(
          DriftOwnerUpgradeRepository(
            database,
            nowUtc: () => nowUtc,
            generateConflictId: () => 'complete-${conflictSequence++}',
            generateOwnerId: () => 'unexpected-owner',
            generateOwnerOperationToken: () => 'complete-owner-operation',
            deleteOwnerSecrets: (_) async {},
          ),
        )(activeOwnerId: 'guest-owner', firebaseUid: 'firebase-new');

        expect(result.mode, OwnerUpgradeMode.mergedExisting);
        expect(result.targetOwnerId, 'account-owner');
        final active = await (database.select(
          database.localOwners,
        )..where((row) => row.isActive.equals(true))).getSingle();
        expect(active.id, 'account-owner');
        await _expectWithdrawnResearchConsent(database, nowUtc);
        expect(await _foreignOwnerSnapshot(database), foreignBefore);
        for (final table in ownerUpgradeInventory) {
          expect(
            await _ownerRowCount(database, table, 'guest-owner'),
            0,
            reason: '$table must be fully rehomed',
          );
        }
        expect(
          await _ownerNaturalKeyCount(
            database,
            'streak_states',
            'account-owner',
          ),
          1,
        );
        final streak = await (database.select(
          database.streakStates,
        )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
        expect(streak.currentStreakDays, 3);
        expect(streak.longestStreakDays, 12);
        expect(streak.freezeCount, 5);
        expect(streak.lastLearnedAtUtcMs, 200);
        final day = await (database.select(
          database.learningDayLog,
        )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
        expect(day.id, 'target:day:guest-owner:2026-08-09');
        expect(day.firstSessionAtUtcMs, 20);
        final association = await (database.select(
          database.associationRecords,
        )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
        expect(association.id, 'target:association-1');
        expect(association.content, 'account-newer');
        final memory = await (database.select(
          database.associativeMemoryStates,
        )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
        expect(memory.id, 'target:memory-1');
        expect(memory.stability, 9);
        expect(memory.lastReviewedAtUtcMs, 200);
        final quest = await (database.select(
          database.questInstances,
        )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
        expect(quest.instanceId, 'target:quest-instance-1');
        expect(quest.state, 'active');
        final objectives =
            await (database.select(database.questObjectiveProgress)
                  ..where(
                    (row) => row.instanceId.equals('target:quest-instance-1'),
                  )
                  ..orderBy([(row) => OrderingTerm.asc(row.objectiveId)]))
                .get();
        expect(objectives, hasLength(2));
        final objective = objectives.singleWhere(
          (row) => row.objectiveId == 'answer-once',
        );
        expect(objective.id, 'target:objective-1');
        expect(objective.currentCount, 1);
        expect(objective.targetCount, 1);
        final guestOnlyObjective = objectives.singleWhere(
          (row) => row.objectiveId == 'guest-only',
        );
        expect(guestOnlyObjective.id, 'target:quest-instance-1:guest-only');
        expect(guestOnlyObjective.currentCount, 2);
        expect(guestOnlyObjective.targetCount, 3);
        final importHashes = await database
            .customSelect(
              'SELECT source_hash FROM vocabulary_imports '
              'WHERE owner_id = ? ORDER BY source_hash',
              variables: const [Variable<String>('account-owner')],
            )
            .get()
            .then(
              (rows) =>
                  rows.map((row) => row.read<String>('source_hash')).toList(),
            );
        expect(importHashes, <String>[
          'hash-1',
          'hash-1:merged:import-1',
          'hash-1:merged:import-1:1',
        ]);
        final rewardKeys = await database
            .customSelect(
              'SELECT idempotency_key FROM reward_transactions '
              'WHERE owner_id = ? ORDER BY idempotency_key',
              variables: const [Variable<String>('account-owner')],
            )
            .get()
            .then(
              (rows) => rows
                  .map((row) => row.read<String>('idempotency_key'))
                  .toList(),
            );
        expect(rewardKeys, <String>[
          'economy:v1:legacy:27925de0205bdf9121f6d8ff25eddee5f512d2659bed21b231cfce184866d531',
          'economy:v1:legacy:6765a58b5cbdaf6214f8604244a36faa46ae91a9a746a8bbcd9a06d715a5fba3',
          'economy:v1:legacy:a6a6ac178ebf92f281b7141d89888b96777d3f7c105fbdc4231d9b7763161559',
          'merged:reward-1',
          'merged:reward-1:1',
          'merged:reward-equip-1',
          'reward-equip-key-1',
          'reward-key-1',
        ]);
        final mergedSrs = await (database.select(
          database.srsStates,
        )..where((row) => row.ownerId.equals('account-owner'))).getSingle();
        expect(mergedSrs.id, 'srs:account-owner:target:word-1');
        expect(mergedSrs.repetitions, 2);
        expect(
          await _ownerNaturalKeyCount(
            database,
            'learning_day_log',
            'account-owner',
          ),
          1,
        );
        expect(
          await _ownerNaturalKeyCount(
            database,
            'association_records',
            'account-owner',
          ),
          1,
        );
        expect(
          await _ownerNaturalKeyCount(
            database,
            'associative_memory_states',
            'account-owner',
          ),
          1,
        );
        expect(
          await _ownerNaturalKeyCount(
            database,
            'quest_instances',
            'account-owner',
          ),
          1,
        );
        expect(
          await database
              .customSelect(
                'SELECT word_id FROM speech_evidence WHERE owner_id = ?',
                variables: const [Variable<String>('account-owner')],
              )
              .map((row) => row.read<String>('word_id'))
              .get(),
          everyElement('target:word-1'),
        );

        await database.close();
        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        final restartedStreak = StreakUseCases(
          repository: DriftStreakRepository(database),
          owners: DriftLocalOwnerRepository(
            database,
            generateId: () => 'unexpected-streak-owner',
            nowUtc: () => nowUtc,
          ),
          nowUtc: () => nowUtc,
          timezoneId: 'UTC',
        );
        expect((await restartedStreak.getGentleStreak()).freezeCount, 5);
        await expectLater(
          restartedStreak.grantFreezeTokens(1),
          throwsRangeError,
        );
        expect(await restartedStreak.useFreezeToken(), isTrue);
        expect((await restartedStreak.getGentleStreak()).freezeCount, 4);
        final replay = await UpgradeGuestOwner(
          DriftOwnerUpgradeRepository(
            database,
            nowUtc: () => nowUtc,
            generateConflictId: () => 'replay-${conflictSequence++}',
            generateOwnerId: () => 'unexpected-owner',
            generateOwnerOperationToken: () => 'replay-owner-operation',
            deleteOwnerSecrets: (_) async {},
          ),
        )(activeOwnerId: 'account-owner', firebaseUid: 'firebase-new');
        expect(replay.mode, OwnerUpgradeMode.alreadyBound);
        await _expectWithdrawnResearchConsent(database, nowUtc);
        final firstRun = await buildEngine(database).run();
        expect(firstRun.status, SyncRunStatus.completed);
        expect(firstRun.pushed, greaterThan(0));
        final afterFirstRun = await _ownerInventorySnapshot(
          database,
          'account-owner',
        );
        final pushesAfterFirstRun = gateway.pushFirebaseUids.length;
        expect(await _foreignOwnerSnapshot(database), foreignBefore);

        await database.close();
        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        nowUtc = nowUtc.add(const Duration(minutes: 1));
        final secondRun = await buildEngine(database).run();

        expect(secondRun.status, SyncRunStatus.completed);
        expect(secondRun.pushed, 0);
        await _expectWithdrawnResearchConsent(database, nowUtc);
        expect(gateway.pushFirebaseUids, hasLength(pushesAfterFirstRun));
        expect(
          await _ownerInventorySnapshot(database, 'account-owner'),
          afterFirstRun,
        );
        expect(await _foreignOwnerSnapshot(database), foreignBefore);
      } finally {
        await database?.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );
}

Future<({String sessionId, String assignmentId})> _seedRestartAssessmentGraph(
  AppDatabase database,
) async {
  const ownerId = 'assessment-guest';
  const sessionId = 'assessment-session';
  const attemptId = 'assessment-evidence';
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('$ownerId', NULL, 'localGuest', 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO research_consents '
    '(id, owner_id, consent_version, consent_state, decided_at_utc_ms, '
    'withdrawn_at_utc_ms) VALUES '
    "('assessment-consent', '$ownerId', 1, 'accepted', 10, NULL)",
  );
  final assignment = await DriftExperimentAssignmentRepository(database)
      .assignIfAbsent(
        ownerId: ownerId,
        experimentId: 'assessment-study',
        experimentVersion: 1,
        cohort: 'enforced-a',
        protocolVersion: 'assessment-protocol-v1',
        assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(5, isUtc: true),
      );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES '
    "('assessment-category', '$ownerId', 'Assessment', 'assessment', 20, 20)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
    'normalized_meaning, part_of_speech, created_at_utc_ms, '
    'updated_at_utc_ms) VALUES '
    "('assessment-word', '$ownerId', 'assessment-category', 'word', 'word', "
    "'meaning', 'meaning', 'noun', 20, 20)",
  );
  await database.customInsert(
    'INSERT INTO learning_sessions '
    '(id, owner_id, activity_type, state, started_at_utc_ms, '
    'ended_at_utc_ms, app_version, build_id) VALUES '
    "('$sessionId', '$ownerId', 'assessment', 'completed', 20, 50, "
    "'1.0.0', 'task-12-restart')",
  );
  final repository = DriftAssessmentRepository(database);
  await repository.start(
    AssessmentRun(
      id: 'assessment-run',
      ownerId: ownerId,
      learningSessionId: sessionId,
      studyCycleId: 'assessment-cycle',
      phase: AssessmentPhase.pre,
      state: AssessmentRunState.active,
      protocolId: 'assessment-protocol',
      protocolVersion: assignment.protocolVersion,
      experimentId: assignment.experimentId,
      experimentVersion: assignment.experimentVersion,
      assignmentId: assignment.id,
      cohort: assignment.cohort,
      consentVersion: 1,
      consentDecidedAtUtc: DateTime.fromMillisecondsSinceEpoch(10, isUtc: true),
      instrumentId: 'vocabulary-outcome',
      instrumentVersion: '1.0.0',
      formId: 'form-a',
      formVersion: '1.0.0',
      instrumentChecksumSha256:
          '1111111111111111111111111111111111111111111111111111111111111111',
      formChecksumSha256:
          '2222222222222222222222222222222222222222222222222222222222222222',
      appVersion: '1.0.0',
      buildId: 'task-12-restart',
      databaseSchemaVersion: AppDatabase.currentSchemaVersion,
      contentRevision: 'assessment-content-r1',
      evidencePolicyVersion: EvidenceContext.currentPolicyVersion,
      featureContractRevision: currentFeatureContractIdentity.revision,
      featureContractHash: currentFeatureContractIdentity.semanticHash,
      startedAtUtc: DateTime.fromMillisecondsSinceEpoch(20, isUtc: true),
      completedAtUtc: null,
      abandonedAtUtc: null,
    ),
  );
  await repository.complete(
    runId: 'assessment-run',
    completedAtUtc: DateTime.fromMillisecondsSinceEpoch(50, isUtc: true),
  );
  final context = EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.assessment,
    skillId: 'assessment-word',
    hintLevel: 0,
    contentRevision: 'assessment-content-r1',
    rolloutMode: EvidencePolicyRolloutMode.enforced,
    protocolId: 'assessment-protocol',
    protocolVersion: assignment.protocolVersion,
    experimentId: assignment.experimentId,
    experimentVersion: assignment.experimentVersion,
    assignmentId: assignment.id,
    cohort: assignment.cohort,
    researchConsentVersion: 1,
    instrumentId: 'vocabulary-outcome',
    instrumentVersion: '1.0.0',
    formId: 'form-a',
    formVersion: '1.0.0',
    assessmentItemId: 'item-1',
    assessmentResponseCode: 'choice-a',
    scoringRuleVersion: 'binary-v1',
    engagementAllowed: false,
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, evidence_class, '
    'evidence_context_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>(attemptId),
      const Variable<String>(ownerId),
      const Variable<String>(sessionId),
      const Variable<String>('assessment-word'),
      const Variable<String>('meaningChoice'),
      const Variable<bool>(true),
      const Variable<int>(100),
      const Variable<int>(1),
      const Variable<int>(30),
      const Variable<String>('assessment'),
      Variable<String>(jsonEncode(context.toJson())),
    ],
  );
  await database.customInsert(
    'INSERT INTO events_v2 '
    '(event_id, event_type, event_version, occurred_at_utc, recorded_at_utc, '
    'actor_identity, owner_id, aggregate_type, aggregate_id, idempotency_key, '
    'consent_context_json, app_version, build_id, privacy_classification, '
    'payload_json) VALUES '
    "('assessment-event', 'QuizCompleted', 2, 30, 31, '$ownerId', "
    "'$ownerId', 'LearningSession', '$sessionId', "
    "'learning-attempt:$attemptId:v2', '{}', '1.0.0', 'task-12-restart', "
    "'research', '{\"attemptId\":\"$attemptId\"}')",
  );
  await database.customInsert(
    'INSERT INTO outbox_operations '
    '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
    'payload_version, base_revision, state, created_at_utc_ms) VALUES '
    "('attempt:$attemptId:2', '$ownerId', 'attempt', '$attemptId', "
    "'upsert', 2, 0, 'pending', 30)",
  );
  return (sessionId: sessionId, assignmentId: assignment.id);
}

Future<Map<String, Object?>> _restartAssessmentSnapshot(AppDatabase database) =>
    database
        .customSelect(
          "SELECT * FROM assessment_runs WHERE id = 'assessment-run'",
        )
        .map((row) => row.data)
        .getSingle();

Future<Map<String, Object?>> _restartAssessmentAttemptSnapshot(
  AppDatabase database,
) => database
    .customSelect(
      "SELECT * FROM answer_attempts WHERE id = 'assessment-evidence'",
    )
    .map((row) => row.data)
    .getSingle();

Future<Map<String, Object?>> _restartAssessmentEventSnapshot(
  AppDatabase database,
) => database
    .customSelect("SELECT * FROM events_v2 WHERE event_id = 'assessment-event'")
    .map((row) => row.data)
    .getSingle();

Future<Map<String, Object?>> _restartAssessmentOutboxSnapshot(
  AppDatabase database,
) => database
    .customSelect(
      "SELECT * FROM outbox_operations WHERE entity_id = 'assessment-evidence'",
    )
    .map((row) => row.data)
    .getSingle();

Future<void> _seedLearningEvidenceVocabulary(
  AppDatabase database,
  String ownerId,
) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'learning-category',
          ownerId: ownerId,
          name: 'Learning',
          normalizedName: 'learning',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'learning-word',
          ownerId: ownerId,
          categoryId: 'learning-category',
          spelling: 'durable',
          normalizedSpelling: 'durable',
          meaning: 'persistent',
          normalizedMeaning: 'persistent',
          partOfSpeech: 'adjective',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

final class _UnavailableLearningEventContextProvider
    implements LearningEventContextProvider {
  int calls = 0;

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async {
    calls++;
    throw StateError('learning event context must not resolve during replay');
  }
}

Future<void> _expectWithdrawnResearchConsent(
  AppDatabase database,
  DateTime nowUtc,
) async {
  final rows = await (database.select(
    database.researchConsents,
  )..where((row) => row.ownerId.equals('account-owner'))).get();
  expect(rows, hasLength(1));
  expect(rows.single.id, 'target:consent-1');
  expect(rows.single.consentState, 'withdrawn');
  expect(rows.single.decidedAtUtcMs, 200);
  expect(rows.single.withdrawnAtUtcMs, 200);

  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'unexpected-consent-owner',
    nowUtc: () => nowUtc,
  );
  final researchConsent = ResearchConsentUseCases(
    owners: owners,
    repository: DriftResearchConsentRepository(database),
    nowUtc: () => nowUtc,
  );
  final status = await researchConsent.load();
  expect(status.accepted, isFalse);
  expect(
    status.decidedAtUtc,
    DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
  );
  expect(
    status.withdrawnAtUtc,
    DateTime.fromMillisecondsSinceEpoch(200, isUtc: true),
  );

  final exports = ExportUseCases(
    reader: DriftExportReader(database),
    store: _UnexpectedExportStore(),
    nowUtc: () => nowUtc,
    loadThaiFont: () async => throw StateError('font load was unexpected'),
  );
  await expectLater(
    exports.prepare(
      format: ExportFormat.researchJson,
      selection: const ExportSelection(
        includeVocabulary: true,
        includeAttempts: false,
        includeReading: false,
      ),
      cancellation: ExportCancellation(),
    ),
    throwsA(
      isA<ExportException>().having(
        (error) => error.code,
        'code',
        ExportFailureCode.consentRequired,
      ),
    ),
  );
}

final class _UnexpectedExportStore implements ExportArtifactStore {
  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
  }) async {
    throw StateError('research export save was unexpected');
  }
}

const Set<String> _sevenEntityTypes = <String>{
  'category',
  'word',
  'attempt',
  'readingEvent',
  'rewardTransaction',
  'srsState',
  'achievementUnlock',
};

const Set<String> _completeInventoryEntityTypes = <String>{
  ..._sevenEntityTypes,
  'assessmentRun',
};

final class _UpgradeCloud implements SyncGateway {
  _UpgradeCloud(this.nowUtc);

  final DateTime nowUtc;
  final Completer<void> firstPushEntered = Completer<void>();
  final Completer<void> releaseFirstPush = Completer<void>();
  final List<String> pushFirebaseUids = <String>[];
  final List<String> pullFirebaseUids = <String>[];
  final Map<String, int> namespaceApplyCounts = <String, int>{};

  int get totalProviderCalls =>
      pushFirebaseUids.length + pullFirebaseUids.length;

  @override
  Future<PushResult> push(PushMutation mutation) async {
    pushFirebaseUids.add(mutation.firebaseUid);
    if (!firstPushEntered.isCompleted) {
      firstPushEntered.complete();
      await releaseFirstPush.future;
    }
    final namespaceKey = '${mutation.firebaseUid}:${mutation.operationId}';
    namespaceApplyCounts.update(
      namespaceKey,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return PushAcknowledged(
      operationId: mutation.operationId,
      resultingRevision: mutation.localRevision,
      acknowledgedAtUtc: nowUtc,
    );
  }

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async {
    pullFirebaseUids.add(firebaseUid);
    return PullPage(
      changes: const <SyncEntity>[],
      nextCursor: after,
      hasMore: false,
    );
  }

  @override
  Future<CloudSyncPolicy> fetchPolicy() async => CloudSyncPolicy(
    enabled: true,
    source: CloudSyncPolicySource.remote,
    fetchedAtUtc: nowUtc,
    expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
  );
}

final class _AnonymousBoundCloud implements SyncGateway {
  _AnonymousBoundCloud(this.nowUtc);

  final DateTime nowUtc;
  final List<String> pushFirebaseUids = <String>[];
  final Map<String, int> namespaceApplyCounts = <String, int>{};
  final Map<String, PushAcknowledged> acknowledgements =
      <String, PushAcknowledged>{};

  @override
  Future<PushResult> push(PushMutation mutation) async {
    pushFirebaseUids.add(mutation.firebaseUid);
    final key = '${mutation.firebaseUid}:${mutation.operationId}';
    final existing = acknowledgements[key];
    if (existing != null) return existing;
    namespaceApplyCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    final acknowledgement = PushAcknowledged(
      operationId: mutation.operationId,
      resultingRevision: mutation.localRevision,
      acknowledgedAtUtc: nowUtc,
    );
    acknowledgements[key] = acknowledgement;
    return acknowledgement;
  }

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async => PullPage(
    changes: const <SyncEntity>[],
    nextCursor: after,
    hasMore: false,
  );

  @override
  Future<CloudSyncPolicy> fetchPolicy() async => CloudSyncPolicy(
    enabled: true,
    source: CloudSyncPolicySource.remote,
    fetchedAtUtc: nowUtc,
    expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
  );
}

const Map<String, String> _inventoryIdentityColumns = <String, String>{
  'research_consents': 'id',
  'experiment_assignments': 'id',
  'assessment_runs': 'id',
  'vocabulary_categories': 'id',
  'vocabulary_words': 'id',
  'vocabulary_imports': 'id',
  'vocabulary_import_rows': 'id',
  'learning_sessions': 'id',
  'answer_attempts': 'id',
  'srs_states': 'id',
  'reading_progress_entries': 'id',
  'reading_events': 'id',
  'points_ledger_entries': 'id',
  'achievement_unlocks': 'id',
  'reward_transactions': 'id',
  'owned_reward_items': 'id',
  'equipped_reward_items': 'id',
  'outbox_operations': 'operation_id',
  'sync_checkpoints': 'id',
  'sync_conflicts': 'id',
  'events_v2': 'event_id',
  'quest_instances': 'instance_id',
  'quest_objective_progress': 'id',
  'streak_states': 'owner_id',
  'learning_day_log': 'id',
  'association_records': 'id',
  'associative_memory_states': 'id',
  'speech_evidence': 'id',
  'ai_usage_events': "owner_id || ':' || event_id",
};

Future<Map<String, List<String>>> _completeInventoryIdentity(
  AppDatabase database,
) async {
  final result = <String, List<String>>{};
  for (final entry in _inventoryIdentityColumns.entries) {
    final rows = await database
        .customSelect(
          'SELECT ${entry.value} AS row_identity FROM ${entry.key} '
          'ORDER BY row_identity',
        )
        .get();
    result[entry.key] = rows
        .map((row) => row.read<String>('row_identity'))
        .toList();
  }
  return result;
}

Future<Map<String, int>> _completeInventoryCounts(AppDatabase database) async {
  final result = <String, int>{};
  for (final table in ownerUpgradeInventory) {
    result[table] = await _tableCount(database, table);
  }
  return result;
}

Future<int> _tableCount(AppDatabase database, String table) => database
    .customSelect('SELECT COUNT(*) AS count FROM $table')
    .getSingle()
    .then((row) => row.read<int>('count'));

Future<int> _ownerRowCount(
  AppDatabase database,
  String table,
  String ownerId,
) => database
    .customSelect(
      'SELECT COUNT(*) AS count FROM $table WHERE owner_id = ?',
      variables: [Variable<String>(ownerId)],
    )
    .getSingle()
    .then((row) => row.read<int>('count'));

Future<int> _ownerNaturalKeyCount(
  AppDatabase database,
  String table,
  String ownerId,
) => _ownerRowCount(database, table, ownerId);

Future<int> _projectionEventCount(AppDatabase database, String ownerId) =>
    database
        .customSelect(
          'SELECT COUNT(*) AS count FROM events_v2 '
          'WHERE owner_id = ? AND event_type LIKE ?',
          variables: [
            Variable<String>(ownerId),
            const Variable<String>('LearningProjection%'),
          ],
        )
        .getSingle()
        .then((row) => row.read<int>('count'));

Future<Map<String, List<String>>> _foreignOwnerSnapshot(AppDatabase database) =>
    _ownerInventorySnapshot(database, 'foreign-owner');

Future<Map<String, List<String>>> _ownerInventorySnapshot(
  AppDatabase database,
  String ownerId,
) async {
  final result = <String, List<String>>{};
  final ownerRows = await database
      .customSelect(
        'SELECT * FROM local_owners WHERE id = ?',
        variables: [Variable<String>(ownerId)],
      )
      .get();
  result['local_owners'] = ownerRows.map(_rowFingerprint).toList();
  for (final table in ownerUpgradeInventory) {
    final rows = await database
        .customSelect(
          'SELECT * FROM $table WHERE owner_id = ? ORDER BY rowid',
          variables: [Variable<String>(ownerId)],
        )
        .get();
    result[table] = rows.map(_rowFingerprint).toList();
  }
  final importRows = await database
      .customSelect(
        'SELECT child.* FROM vocabulary_import_rows AS child '
        'JOIN vocabulary_imports AS parent ON parent.id = child.import_id '
        'WHERE parent.owner_id = ? ORDER BY child.rowid',
        variables: [Variable<String>(ownerId)],
      )
      .get();
  result['vocabulary_import_rows'] = importRows.map(_rowFingerprint).toList();
  final objectiveRows = await database
      .customSelect(
        'SELECT child.* FROM quest_objective_progress AS child '
        'JOIN quest_instances AS parent '
        'ON parent.instance_id = child.instance_id '
        'WHERE parent.owner_id = ? ORDER BY child.rowid',
        variables: [Variable<String>(ownerId)],
      )
      .get();
  result['quest_objective_progress'] = objectiveRows
      .map(_rowFingerprint)
      .toList();
  return result;
}

String _rowFingerprint(QueryRow row) {
  final entries = row.data.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return entries
      .map((entry) => '${entry.key}:${entry.value.runtimeType}:${entry.value}')
      .join('|');
}

Future<Map<String, Object>> _completeInventorySnapshot(
  AppDatabase database,
) async {
  final owner = await (database.select(
    database.localOwners,
  )..where((row) => row.isActive.equals(true))).getSingle();
  final operations = await database
      .customSelect(
        'SELECT operation_id, entity_type, entity_id, state, attempt_count, '
        'acknowledged_at_utc_ms FROM outbox_operations WHERE owner_id = ? '
        'ORDER BY operation_id',
        variables: [const Variable<String>('guest-owner')],
      )
      .get();
  final objectives = await database
      .customSelect(
        'SELECT child.id, child.instance_id, child.objective_id '
        'FROM quest_objective_progress AS child '
        'JOIN quest_instances AS parent '
        'ON parent.instance_id = child.instance_id '
        'WHERE parent.owner_id = ? ORDER BY child.id',
        variables: [const Variable<String>('guest-owner')],
      )
      .get();
  return <String, Object>{
    'activeOwnerId': owner.id,
    'firebaseUid': owner.firebaseUid ?? '',
    'inventoryIdentity': await _completeInventoryIdentity(database),
    'inventoryCounts': await _completeInventoryCounts(database),
    'operationRows': operations
        .map(
          (row) =>
              '${row.read<String>('operation_id')}|'
              '${row.read<String>('entity_type')}|'
              '${row.read<String>('entity_id')}|'
              '${row.read<String>('state')}|'
              '${row.read<int>('attempt_count')}|'
              '${row.readNullable<int>('acknowledged_at_utc_ms')}',
        )
        .toList(),
    'operationTypes': operations
        .map((row) => row.read<String>('entity_type'))
        .toSet(),
    'objectiveRows': objectives
        .map(
          (row) =>
              '${row.read<String>('id')}|'
              '${row.read<String>('instance_id')}|'
              '${row.read<String>('objective_id')}',
        )
        .toList(),
  };
}

Future<Map<String, Object>> _inventorySnapshot(AppDatabase database) async {
  const inventoryTables = <String>[
    'vocabulary_categories',
    'vocabulary_words',
    'answer_attempts',
    'reading_events',
    'reward_transactions',
    'srs_states',
    'achievement_unlocks',
  ];
  final rowIds = <String>[];
  var guestInventoryCount = 0;
  for (final table in inventoryTables) {
    final rows = await database
        .customSelect('SELECT id, owner_id FROM $table ORDER BY id')
        .get();
    rowIds.addAll(rows.map((row) => '$table:${row.read<String>('id')}'));
    guestInventoryCount += rows
        .where((row) => row.read<String>('owner_id') == 'guest-owner')
        .length;
  }
  final operations = await database
      .customSelect(
        'SELECT operation_id, entity_type, entity_id, attempt_count, state '
        'FROM outbox_operations ORDER BY operation_id',
      )
      .get();
  final checkpoints = await database
      .customSelect(
        'SELECT id, server_cursor FROM sync_checkpoints ORDER BY id',
      )
      .get();
  final activeOwner = await database
      .customSelect('SELECT id FROM local_owners WHERE is_active = 1')
      .getSingle();

  return <String, Object>{
    'activeOwnerId': activeOwner.read<String>('id'),
    'rowIds': rowIds,
    'operationRows': operations
        .map(
          (row) =>
              '${row.read<String>('operation_id')}|'
              '${row.read<String>('entity_type')}|'
              '${row.read<String>('entity_id')}|'
              '${row.read<int>('attempt_count')}|'
              '${row.read<String>('state')}',
        )
        .toList(),
    'operationTypes': operations
        .map((row) => row.read<String>('entity_type'))
        .toSet(),
    'checkpointRows': checkpoints
        .map(
          (row) =>
              '${row.read<String>('id')}|${row.readNullable<String>('server_cursor')}',
        )
        .toList(),
    'checkpointCount': checkpoints.length,
    'guestInventoryCount': guestInventoryCount,
  };
}

String _legacyBackfillOperationId(String pointId) {
  final digest = sha256.convert(utf8.encode(pointId));
  return 'rewardTransaction:reward:legacy:$digest:1';
}

Future<void> _seedCompleteSyncInventory(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('guest-owner', 'anonymous-old', 'firebaseBound', 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('account-owner', 'firebase-new', 'firebaseBound', 2, 0)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, sort_order, local_revision, '
    'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) VALUES '
    "('category-1', 'guest-owner', 'Travel', 'travel', 0, 1, 0, 0, 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
    'normalized_meaning, part_of_speech, source, is_global, local_revision, '
    'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) VALUES '
    "('word-1', 'guest-owner', 'category-1', 'station', 'station', "
    "'station', 'station', 'noun', 'manual', 0, 1, 0, 0, 1, 1)",
  );
  await database.customInsert(
    "INSERT INTO learning_sessions (id, owner_id, activity_type, state, "
    "started_at_utc_ms, ended_at_utc_ms, correct_count, wrong_count, score, "
    "app_version, build_id) VALUES ('session-1', 'guest-owner', "
    "'quiz', 'completed', 1, 2, 1, 0, 100, '1', '1')",
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, '
    'provider_provenance) VALUES '
    "('attempt-1', 'guest-owner', 'session-1', 'word-1', 'meaning', 1, "
    '100, 1, 2, NULL)',
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES ('srs-1', 'guest-owner', 'word-1', "
    '1, 1, 1, 1, 0, 2, 3, 1)',
  );
  await database.customInsert(
    "INSERT INTO reading_events VALUES ('reading-1', 'guest-owner', "
    "'doc-1', 1, 'position', 5, 2)",
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries VALUES ('reading-progress-1', "
    "'guest-owner', 'doc-1', 1, 5, 0, 2)",
  );
  await database.customInsert(
    "INSERT INTO points_ledger_entries VALUES ('points-1', 'guest-owner', "
    "'seed-points', 'quizCorrect', 200, NULL, 2)",
  );
  await database.customInsert(
    "INSERT INTO reward_transactions VALUES ('reward-1', 'guest-owner', "
    "'reward-key-1', 'purchase', -80, 'theme_ocean', 1, NULL, 2)",
  );
  await database.customInsert(
    "INSERT INTO achievement_unlocks VALUES ('achievement-1', 'guest-owner', "
    "'first-answer', 1, 'attempt-1', 2)",
  );

  const operations = <(String, String, String)>[
    ('operation:category', 'category', 'category-1'),
    ('operation:word', 'word', 'word-1'),
    ('operation:attempt', 'attempt', 'attempt-1'),
    ('operation:reading', 'readingEvent', 'reading-1'),
    ('operation:reward', 'rewardTransaction', 'reward-1'),
    ('operation:srs', 'srsState', 'word-1'),
    ('operation:achievement', 'achievementUnlock', 'achievement-1'),
  ];
  var createdAt = 1;
  for (final operation in operations) {
    await database.customInsert(
      'INSERT INTO outbox_operations '
      '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
      'created_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<String>(operation.$1),
        const Variable<String>('guest-owner'),
        Variable<String>(operation.$2),
        Variable<String>(operation.$3),
        const Variable<String>('upsert'),
        Variable<int>(createdAt++),
      ],
    );
  }
}

Future<void> _seedAnonymousBoundCompleteInventory(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('guest-owner', NULL, 'localGuest', 1, 1)",
  );
  await database.customInsert(
    "INSERT INTO research_consents VALUES "
    "('consent-1', 'guest-owner', 1, 'accepted', 10, NULL)",
  );
  final assignmentId =
      DriftExperimentAssignmentRepository.canonicalAssignmentId(
        ownerId: 'guest-owner',
        experimentId: 'research-assessment',
        experimentVersion: 1,
      );
  await database.customInsert(
    'INSERT INTO experiment_assignments '
    '(id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms) VALUES '
    "(?, 'guest-owner', 'research-assessment', 1, 'treatment-a', "
    "'2026.08', 1723201200000)",
    variables: [Variable<String>(assignmentId)],
  );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, sort_order, local_revision, '
    'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) VALUES '
    "('category-1', 'guest-owner', 'Travel', 'travel', 0, 1, 4, 0, 10, 10)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
    'normalized_meaning, part_of_speech, source, is_global, local_revision, '
    'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) VALUES '
    "('word-1', 'guest-owner', 'category-1', 'station', 'station', "
    "'station', 'station', 'noun', 'manual', 0, 1, 3, 0, 10, 10)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_imports VALUES "
    "('import-1', 'guest-owner', 'category-1', 'csv', 'travel.csv', "
    "'hash-1', 'complete', 1, 0, 0, 10, 11)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_import_rows VALUES "
    "('import-row-1', 'import-1', 1, 'row-hash-1', 'accepted', NULL, 'word-1')",
  );
  await database.customInsert(
    "INSERT INTO learning_sessions (id, owner_id, activity_type, state, "
    "started_at_utc_ms, ended_at_utc_ms, correct_count, wrong_count, score, "
    "app_version, build_id) VALUES ('session-1', 'guest-owner', "
    "'quiz', 'completed', 10, 20, 1, 0, 100, '1', '1')",
  );
  await _seedCompleteInventoryAssessmentRun(
    database,
    runId: 'assessment-inventory-run',
    ownerId: 'guest-owner',
    learningSessionId: 'session-1',
    assignmentId: assignmentId,
  );
  await database.customInsert(
    'INSERT INTO answer_attempts '
    '(id, owner_id, session_id, word_id, prompt_mode, is_correct, '
    'response_time_ms, attempt_number, occurred_at_utc_ms, '
    'provider_provenance) VALUES '
    "('attempt-1', 'guest-owner', 'session-1', 'word-1', 'meaning', 1, "
    '100, 1, 15, NULL)',
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES ('srs-1', 'guest-owner', 'word-1', "
    '1, 1, 1, 1, 0, 15, 30, 1)',
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries VALUES ('reading-progress-1', "
    "'guest-owner', 'doc-1', 1, 5, 0, 20)",
  );
  await database.customInsert(
    "INSERT INTO reading_events VALUES ('reading-1', 'guest-owner', "
    "'doc-1', 1, 'position', 5, 20)",
  );
  await database.customInsert(
    "INSERT INTO points_ledger_entries VALUES ('points-1', 'guest-owner', "
    "'answer:1', 'quizCorrect', 200, NULL, 20)",
  );
  await database.customInsert(
    "INSERT INTO achievement_unlocks VALUES ('achievement-1', 'guest-owner', "
    "'first-answer', 1, 'attempt-1', 20)",
  );
  await database.customInsert(
    "INSERT INTO reward_transactions VALUES ('reward-1', 'guest-owner', "
    "'reward-key-1', 'purchase', -80, 'theme_ocean', 1, NULL, 20)",
  );
  await database.customInsert(
    "INSERT INTO reward_transactions VALUES ('reward-equip-1', "
    "'guest-owner', 'reward-equip-key-1', 'equip', 0, 'theme_ocean', 1, "
    'NULL, 21)',
  );
  await database.customInsert(
    "INSERT INTO owned_reward_items VALUES ('owned:guest-owner:theme_ocean', 'guest-owner', "
    "'theme_ocean', 1, 'reward-1', 20)",
  );
  await database.customInsert(
    "INSERT INTO equipped_reward_items VALUES ('equipped:guest-owner:theme', 'guest-owner', "
    "'theme', 'theme_ocean', 21)",
  );

  const operations = <(String, String, String)>[
    ('operation:category', 'category', 'category-1'),
    ('operation:word', 'word', 'word-1'),
    ('operation:attempt', 'attempt', 'attempt-1'),
    ('operation:reading', 'readingEvent', 'reading-1'),
    ('operation:reward', 'rewardTransaction', 'reward-1'),
    ('operation:srs', 'srsState', 'word-1'),
    ('operation:achievement', 'achievementUnlock', 'achievement-1'),
  ];
  var createdAt = 20;
  for (final operation in operations) {
    if (operation.$1 == 'operation:category') {
      await database.customInsert(
        'INSERT INTO outbox_operations '
        '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
        'state, attempt_count, last_attempt_at_utc_ms, created_at_utc_ms, '
        'failure_code) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(operation.$1),
          const Variable<String>('guest-owner'),
          Variable<String>(operation.$2),
          Variable<String>(operation.$3),
          const Variable<String>('upsert'),
          const Variable<String>('permanentFailure'),
          const Variable<int>(5),
          const Variable<int>(19),
          Variable<int>(createdAt++),
          const Variable<String>('oldNamespaceFailure'),
        ],
      );
      continue;
    }
    await database.customInsert(
      'INSERT INTO outbox_operations '
      '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
      'created_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<String>(operation.$1),
        const Variable<String>('guest-owner'),
        Variable<String>(operation.$2),
        Variable<String>(operation.$3),
        const Variable<String>('upsert'),
        Variable<int>(createdAt++),
      ],
    );
  }

  final seededCursor = SyncCursor(
    serverUpdatedAtUtc: DateTime.utc(2026, 8, 8, 8),
    documentId: 'old-namespace-word',
  );
  await database.customInsert(
    'INSERT INTO sync_checkpoints '
    '(id, owner_id, collection_name, server_cursor, last_success_at_utc_ms) '
    'VALUES (?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('guest-owner:words'),
      const Variable<String>('guest-owner'),
      const Variable<String>('words'),
      Variable<String>(seededCursor.toJsonString()),
      const Variable<int>(19),
    ],
  );
  await database.customInsert(
    'INSERT INTO sync_conflicts '
    '(id, owner_id, entity_type, entity_id, local_revision, cloud_revision, '
    'resolution_policy, outcome, resolved_at_utc_ms) VALUES '
    "('conflict-1', 'guest-owner', 'word', 'word-1', 1, 2, "
    "'cloudWins', 'cloudApplied', 20)",
  );

  const eventRows = <(String, String, String, String, String)>[
    (
      'event-source-1',
      'QuizCompleted',
      'LearningSession',
      'session-1',
      'source-event-1',
    ),
    (
      'projection-result-1',
      'LearningProjectionApplied',
      'LearningProjection',
      'event-source-1',
      'projection-result-1',
    ),
    (
      'projection-cursor-1',
      'LearningProjectionCursor',
      'LearningProjectionCursor',
      'event-source-1',
      'projection-cursor-1',
    ),
  ];
  for (final event in eventRows) {
    await database.customInsert(
      'INSERT INTO events_v2 '
      '(event_id, event_type, event_version, occurred_at_utc, recorded_at_utc, '
      'actor_identity, owner_id, aggregate_type, aggregate_id, '
      'idempotency_key, consent_context_json, app_version, build_id, '
      'privacy_classification, payload_json) VALUES '
      '(?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<String>(event.$1),
        Variable<String>(event.$2),
        Variable<DateTime>(DateTime.utc(2026, 8, 9, 10)),
        Variable<DateTime>(DateTime.utc(2026, 8, 9, 10, 0, 1)),
        const Variable<String>('guest-owner'),
        const Variable<String>('guest-owner'),
        Variable<String>(event.$3),
        Variable<String>(event.$4),
        Variable<String>(event.$5),
        const Variable<String>('{}'),
        const Variable<String>('1.0.0'),
        const Variable<String>('task-5-scenario'),
        const Variable<String>('anonymized'),
        const Variable<String>('{}'),
      ],
    );
  }

  await database.customInsert(
    'INSERT INTO quest_definitions '
    '(quest_id, catalog_version, title, description, type, objectives_json, '
    'reward_json) VALUES '
    "('quest-1', 1, 'Seed Quest', 'Seed', 'daily', '[]', "
    "'{\"xpAmount\":10,\"rewardItemId\":null}')",
  );
  await database.customInsert(
    'INSERT INTO quest_instances '
    '(instance_id, quest_id, owner_id, catalog_version, assigned_at_utc_ms, '
    "state) VALUES ('quest-instance-1', 'quest-1', 'guest-owner', 1, 20, "
    "'active')",
  );
  await database.customInsert(
    'INSERT INTO quest_objective_progress '
    '(id, instance_id, objective_id, current_count, target_count, '
    "source_event_ids_json) VALUES ('objective-1', 'quest-instance-1', "
    "'answer-once', 1, 1, '[\"event-source-1\"]')",
  );
  await database.customInsert(
    'INSERT INTO streak_states '
    '(owner_id, current_streak_days, longest_streak_days, freeze_count, '
    "updated_at_utc_ms) VALUES ('guest-owner', 1, 1, 0, 20)",
  );
  await database.customInsert(
    'INSERT INTO learning_day_log '
    '(id, owner_id, learning_day, first_session_at_utc_ms) VALUES '
    "('day:guest-owner:2026-08-09', 'guest-owner', '2026-08-09', 20)",
  );
  await database.customInsert(
    'INSERT INTO association_records '
    '(id, owner_id, word_key, type, content, created_at_utc_ms) VALUES '
    "('association-1', 'guest-owner', 'station', 'keyword', 'train stop', 20)",
  );
  await database.customInsert(
    'INSERT INTO associative_memory_states '
    '(id, owner_id, word_key, stability, difficulty, cue_dependency, '
    'lapse_count, next_due_at_utc_ms, algorithm_version) VALUES '
    "('memory-1', 'guest-owner', 'station', 1.0, 5.0, 0.0, 0, 30, 'v1')",
  );
  await database.customInsert(
    'INSERT INTO speech_evidence '
    '(id, owner_id, session_id, word_id, prompt_mode, target_content, '
    'recognized_transcript, locale, stt_engine, similarity_algorithm, '
    'similarity_score, is_exact_match, recognition_confidence, sample_size, '
    'occurred_at_utc_ms, duration_ms) VALUES '
    "('speech-1', 'guest-owner', 'session-1', 'word-1', 'meaning', "
    "'station', 'station', 'en-US', 'fake-stt', 'levenshtein', 100, 1, "
    '0.95, 1, 20, 500)',
  );
  await database.customInsert(
    'INSERT INTO ai_usage_events '
    '(event_id, owner_id, occurred_at_utc_ms, provider_id, model, '
    'request_type, outcome, latency_ms) VALUES '
    "('ai-usage-1', 'guest-owner', 20, 'fake-provider', 'fake-model', "
    "'tutorReply', 'success', 10)",
  );
  await _seedForeignOwnerInventory(database);
}

Future<void> _seedCompleteInventoryAssessmentRun(
  AppDatabase database, {
  required String runId,
  required String ownerId,
  required String learningSessionId,
  required String assignmentId,
}) async {
  final repository = DriftAssessmentRepository(database);
  final startedAtUtc = DateTime.fromMillisecondsSinceEpoch(
    1723651200010,
    isUtc: true,
  );
  await repository.start(
    AssessmentRun(
      id: runId,
      ownerId: ownerId,
      learningSessionId: learningSessionId,
      studyCycleId: 'inventory-assessment-cycle',
      phase: AssessmentPhase.pre,
      state: AssessmentRunState.active,
      protocolId: 'research-assessment-protocol',
      protocolVersion: '2026.08',
      experimentId: 'research-assessment',
      experimentVersion: 1,
      assignmentId: assignmentId,
      cohort: 'treatment-a',
      consentVersion: 1,
      consentDecidedAtUtc: DateTime.fromMillisecondsSinceEpoch(10, isUtc: true),
      instrumentId: 'vocabulary-outcome',
      instrumentVersion: '1.0.0',
      formId: 'inventory-form-a',
      formVersion: '1.0.0',
      instrumentChecksumSha256:
          '1111111111111111111111111111111111111111111111111111111111111111',
      formChecksumSha256:
          '2222222222222222222222222222222222222222222222222222222222222222',
      appVersion: '1.0.0',
      buildId: 'guest-inventory-fixture',
      databaseSchemaVersion: AppDatabase.currentSchemaVersion,
      contentRevision: 'assessment-content-r1',
      evidencePolicyVersion: EvidenceContext.currentPolicyVersion,
      featureContractRevision: currentFeatureContractIdentity.revision,
      featureContractHash: currentFeatureContractIdentity.semanticHash,
      startedAtUtc: startedAtUtc,
      completedAtUtc: null,
      abandonedAtUtc: null,
    ),
  );
  await repository.complete(
    runId: runId,
    completedAtUtc: startedAtUtc.add(const Duration(milliseconds: 10)),
  );
}

Future<void> _seedForeignOwnerInventory(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('foreign-owner', 'firebase-foreign', 'firebaseBound', 2, 0)",
  );
  for (final table in ownerUpgradeInventory) {
    if (table == 'experiment_assignments' || table == 'assessment_runs') {
      continue;
    }
    final schema = await database
        .customSelect('PRAGMA table_info("$table")')
        .get();
    final columns = schema.map((row) => row.read<String>('name')).toList();
    final quotedColumns = columns.map((column) => '"$column"').join(', ');
    final projections = columns
        .map((column) {
          final quoted = '"$column"';
          if (column == 'owner_id') return "'foreign-owner'";
          if (column == 'quest_id') return quoted;
          if (column == 'idempotency_key') return "'foreign:' || $quoted";
          if (column == 'id' || column.endsWith('_id')) {
            return 'CASE WHEN $quoted IS NULL THEN NULL '
                "ELSE 'foreign:' || $quoted END";
          }
          return quoted;
        })
        .join(', ');
    await database.customInsert(
      'INSERT INTO "$table" ($quotedColumns) '
      'SELECT $projections FROM "$table" WHERE owner_id = ?',
      variables: [const Variable<String>('guest-owner')],
    );
  }
  final targetAssignmentId =
      DriftExperimentAssignmentRepository.canonicalAssignmentId(
        ownerId: 'foreign-owner',
        experimentId: 'research-assessment',
        experimentVersion: 1,
      );
  await database.customInsert(
    'INSERT INTO experiment_assignments '
    '(id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms) VALUES '
    "(?, 'foreign-owner', 'research-assessment', 1, 'treatment-a', "
    "'2026.08', 1723201200000)",
    variables: [Variable<String>(targetAssignmentId)],
  );
  await _seedCompleteInventoryAssessmentRun(
    database,
    runId: 'foreign:assessment-inventory-run',
    ownerId: 'foreign-owner',
    learningSessionId: 'foreign:session-1',
    assignmentId: targetAssignmentId,
  );
  await database.customInsert(
    'INSERT INTO vocabulary_import_rows '
    '(id, import_id, row_number, payload_hash, status, failure_code, word_id) '
    "SELECT 'foreign:' || id, 'foreign:' || import_id, row_number, "
    'payload_hash, status, failure_code, '
    "CASE WHEN word_id IS NULL THEN NULL ELSE 'foreign:' || word_id END "
    'FROM vocabulary_import_rows WHERE import_id = ?',
    variables: [const Variable<String>('import-1')],
  );
  await database.customInsert(
    'INSERT INTO quest_objective_progress '
    '(id, instance_id, objective_id, current_count, target_count, '
    'source_event_ids_json) '
    "SELECT 'foreign:' || id, 'foreign:' || instance_id, objective_id, "
    'current_count, target_count, source_event_ids_json '
    'FROM quest_objective_progress WHERE instance_id = ?',
    variables: [const Variable<String>('quest-instance-1')],
  );
}

Future<void> _seedTargetCollisionInventory(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('account-owner', 'firebase-new', 'firebaseBound', 3, 0)",
  );
  for (final table in ownerUpgradeInventory) {
    if (table == 'experiment_assignments' || table == 'assessment_runs') {
      continue;
    }
    final schema = await database
        .customSelect('PRAGMA table_info("$table")')
        .get();
    final columns = schema.map((row) => row.read<String>('name')).toList();
    final quotedColumns = columns.map((column) => '"$column"').join(', ');
    final projections = columns
        .map((column) {
          final quoted = '"$column"';
          if (column == 'owner_id') return "'account-owner'";
          if (column == 'actor_identity') return "'account-owner'";
          if (table == 'ai_usage_events' && column == 'event_id') {
            return quoted;
          }
          if (column == 'quest_id' ||
              column == 'achievement_id' ||
              column == 'item_id' ||
              column == 'idempotency_key') {
            return quoted;
          }
          if (column == 'id' || column.endsWith('_id')) {
            return 'CASE WHEN $quoted IS NULL THEN NULL '
                "ELSE 'target:' || $quoted END";
          }
          return quoted;
        })
        .join(', ');
    await database.customInsert(
      'INSERT INTO "$table" ($quotedColumns) '
      'SELECT $projections FROM "$table" WHERE owner_id = ?',
      variables: [const Variable<String>('guest-owner')],
    );
  }
  final targetAssignmentId =
      DriftExperimentAssignmentRepository.canonicalAssignmentId(
        ownerId: 'account-owner',
        experimentId: 'research-assessment',
        experimentVersion: 1,
      );
  await database.customInsert(
    'INSERT INTO experiment_assignments '
    '(id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms) VALUES '
    "(?, 'account-owner', 'research-assessment', 1, 'treatment-a', "
    "'2026.08', 1723201200000)",
    variables: [Variable<String>(targetAssignmentId)],
  );
  await _seedCompleteInventoryAssessmentRun(
    database,
    runId: 'target:assessment-inventory-run',
    ownerId: 'account-owner',
    learningSessionId: 'target:session-1',
    assignmentId: targetAssignmentId,
  );
  await database.customInsert(
    'INSERT INTO vocabulary_import_rows '
    '(id, import_id, row_number, payload_hash, status, failure_code, word_id) '
    "SELECT 'target:' || id, 'target:' || import_id, row_number, "
    'payload_hash, status, failure_code, '
    "CASE WHEN word_id IS NULL THEN NULL ELSE 'target:' || word_id END "
    'FROM vocabulary_import_rows WHERE import_id = ?',
    variables: [const Variable<String>('import-1')],
  );
  await database.customInsert(
    'INSERT INTO quest_objective_progress '
    '(id, instance_id, objective_id, current_count, target_count, '
    'source_event_ids_json) '
    "SELECT 'target:' || id, 'target:' || instance_id, objective_id, "
    'current_count + 1, target_count + 1, source_event_ids_json '
    'FROM quest_objective_progress WHERE instance_id = ?',
    variables: [const Variable<String>('quest-instance-1')],
  );
}
