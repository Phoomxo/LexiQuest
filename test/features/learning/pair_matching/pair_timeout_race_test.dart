import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_active_clock.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_engine.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_repair_policy.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/data/pair_matching_checkpoint_codec.dart';
import 'pair_matching_evidence_contract_test.dart';
import 'pair_timeout_recovery_test.dart';
import 'pair_matching_source_composer_test.dart' as f;

void main() {
  for (final lostAck in [false, true]) {
    test(
      'direct flush holds capacity before automatic resume lostAck=$lostAck',
      () async {
        var micros = 0;
        final h = PairHarness(
          pinnedPlan: timedPlan(density: PairDensity.standard6),
        );
        addTearDown(h.db.close);
        await h.initialize();
        final c = await clocked(h, () => micros);
        c.resumeInteraction();
        for (var i = 0; i < 22; i++) {
          micros += 1000;
          if (lostAck && i == 21) {
            h.repository.checkpointFault = 23;
            h.repository.afterWrite = true;
            await expectLater(c.flush(), throwsStateError);
            await c.retryPending();
          } else {
            await c.flush();
          }
        }
        expect(c.checkpointRevision, 23);
        expect(c.timerPaused, true);
        final elapsed = c.timer.elapsedActiveMs;
        micros += 1000000;
        expect(c.timer.elapsedActiveMs, elapsed);
        final modal = c.pause(PairPauseReason.modal),
            narration = c.pause(PairPauseReason.narration);
        final background = c.pause(PairPauseReason.background);
        await c.dispatch(decision(c, PairTimerAction.continueUntimed));
        expect(c.timer.reasons, {
          PairPauseReason.modal,
          PairPauseReason.narration,
          PairPauseReason.background,
        });
        c.releasePause(modal);
        c.releasePause(narration);
        expect(c.timerPaused, true);
        c.releasePause(background);
        expect(c.timerPaused, false);
        await h.finishBounded(c);
        await c.finish();
        await c.markSummaryPresented();
        expect(c.checkpointRevision, lessThanOrEqualTo(64));
        expect(c.state.attempts.where((a) => !a.isCorrect), isNotEmpty);
        expect((await h.restore()).summaryPresented, true);
      },
    );
  }
  test(
    'tight admission with five independent matches retains last correct and three receipts',
    () async {
      var micros = 0;
      final h = PairHarness(
        pinnedPlan: timedPlan(density: PairDensity.standard6),
      );
      addTearDown(h.db.close);
      await h.initialize();
      final c = await clocked(h, () => micros);
      c.resumeInteraction();
      for (var i = 0; i < 5; i++) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      expect(c.state.supportedWordIds, isEmpty);
      for (var i = 0; i < 64; i++) {
        micros += 1000;
        final token = c.pause(PairPauseReason.modal);
        await c.flush();
        try {
          c.releasePause(token);
        } on StateError catch (e) {
          expect(e.message, contains('capacity'));
          break;
        }
      }
      await c.dispatch(decision(c, PairTimerAction.continueUntimed));
      await h.tap(c, 'synthetic-5', PairTileSide.prompt);
      await h.tap(c, 'synthetic-5', PairTileSide.target);
      await c.finish();
      await c.markSummaryPresented();
      expect(c.checkpointRevision, lessThanOrEqualTo(64));
      expect(c.state.attempts, hasLength(6));
      debugPrint(
        'PM4 tight five-independent final revision=${c.checkpointRevision}',
      );
    },
  );
  test(
    'maximum admitted Unicode plan keeps pending timer repair and close below byte ceiling',
    () async {
      final items = List.generate(4, (i) {
        final item = f.fixture(
          i,
          spelling: '${'e' * 255}$i',
          meaning: '${'ก' * 255}$i',
        );
        return PairLexicalItem(
          wordId: '${'ก' * 255}$i',
          contentRevision: item.contentRevision,
          checksum: item.checksum,
          spelling: item.spelling,
          meaning: item.meaning,
          sourceLocale: 'en',
          targetLocale: 'th',
          sourceReasons: PairSourceReason.values.where(
            (r) => r != PairSourceReason.reported,
          ),
        );
      });
      final owner = 'o' * 256, launch = 'l' * 256;
      final plan = PairMatchingPlanV1(
        ownerId: owner,
        orderedLexicalItems: items,
        direction: PairDirection.thToEn,
        density: PairDensity.compact4,
        shuffleSeed: 42,
        timerPreset: PairTimerPreset.seconds120,
        allowlistVersion: 'a' * 256,
        learningSessionId: pairSessionId(owner, launch),
        entryKind: PairSourceSurface.learn,
        sourceSnapshotId: 's' * 256,
        createdAtUtc: DateTime.utc(2026, 9, 5),
      );
      var id = 0, micros = 0;
      final h = PairHarness(
        pinnedPlan: plan,
        launchId: launch,
        buildTag: 'b' * 256,
        evidenceId: () => '${'x' * 186}${(++id).toString().padLeft(3, '0')}',
      );
      addTearDown(h.db.close);
      await h.initialize();
      final c = await clocked(h, () => micros);
      c.resumeInteraction();
      micros += 120000000;
      await c.expire();
      await c.dispatch(decision(c, PairTimerAction.extend));
      micros += 30000000;
      await c.expire();
      await c.dispatch(decision(c, PairTimerAction.restart));
      micros += 120000000;
      await c.expire();
      await c.dispatch(decision(c, PairTimerAction.continueUntimed));
      await h.finishBounded(c);
      await c.finish();
      await c.markSummaryPresented();
      final maxBytes = h.repository.checkpoints
          .map((v) => utf8.encode(jsonEncode(v.state)).length)
          .reduce((a, b) => a > b ? a : b);
      expect(maxBytes, lessThanOrEqualTo(65536));
      expect(c.checkpointRevision, lessThanOrEqualTo(64));
      expect(
        h.repository.checkpoints.any((v) => v.state['frozenEvidence'] != null),
        true,
      );
      expect(c.state.attempts.where((a) => !a.isCorrect), isNotEmpty);
      final projected = PairMatchingCheckpointCodec.reservedCompletionBytes(
        PairMatchingCheckpointCodec.decode(h.operation.initialCheckpoint.state),
      );
      debugPrint(
        'PM4 Thai256 compact4 max written=$maxBytes; initial reserved=$projected; terminal revision=${c.checkpointRevision}; attempts=${c.state.attempts.length}',
      );
    },
  );
  test(
    'M12 routes same canonical close through host owner and completer',
    () async {
      final h = PairHarness();
      addTearDown(h.db.close);
      await h.initialize();
      var owned = 0, completed = 0;
      late Future<void> hostDurable;
      final c = await const MatchingModeAdapter().preparePairSession(
        operation: h.operation,
        learning: h.learning,
        evidence: CurrentActivityEvidenceAdapter(learning: h.learning),
        activeOwnerId: () => h.owner,
        monotonicMicros: () => 0,
        ownClose: (close, ensureDurable) {
          expect(close.belongsToLearningAuthority(h.learning), true);
          owned++;
          hostDurable = ensureDurable();
        },
        completeSession: (close) async {
          completed++;
          return close.requiresRetry ? close.retry() : close.finish();
        },
      );
      for (var i = 0; i < 4; i++) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      await c.finish();
      await hostDurable;
      expect(owned, 1);
      expect(completed, 1);
      await c.markSummaryPresented();
    },
  );
  test(
    'clock fault Continue removes fault pause and finishes real session',
    () async {
      var micros = 1000;
      final h = PairHarness(pinnedPlan: timedPlan());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await clocked(h, () => micros);
      c.resumeInteraction();
      micros += 5000000;
      c.timer;
      micros = 0;
      expect(c.timer.reasons, contains(PairPauseReason.clockFault));
      await c.dispatch(decision(c, PairTimerAction.continueUntimed));
      expect(c.timer.reasons, isNot(contains(PairPauseReason.clockFault)));
      expect(c.timerPaused, false);
      await h.finishBounded(c);
      await c.finish();
      await c.markSummaryPresented();
      expect((await h.restore()).summaryPresented, true);
    },
  );
  test(
    'capacity-paused board accepts stale releases and Continue completion',
    () async {
      var micros = 0;
      final h = PairHarness(
        pinnedPlan: timedPlan(density: PairDensity.standard6),
      );
      addTearDown(h.db.close);
      await h.initialize();
      final c = await clocked(h, () => micros);
      c.resumeInteraction();
      final stale = c.pause(PairPauseReason.modal);
      c.releasePause(stale);
      for (var i = 0; i < 64; i++) {
        micros += 1000;
        final token = c.pause(PairPauseReason.modal);
        await c.flush();
        try {
          c.releasePause(token);
        } on StateError catch (e) {
          expect(e.message, contains('capacity'));
          break;
        }
      }
      expect(c.timerPaused, true);
      c.releasePause(stale);
      c.releasePause(stale);
      await c.dispatch(decision(c, PairTimerAction.continueUntimed));
      await h.finishBounded(c);
      await c.finish();
      await c.markSummaryPresented();
      expect(c.checkpointRevision, lessThanOrEqualTo(64));
    },
  );
  for (final density in PairDensity.values) {
    test(
      'worst admitted restart sequence reserves full PM3 round and real close $density',
      () async {
        var micros = 0;
        final h = PairHarness(pinnedPlan: timedPlan(density: density));
        addTearDown(h.db.close);
        await h.initialize();
        final c = await clocked(h, () => micros);
        c.resumeInteraction();
        var restarts = 0;
        while (true) {
          if (c.timer.reasons.contains(PairPauseReason.capacity)) {
            final revision = c.checkpointRevision;
            expect(() => c.resumeInteraction(), throwsStateError);
            expect(c.checkpointRevision, revision);
            final elapsed = c.timer.elapsedActiveMs;
            micros += 60000000;
            expect(c.timer.elapsedActiveMs, elapsed);
            break;
          }
          micros += 60000000;
          await c.expire();
          final revision = c.checkpointRevision, round = c.state.roundOrdinal;
          final restartAvailable = c.timerAvailability.restart.available;
          try {
            await c.dispatch(decision(c, PairTimerAction.restart));
            expect(restartAvailable, true);
            restarts++;
          } on StateError catch (e) {
            expect(restartAvailable, false);
            expect(e.message, contains('capacity'));
            expect(c.checkpointRevision, revision);
            expect(c.state.roundOrdinal, round);
            break;
          }
          expect(restarts, lessThan(32));
        }
        expect(restarts, greaterThan(0));
        // Optional extension must be admitted with a subsequent expiry+Continue
        // reserve or refused before entitlement changes.
        if (c.timer.mode == PairTimerMode.timeoutDecision) {
          try {
            await c.dispatch(decision(c, PairTimerAction.extend));
            micros += 30000000;
            await c.expire();
          } on StateError catch (e) {
            expect(e.message, contains('capacity'));
            expect(c.timer.extensionUsed, false);
          }
        }
        await c.dispatch(decision(c, PairTimerAction.continueUntimed));
        await h.finishBounded(c);
        await c.finish();
        await c.markSummaryPresented();
        expect(c.checkpointRevision, lessThanOrEqualTo(64));
        expect(c.state.attempts.where((a) => !a.isCorrect), isNotEmpty);
        expect(
          c.state.attempts.where((a) => a.isCorrect),
          hasLength(density.pairCount),
        );
        expect((await h.restore()).summaryPresented, true);
        debugPrint(
          'PM4 $density admitted restarts=$restarts; terminal revision=${c.checkpointRevision}; attempts=${c.state.attempts.length}',
        );
      },
    );
  }
  test(
    'admitted answer pauses timer and fences timeout/restart until exact ack',
    () async {
      var micros = 0;
      final h = PairHarness(pinnedPlan: timedPlan());
      addTearDown(h.db.close);
      await h.initialize();
      final c = await clocked(h, () => micros);
      c.resumeInteraction();
      final entered = Completer<void>(), release = Completer<void>();
      h.repository.beforeAnswer = () async {
        entered.complete();
        await release.future;
      };
      micros = 59000000;
      await h.tap(c, 'synthetic-0', PairTileSide.prompt);
      final answer = h.tap(c, 'synthetic-0', PairTileSide.target);
      await entered.future;
      micros += 999000000;
      expect(c.timer.remainingActiveMs, 1000);
      await expectLater(
        c.dispatch(decision(c, PairTimerAction.restart)),
        throwsStateError,
      );
      release.complete();
      await answer;
      expect(c.state.attempts, hasLength(1));
      micros += 1000000;
      await c.expire();
      expect(c.timer.mode, PairTimerMode.timeoutDecision);
      await expectLater(
        h.tap(c, 'synthetic-1', PairTileSide.prompt),
        throwsStateError,
      );
      await c.dispatch(decision(c, PairTimerAction.continueUntimed));
      expect(c.state.attempts, hasLength(1));
    },
  );
  for (final density in PairDensity.values) {
    test('restart retains support and ticket-local spacing $density', () async {
      var micros = 0;
      final h = PairHarness(pinnedPlan: timedPlan(density: density));
      addTearDown(h.db.close);
      await h.initialize();
      var c = await clocked(h, () => micros);
      c.resumeInteraction();
      for (var i = 0; i < density.pairCount ~/ 2; i++) {
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      final oldIds = h.repository.commands.map((a) => a.id).toList();
      micros += 60000000;
      await c.expire();
      await c.dispatch(decision(c, PairTimerAction.restart));
      expect(c.state.matchedWordIds, isEmpty);
      final wrong = 'synthetic-${density.pairCount - 1}';
      await h.tap(c, wrong, PairTileSide.prompt);
      await h.tap(c, 'synthetic-0', PairTileSide.target);
      for (var i = 0; i < density.pairCount ~/ 2; i++) {
        expect(c.state.repairFor(wrong)!.status, PairRepairStatus.waiting);
        await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
        await h.tap(c, 'synthetic-$i', PairTileSide.target);
      }
      expect(c.state.repairFor(wrong)!.status, PairRepairStatus.available);
      expect(
        h.repository.commands.take(oldIds.length).map((a) => a.id),
        oldIds,
      );
      c.dispose();
      c = await clocked(h, () => micros);
      expect(c.state.repairFor(wrong)!.status, PairRepairStatus.available);
      expect(c.state.attempts.first.roundOrdinal, 0);
      expect(c.state.attempts.last.roundOrdinal, 1);
    });
  }
  for (final after in [false, true]) {
    for (final fault in ['pendingClose', 'close', 'ack', 'presented']) {
      test('exact real terminal recovery $fault after=$after', () async {
        final h = PairHarness();
        addTearDown(h.db.close);
        await h.initialize();
        var c = await h.restore();
        for (var i = 0; i < 4; i++) {
          await h.tap(c, 'synthetic-$i', PairTileSide.prompt);
          await h.tap(c, 'synthetic-$i', PairTileSide.target);
        }
        final base = c.checkpointRevision;
        h.repository.afterWrite = after;
        if (fault == 'close') {
          h.repository.closeFault = true;
        } else {
          h.repository.checkpointFault =
              base +
              (fault == 'pendingClose'
                  ? 1
                  : fault == 'ack'
                  ? 2
                  : 3);
        }
        if (fault == 'presented') {
          await c.finish();
          await expectLater(c.markSummaryPresented(), throwsStateError);
        } else {
          await expectLater(c.finish(), throwsStateError);
        }
        final attempted = h.repository.checkpoints.last;
        c.dispose();
        c = await h.restore();
        await c.finish();
        await c.markSummaryPresented();
        expect(c.checkpointRevision, base + 3);
        expect(c.summaryPresented, true);
        final summary = (await h.db.select(h.db.learningSessions).get()).single;
        expect(summary.state, 'completed');
        expect(await h.db.select(h.db.answerAttempts).get(), hasLength(4));
        final same = h.repository.checkpoints.where(
          (v) => v.revision == attempted.revision,
        );
        expect(same.map((v) => v.terminalAtUtc).toSet(), hasLength(1));
      });
    }
  }
}
