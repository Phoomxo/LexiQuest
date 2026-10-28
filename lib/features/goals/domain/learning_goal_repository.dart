import 'learning_goal.dart';

typedef LearningGoalMutationGuard = bool Function();

final class LearningGoalOwnerChanged implements Exception {
  const LearningGoalOwnerChanged();
}

final class LearningGoalMutationUnavailable implements Exception {
  const LearningGoalMutationUnavailable();

  @override
  String toString() => 'LearningGoalMutationUnavailable';
}

abstract interface class LearningGoalRepository {
  Future<void> save(
    LearningGoal goal, {
    LearningGoalMutationGuard? mutationAllowed,
    String? expectedOwnerId,
  });

  Future<List<LearningGoal>> list();
}
