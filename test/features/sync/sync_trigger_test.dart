import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_trigger.dart';

void main() {
  test(
    'request waits through gate contention and runs once after release',
    () async {
      var gateHeld = true;
      var calls = 0;
      var completedRuns = 0;
      final waitEntered = Completer<void>();
      final releaseWait = Completer<void>();
      final trigger = SyncTrigger(
        () async {
          calls += 1;
          if (gateHeld) {
            return const SyncRunResult(status: SyncRunStatus.alreadyRunning);
          }
          completedRuns += 1;
          return const SyncRunResult(status: SyncRunStatus.completed);
        },
        retryDelay: (_) {
          waitEntered.complete();
          return releaseWait.future;
        },
      );

      final requested = trigger.request(SyncTriggerReason.accountBinding);
      await waitEntered.future;
      expect(calls, 1);
      gateHeld = false;
      releaseWait.complete();
      final result = await requested;

      expect(result.status, SyncRunStatus.completed);
      expect(calls, 2);
      expect(completedRuns, 1);
    },
  );

  test('a queued request can be cancelled without a hot loop', () async {
    var calls = 0;
    final waitEntered = Completer<void>();
    final neverReleased = Completer<void>();
    final cancelled = Completer<void>();
    final trigger = SyncTrigger(
      () async {
        calls += 1;
        return const SyncRunResult(status: SyncRunStatus.alreadyRunning);
      },
      retryDelay: (_) {
        waitEntered.complete();
        return neverReleased.future;
      },
    );

    final requested = trigger.request(
      SyncTriggerReason.backgroundWork,
      cancelled: cancelled.future,
    );
    await waitEntered.future;
    cancelled.complete();
    final result = await requested;

    expect(result.status, SyncRunStatus.alreadyRunning);
    expect(calls, 1);
  });

  test('gate contention retries are bounded', () async {
    var calls = 0;
    final trigger = SyncTrigger(
      () async {
        calls += 1;
        return const SyncRunResult(status: SyncRunStatus.alreadyRunning);
      },
      retryDelay: (_) async {},
      retryInterval: const Duration(seconds: 1),
      maxGateWait: const Duration(seconds: 1),
    );

    final result = await trigger.request(SyncTriggerReason.manualRetry);

    expect(result.status, SyncRunStatus.alreadyRunning);
    expect(calls, 2);
  });
}
