import 'cloud_sync_policy.dart';
import 'sync_entity.dart';
import 'sync_result.dart';

abstract interface class SyncGateway {
  Future<PushResult> push(PushMutation mutation);

  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  });

  Future<CloudSyncPolicy> fetchPolicy();
}

abstract interface class LearningTimeSegmentSyncRolloutGateway {
  LearningTimeSegmentSyncRollout get learningTimeSegmentSyncRollout;
}

abstract interface class LearningGoalSyncRolloutGateway {
  LearningGoalSyncRollout get learningGoalSyncRollout;
}

abstract interface class LearnerPreferenceSyncRolloutGateway {
  LearnerPreferenceSyncRollout get learnerPreferenceSyncRollout;
}
