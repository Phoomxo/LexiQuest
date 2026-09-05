import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_session_coordinator.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_active_clock.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart';
import 'pair_matching_evidence_contract_test.dart';
import 'pair_matching_source_composer_test.dart' as f;

PairMatchingPlanV1 timedPlan({
  PairDensity density = PairDensity.compact4,
  PairTimerPreset preset = PairTimerPreset.seconds60,
}) => PairMatchingPlanV1(
  ownerId: 'synthetic-owner',
  orderedLexicalItems: List.generate(density.pairCount, f.fixture),
  direction: PairDirection.enToTh,
  density: density,
  shuffleSeed: 42,
  timerPreset: preset,
  allowlistVersion: 'synthetic-v1',
  learningSessionId: pairSessionId('synthetic-owner', 'synthetic-operation'),
  entryKind: PairSourceSurface.learn,
  sourceSnapshotId: 'synthetic-snapshot',
  createdAtUtc: DateTime.utc(2026, 9, 5),
);

Future<PairMatchingSessionCoordinator> clocked(
  PairHarness h,
  int Function() now,
) => PairMatchingSessionCoordinator.restore(
  operation: h.operation,
  learning: h.learning,
  evidence: CurrentActivityEvidenceAdapter(learning: h.learning),
  activeOwnerId: () => h.owner,
  monotonicMicros: now,
);
PairTimerDecision decision(
  PairMatchingSessionCoordinator c,
  PairTimerAction action,
) => PairTimerDecision(
  operationId: '${c.state.operationRevision}:${action.name}',
  ownerId: c.operation.plan.ownerId,
  sessionId: c.operation.plan.learningSessionId,
  roundOrdinal: c.state.roundOrdinal,
  expectedRevision: c.state.operationRevision,
  action: action,
);

