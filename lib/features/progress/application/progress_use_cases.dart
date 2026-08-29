import '../../identity/domain/local_owner_repository.dart';
import '../data/drift_progress_queries.dart';
import '../domain/progress_models.dart';

typedef ProgressUtcNow = DateTime Function();

final class ProgressUseCases {
  const ProgressUseCases({
    required this.owners,
    required this.queries,
    required this.nowUtc,
  });

  final LocalOwnerRepository owners;
  final DriftProgressQueries queries;
  final ProgressUtcNow nowUtc;

  Future<ProgressSnapshot> load() async {
    final owner = await owners.getOrCreateActiveOwner();
    return loadForOwner(owner.id);
  }

  Future<ProgressSnapshot> loadForOwner(String ownerId) async {
    if (ownerId.isEmpty || ownerId.trim() != ownerId) {
      throw ArgumentError.value(ownerId, 'ownerId');
    }
    final now = nowUtc();
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'nowUtc', 'must be UTC');
    }
    return queries.load(ownerId: ownerId, nowUtc: now);
  }
}
