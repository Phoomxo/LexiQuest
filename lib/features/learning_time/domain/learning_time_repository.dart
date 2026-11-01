part of '../application/learning_time_use_cases.dart';

abstract interface class LearningTimeRepository {
  /// Absence is disabled revision zero; null/error/done means unavailable.
  Stream<LearningTimePreference?> watchPreference(String ownerId);
  Future<LearningTimePreference> readPreference({
    required String expectedOwnerId,
    required bool Function() isCurrent,
  });
  Future<LearningTimePreference> commitPreference(
    LearningTimePreferenceIntent intent,
  );
  Future<TimeSourceAdmission> admitSource({
    required TimeSource source,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  });

  /// Require belongsTo(this), isCurrent, exact enabled preference revision,
  /// closed source verification, and exact immutable insert/readback in one
  /// owned commit. Never require the previous live route to remain current.
  Future<void> commitSegment(ClosedTimeSegmentIntent intent);
  Future<TimeSessionLinkAdmission> prepareSessionLink({
    required LearningTimeScope scope,
    required CanonicalLearningTimeSessionLinkReceipt proof,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  });
  Future<void> commitSessionLink(TimeSessionLinkIntent intent);
  Future<RecordedTimeRead> read({
    required TimeReadTarget target,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  });
}
