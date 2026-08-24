import 'content_quality_report.dart';

abstract interface class ContentQualityReportRepository {
  Future<void> submit(ContentQualityReport report);
}
