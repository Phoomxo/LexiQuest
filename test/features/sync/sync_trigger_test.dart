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

  test(
    'two requests during gate wait coalesce into one post-release run',
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
          if (!waitEntered.isCompleted) waitEntered.complete();
          return releaseWait.future;
        },
      );

      final first = trigger.request(SyncTriggerReason.accountBinding);
      await waitEntered.future;
      final second = trigger.request(SyncTriggerReason.localMutation);
      gateHeld = false;
      releaseWait.complete();

      final results = await Future.wait(<Future<SyncRunResult>>[first, second]);
      expect(
        results.map((result) => result.status),
        everyElement(SyncRunStatus.completed),
      );
      expect(calls, 2);
      expect(completedRuns, 1);
    },
  );

  test('request during a successful run schedules one follow-up', () async {
    var calls = 0;
    final firstRunEntered = Completer<void>();
    final releaseFirstRun = Completer<void>();
    final trigger = SyncTrigger(() async {
      calls += 1;
      if (calls == 1) {
        firstRunEntered.complete();
        await releaseFirstRun.future;
      }
      return const SyncRunResult(status: SyncRunStatus.completed);
    });

    final first = trigger.request(SyncTriggerReason.startup);
    await firstRunEntered.future;
    final duringRun = trigger.request(SyncTriggerReason.localMutation);
    releaseFirstRun.complete();

    final results = await Future.wait(<Future<SyncRunResult>>[
      first,
      duringRun,
    ]);
    expect(
      results.map((result) => result.status),
      everyElement(SyncRunStatus.completed),
    );
    expect(calls, 2);
  });

  test('request at successful-run teardown starts a new run', () async {
    var calls = 0;
    final firstResult = Completer<SyncRunResult>();
    final trigger = SyncTrigger(() {
      calls += 1;
      if (calls == 1) return firstResult.future;
      return Future<SyncRunResult>.value(
        const SyncRunResult(status: SyncRunStatus.completed),
      );
    });

    final first = trigger.request(SyncTriggerReason.startup);
    final boundaryRequest = firstResult.future.then(
      (_) => trigger.request(SyncTriggerReason.localMutation),
    );
    firstResult.complete(const SyncRunResult(status: SyncRunStatus.completed));

    final results = await Future.wait(<Future<SyncRunResult>>[
      first,
      boundaryRequest,
    ]);
    expect(
      results.map((result) => result.status),
      everyElement(SyncRunStatus.completed),
    );
    expect(calls, 2);
  });

  test('dispose cancels gate wait and rejects future requests', () async {
    var calls = 0;
    final waitEntered = Completer<void>();
    final neverReleased = Completer<void>();
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

    final requested = trigger.request(SyncTriggerReason.backgroundWork);
    await waitEntered.future;
    final firstDispose = trigger.dispose();
    final secondDispose = trigger.dispose();
    final result = await requested;
    await Future.wait(<Future<void>>[firstDispose, secondDispose]);

    expect(result.status, SyncRunStatus.alreadyRunning);
    expect(calls, 1);
    await expectLater(
      trigger.request(SyncTriggerReason.manualRetry),
      throwsA(isA<StateError>()),
    );
  });

  test('dispose drains an active provider run before completing', () async {
    final runEntered = Completer<void>();
    final releaseRun = Completer<void>();
    var disposeCompleted = false;
    final trigger = SyncTrigger(() async {
      runEntered.complete();
      await releaseRun.future;
      return const SyncRunResult(status: SyncRunStatus.completed);
    });

    final requested = trigger.request(SyncTriggerReason.startup);
    await runEntered.future;
    final disposing = trigger.dispose().whenComplete(
      () => disposeCompleted = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(disposeCompleted, isFalse);

    releaseRun.complete();
    expect((await requested).status, SyncRunStatus.completed);
    await disposing;
    expect(disposeCompleted, isTrue);
  });

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