void main() {
  for (final loss in ['capacity', 'clock']) {
    test(
      'measured OFF $loss coverage loss remains playable through all answers and three receipts',
      () async {
        var micros = 0;
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize(measured: true);
        var c = await clocked(h, () => micros);
        c.resumeInteraction();
        if (loss == 'capacity') {
          for (
            var i = 0;
            i < 100 && c.timer.interactiveElapsedMs != null;
            i++
          ) {
            micros += 1000;
            await c.flush();
          }
        } else {
          micros = 1000000;
          expect(c.timer.interactiveElapsedMs, 1000);
          micros = 0;
        }
        expect(c.timer.interactiveElapsedMs, isNull);
        expect(c.hostStatus.canDispatch, true);
        await h.tap(c, 'synthetic-0', PairTileSide.prompt);
        await h.tap(c, 'synthetic-0', PairTileSide.target);
        c.dispose();
        c = await clocked(h, () => micros);
        c.resumeInteraction();
        expect(c.timer.interactiveElapsedMs, isNull);
        for (var i = 1; i < 4; i++) {
          await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
          await h.tap(c, 'synthetic-$i', PairTileSide.target);
        }
        await c.finish();
        await c.markSummaryPresented();
        final result = await h.real.read(
          ownerId: h.owner,
          sessionId: h.operation.plan.learningSessionId,
        );
        expect(result.snapshot!.timer!.interactiveElapsedMs, isNull);
        expect(result.snapshot!.terminal!.presented, true);
        expect(
          h.repository.checkpoints.where((p) => p.terminalAtUtc != null),
          hasLength(3),
        );
        expect((await h.db.select(h.db.answerAttempts).get()), hasLength(4));
      },
    );
  }
  test(
    'read-only restart availability includes restored matches and future byte reserve',
    () async {
      var micros = 0;
      final h = PairHarness(pinnedPlan: timedPlan());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await clocked(h, () => micros);
      c.resumeInteraction();
      for (var i = 0; i < 3; i++) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      for (var i = 0; i < 38; i++) {
        micros += 1000;
        await c.flush();
      }
      micros += 60000000;
      await c.expire();
      expect(c.timerAvailability.restart.available, false);
      expect(c.timerAvailability.continueUntimed.available, true);
      await expectLater(
        c.dispatch(decision(c, PairTimerAction.restart)),
        throwsStateError,
      );
      await c.dispatch(decision(c, PairTimerAction.continueUntimed));
      await h.tap(c, 'synthetic-3', PairTileSide.prompt);
      await h.tap(c, 'synthetic-3', PairTileSide.target);
      await c.finish();
      await c.markSummaryPresented();
    },
  );
  test(
    'typed host status retains failed capture and read-only timer availability',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      final c = await h.restore();
      final revision = c.checkpointRevision;
      expect(c.hostStatus.canDispatch, true);
      expect(c.timerAvailability.continueUntimed.available, false);
      expect(c.checkpointRevision, revision);
      h.repository.answerFault = true;
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      await expectLater(
        h.tap(c, 'synthetic-0', PairTileSide.target),
        throwsStateError,
      );
      expect(c.hostStatus.canDispatch, false);
      expect(c.hostStatus.canRetry, true);
      await c.retryPending();
      expect(c.hostStatus.canDispatch, true);
    },
  );
  test(
    'measured OFF pause flush and reopen retains full elapsed through terminal receipts',
    () async {
      var micros = 0;
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize(measured: true);
      var c = await clocked(h, () => micros);
      c.resumeInteraction();
      micros += 1250000;
      c.pause(PairPauseReason.background);
      await c.flush();
      c.dispose();
      c = await clocked(h, () => micros);
      expect(c.timer.interactiveElapsedMs, 1250);
      c.resumeInteraction();
      micros += 750000;
      for (var i = 0; i < 4; i++) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      await c.finish();
      micros += 90000000;
      await c.markSummaryPresented();
      final persisted = await h.real.read(
        ownerId: h.owner,
        sessionId: h.operation.plan.learningSessionId,
      );
      expect(persisted.snapshot!.timer!.interactiveElapsedMs, 2000);
      expect(
        h.repository.checkpoints.where((p) => p.terminalAtUtc != null).length,
        3,
      );
    },
  );
  test(
    'completed board stops active clock before delayed summary request',
    () async {
      var micros = 0;
      final h = PairHarness(pinnedPlan: timedPlan());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await clocked(h, () => micros);
      c.resumeInteraction();
      micros = 5000000;
      for (var i = 0; i < 4; i++) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      final elapsed = c.timer.elapsedActiveMs;
      micros += 30000000;
      expect(c.timer.elapsedActiveMs, elapsed);
      final restored = await clocked(h, () => micros);
      expect(() => restored.resumeInteraction(), throwsStateError);
      await c.finish();
      expect(c.timer.elapsedActiveMs, elapsed);
    },
  );
  test(
    'codec rejects timer identity detached from actual bound decision',
    () async {
      var micros = 0;
      final h = PairHarness(pinnedPlan: timedPlan());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await clocked(h, () => micros);
      c.resumeInteraction();
      micros = 60000000;
      await c.expire();
      final source =
          jsonDecode(jsonEncode(h.repository.checkpoints.last.state))
              as Map<String, dynamic>;
      (source['timer'] as Map)['lastOperationId'] = '0:forged';
      expect(
        () => PairMatchingCheckpointCodec.decode(source),
        throwsFormatException,
      );
    },
  );
  for (final measured in [false, true]) {
  for (final after in [false, true]) {
    for (final action in [
      'pause',
      'expire',
      'extend',
      'restart',
      'continueUntimed',
    ]) {
      test(
        'disk reopen preserves actual durable $action after=$after measured=$measured',
        () async {
          var micros = 0;
          final directory = await Directory.systemTemp.createTemp(
            'lexiquest-pm4-synthetic-',
          );
          final file = File('${directory.path}/pair.sqlite');
          final h = PairHarness(
            pinnedPlan: timedPlan(),
            executor: NativeDatabase(file),
          );
          await h.initialize(measured: measured);
          final c = await clocked(h, () => micros);
          c.resumeInteraction();
          micros = 3000000;
          final token = c.pause(PairPauseReason.modal);
          await c.flush();
          c.releasePause(token);
          if (action != 'pause' && action != 'expire') {
            micros += 57000000;
            await c.expire();
          }
          h.repository.checkpointFault = c.checkpointRevision + 1;
          h.repository.afterWrite = after;
          if (action == 'pause') {
            micros += 2000000;
            c.pause(PairPauseReason.background);
            await expectLater(c.flush(), throwsStateError);
          } else if (action == 'expire') {
            micros += 57000000;
            await expectLater(c.expire(), throwsStateError);
          } else {
            await expectLater(
              c.dispatch(decision(c, PairTimerAction.values.byName(action))),
              throwsStateError,
            );
          }
          final actual = await h.real.loadExactActivityRecovery(
            ownerId: h.owner,
            sessionId: h.operation.plan.learningSessionId,
            activityType: 'matching',
          );
          final bytes = jsonEncode(actual!.checkpoint!.state);
          c.dispose();
          await h.db.close();
          final db = AppDatabase(NativeDatabase(file));
          addTearDown(() async {
            await db.close();
            await file.delete();
            await directory.delete();
          });
          final learning = LearningUseCases(
            owners: DriftLocalOwnerRepository(
              db,
              generateId: () => throw StateError('no owner mint'),
              nowUtc: () => DateTime.utc(2026, 9, 5),
            ),
            repository: DriftLearningRepository(db),
            generateId: () => throw StateError('no evidence mint'),
            nowUtc: () => DateTime.utc(2026, 9, 5, 2),
            buildInfo: const AppBuildInfo(
              version: 'synthetic',
              buildId: 'synthetic',
            ),
          );
          final restored = await PairMatchingSessionCoordinator.restore(
            operation: h.operation,
            learning: learning,
            evidence: CurrentActivityEvidenceAdapter(learning: learning),
            activeOwnerId: () => h.owner,
            monotonicMicros: () => micros,
          );
          final again = await learning.loadExactActivityRecovery(
            ownerId: h.owner,
            sessionId: h.operation.plan.learningSessionId,
            activityType: 'matching',
          );
          expect(jsonEncode(again!.checkpoint!.state), bytes);
          expect(
            restored.timer.elapsedActiveMs,
            action == 'pause'
                ? (after ? 5000 : 3000)
                : action == 'expire'
                ? (after ? 60000 : 3000)
                : 60000,
          );
          expect(restored.timerPaused, true);
          final elapsed = restored.timer.elapsedActiveMs;
          expect(restored.timer.interactiveElapsedMs, measured ? elapsed : null);
          micros += 999999999;
          expect(restored.timer.elapsedActiveMs, elapsed);
          expect(restored.timer.extensionUsed, action == 'extend' && after);
          expect(
            restored.state.roundOrdinal,
            action == 'restart' && after ? 1 : 0,
          );
          expect(await db.select(db.answerAttempts).get(), isEmpty);
        },
      );
    }
  }
  }
  for (final tamper in [
    'elapsed',
    'remaining',
    'entitlement',
    'round',
    'terminal',
  ]) {
    test('repository rejects forged Pair $tamper transition', () async {
      var micros = 0;
      final h = PairHarness(pinnedPlan: timedPlan());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await clocked(h, () => micros);
      c.resumeInteraction();
      micros = 1000000;
      c.pause(PairPauseReason.background);
      await c.flush();
      final last = h.repository.checkpoints.last;
      final map = jsonDecode(jsonEncode(last.state)) as Map<String, dynamic>;
      final timer = map['timer'] as Map;
      switch (tamper) {
        case 'elapsed':
          timer['elapsedActiveMs'] = 0;
        case 'remaining':
          timer['remainingActiveMs'] = 60000;
        case 'entitlement':
          timer['extensionUsed'] = true;
        case 'round':
          (map['engine'] as Map)['roundOrdinal'] =
              1; // seed also forged coherently
          final state = c.state;
          map['roundSeed'] = int.parse(
            pairHash('${state.plan.shuffleSeed}:round:1:v1').substring(0, 7),
            radix: 16,
          );
        case 'terminal':
          break;
      }
      await expectLater(
        h.real.appendActivityCheckpoint(
          ownerId: h.owner,
          checkpoint: LearningActivityCheckpoint(
            sessionId: last.sessionId,
            activityType: 'matching',
            revision: last.revision + 1,
            occurredAtUtc: last.occurredAtUtc,
            state: map,
            terminalAtUtc: tamper == 'terminal' ? last.occurredAtUtc : null,
          ),
        ),
        throwsStateError,
      );
    });
  }
  for (final after in [false, true]) {
    test(
      'durable expiry extension restart Continue lost ack after=$after',
      () async {
        var micros = 0;
        final h = PairHarness(pinnedPlan: timedPlan());
        addTearDown(h.db.close);
        await h.initialize();
        var c = await clocked(h, () => micros);
        c.resumeInteraction();
        micros = 7000000;
        final pause = c.pause(PairPauseReason.background);
        await c.flush();
        expect(c.timer.remainingActiveMs, 53000);
        c.dispose();
        c = await clocked(h, () => micros);
        expect(c.timer.elapsedActiveMs, 7000);
        micros += 100000000;
        expect(c.timer.elapsedActiveMs, 7000);
        c.releasePause(pause); // lease belongs to disposed coordinator
        expect(c.timerPaused, true);
        c.resumeInteraction();
        micros += 53000000;
        await c.expire();
        expect(c.timer.mode, PairTimerMode.timeoutDecision);
        expect(await h.db.select(h.db.answerAttempts).get(), isEmpty);
        expect(
          (await h.db.select(h.db.learningSessions).get()).single.state,
          'active',
        );
        final extension = decision(c, PairTimerAction.extend);
        h.repository.checkpointFault = c.checkpointRevision + 1;
        h.repository.afterWrite = after;
        await expectLater(c.dispatch(extension), throwsStateError);
        await c.retryPending();
        await c.dispatch(extension);
        expect(c.timer.extensionUsed, true);
        expect(c.timer.remainingActiveMs, 30000);
        micros += 30000000;
        await c.expire();
        await c.dispatch(decision(c, PairTimerAction.restart));
        expect(c.state.roundOrdinal, 1);
        expect(c.timer.extensionUsed, true);
        expect(
          c.state.plan.stableSerialization,
          h.operation.plan.stableSerialization,
        );
        c.dispose();
        c = await clocked(h, () => micros);
        expect(c.state.roundOrdinal, 1);
        expect(c.timerPaused, true);
        c.resumeInteraction();
        micros += 60000000;
        await c.expire();
        await expectLater(
          c.dispatch(decision(c, PairTimerAction.extend)),
          throwsStateError,
        );
        await c.dispatch(decision(c, PairTimerAction.continueUntimed));
        for (var i = 0; i < 4; i++) {
          await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
          await h.tap(c, 'synthetic-$i', PairTileSide.target);
        }
        final revision = c.checkpointRevision;
        final summary = await c.finish();
        expect(summary.state, 'completed');
        expect(c.checkpointRevision, revision + 2);
        await c.markSummaryPresented();
        expect(c.checkpointRevision, revision + 3);
        await c.markSummaryPresented();
        expect(c.checkpointRevision, revision + 3);
        expect(
          h.repository.checkpoints.every(
            (v) => utf8.encode(jsonEncode(v.state)).length <= 65536,
          ),
          true,
        );
        c.dispose();
        c = await clocked(h, () => micros);
        expect((await c.finish()).id, summary.id);
        await c.markSummaryPresented();
        expect(c.checkpointRevision, revision + 3);
      },
    );
  }
}
