import '../../export/domain/export_contracts.dart';
import '../domain/study_archive.dart';

final class ControlledStudyArchiveUseCases {
  const ControlledStudyArchiveUseCases({
    required this.repository,
    required this.store,
  });

  final StudyArchiveRepository repository;
  final ExportArtifactStore store;

  Future<List<StudyArchivePreview>> listCycles({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => repository.listCycles(
    expectedOwnerId: expectedOwnerId,
    stillCurrent: stillCurrent,
  );

  Future<ExportSaveResult> exportCycle({
    required StudyArchiveTarget target,
    required ExportCancellation cancellation,
    required bool Function() stillCurrent,
  }) async {
    cancellation.throwIfCancelled();
    bool current() => !cancellation.isCancelled && stillCurrent();
    final prepared = await repository.prepare(target, stillCurrent: current);
    await repository.requireCurrent(prepared, stillCurrent: current);
    cancellation.throwIfCancelled();
    return store.save(
      prepared.artifact,
      cancellation: cancellation,
      revalidateBeforeWrite: () =>
          repository.requireCurrent(prepared, stillCurrent: current),
    );
  }
}
