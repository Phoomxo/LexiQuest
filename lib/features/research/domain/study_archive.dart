import '../../export/domain/export_contracts.dart';
import 'research_authority_snapshot.dart';

final class StudyArchiveTarget {
  const StudyArchiveTarget({
    required this.expectedOwnerId,
    required this.studyCycleId,
  });

  final String expectedOwnerId;
  final String studyCycleId;
}

final class StudyArchivePreview {
  StudyArchivePreview({
    required this.target,
    required this.state,
    required this.startedAtUtc,
    required this.motivationResponseCount,
    required List<String> assessmentPhases,
    required List<String> missingPhases,
  }) : assessmentPhases = List.unmodifiable(assessmentPhases),
       missingPhases = List.unmodifiable(missingPhases);

  final StudyArchiveTarget target;
  final String state;
  final DateTime startedAtUtc;
  final int motivationResponseCount;
  final List<String> assessmentPhases;
  final List<String> missingPhases;
}

abstract interface class PreparedStudyArchive {
  StudyArchivePreview get preview;
  ExportArtifact get artifact;
}

abstract interface class StudyArchiveRepository {
  Future<List<StudyArchivePreview>> listCycles({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  });

  Future<PreparedStudyArchive> prepare(
    StudyArchiveTarget target, {
    required bool Function() stillCurrent,
  });

  Future<void> requireCurrent(
    PreparedStudyArchive prepared, {
    required bool Function() stillCurrent,
  });
}

abstract interface class PreparedStudyUploadArchive
    implements PreparedStudyArchive {
  ResearchAuthorityScope get motivationScope;
  ResearchAuthorityScope get assessmentScope;
}

abstract interface class StudyUploadArchiveRepository
    implements StudyArchiveRepository {
  Future<List<StudyArchivePreview>> listUploadCycles({
    required String expectedOwnerId,
    required bool Function() stillCurrent,
  });

  Future<PreparedStudyUploadArchive> prepareUpload(
    StudyArchiveTarget target, {
    required bool Function() stillCurrent,
  });

  Future<void> requireCurrentUpload(
    PreparedStudyUploadArchive prepared, {
    required bool Function() stillCurrent,
  });
}
