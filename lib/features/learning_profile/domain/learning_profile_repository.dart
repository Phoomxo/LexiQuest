import 'learning_profile.dart';

abstract interface class LearningProfileRepository {
  Future<LearningProfileSnapshot> read({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  });
  Future<LearningProfile> save(LearningProfileChange change);
  Stream<LearningProfileSnapshot> watch({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  });
  Stream<String?> watchActiveOwnerId();
}
