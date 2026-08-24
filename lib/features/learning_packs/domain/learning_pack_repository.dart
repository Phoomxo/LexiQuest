import 'learning_pack.dart';

/// The sole catalog authority. f02 extends this same interface with its
/// pinned-detail read; it must not introduce another pack repository.
abstract interface class LearningPackRepository {
  Future<List<LearningPackSummary>> list(LearningPackFilter filter);
}
