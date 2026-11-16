import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/platform/background_sync_scheduler.dart';
import 'package:vocab_learning_app/features/sync/platform/workmanager_sync_scheduler.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';

void main() {
  test('Android registers one owner-scoped connected periodic job', () async {
    final client = _FakeWorkmanagerClient();
    final scheduler = WorkmanagerSyncScheduler(
      client: client,
      isAndroid: true,
      cloudSyncEnabled: true,
    );

    final first = await scheduler.schedule(ownerId: 'local-owner');
    final second = await scheduler.schedule(ownerId: 'local-owner');

    expect(first, BackgroundSyncScheduleResult.scheduled);
    expect(second, BackgroundSyncScheduleResult.scheduled);
    expect(client.initializeCalls, 1);
    expect(client.registrations, hasLength(2));
    expect(client.registrations.map((item) => item.uniqueName).toSet(), {
      'lexiquest.sync.local-owner',
    });
    final registration = client.registrations.first;
    expect(registration.requiresConnectedNetwork, isTrue);
    expect(registration.updateExisting, isTrue);
    expect(registration.exponentialBackoff, isTrue);
    expect(registration.frequency, const Duration(hours: 1));
  });

  test('non-Android and cloud-off scheduling are no-ops', () async {
    final unsupportedClient = _FakeWorkmanagerClient();
    final unsupported = WorkmanagerSyncScheduler(
      client: unsupportedClient,
      isAndroid: false,
      cloudSyncEnabled: true,
    );
    final disabledClient = _FakeWorkmanagerClient();
    final disabled = WorkmanagerSyncScheduler(
      client: disabledClient,
      isAndroid: true,
      cloudSyncEnabled: false,
    );

    expect(
      await unsupported.schedule(ownerId: 'owner'),
      BackgroundSyncScheduleResult.unsupported,
    );
    expect(
      await disabled.schedule(ownerId: 'owner'),
      BackgroundSyncScheduleResult.cloudDisabled,
    );
    expect(unsupportedClient.initializeCalls, 0);
    expect(disabledClient.initializeCalls, 0);
  });

  test('background result retries only retryable partial failures', () {
    expect(
      workmanagerSuccess(const SyncRunResult(status: SyncRunStatus.completed)),
      isTrue,
    );
    expect(
      workmanagerSuccess(
        const SyncRunResult(
          status: SyncRunStatus.partialFailure,
          failures: 1,
          retryRecommended: true,
        ),
      ),
      isFalse,
    );
    expect(
      workmanagerSuccess(
        const SyncRunResult(
          status: SyncRunStatus.partialFailure,
          failures: 1,
          retryRecommended: false,
        ),
      ),
      isTrue,
    );
  });

  test('scheduler failure never blocks local startup', () async {
    final result = await scheduleBackgroundSyncSafely(
      scheduler: _ThrowingScheduler(),
      owners: _OwnerRepository(),
    );

    expect(result, BackgroundSyncScheduleResult.failed);
  });
}

final class _FakeWorkmanagerClient implements WorkmanagerClient {
  int initializeCalls = 0;
  final List<BackgroundTaskRegistration> registrations = [];

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<void> registerPeriodic(BackgroundTaskRegistration registration) async {
    registrations.add(registration);
  }
}

final class _ThrowingScheduler implements BackgroundSyncScheduler {
  @override
  Future<BackgroundSyncScheduleResult> schedule({required String ownerId}) {
    throw StateError('platform unavailable');
  }
}

final class _OwnerRepository implements LocalOwnerRepository {
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) {
    throw UnimplementedError();
  }

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    return LocalOwner(
      id: 'local-owner',
      createdAtUtc: DateTime.utc(2026, 7, 30),
    );
  }
}
