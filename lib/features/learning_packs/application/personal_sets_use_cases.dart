import '../../ai_tutor/application/owner_operation_coordinator.dart';
import '../../ai_tutor/domain/ai_tutor_contracts.dart';
import '../../identity/application/owner_generation.dart';
import '../data/drift_personal_set_repository.dart';
import '../domain/personal_sets.dart';
import '../domain/personal_set_archive.dart';

final class PersonalSetsUseCases {
  PersonalSetsUseCases({
    required this.repository,
    required this.ownerOperations,
    required this.ownerGeneration,
  });
  final DriftPersonalSetRepository repository;
  final OwnerOperationCoordinator ownerOperations;
  final OwnerGeneration ownerGeneration;
  Future<OwnerGenerationToken> begin() => ownerGeneration.capture();
  Future<List<PersonalSetRevision>> list(
    OwnerGenerationToken owner, {
    bool includeArchived = false,
  }) => _run(
    owner,
    (_) => repository.listLatest(
      ownerId: owner.ownerId,
      includeArchived: includeArchived,
    ),
  );
  Future<PersonalSetRevision?> read(
    OwnerGenerationToken owner, {
    required String setId,
    required int revision,
  }) => _run(
    owner,
    (_) => repository.readExact(
      ownerId: owner.ownerId,
      setId: setId,
      revision: revision,
    ),
  );
  Future<PersonalSetArchive> exportArchive(OwnerGenerationToken owner) => _run(
    owner,
    (lease) =>
        repository.exportArchive(ownerId: owner.ownerId, leaseToken: lease),
  );
  Future<void> restoreArchive(
    OwnerGenerationToken owner,
    Map<String, Object?> envelope,
  ) {
    // Freeze nested caller-owned maps before waiting for the lease.
    final frozen = PersonalSetArchive.fromJson(envelope).toJson();
    return _run(
      owner,
      (lease) => repository.restoreArchive(
        ownerId: owner.ownerId,
        leaseToken: lease,
        envelope: frozen,
        requireCurrentGeneration: () =>
            ownerGeneration.requireCurrentAsync(owner),
      ),
    );
  }

  Future<PersonalSetRevision> save(
    OwnerGenerationToken owner,
    PersonalSetRevision revision,
  ) => _run(
    owner,
    (lease) => repository.save(
      ownerId: owner.ownerId,
      leaseToken: lease,
      revision: revision,
      requireCurrentGeneration: () =>
          ownerGeneration.requireCurrentAsync(owner),
    ),
  );

  Future<T> _run<T>(
    OwnerGenerationToken owner,
    Future<T> Function(String lease) operation,
  ) async {
    await ownerGeneration.requireCurrentAsync(owner);
    return ownerOperations.run(AiCancellation(), (activeOwner) async {
      await ownerGeneration.requireCurrentAsync(owner);
      if (activeOwner != owner.ownerId) {
        throw StateError('Personal set owner changed');
      }
      final result = await operation(ownerOperations.currentOperationVersion);
      await ownerGeneration.requireCurrentAsync(owner);
      return result;
    });
  }
}
