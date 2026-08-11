import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_repository.dart';

QuestUseCases testQuestUseCases() {
  return QuestUseCases(
    repository: _TestQuestRepository(),
    owners: _TestOwnerRepository(),
    generateId: () => 'test-quest-instance',
    nowUtc: () => DateTime.utc(2026, 8, 11),
    timezoneId: 'Asia/Bangkok',
  );
}

final class _TestOwnerRepository implements LocalOwnerRepository {
  static final owner = LocalOwner(
    id: 'local:test-quest-owner',
    createdAtUtc: DateTime.utc(2026, 8, 11),
  );

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => owner;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) async {
    return owner;
  }
}

final class _TestQuestRepository implements QuestRepository {
  @override
  Future<List<QuestInstance>> getAllInstances(
    String ownerId, {
    int limit = 50,
  }) async => const [];

  @override
  Future<List<QuestInstance>> getActiveInstances(String ownerId) async =>
      const [];

  @override
  Future<List<QuestInstance>> getCompletedInstancesForSourceEvent({
    required String ownerId,
    required String sourceEventId,
    required Iterable<String> questIds,
    int limit = 64,
  }) async => const [];

  @override
  Future<QuestDefinition?> getDefinition(String questId) async => null;

  @override
  Future<void> markAbandoned(String instanceId) async {}

  @override
  Future<void> markCompleted(
    String instanceId,
    DateTime completedAtUtc,
  ) async {}

  @override
  Future<void> markExpired(String instanceId, DateTime expiredAtUtc) async {}

  @override
  Future<void> saveProgress(
    String instanceId,
    List<ObjectiveProgress> progress,
  ) async {}

  @override
  Future<void> startInstance(QuestInstance instance) async {}

  @override
  Future<void> upsertDefinition(QuestDefinition def) async {}
}
