import '../../export/domain/export_contracts.dart';
import '../domain/research_transport_contracts.dart';
import '../domain/study_archive.dart';

final class ControlledStudyUploadUseCases {
  const ControlledStudyUploadUseCases({
    required this.repository,
    required this.gateway,
  });
  final StudyUploadArchiveRepository repository;
  final StudyUploadGateway gateway;

  Future<List<StudyArchivePreview>> listCycles({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  }) => repository.listUploadCycles(
    expectedOwnerId: expectedOwnerId,
    stillCurrent: stillCurrent,
  );

  Future<StudyUploadReceipt> uploadCycle({
    required StudyArchiveTarget target,
    required ExportCancellation cancellation,
    required bool Function() stillCurrent,
  }) async {
    final intent = await prepareCycle(
      target: target,
      cancellation: cancellation,
      stillCurrent: stillCurrent,
    );
    return submit(
      intent,
      cancellation: cancellation,
      stillCurrent: stillCurrent,
    );
  }

  Future<StudyUploadIntent> prepareCycle({
    required StudyArchiveTarget target,
    required ExportCancellation cancellation,
    required bool Function() stillCurrent,
  }) async {
    bool current() => !cancellation.isCancelled && stillCurrent();
    cancellation.throwIfCancelled();
    final prepared = await repository.prepareUpload(
      target,
      stillCurrent: current,
    );
    final bytes = prepared.artifact.bytes;
    if (bytes.isEmpty || bytes.length > maximumStudyUploadBytes) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.denied,
      );
    }
    await repository.requireCurrentUpload(prepared, stillCurrent: current);
    final request = StudyUploadRequest(
      motivationScope: prepared.motivationScope,
      assessmentScope: prepared.assessmentScope,
      cycleKey: target.studyCycleId,
      bytes: bytes,
    );
    return StudyUploadIntent._(this, target, request);
  }

  Future<StudyUploadReceipt> submit(
    StudyUploadIntent intent, {
    required ExportCancellation cancellation,
    required bool Function() stillCurrent,
  }) async {
    bool current() => !cancellation.isCancelled && stillCurrent();
    cancellation.throwIfCancelled();
    if (!identical(intent._issuer, this)) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.denied,
      );
    }
    final prepared = await repository.prepareUpload(
      intent._target,
      stillCurrent: current,
    );
    final request = intent._request;
    final fresh = StudyUploadRequest(
      motivationScope: prepared.motivationScope,
      assessmentScope: prepared.assessmentScope,
      cycleKey: intent._target.studyCycleId,
      bytes: prepared.artifact.bytes,
    );
    if (fresh.motivationScope != request.motivationScope ||
        fresh.assessmentScope != request.assessmentScope ||
        fresh.payloadSha256 != request.payloadSha256) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.conflict,
      );
    }
    await repository.requireCurrentUpload(prepared, stillCurrent: current);
    final receipt = await gateway.upload(
      request,
      stillCurrent: current,
      revalidateBeforeSubmit: () =>
          repository.requireCurrentUpload(prepared, stillCurrent: current),
    );
    cancellation.throwIfCancelled();
    await repository.requireCurrentUpload(prepared, stillCurrent: current);
    return receipt;
  }
}

final class StudyUploadIntent {
  const StudyUploadIntent._(this._issuer, this._target, this._request);
  final ControlledStudyUploadUseCases _issuer;
  final StudyArchiveTarget _target;
  final StudyUploadRequest _request;
}
