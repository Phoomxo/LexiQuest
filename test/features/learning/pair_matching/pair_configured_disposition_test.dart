import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_unavailable_session.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_matching_experience_host.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/presentation/pair_board_view.dart';

import 'pair_matching_evidence_contract_test.dart'
    show PairHarness, PairFaultRepository;
import '../../../support/pair_measurement_fixture.dart';

SessionConfiguration _configuration() => SessionConfiguration.validated(
  schemaVersion: 1,
  policyVersion: sessionConfigurationPolicyVersion,
  ownerId: 'synthetic-owner',
  mode: LessonMode.matching,
  itemCount: 4,
  direction: SessionDirection.forward,
  difficulty: SessionDifficulty.standard,
  hintBudget: 0,
  timing: const SessionTiming.timed(Duration(minutes: 10)),
  packIdentity: null,
  protocolId: 'synthetic-research',
  protocolVersion: '1',
  protocolLimitsIdentity: 'synthetic-research-pins',
);

void main() {
  for (final changeOwner in [false, true]) {
    test(
      'in-flight disposition ${changeOwner ? "rejects owner drift" : "drains on local dispose"}',
      () async {
        final f = PairMeasurementFixture();
        addTearDown(f.database.close);
        await f.initialize();
        final operation = await _admitConfigured(f);
        final entered = Completer<void>(), release = Completer<void>();
        final repository =
            _DispositionFaultRepository(
                f,
                afterCommit: false,
                failCompletion: false,
              )
              ..fault = false
              ..afterInspect = () async {
                if (!entered.isCompleted) {
                  entered.complete();
                  await release.future;
                }
              };
        final learning = LearningUseCases(
          owners: f.learning.owners,
          repository: repository,
          generateId: () => throw StateError('Disposition cannot capture'),
          nowUtc: f.learning.nowUtc,
          buildInfo: f.learning.buildInfo,
        );
        var owner = PairMeasurementFixture.owner;
        final service = PairMatchingUnavailableSession(
          operation: operation,
          learning: learning,
          currentActivityEvidence: _researchEvidence(f, learning),
          requireOwner: () async => owner,
        );
        final pending = service.resolve(abandonIncomplete: true);
        final rejection = changeOwner
            ? expectLater(pending, throwsStateError)
            : null;
        await entered.future;
        if (changeOwner) {
          owner = 'synthetic-other-owner';
          await f.database.customStatement(
            'UPDATE local_owners SET is_active=0',
          );
        } else {
          service.dispose();
        }
        release.complete();
        if (changeOwner) {
          await rejection;
          expect(
            (await f.database.select(f.database.learningSessions).get())
                .single
                .state,
            'active',
          );
        } else {
          expect((await pending).kind, PairAcceptedDispositionKind.stopped);
          await expectLater(
            service.resolve(abandonIncomplete: true),
            throwsStateError,
          );
        }
        expect(
          await f.database.select(f.database.answerAttempts).get(),
          isEmpty,
        );
        service.dispose();
      },
    );
  }
  test(
    'disposition transaction rejects answer committed after inspection then retains it on exact retry',
    () async {
      final f = PairMeasurementFixture();
      addTearDown(f.database.close);
      await f.initialize();
      final operation = await _admitConfigured(f);
      final c = await _researchCoordinator(f, operation);
      await _answer(c, 'synthetic-0');
      final repository = _DispositionFaultRepository(
        f,
        afterCommit: false,
        failCompletion: false,
      )..fault = false;
      repository.beforeAbandon = () async {
        repository.beforeAbandon = null;
        await _answer(c, 'synthetic-1');
      };
      final learning = LearningUseCases(
        owners: f.learning.owners,
        repository: repository,
        generateId: () => throw StateError('Disposition cannot capture'),
        nowUtc: f.learning.nowUtc,
        buildInfo: f.learning.buildInfo,
      );
      final service = PairMatchingUnavailableSession(
        operation: operation,
        learning: learning,
        currentActivityEvidence: _researchEvidence(f, learning),
        requireOwner: f.runtime.requireOwner,
      );
      final cutoff = f.now;
      await expectLater(
        service.resolve(abandonIncomplete: true),
        throwsStateError,
      );
      expect(
        (await f.real.getActiveSession(
          ownerId: PairMeasurementFixture.owner,
        ))!.correctCount,
        2,
      );
      f.now = f.now.add(const Duration(minutes: 1));
      final stopped = await service.resolve(abandonIncomplete: true);
      expect(stopped.recovery.attempts, hasLength(2));
      expect(stopped.recovery.session.endedAtUtc, cutoff);
      expect(stopped.kind, PairAcceptedDispositionKind.stopped);
      c.dispose();
      service.dispose();
    },
  );
  test(
    'disposition rejects inconsistent canonical answer counts before terminal mutation',
    () async {
      final h = PairHarness(configuration: _configuration());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      c.dispose();
      await h.db.customStatement(
        'UPDATE learning_sessions SET correct_count=0',
      );
      await expectLater(
        h.real.inspectPairDisposition(
          ownerId: h.owner,
          startOperation: h.operation.stableSerialization,
        ),
        throwsStateError,
      );
      expect(
        (await h.db.select(h.db.learningSessions).get()).single.state,
        'active',
      );
    },
  );

  test(
    'disposition rejects an abandoned row with an authenticated committed pending answer',
    () async {
      final f = PairMeasurementFixture();
      addTearDown(f.database.close);
      await f.initialize();
      final operation = await _admitConfigured(f);
      final faulty = _WithdrawalAnswerRepository(f, committed: true);
      final learning = LearningUseCases(
        owners: f.learning.owners,
        repository: faulty,
        generateId: f.learning.generateId,
        nowUtc: f.learning.nowUtc,
        buildInfo: f.learning.buildInfo,
        eventContextProvider: f.learning.eventContextProvider,
      );
      final c = await _researchCoordinator(f, operation, learning: learning);
      await expectLater(_answer(c, 'synthetic-0'), throwsStateError);
      c.dispose();
      await f.database.customStatement(
        "UPDATE learning_sessions SET state='abandoned',ended_at_utc_ms=?",
        [f.now.millisecondsSinceEpoch],
      );
      await expectLater(
        f.real.inspectPairDisposition(
          ownerId: PairMeasurementFixture.owner,
          startOperation: operation.stableSerialization,
        ),
        throwsStateError,
      );
    },
  );
  for (final afterCommit in [false, true]) {
    for (final complete in [false, true]) {
      test(
        'unavailable ${complete ? "completion" : "abandonment"} retains first cutoff afterCommit=$afterCommit',
        () async {
          final f = PairMeasurementFixture();
          addTearDown(f.database.close);
          await f.initialize();
          final operation = await _admitConfigured(f);
          final original = await _researchCoordinator(f, operation);
          for (var i = 0; i < (complete ? 4 : 1); i++) {
            await _answer(original, 'synthetic-$i');
          }
          original.dispose();
          await f.research.withdraw(PairMeasurementFixture.owner);
          final repository = _DispositionFaultRepository(
            f,
            afterCommit: afterCommit,
            failCompletion: complete,
          );
          final learning = LearningUseCases(
            owners: f.learning.owners,
            repository: repository,
            generateId: () =>
                throw StateError('No new capture during disposition'),
            nowUtc: f.learning.nowUtc,
            buildInfo: f.learning.buildInfo,
          );
          final service = PairMatchingUnavailableSession(
            operation: operation,
            learning: learning,
            currentActivityEvidence: _researchEvidence(f, learning),
            requireOwner: f.runtime.requireOwner,
          );
          final firstCutoff = f.now;
          await expectLater(
            service.resolve(abandonIncomplete: true),
            throwsStateError,
          );
          f.now = f.now.add(const Duration(minutes: 1));
          final retried = await service.resolve(abandonIncomplete: true);
          expect(retried.recovery.session.endedAtUtc, firstCutoff);
          expect(repository.cutoffs, isNotEmpty);
          expect(repository.cutoffs.every((at) => at == firstCutoff), true);
          expect(
            retried.recovery.session.state,
            complete ? 'completed' : 'abandoned',
          );
          expect(retried.recovery.attempts.length, complete ? 4 : 1);
          if (complete) await service.markPresented();
          service.dispose();
        },
      );
    }
  }

  testWidgets(
    'temporary protocol unavailability keeps exact saved-session retry',
    (tester) async {
      final f = PairMeasurementFixture();
      addTearDown(f.database.close);
      late PairMatchingStartOperation operation;
      await tester.runAsync(() async {
        await f.initialize();
        operation = await _admitConfigured(f);
      });
      final provider = _TemporaryProtocols(f.protocols);
      final source = f.runtime;
      final runtime = PairMatchingExperienceRuntime(
        database: source.database,
        learning: source.learning,
        currentActivityEvidence: source.currentActivityEvidence,
        registry: source.registry,
        createController: source.createController,
        composer: source.composer,
        start: source.start,
        protocols: provider,
        canStart: source.canStart,
        monotonicMicros: source.monotonicMicros,
        features: source.features,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PairMatchingExperienceHost.recover(
            runtime: runtime,
            operation: operation,
            onExit: () {},
          ),
        ),
      );
      await _pump(tester);
      expect(find.byType(PairBoardView), findsNothing);
      final retry = find.byKey(const ValueKey('pair-retry-attachment'));
      expect(retry, findsOneWidget);
      provider.unavailable = false;
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await _pump(tester);
      expect(find.byType(PairBoardView), findsOneWidget);
      expect(
        tester
            .widget<PairBoardView>(find.byType(PairBoardView))
            .model
            .state
            .plan
            .learningSessionId,
        operation.plan.learningSessionId,
      );
      expect(
        await tester.runAsync(
          () => f.database.select(f.database.learningSessions).get(),
        ),
        hasLength(1),
      );
      expect(
        await tester.runAsync(
          () => f.database.select(f.database.answerAttempts).get(),
        ),
        isEmpty,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester);
    },
  );
  for (final stage in [
    'complete-acknowledged',
    'complete-active',
    'pending-uncommitted',
    'pending-committed',
    'pending-last',
  ]) {
    testWidgets(
      'actual withdrawn host recovers $stage without interaction or new capture',
      (tester) async {
        final f = PairMeasurementFixture();
        addTearDown(f.database.close);
        late PairMatchingStartOperation operation;
        late int capturedIds;
        late List<Map<String, Object?>> receipts;
        await tester.runAsync(() async {
          await f.initialize();
          operation = await _admitConfigured(f);
          final first = await _researchCoordinator(f, operation);
          final isComplete = stage.startsWith('complete');
          final count = isComplete
              ? 4
              : stage == 'pending-last'
              ? 3
              : 0;
          for (var i = 0; i < count; i++) {
            await _answer(first, 'synthetic-$i');
          }
          if (stage == 'complete-acknowledged') {
            await first.finish();
            await first.markSummaryPresented();
          }
          first.dispose();
          if (isComplete) {
            await f.research.withdraw(PairMeasurementFixture.owner);
          } else {
            final faulty = _WithdrawalAnswerRepository(
              f,
              committed: stage != 'pending-uncommitted',
            );
            final learning = LearningUseCases(
              owners: f.learning.owners,
              repository: faulty,
              generateId: f.learning.generateId,
              nowUtc: f.learning.nowUtc,
              buildInfo: f.learning.buildInfo,
              eventContextProvider: f.learning.eventContextProvider,
            );
            final c = await _researchCoordinator(
              f,
              operation,
              learning: learning,
            );
            await expectLater(
              _answer(
                c,
                stage == 'pending-last' ? 'synthetic-3' : 'synthetic-0',
              ),
              throwsStateError,
            );
            c.dispose();
          }
          capturedIds = f.generatedIds;
          receipts = await _answerReceipts(f);
        });
        final complete =
            stage.startsWith('complete') || stage == 'pending-last';
        Future<void> mount() => tester.pumpWidget(
          MaterialApp(
            home: PairMatchingExperienceHost.recover(
              runtime: f.runtime,
              operation: operation,
              onExit: () {},
            ),
          ),
        );
        await mount();
        await _pump(tester);
        if (complete) {
          expect(find.byKey(const ValueKey('pair-result')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('pair-dispose-unavailable')),
            findsNothing,
          );
        } else {
          final end = find.byKey(const ValueKey('pair-dispose-unavailable'));
          expect(end, findsOneWidget);
          await tester.ensureVisible(end);
          await tester.tap(end);
          await _pump(tester);
          expect(
            find.byKey(const ValueKey('pair-incomplete-ended')),
            findsOneWidget,
          );
          if (stage == 'pending-uncommitted') {
            expect(
              find.text(
                'The pending answer was not recorded and will not be submitted later.',
              ),
              findsOneWidget,
            );
          }
        }
        expect(f.generatedIds, capturedIds);
        await tester.runAsync(() async {
          expect(await _answerReceipts(f), receipts);
          final result = await f.real.inspectPairDisposition(
            ownerId: PairMeasurementFixture.owner,
            startOperation: operation.stableSerialization,
          );
          expect(
            result.recovery.session.state,
            complete ? 'completed' : 'abandoned',
          );
          expect(result.recovery.checkpoint!.terminalAcknowledged, complete);
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(tester);
        await mount();
        await _pump(tester);
        expect(
          find.byKey(
            ValueKey(complete ? 'pair-result' : 'pair-incomplete-ended'),
          ),
          findsOneWidget,
        );
        if (stage == 'pending-uncommitted') {
          expect(
            find.text(
              'The pending answer was not recorded and will not be submitted later.',
            ),
            findsOneWidget,
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await _pump(tester);
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
  for (final committed in [false, true]) {
    test(
      'withdrawal classifies frozen pending committed=$committed without first-write retry',
      () async {
        final f = PairMeasurementFixture();
        addTearDown(f.database.close);
        await f.initialize();
        final operation = await _admitConfigured(f);
        final faulty = _WithdrawalAnswerRepository(f, committed: committed);
        final learning = LearningUseCases(
          owners: f.learning.owners,
          repository: faulty,
          generateId: f.learning.generateId,
          nowUtc: f.learning.nowUtc,
          buildInfo: f.learning.buildInfo,
          eventContextProvider: f.learning.eventContextProvider,
        );
        final c = await _researchCoordinator(f, operation, learning: learning);
        await expectLater(_answer(c, 'synthetic-0'), throwsStateError);
        c.dispose();
        final loaded = await f.real.inspectPairDisposition(
          ownerId: PairMeasurementFixture.owner,
          startOperation: operation.stableSerialization,
        );
        expect(
          loaded.kind,
          committed
              ? PairAcceptedDispositionKind.pendingCommitted
              : PairAcceptedDispositionKind.pendingUncommitted,
        );
        final frozen = jsonEncode(loaded.recovery.checkpoint!.state);
        final evidenceBefore = await _answerReceipts(f);
        expect(loaded.recovery.attempts.length, committed ? 1 : 0);
        if (committed) {
          expect(
            loaded.recovery.attempts.single.evidenceContext.rolloutMode,
            EvidencePolicyRolloutMode.enforced,
          );
        }
        final service = PairMatchingUnavailableSession(
          operation: operation,
          learning: f.learning,
          currentActivityEvidence: f.currentActivityEvidence,
          requireOwner: f.runtime.requireOwner,
        );
        final result = await service.resolve(abandonIncomplete: true);
        expect(result.kind, PairAcceptedDispositionKind.stopped);
        expect(result.recovery.attempts.length, committed ? 1 : 0);
        expect(result.recovery.checkpoint!.terminalAcknowledged, false);
        expect(await _answerReceipts(f), evidenceBefore);
        if (!committed) {
          expect(jsonEncode(result.recovery.checkpoint!.state), frozen);
          await expectLater(
            f.real.recordAnswer(faulty.commands.single),
            throwsStateError,
          );
          await expectLater(
            f.real.appendActivityCheckpoint(
              ownerId: PairMeasurementFixture.owner,
              checkpoint: result.recovery.checkpoint!,
            ),
            throwsStateError,
          );
        }
        service.dispose();
      },
    );
  }

  test(
    'withdrawn committed last answer finishes with exact three receipts and no new capture',
    () async {
      final f = PairMeasurementFixture();
      addTearDown(f.database.close);
      await f.initialize();
      final operation = await _admitConfigured(f);
      final before = await _researchCoordinator(f, operation);
      for (var i = 0; i < 3; i++) {
        await _answer(before, 'synthetic-$i');
      }
      before.dispose();
      final faulty = _WithdrawalAnswerRepository(f, committed: true);
      final learning = LearningUseCases(
        owners: f.learning.owners,
        repository: faulty,
        generateId: f.learning.generateId,
        nowUtc: f.learning.nowUtc,
        buildInfo: f.learning.buildInfo,
        eventContextProvider: f.learning.eventContextProvider,
      );
      final c = await _researchCoordinator(f, operation, learning: learning);
      await expectLater(_answer(c, 'synthetic-3'), throwsStateError);
      c.dispose();
      final receipts = await _answerReceipts(f);
      final service = PairMatchingUnavailableSession(
        operation: operation,
        learning: f.learning,
        currentActivityEvidence: f.currentActivityEvidence,
        requireOwner: f.runtime.requireOwner,
      );
      final resolved = await service.resolve(abandonIncomplete: true);
      expect(resolved.kind, PairAcceptedDispositionKind.complete);
      expect(resolved.recovery.session.state, 'completed');
      expect(resolved.recovery.attempts, hasLength(4));
      await service.markPresented();
      final repeated = await service.resolve(abandonIncomplete: true);
      expect(
        repeated.recovery.session.endedAtUtc,
        resolved.recovery.session.endedAtUtc,
      );
      expect(await _answerReceipts(f), receipts);
      final terminalRows = (await f.database.select(f.database.eventsV2).get())
          .where((r) => r.eventType == 'LearningActivityCheckpoint')
          .map((r) => jsonDecode(r.payloadJson) as Map)
          .where((p) => p['terminalAtUtc'] != null)
          .toList();
      expect(terminalRows, hasLength(3));
      service.dispose();
    },
  );

  test(
    'revoked pending with orphan decision is corrupt rather than uncommitted',
    () async {
      final f = PairMeasurementFixture();
      addTearDown(f.database.close);
      await f.initialize();
      final operation = await _admitConfigured(f);
      final faulty = _WithdrawalAnswerRepository(f, committed: true);
      final learning = LearningUseCases(
        owners: f.learning.owners,
        repository: faulty,
        generateId: f.learning.generateId,
        nowUtc: f.learning.nowUtc,
        buildInfo: f.learning.buildInfo,
        eventContextProvider: f.learning.eventContextProvider,
      );
      final c = await _researchCoordinator(f, operation, learning: learning);
      await expectLater(_answer(c, 'synthetic-0'), throwsStateError);
      c.dispose();
      await f.database.customStatement('DELETE FROM answer_attempts');
      final before = await _answerReceipts(f);
      final service = PairMatchingUnavailableSession(
        operation: operation,
        learning: f.learning,
        currentActivityEvidence: f.currentActivityEvidence,
        requireOwner: f.runtime.requireOwner,
      );
      await expectLater(
        service.resolve(abandonIncomplete: true),
        throwsStateError,
      );
      expect(await _answerReceipts(f), before);
      expect(
        (await f.real.getActiveSession(
          ownerId: PairMeasurementFixture.owner,
        ))!.state,
        'active',
      );
      service.dispose();
    },
  );
  testWidgets(
    'withdrawn configured Pair offers explicit canonical disposition then baseline start',
    (tester) async {
      final f = PairMeasurementFixture();
      addTearDown(f.database.close);
      late PairMatchingStartOperation operation;
      await tester.runAsync(() async {
        await f.initialize();
        operation = await _admitConfigured(f);
        final c = await _researchCoordinator(f, operation);
        await _answer(c, 'synthetic-0');
        c.dispose();
        await f.research.withdraw(PairMeasurementFixture.owner);
        await expectLater(
          f.runtime.revalidate(operation.configuration!),
          throwsA(isA<SessionConfigurationResetRequired>()),
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: PairMatchingExperienceHost.recover(
            runtime: f.runtime,
            operation: operation,
            onExit: () {},
          ),
        ),
      );
      await _pump(tester);
      expect(
        find.byKey(const ValueKey('pair-dispose-unavailable')),
        findsOneWidget,
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('pair-dispose-unavailable')),
      );
      await tester.tap(find.byKey(const ValueKey('pair-dispose-unavailable')));
      await _pump(tester);
      expect(
        find.byKey(const ValueKey('pair-incomplete-ended')),
        findsOneWidget,
      );
      await tester.runAsync(() async {
        final stopped = await f.real.inspectPairDisposition(
          ownerId: PairMeasurementFixture.owner,
          startOperation: operation.stableSerialization,
        );
        expect(stopped.kind, PairAcceptedDispositionKind.stopped);
        expect(stopped.recovery.attempts, hasLength(1));
        final baseline = await _admitConfigured(
          f,
          launchId: 'ordinary-after-withdrawal',
        );
        expect(baseline.configuration!.protocolId, 'protocol:local-standard');
        final c = await _researchCoordinator(f, baseline);
        for (var i = 0; i < 4; i++) {
          await _answer(c, 'synthetic-$i');
        }
        await c.finish();
        expect(
          (await f.real.loadExactActivityRecovery(
            ownerId: PairMeasurementFixture.owner,
            sessionId: baseline.plan.learningSessionId,
            activityType: 'matching',
          ))!.session.state,
          'completed',
        );
        c.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await _pump(tester);
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
  test(
    'terminal-only unavailable recovery finishes exact complete Pair without new answers',
    () async {
      final h = PairHarness(configuration: _configuration());
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final c = await h.restore();
      for (var i = 0; i < 4; i++) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      c.dispose();
      final learning = LearningUseCases(
        owners: h.learning.owners,
        repository: h.real,
        nowUtc: h.learning.nowUtc,
        generateId: () =>
            throw StateError('recovery must not capture another answer'),
        buildInfo: h.learning.buildInfo,
      );
      final recovery = PairMatchingUnavailableSession(
        operation: h.operation,
        learning: learning,
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: learning,
        ),
        requireOwner: () async => h.owner,
      );
      final resolved = await recovery.resolve(abandonIncomplete: false);
      expect(resolved.kind, PairAcceptedDispositionKind.complete);
      expect(resolved.recovery.session.state, 'completed');
      expect(resolved.recovery.checkpoint!.terminalAcknowledged, true);
      expect(resolved.recovery.attempts, hasLength(4));
      final firstTerminal = resolved.recovery.session.endedAtUtc;
      await recovery.markPresented();
      final replayed = await recovery.resolve(abandonIncomplete: true);
      expect(replayed.recovery.session.endedAtUtc, firstTerminal);
      expect(replayed.recovery.attempts, hasLength(4));
      recovery.dispose();
    },
  );
  test(
    'explicit unavailable disposition retains exact answers and checkpoints',
    () async {
      final h = PairHarness(configuration: _configuration());
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      final before = await h.real.inspectPairDisposition(
        ownerId: h.owner,
        startOperation: h.operation.stableSerialization,
      );
      expect(before.kind, PairAcceptedDispositionKind.incomplete);
      final checkpoint = before.recovery.checkpoint!;
      final cutoff = DateTime.utc(2026, 9, 5, 0, 2);
      final stopped = await h.real.abandonUnavailablePairSession(
        ownerId: h.owner,
        startOperation: h.operation.stableSerialization,
        expectedCheckpoint: checkpoint,
        abandonedAtUtc: cutoff,
      );
      expect(stopped.state, 'abandoned');
      expect(stopped.endedAtUtc, cutoff);
      expect(stopped.correctCount, 1);
      final after = await h.real.inspectPairDisposition(
        ownerId: h.owner,
        startOperation: h.operation.stableSerialization,
      );
      expect(after.kind, PairAcceptedDispositionKind.stopped);
      expect(
        jsonEncode(after.recovery.checkpoint!.state),
        jsonEncode(checkpoint.state),
      );
      expect(after.recovery.attempts, hasLength(1));
      expect(after.recovery.checkpoint!.terminalAcknowledged, false);
      expect(await h.real.getActiveSession(ownerId: h.owner), isNull);
      final retry = await h.real.abandonUnavailablePairSession(
        ownerId: h.owner,
        startOperation: h.operation.stableSerialization,
        expectedCheckpoint: checkpoint,
        abandonedAtUtc: cutoff,
      );
      expect(retry.endedAtUtc, cutoff);
      await expectLater(
        h.real.abandonUnavailablePairSession(
          ownerId: h.owner,
          startOperation: h.operation.stableSerialization,
          expectedCheckpoint: checkpoint,
          abandonedAtUtc: cutoff.add(const Duration(seconds: 1)),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'unavailable disposition rejects a stale checkpoint and changed owner',
    () async {
      final h = PairHarness(configuration: _configuration());
      addTearDown(h.db.close);
      await h.initialize();
      final before = await h.real.inspectPairDisposition(
        ownerId: h.owner,
        startOperation: h.operation.stableSerialization,
      );
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      Future<void> abandon() async {
        await h.real.abandonUnavailablePairSession(
          ownerId: h.owner,
          startOperation: h.operation.stableSerialization,
          expectedCheckpoint: before.recovery.checkpoint!,
          abandonedAtUtc: DateTime.utc(2026, 9, 5, 0, 2),
        );
      }

      await expectLater(abandon(), throwsStateError);
      expect(
        (await h.real.getActiveSession(ownerId: h.owner))!.state,
        'active',
      );
      await h.db.customStatement('UPDATE local_owners SET is_active=0');
      await expectLater(abandon(), throwsStateError);
      expect(
        (await h.db.select(h.db.learningSessions).get()).single.state,
        'active',
      );
    },
  );

  test(
    'disposition classifier rejects missing committed decision instead of recreating it',
    () async {
      final h = PairHarness(configuration: _configuration());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      await h.db.customStatement(
        "DELETE FROM events_v2 WHERE event_type='LearningEvidenceDecisionSet'",
      );
      await expectLater(
        h.real.inspectPairDisposition(
          ownerId: h.owner,
          startOperation: h.operation.stableSerialization,
        ),
        throwsStateError,
      );
      expect(
        await h.db
            .customSelect(
              "SELECT count(*) AS n FROM events_v2 WHERE event_type='LearningEvidenceDecisionSet'",
            )
            .getSingle()
            .then((r) => r.read<int>('n')),
        0,
      );
      expect(
        (await h.real.getActiveSession(ownerId: h.owner))!.state,
        'active',
      );
    },
  );

  test(
    'authenticated complete Pair cannot be disposed as incomplete',
    () async {
      final h = PairHarness(configuration: _configuration());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      for (var i = 0; i < 4; i++) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      final loaded = await h.real.inspectPairDisposition(
        ownerId: h.owner,
        startOperation: h.operation.stableSerialization,
      );
      expect(loaded.kind, PairAcceptedDispositionKind.complete);
      await expectLater(
        h.real.abandonUnavailablePairSession(
          ownerId: h.owner,
          startOperation: h.operation.stableSerialization,
          expectedCheckpoint: loaded.recovery.checkpoint!,
          abandonedAtUtc: DateTime.utc(2026, 9, 5, 0, 2),
        ),
        throwsStateError,
      );
      expect(
        (await h.real.getActiveSession(ownerId: h.owner))!.state,
        'active',
      );
    },
  );
}

Future<PairMatchingStartOperation> _admitConfigured(
  PairMeasurementFixture f, {
  String launchId = 'research-before-withdrawal',
}) async {
  final launch = PairMatchingLaunchIntent(
    ownerId: PairMeasurementFixture.owner,
    sourceSurface: PairSourceSurface.today,
    sourceSnapshotRef: 'today:${f.today.evaluatedAtUtc.millisecondsSinceEpoch}',
    operationId: launchId,
    createdAtUtc: f.now,
    requestedDirection: PairDirection.enToTh,
    requestedDensity: PairDensity.compact4,
    timerPreset: PairTimerPreset.off,
  );
  final resolved = f.runtime.composer.compose(
    launch: launch,
    source: PairSourceSnapshot.today(snapshot: f.today, allowlist: f.allowlist),
    preferences: f.preferences,
    shuffleSeed: 42,
    canPrompt: true,
  );
  final plan = (resolved as PairPlanReady).plan;
  final limits = await f.protocols.resolveForOwner(
    PairMeasurementFixture.owner,
  );
  const policy = SessionConfigurationPolicy();
  final config = policy.validate(
    draft: policy
        .defaultsFor(registration: f.runtime.registration, limits: limits)
        .copyWith(itemCount: 4),
    registration: f.runtime.registration,
    limits: limits,
    ownerId: PairMeasurementFixture.owner,
    availablePackIdentities: const [],
  );
  final operation = PairMatchingStartOperation(
    plan: plan,
    launchOperationId: launchId,
    appVersion: '1',
    buildId: 'test',
    configuration: config,
  );
  await f.runtime.start.startMeasured(operation);
  return operation;
}

CurrentActivityEvidenceAdapter _researchEvidence(
  PairMeasurementFixture f,
  LearningUseCases learning,
) => identical(learning, f.learning)
    ? f.currentActivityEvidence
    : CurrentActivityEvidenceAdapter(
        learning: learning,
        rolloutModeProvider: f.rollout,
        researchStateProvider: f.rollout.currentActivityResearchStateProvider!,
      );

Future<PairMatchingSessionCoordinator> _researchCoordinator(
  PairMeasurementFixture f,
  PairMatchingStartOperation operation, {
  LearningUseCases? learning,
}) => PairMatchingSessionCoordinator.restore(
  operation: operation,
  learning: learning ?? f.learning,
  evidence: _researchEvidence(f, learning ?? f.learning),
  activeOwnerId: () => PairMeasurementFixture.owner,
  monotonicMicros: () => 0,
);

Future<void> _answer(PairMatchingSessionCoordinator c, String word) async {
  for (final side in PairTileSide.values) {
    await c.dispatch(
      PairSelectTile(
        operationId: '${c.state.operationRevision}:answer',
        ownerId: c.operation.plan.ownerId,
        sessionId: c.operation.plan.learningSessionId,
        roundOrdinal: c.state.roundOrdinal,
        expectedRevision: c.state.operationRevision,
        tile: PairTile(side, word),
        responseTimeMs: 20,
      ),
    );
  }
}

final class _WithdrawalAnswerRepository extends PairFaultRepository {
  _WithdrawalAnswerRepository(this.fixture, {required this.committed})
    : super(fixture.real);
  final PairMeasurementFixture fixture;
  final bool committed;
  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (committed) {
      await delegate.recordAnswer(command);
      await fixture.research.withdraw(PairMeasurementFixture.owner);
      throw StateError(
        'synthetic commit then withdrawal then lost acknowledgement',
      );
    }
    await fixture.research.withdraw(PairMeasurementFixture.owner);
    return delegate.recordAnswer(command);
  }
}

Future<List<Map<String, Object?>>> _answerReceipts(
  PairMeasurementFixture f,
) async => [
  for (final row
      in await f.database
          .customSelect(
            "SELECT event_id,event_type,payload_json FROM events_v2 WHERE event_type != 'LearningActivityCheckpoint' ORDER BY event_id",
          )
          .get())
    row.data,
];

final class _TemporaryProtocols
    implements SessionConfigurationProtocolProvider {
  _TemporaryProtocols(this.delegate);
  final SessionConfigurationProtocolProvider delegate;
  bool unavailable = true;
  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(String ownerId) {
    if (unavailable) {
      throw StateError('synthetic temporarily unavailable catalog');
    }
    return delegate.resolveForOwner(ownerId);
  }
}

final class _DispositionFaultRepository extends PairFaultRepository
    implements PairAcceptedSessionDispositionRepository {
  _DispositionFaultRepository(
    this.fixture, {
    required this.afterCommit,
    required this.failCompletion,
  }) : super(fixture.real);
  final PairMeasurementFixture fixture;
  final bool afterCommit, failCompletion;
  bool fault = true;
  Future<void> Function()? afterInspect, beforeAbandon;
  final cutoffs = <DateTime>[];
  @override
  Future<PairAcceptedDispositionSnapshot> inspectPairDisposition({
    required String ownerId,
    required String startOperation,
  }) async {
    final result = await delegate.inspectPairDisposition(
      ownerId: ownerId,
      startOperation: startOperation,
    );
    await afterInspect?.call();
    return result;
  }

  @override
  Future<void> replayAcceptedPairAnswer({
    required String ownerId,
    required String startOperation,
    required String sourceEvidenceId,
  }) => delegate.replayAcceptedPairAnswer(
    ownerId: ownerId,
    startOperation: startOperation,
    sourceEvidenceId: sourceEvidenceId,
  );
  @override
  Future<LearningSessionSummary> abandonUnavailablePairSession({
    required String ownerId,
    required String startOperation,
    required LearningActivityCheckpoint expectedCheckpoint,
    required DateTime abandonedAtUtc,
  }) async {
    cutoffs.add(abandonedAtUtc);
    await beforeAbandon?.call();
    final fail = !failCompletion && fault;
    if (fail) fault = false;
    if (fail && !afterCommit) {
      throw StateError('synthetic disposition before commit');
    }
    final result = await delegate.abandonUnavailablePairSession(
      ownerId: ownerId,
      startOperation: startOperation,
      expectedCheckpoint: expectedCheckpoint,
      abandonedAtUtc: abandonedAtUtc,
    );
    if (fail) throw StateError('synthetic disposition lost acknowledgement');
    return result;
  }

  @override
  Future<LearningSessionSummary> completeUnavailablePairSession({
    required String ownerId,
    required String startOperation,
    required DateTime completedAtUtc,
  }) async {
    cutoffs.add(completedAtUtc);
    final fail = failCompletion && fault;
    if (fail) fault = false;
    if (fail && !afterCommit) {
      throw StateError('synthetic completion before commit');
    }
    final result = await delegate.completeUnavailablePairSession(
      ownerId: ownerId,
      startOperation: startOperation,
      completedAtUtc: completedAtUtc,
    );
    if (fail) throw StateError('synthetic completion lost acknowledgement');
    return result;
  }
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}
