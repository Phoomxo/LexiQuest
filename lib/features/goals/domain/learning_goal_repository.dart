import 'learning_goal.dart';

typedef LearningGoalMutationGuard = bool Function();

final class LearningGoalMutationUnavailable implements Exception {
  const LearningGoalMutationUnavailable();

  @override
  String toString() => 'LearningGoalMutationUnavailable';
}

abstract interface class LearningGoalRepository {
  Future<void> save(
    LearningGoal goal, {
    LearningGoalMutationGuard? mutationAllowed,
  });

  Future<List<LearningGoal>> list();
}
