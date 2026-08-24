import 'learning_pack.dart';
import 'learning_pack_detail.dart';

/// The sole catalog authority. f02 extends this same interface with its
/// pinned-detail read; it must not introduce another pack repository.
abstract interface class LearningPackRepository {
  Future<List<LearningPackSummary>> list(LearningPackFilter filter);

  /// Returns only the requested immutable revision, after f04 verification.
  Future<LearningPackDetail> getVersion(String packId, int revision);
}
