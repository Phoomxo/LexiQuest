import '../../learning_packs/domain/content_manifest.dart';
import '../domain/content_quality_report.dart';
import '../domain/content_quality_report_repository.dart';

typedef ContentReportIdGenerator = String Function();
typedef ContentReportClock = DateTime Function();

final class ContentReportUseCases {
  const ContentReportUseCases({
    required this.repository,
    required this.generateId,
    required this.nowUtc,
  });

  final ContentQualityReportRepository repository;
  final ContentReportIdGenerator generateId;
  final ContentReportClock nowUtc;

  Future<void> report({
    required ContentIdentity identity,
    required ContentReportReason reason,
    String? comment,
  }) async {
    await repository.submit(
      ContentQualityReport(
        id: generateId(),
        contentIdentity: identity,
        reason: reason,
        comment: comment,
        submittedAtUtc: nowUtc(),
      ),
    );
  }
}
