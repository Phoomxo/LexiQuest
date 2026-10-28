import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_unavailable_session.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_practice_replay.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/drift_pair_matching_session_purpose_reader.dart';
import 'package:vocab_learning_app/features/account/application/local_data_deletion.dart';
import 'package:vocab_learning_app/features/export/application/owner_lifecycle_archive.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'pair_matching_evidence_contract_test.dart';
import 'pair_matching_source_composer_test.dart' as lexical;

Future<void> mergePairOwner(
  PairHarness h, {
  String target = 'synthetic-account',
  bool collision = false,
}) async {
  await h.db
      .into(h.db.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: target,
          firebaseUid: const Value('synthetic-uid'),
          accountState: const Value('firebaseBound'),
          isActive: const Value(false),
          createdAtUtcMs: 1,
        ),
      );
  if (collision) {
    await h.db
        .into(h.db.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'pm8-target-category',
            ownerId: target,
            name: 'Synthetic',
            normalizedName: 'synthetic',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    final item = h.operation.plan.orderedLexicalItems.first;
    await h.db
        .into(h.db.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'pm8-target-word',
            ownerId: target,
            categoryId: 'pm8-target-category',
            spelling: item.spelling,
            normalizedSpelling: item.spelling,
            meaning: item.meaning,
            normalizedMeaning: item.meaning,
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  }
  var sequence = 0;
  await DriftOwnerUpgradeRepository(
    h.db,
    nowUtc: () => DateTime.utc(2026, 9, 6),
    generateConflictId: () => 'pm8-conflict-${sequence++}',
    generateOwnerId: () => 'pm8-next-guest',
    generateOwnerOperationToken: () => 'pm8-operation-${sequence++}',
    deleteOwnerSecrets: (_) async {},
    ownerGateDelay: (_) => Completer<void>().future,
  ).upgrade(activeOwnerId: h.owner, firebaseUid: 'synthetic-uid');
  h.owner = target;
}

Future<void> planTap(
  PairHarness h,
  PairMatchingSessionCoordinator c,
  String word,
  PairTileSide side,
) => c.dispatch(
  PairSelectTile(
    operationId: '${c.state.operationRevision}:tap',
    ownerId: h.operation.plan.ownerId,
    sessionId: h.operation.plan.learningSessionId,
    roundOrdinal: c.state.roundOrdinal,
    expectedRevision: c.state.operationRevision,
    tile: PairTile(side, word),
    responseTimeMs: 25,
  ),
);

LearningUseCases realLearning(PairHarness h) => LearningUseCases(
  owners: h.learning.owners,
  repository: h.real,
  generateId: h.learning.generateId,
  nowUtc: h.learning.nowUtc,
  buildInfo: h.learning.buildInfo,
);

SessionConfiguration ownerConfiguration() => SessionConfiguration.validated(
  schemaVersion: 2,
  policyVersion: sessionConfigurationPolicyVersion,
  ownerId: 'synthetic-owner',
  mode: LessonMode.matching,
  itemCount: 4,
  direction: SessionDirection.forward,
  difficulty: SessionDifficulty.standard,
  hintBudget: 0,
  timing: const SessionTiming.timed(Duration(minutes: 10)),
  packIdentity: null,
  protocolId: 'protocol:local-standard',
  protocolVersion: '1',
  protocolLimitsIdentity:
      const SessionConfigurationProtocolLimits.standard().contentIdentity,
  pairDensityPreference: PairDensityPreference(
    density: PairDensity.compact4,
    provenance: PairDensityProvenance.learner,
  ),
);

class _OwnerProtocols implements SessionConfigurationProtocolProvider {
  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(
    String ownerId,
  ) async => const SessionConfigurationProtocolLimits.standard();
}

class _HeldResetOwnerProtocols implements SessionConfigurationProtocolProvider {
  final entered = Completer<void>(), release = Completer<void>();
  final owners = <String>[];

  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(
    String ownerId,
  ) async {
    owners.add(ownerId);
    if (owners.length == 1) {
      entered.complete();
      await release.future;
    }
    throw const SessionConfigurationResetRequired(
      SessionConfigurationResetReason.staleProtocol,
    );
  }
}

PairMatchingExperienceRuntime ownerRuntime(
  PairHarness h, {
  SessionConfigurationProtocolProvider? protocols,
}) {
  final learning = realLearning(h);
  final allowlist = PairCuratedAllowlist(
    version: h.operation.plan.allowlistVersion,
    items: h.operation.plan.orderedLexicalItems,
  );
  return PairMatchingExperienceRuntime(
    database: h.db,
    learning: learning,
    currentActivityEvidence: CurrentActivityEvidenceAdapter(learning: learning),
    registry: buildLessonModeRegistry(
      internalPairMatching: true,
      matchingDeliveryState: LessonModeDeliveryState.enabled,
    ),
    createController: (adapter) => UnifiedLessonController(
      learning: learning,
      adapter: adapter,
      sessionPurposeReader: h.real,
    ),
    composer: PairMatchingSourceComposer(allowlist: allowlist),
    start: PairMatchingAtomicStartAdapter(
      repository: h.real,
      capability: InternalPairMatchingCapability(
        allowlist: allowlist,
        isEnabled: () => false,
      ),
    ),
    protocols: protocols ?? _OwnerProtocols(),
    canStart: () => false,
    monotonicMicros: () => 0,
  );
}

PairPracticeReplay ownerReplay(PairHarness h) => PairPracticeReplay(
  reader: DriftPairMatchingSessionPurposeReader(h.db),
  start: PairMatchingAtomicStartAdapter(
    repository: h.real,
    capability: InternalPairMatchingCapability(
      allowlist: PairCuratedAllowlist(
        version: h.operation.plan.allowlistVersion,
        items: h.operation.plan.orderedLexicalItems,
      ),
      isEnabled: () => true,
    ),
  ),
);

void main() {
  setUpAll(tz.initializeTimeZones);
  for (final configured in [false, true]) {
    testWidgets(
      'actual recovered host binds account owner configured=$configured',
      (tester) async {
        final h = PairHarness(
          configuration: configured ? ownerConfiguration() : null,
        );
        addTearDown(h.db.close);
        await h.initialize();
        await mergePairOwner(h);
        await tester.pumpWidget(
          MaterialApp(
            home: PairMatchingExperienceHost.recover(
              runtime: ownerRuntime(h),
              operation: h.operation,
              onExit: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('pair-board-regular')),
          findsOneWidget,
        );
        await tester.tap(
          find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('pair-tile:target:synthetic-0')),
        );
        await tester.pumpAndSettle();
        expect(
          (await h.db.select(h.db.answerAttempts).get()).single.ownerId,
          h.owner,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'configured disposition binds runtime once and cannot follow a merge in a stale closure',
    () async {
      final h = PairHarness(configuration: ownerConfiguration());
      addTearDown(h.db.close);
      await h.initialize();
      final oldLearning = realLearning(h);
      final old = PairMatchingUnavailableSession(
        operation: h.operation,
        learning: oldLearning,
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: oldLearning,
        ),
        requireOwner: () async => h.owner,
      );
      await old.resolve(abandonIncomplete: false);
      await mergePairOwner(h);
      await expectLater(old.resolve(abandonIncomplete: true), throwsStateError);
      final freshLearning = realLearning(h);
      final fresh = PairMatchingUnavailableSession(
        operation: h.operation,
        learning: freshLearning,
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: freshLearning,
        ),
        requireOwner: () async => h.owner,
      );
      final result = await fresh.resolve(abandonIncomplete: true);
      expect(result.kind, PairAcceptedDispositionKind.stopped);
      expect(result.recovery.session.ownerId, h.owner);
      expect(result.recovery.attempts, isEmpty);
    },
  );

  for (final pendingCommitted in [true, false]) {
    testWidgets(
      'stale configured host cannot first-bind moved disposition pendingCommitted=$pendingCommitted',
      (tester) async {
        final h = PairHarness(configuration: ownerConfiguration());
        addTearDown(h.db.close);
        await h.initialize();
        final originalOwner = h.owner;
        final c = await h.restore();
        if (pendingCommitted) {
          await planTap(h, c, 'synthetic-0', PairTileSide.prompt);
          h.repository.answerFault = true;
          h.repository.afterWrite = true;
          await expectLater(
            planTap(h, c, 'synthetic-0', PairTileSide.target),
            throwsStateError,
          );
        } else {
          for (final item in h.operation.plan.orderedLexicalItems) {
            await planTap(h, c, item.wordId, PairTileSide.prompt);
            await planTap(h, c, item.wordId, PairTileSide.target);
          }
        }
        c.dispose();
        final protocols = _HeldResetOwnerProtocols();
        final runtime = ownerRuntime(h, protocols: protocols);
        Future<void> mount() => tester.pumpWidget(
          MaterialApp(
            home: PairMatchingExperienceHost.recover(
              runtime: runtime,
              operation: h.operation,
              onExit: () {},
            ),
          ),
        );
        Future<String> durableBytes() async => jsonEncode({
          for (final table in [
            'learning_sessions',
            'answer_attempts',
            'events_v2',
            'outbox_operations',
          ])
            table:
                (await h.db
                        .customSelect('SELECT * FROM $table ORDER BY 1')
                        .get())
                    .map((row) => row.data)
                    .toList(),
        });
        await mount();
        for (var i = 0; i < 40 && !protocols.entered.isCompleted; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(protocols.entered.isCompleted, true);
        expect(protocols.owners, [originalOwner]);
        await mergePairOwner(h);
        final before = await durableBytes();
        final beforeDisposition = await h.real.inspectPairDisposition(
          ownerId: h.owner,
          startOperation: h.operation.stableSerialization,
        );
        expect(
          beforeDisposition.kind,
          pendingCommitted
              ? PairAcceptedDispositionKind.pendingCommitted
              : PairAcceptedDispositionKind.complete,
        );
        expect(beforeDisposition.recovery.checkpoint!.terminalAtUtc, isNull);
        protocols.release.complete();
        await tester.pumpAndSettle();
        expect(
          await durableBytes(),
          before,
          reason: 'the stale P pane cannot acknowledge or finish R work',
        );
        expect(find.byKey(const ValueKey('pair-result')), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(
          await durableBytes(),
          before,
          reason: 'disposing the stale pane also retains exact R work',
        );
        await mount();
        await tester.pumpAndSettle();
        expect(protocols.owners, [originalOwner, h.owner]);
        final fresh = await h.real.inspectPairDisposition(
          ownerId: h.owner,
          startOperation: h.operation.stableSerialization,
        );
        expect(fresh.recovery.session.ownerId, h.owner);
        expect(fresh.recovery.attempts, hasLength(pendingCommitted ? 1 : 4));
        expect(fresh.recovery.checkpoint!.state['frozenEvidence'], isNull);
        expect(
          fresh.kind,
          pendingCommitted
              ? PairAcceptedDispositionKind.incomplete
              : PairAcceptedDispositionKind.complete,
        );
        if (!pendingCommitted) {
          expect(fresh.recovery.session.state, 'completed');
          expect(fresh.recovery.checkpoint!.terminalAcknowledged, true);
          expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
        }
        expect(await durableBytes(), isNot(before));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'real merged configured host enforces the accepted cap under runtime owner',
    (tester) async {
      final h = PairHarness(configuration: ownerConfiguration());
      addTearDown(h.db.close);
      await h.initialize();
      final acceptedConfiguration =
          h.operation.configuration!.stableSerialization;
      await mergePairOwner(h);
      await tester.pumpWidget(
        MaterialApp(
          home: PairMatchingExperienceHost.recover(
            runtime: ownerRuntime(h),
            operation: h.operation,
            onExit: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('pair-tile:prompt:synthetic-0')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('pair-tile:target:synthetic-0')),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(minutes: 10, seconds: 1));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      final end = find.byKey(const ValueKey('pair-end-at-limit'));
      expect(end, findsOneWidget);
      await tester.tap(end);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('pair-incomplete-ended')),
        findsOneWidget,
      );
      expect(await h.real.getActiveSession(ownerId: h.owner), isNull);
      final result = await h.real.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(result.snapshot!.terminal, isNull);
      expect(result.snapshot!.evidenceIds, hasLength(1));
      expect(
        PairMatchingStartOperation.fromStableSerialization(
          result.snapshot!.startOperation,
        ).configuration!.stableSerialization,
        acceptedConfiguration,
      );
      expect(
        (await h.db.select(h.db.answerAttempts).get()).single.ownerId,
        h.owner,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final boundary in [
    'before-answer',
    'answer-insert',
    'checkpoint-insert',
  ]) {
    test(
      'merged runtime owner race at $boundary fails before unauthorized durable effects',
      () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        await mergePairOwner(h);
        final c = await h.restore();
        final beforeEvents = await h.db.select(h.db.eventsV2).get();
        if (boundary == 'before-answer') {
          h.repository.beforeAnswer = () => h.db.customStatement(
            'UPDATE local_owners SET is_active=0 WHERE id=?',
            [h.owner],
          );
        } else if (boundary == 'answer-insert') {
          await h.db.customStatement(
            "CREATE TRIGGER pm8_actor_race AFTER INSERT ON answer_attempts BEGIN UPDATE local_owners SET is_active=0 WHERE id=NEW.owner_id; END",
          );
        } else {
          await h.db.customStatement(
            "CREATE TRIGGER pm8_actor_race AFTER INSERT ON events_v2 WHEN NEW.event_type='LearningActivityCheckpoint' BEGIN UPDATE local_owners SET is_active=0 WHERE id=NEW.owner_id; END",
          );
        }
        await planTap(h, c, 'synthetic-0', PairTileSide.prompt);
        await expectLater(
          planTap(h, c, 'synthetic-0', PairTileSide.target),
          throwsStateError,
        );
        expect(await h.db.select(h.db.answerAttempts).get(), isEmpty);
        final rows = await h.db.select(h.db.eventsV2).get();
        expect(
          rows.length,
          beforeEvents.length + (boundary == 'checkpoint-insert' ? 0 : 1),
        );
        final current = await (h.db.select(
          h.db.localOwners,
        )..where((r) => r.id.equals(h.owner))).getSingle();
        expect(current.isActive, boundary != 'before-answer');
      },
    );
  }

  test(
    'long historical frozen actor survives real merge into short runtime owner and fractional retry',
    () async {
      final sourceOwner = '\u0001' * 256;
      final plan = PairMatchingPlanV1(
        ownerId: sourceOwner,
        orderedLexicalItems: List.generate(4, lexical.fixture),
        direction: PairDirection.enToTh,
        density: PairDensity.compact4,
        shuffleSeed: 42,
        timerPreset: PairTimerPreset.off,
        allowlistVersion: 'synthetic-v1',
        learningSessionId: pairSessionId(sourceOwner, 'synthetic-operation'),
        entryKind: PairSourceSurface.learn,
        sourceSnapshotId: 'synthetic-snapshot',
        createdAtUtc: DateTime.utc(2026, 9, 5),
      );
      final h = PairHarness(pinnedPlan: plan);
      addTearDown(h.db.close);
      await h.initialize();
      final fractional = DateTime.utc(2026, 9, 5, 0, 1, 0, 123, 456);
      final c = await PairMatchingSessionCoordinator.restore(
        operation: h.operation,
        learning: h.learning,
        evidence: CurrentActivityEvidenceAdapter(
          learning: h.learning,
          nowUtc: () => fractional,
        ),
        activeOwnerId: () => h.owner,
      );
      await planTap(h, c, 'synthetic-0', PairTileSide.prompt);
      h.repository.answerFault = true;
      await expectLater(
        planTap(h, c, 'synthetic-0', PairTileSide.target),
        throwsStateError,
      );
      final frozen = (await h.real.read(
        ownerId: h.owner,
        sessionId: plan.learningSessionId,
      )).snapshot!.frozenEvidence!;
      await mergePairOwner(h, target: 'r');
      final restored = await h.restore();
      await restored.retryPending();
      final accepted = await h.real.read(
        ownerId: h.owner,
        sessionId: plan.learningSessionId,
      );
      expect(accepted.reservations[frozen['sourceEvidenceId']], frozen);
      expect(
        accepted.reservations[frozen['sourceEvidenceId']]!['occurredAtUtc'],
        fractional.toIso8601String(),
      );
      expect(
        (await h.db.select(h.db.answerAttempts).get()).single.ownerId,
        'r',
      );
      final secondRestore = await h.restore();
      for (final item in plan.orderedLexicalItems.skip(1)) {
        await planTap(h, secondRestore, item.wordId, PairTileSide.prompt);
        await planTap(h, secondRestore, item.wordId, PairTileSide.target);
      }
      await secondRestore.finish();
      expect(secondRestore.completedSummary!.ownerId, 'r');
    },
  );
  test(
    'actual merge restores runtime account with immutable plan and new actor',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final stale = await h.restore();
      final startBytes = h.operation.stableSerialization;
      await mergePairOwner(h);
      final c = await h.restore();
      expect(c.operation.stableSerialization, startBytes);
      expect(c.state.plan.ownerId, 'synthetic-owner');
      await expectLater(
        planTap(h, stale, 'synthetic-0', PairTileSide.prompt),
        throwsStateError,
      );
      await planTap(h, c, 'synthetic-0', PairTileSide.prompt);
      await planTap(h, c, 'synthetic-0', PairTileSide.target);
      final attempts = await h.db.select(h.db.answerAttempts).get();
      expect(attempts.single.ownerId, h.owner);
      final source = await h.real.events.readBySourceEvidenceId(
        attempts.single.id,
      );
      expect(source!.actorIdentity, h.owner);
      final original = await h.db
          .customSelect(
            "SELECT * FROM events_v2 WHERE event_type = 'LearningActivityCheckpoint' ORDER BY occurred_at_utc, event_id",
          )
          .get();
      expect(
        original.any(
          (row) =>
              jsonDecode(row.data['payload_json'] as String)['revision'] == 1 &&
              row.data['actor_identity'] == 'synthetic-owner',
        ),
        isTrue,
      );
    },
  );

  for (final fault in ['before', 'after', 'acknowledged']) {
    test(
      'real owner upgrade preserves terminal $fault receipts and elapsed',
      () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize(measured: true);
        final c = await h.restore();
        for (final item in h.operation.plan.orderedLexicalItems) {
          await planTap(h, c, item.wordId, PairTileSide.prompt);
          await planTap(h, c, item.wordId, PairTileSide.target);
        }
        h.repository.closeFault = fault != 'acknowledged';
        h.repository.afterWrite = fault == 'after';
        if (fault == 'acknowledged') {
          await c.finish();
        } else {
          await expectLater(c.finish(), throwsStateError);
        }
        final before = await h.real.loadExactActivityRecovery(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
          activityType: 'matching',
        );
        final previous = PairMatchingCheckpointCodec.decode(
          before!.checkpoint!.state,
        );
        await mergePairOwner(h, collision: true);
        final r = await h.restore();
        await r.finish();
        final after = await h.real.loadExactActivityRecovery(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
          activityType: 'matching',
        );
        final current = PairMatchingCheckpointCodec.decode(
          after!.checkpoint!.state,
        );
        expect(current.terminal!.atUtc, previous.terminal!.atUtc);
        expect(
          current.timer!.interactiveElapsedMs,
          previous.timer!.interactiveElapsedMs,
        );
        expect(current.engine.toJson(), previous.engine.toJson());
        expect(current.evidenceIds, previous.evidenceIds);
        expect(after.session.state, 'completed');
        final receipts = (await h.db.select(h.db.eventsV2).get())
            .map((e) => e.toJson())
            .toList();
        await (await h.restore()).finish();
        expect(
          (await h.db.select(h.db.eventsV2).get())
              .map((e) => e.toJson())
              .toList(),
          receipts,
        );
      },
    );
  }

  test(
    'moved Pair archive and curated export are scoped and erasure cannot revive retired lineage',
    () async {
      final h = PairHarness(configuration: ownerConfiguration());
      addTearDown(h.db.close);
      await h.initialize();
      await h.db
          .into(h.db.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'unrelated-owner',
              createdAtUtcMs: 1,
              isActive: const Value(false),
            ),
          );
      final unrelated =
          (await h.db
                  .customSelect(
                    "SELECT * FROM local_owners WHERE id='unrelated-owner'",
                  )
                  .getSingle())
              .data;
      final c = await h.restore();
      await planTap(h, c, 'synthetic-0', PairTileSide.prompt);
      await planTap(h, c, 'synthetic-0', PairTileSide.target);
      await mergePairOwner(h, collision: true);
      final export = await DriftExportReader(
        h.db,
      ).loadActiveSnapshot(vocabulary: true, attempts: true, reading: true);
      expect(export.attempts.single.wordId, 'synthetic-0');
      expect(
        export.attempts.single.spelling,
        h.operation.plan.orderedLexicalItems.first.spelling,
      );
      final artifact = await OwnerLifecycleArchiveExporter(
        database: h.db,
        nowUtc: () => DateTime.utc(2026, 9, 6),
      ).prepareActive();
      final bytes = utf8.decode(artifact.bytes);
      final tables =
          ((jsonDecode(bytes) as Map)['content'] as Map)['tables'] as List;
      final sessions =
          (tables.cast<Map>().singleWhere(
                    (row) => row['alias'] == 'learningSessions',
                  )['records']
                  as List)
              .cast<Map>();
      expect(
        sessions.singleWhere(
          (row) => row['activityType'] == 'matching',
        )['correctCount'],
        1,
      );
      expect(
        sessions.singleWhere(
          (row) => row.containsKey('recordCount'),
        )['recordCount'],
        1,
      );
      expect(bytes, isNot(contains('unrelated-owner')));
      expect(bytes, isNot(contains('mergedInto:')));
      expect(bytes, isNot(contains('payload_json')));
      final secrets = <String>[];
      await LocalDataDeletion(
        h.db,
        deleteOwnerSecrets: (owner) async => secrets.add(owner),
      ).eraseAll(ownerId: h.owner);
      expect(secrets, [h.owner]);
      expect(await h.db.select(h.db.learningSessions).get(), isEmpty);
      expect(await h.db.select(h.db.answerAttempts).get(), isEmpty);
      expect(await h.db.select(h.db.vocabularyWords).get(), isEmpty);
      expect(
        (await h.db
                .customSelect(
                  "SELECT * FROM local_owners WHERE id='unrelated-owner'",
                )
                .getSingle())
            .data,
        unrelated,
      );
      expect(
        (await h.db
                .customSelect(
                  'SELECT * FROM local_owners WHERE id=?',
                  variables: [Variable(h.operation.plan.ownerId)],
                )
                .getSingle())
            .data['account_state'],
        'mergedInto:${h.owner}',
      );
      await expectLater(h.restore(), throwsStateError);
    },
  );

  test(
    'fresh replay after canonical noncollision merge uses projected owner configuration',
    () async {
      final h = PairHarness(configuration: ownerConfiguration());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      for (final item in h.operation.plan.orderedLexicalItems) {
        await planTap(h, c, item.wordId, PairTileSide.prompt);
        await planTap(h, c, item.wordId, PairTileSide.target);
      }
      await c.finish();
      final original = h.operation;
      await mergePairOwner(h);
      final replay = ownerReplay(h);
      final operation = await replay.prepare(
        ownerId: h.owner,
        sourceSessionId: original.plan.learningSessionId,
        launchOperationId: 'pm8-new-replay',
        createdAtUtc: DateTime.utc(2026, 9, 6),
        appVersion: 'synthetic',
        buildId: 'synthetic',
      );
      expect(operation.plan.ownerId, h.owner);
      expect(operation.configuration!.ownerId, h.owner);
      expect(operation.configuration!.timing, original.configuration!.timing);
      await replay.start.start(operation);
      expect(await h.db.select(h.db.learningSessions).get(), hasLength(2));
    },
  );

  for (final after in [false, true]) {
    test(
      'accepted practice replay pending after=$after rehomes exact actor with no learning rewards',
      () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        final source = h.operation;
        final normal = await h.restore();
        for (final item in source.plan.orderedLexicalItems) {
          await planTap(h, normal, item.wordId, PairTileSide.prompt);
          await planTap(h, normal, item.wordId, PairTileSide.target);
        }
        await normal.finish();
        final replay = ownerReplay(h);
        h.operation = await replay.prepare(
          ownerId: h.owner,
          sourceSessionId: source.plan.learningSessionId,
          launchOperationId: 'pm8-accepted-replay',
          createdAtUtc: h.learning.nowUtc(),
          appVersion: 'synthetic',
          buildId: 'synthetic',
        );
        await replay.start.start(h.operation);
        final c = await h.restore();
        await planTap(h, c, 'synthetic-0', PairTileSide.prompt);
        h.repository.answerFault = true;
        h.repository.afterWrite = after;
        await expectLater(
          planTap(h, c, 'synthetic-0', PairTileSide.target),
          throwsStateError,
        );
        await mergePairOwner(h, collision: true);
        final tables = [
          'srs_states',
          'points_ledger_entries',
          'learning_time_segments',
        ];
        Future<Map<String, Object?>> sinks() async => {
          for (final table in tables)
            table:
                (await h.db
                        .customSelect('SELECT * FROM $table ORDER BY 1')
                        .get())
                    .map((r) => r.data)
                    .toList(),
        };
        final before = await sinks();
        final restored = await h.restore();
        await restored.retryPending();
        for (final item in h.operation.plan.orderedLexicalItems.skip(1)) {
          await planTap(h, restored, item.wordId, PairTileSide.prompt);
          await planTap(h, restored, item.wordId, PairTileSide.target);
        }
        await restored.finish();
        expect(await sinks(), before);
        final answers = (await h.db.select(h.db.answerAttempts).get())
            .where((a) => a.sessionId == h.operation.plan.learningSessionId)
            .toList();
        expect(answers, hasLength(4));
        expect(
          answers.every(
            (a) => a.ownerId == h.owner && a.evidenceClass == 'recreational',
          ),
          isTrue,
        );
        expect(
          (await h.real.events.readBySourceEvidenceId(
            answers.first.id,
          ))!.actorIdentity,
          source.plan.ownerId,
        );
        expect(
          (await h.real.events.readBySourceEvidenceId(
            answers.last.id,
          ))!.actorIdentity,
          h.owner,
        );
        final unavailable = await ownerReplay(h).prepare(
          ownerId: h.owner,
          sourceSessionId: h.operation.plan.learningSessionId,
          launchOperationId: 'pm8-deleted-replay',
          createdAtUtc: DateTime.utc(2026, 9, 6),
          appVersion: 'synthetic',
          buildId: 'synthetic',
        );
        await expectLater(
          ownerReplay(h).start.start(unavailable),
          throwsStateError,
        );
        expect(await h.db.select(h.db.learningSessions).get(), hasLength(2));
      },
    );
  }

  for (final measured in [false, true]) {
    for (final fault in [
      'answer-before',
      'answer-after',
      'clear-before',
      'clear-after',
    ]) {
      test(
        'real collision $fault survives file reopen measured=$measured with exact frozen actor',
        () async {
          final directory = await Directory.systemTemp.createTemp(
            'pm8-owner-reopen-',
          );
          addTearDown(() => directory.delete(recursive: true));
          final file = File('${directory.path}/synthetic.sqlite');
          final h = PairHarness(executor: NativeDatabase(file));
          await h.initialize(measured: measured);
          final c = await h.restore();
          await planTap(h, c, 'synthetic-0', PairTileSide.prompt);
          h.repository.afterWrite = fault.endsWith('after');
          if (fault.startsWith('answer')) {
            h.repository.answerFault = true;
          } else {
            h.repository.checkpointFault = c.checkpointRevision + 2;
          }
          await expectLater(
            planTap(h, c, 'synthetic-0', PairTileSide.target),
            throwsStateError,
          );
          final before = await h.real.loadExactActivityRecovery(
            ownerId: h.owner,
            sessionId: h.operation.plan.learningSessionId,
            activityType: 'matching',
          );
          final frozen = PairMatchingCheckpointCodec.decode(
            before!.checkpoint!.state,
          ).frozenEvidence;
          final reservedId = h.repository.commands.single.id;
          await mergePairOwner(h, collision: true);
          c.dispose();
          await h.db.close();
          final db = AppDatabase(NativeDatabase(file));
          addTearDown(db.close);
          final real = DriftLearningRepository(db);
          var captures = 0;
          final learning = LearningUseCases(
            owners: DriftLocalOwnerRepository(
              db,
              generateId: () => 'forbidden-guest',
              nowUtc: h.learning.nowUtc,
            ),
            repository: real,
            generateId: () => 'pm8-new-${++captures}',
            nowUtc: h.learning.nowUtc,
            buildInfo: h.learning.buildInfo,
          );
          final restored = await PairMatchingSessionCoordinator.restore(
            operation: h.operation,
            learning: learning,
            evidence: CurrentActivityEvidenceAdapter(learning: learning),
            activeOwnerId: () => h.owner,
          );
          if (restored.state.pending != null) await restored.retryPending();
          expect(captures, 0);
          expect(restored.state.matchedWordIds, contains('synthetic-0'));
          final attempt = (await db.select(db.answerAttempts).get()).single;
          expect(attempt.id, reservedId);
          expect(attempt.ownerId, h.owner);
          final source = await real.events.readBySourceEvidenceId(reservedId);
          expect(source!.actorIdentity, h.operation.plan.ownerId);
          if (frozen != null) {
            final accepted = FrozenPendingCurrentActivityEvidence.fromJson(
              frozen,
            );
            expect(source.occurredAtUtc, accepted.occurredAtUtc);
            expect(
              jsonEncode(
                LearningEventContext.fromEvidenceEnvelope(
                  envelope: source,
                  evidenceContext: accepted.evidenceContext,
                ).toJson(),
              ),
              jsonEncode(accepted.eventContext.toJson()),
            );
          }
          for (final item in h.operation.plan.orderedLexicalItems.skip(1)) {
            await planTap(h, restored, item.wordId, PairTileSide.prompt);
            await planTap(h, restored, item.wordId, PairTileSide.target);
          }
          await restored.finish();
          final finalRecovery = await real.loadExactActivityRecovery(
            ownerId: h.owner,
            sessionId: h.operation.plan.learningSessionId,
            activityType: 'matching',
          );
          final snapshot = PairMatchingCheckpointCodec.decode(
            finalRecovery!.checkpoint!.state,
          );
          expect(snapshot.terminal!.acknowledged, isTrue);
          expect(
            snapshot.timer!.interactiveElapsedMs,
            measured ? isNotNull : isNull,
          );
          expect((await db.select(db.answerAttempts).get()), hasLength(4));
          expect(captures, 3);
          final terminalRows = await db
              .customSelect('SELECT * FROM events_v2 ORDER BY event_id')
              .get();
          final reloaded = await PairMatchingSessionCoordinator.restore(
            operation: h.operation,
            learning: learning,
            evidence: CurrentActivityEvidenceAdapter(learning: learning),
            activeOwnerId: () => h.owner,
          );
          await reloaded.finish();
          expect((await db.select(db.answerAttempts).get()), hasLength(4));
          expect(
            (await db
                    .customSelect('SELECT * FROM events_v2 ORDER BY event_id')
                    .get())
                .map((r) => r.data)
                .toList(),
            terminalRows.map((r) => r.data).toList(),
          );
        },
      );
    }
  }
}
