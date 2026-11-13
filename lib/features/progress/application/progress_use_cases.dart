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
    final now = nowUtc();
    if (!now.isUtc) {
      throw ArgumentError.value(now, 'nowUtc', 'must be UTC');
    }
    return queries.load(ownerId: owner.id, nowUtc: now);
  }

  Future<SessionHistoryEntry?> loadSession(String sessionId) async {
    final owner = await owners.getOrCreateActiveOwner();
    final entry = await queries.loadSession(
      ownerId: owner.id,
      sessionId: sessionId,
    );
    final currentOwner = await owners.getOrCreateActiveOwner();
    if (currentOwner.id != owner.id) throw StateError('progress owner changed');
    return entry;
  }

  Future<SessionHistoryEntry?> loadLatestSessionForCategory(
    String categoryId,
  ) async {
    final owner = await owners.getOrCreateActiveOwner();
    final entry = await queries.loadLatestSessionForCategory(
      ownerId: owner.id,
      categoryId: categoryId,
    );
    final currentOwner = await owners.getOrCreateActiveOwner();
    if (currentOwner.id != owner.id) throw StateError('progress owner changed');
    return entry;
  }
}
