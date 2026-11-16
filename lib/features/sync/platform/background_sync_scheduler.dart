import '../../identity/domain/local_owner_repository.dart';

enum BackgroundSyncScheduleResult {
  scheduled,
  unsupported,
  cloudDisabled,
  failed,
}

abstract interface class BackgroundSyncScheduler {
  Future<BackgroundSyncScheduleResult> schedule({required String ownerId});
}

final class NoOpBackgroundSyncScheduler implements BackgroundSyncScheduler {
  const NoOpBackgroundSyncScheduler({
    this.result = BackgroundSyncScheduleResult.unsupported,
  });

  final BackgroundSyncScheduleResult result;

  @override
  Future<BackgroundSyncScheduleResult> schedule({
    required String ownerId,
  }) async {
    return result;
  }
}

Future<BackgroundSyncScheduleResult> scheduleBackgroundSyncSafely({
  required BackgroundSyncScheduler scheduler,
  required LocalOwnerRepository owners,
}) async {
  try {
    final owner = await owners.getOrCreateActiveOwner();
    return await scheduler.schedule(ownerId: owner.id);
  } catch (_) {
    return BackgroundSyncScheduleResult.failed;
  }
}
