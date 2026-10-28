import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_trigger.dart';
import 'package:vocab_learning_app/features/sync/platform/workmanager_sync_scheduler.dart';

void main() {
  test('continuation reports totals across all completed runs', () async {
    var calls = 0;
    final trigger = SyncTrigger(() async {
      calls++;
      return SyncRunResult(
        status: SyncRunStatus.completed,
        pushed: calls < 3 ? 500 : 0,
        pulled: calls < 3 ? 100 : 0,
        conflicts: calls == 1 ? 1 : 0,
        hasMoreWork: calls < 3,
        retryRecommended: calls < 3,
      );
    });
    final result = await trigger.request(SyncTriggerReason.manualRetry);
    expect(calls, 3);
    expect(result.pushed, 1000);
    expect(result.pulled, 200);
    expect(result.conflicts, 1);
    expect(result.hasMoreWork, isFalse);
    expect(result.retryRecommended, isFalse);
  });

  test(
    'later completion retains earlier failures that still need retry',
    () async {
      var calls = 0;
      final trigger = SyncTrigger(
        () async => ++calls == 1
            ? const SyncRunResult(
                status: SyncRunStatus.partialFailure,
                failures: 1,
                retryRecommended: true,
                hasMoreWork: true,
              )
            : const SyncRunResult(status: SyncRunStatus.completed, pushed: 1),
      );
      final result = await trigger.request(SyncTriggerReason.startup);
      expect(result.status, SyncRunStatus.partialFailure);
      expect(result.failures, 1);
      expect(result.pushed, 1);
      expect(result.retryRecommended, isTrue);
      expect(result.hasMoreWork, isFalse);
    },
  );

  test(
    'foreground follows bounded backlog without another user request',
    () async {
      var calls = 0;
      final trigger = SyncTrigger(
        () async => SyncRunResult(
          status: SyncRunStatus.completed,
          hasMoreWork: ++calls < 2,
        ),
      );
      final result = await trigger.request(SyncTriggerReason.localMutation);
      expect(calls, 2);
      expect(result.hasMoreWork, isFalse);
    },
  );

  test(
    'a constantly growing backlog has a bounded foreground budget',
    () async {
      var calls = 0;
      final trigger = SyncTrigger(() async {
        calls++;
        return const SyncRunResult(
          status: SyncRunStatus.completed,
          hasMoreWork: true,
        );
      });
      final result = await trigger.request(SyncTriggerReason.startup);
      expect(calls, SyncTrigger.maxAutomaticRuns);
      expect(result.hasMoreWork, isTrue);
      expect(workmanagerSuccess(result), isFalse);
    },
  );
}
