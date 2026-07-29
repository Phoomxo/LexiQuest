import 'learning_commit.dart';

abstract interface class LearningRepository {
  Future<CommitResult> commit(LearningCommit commit);
}
