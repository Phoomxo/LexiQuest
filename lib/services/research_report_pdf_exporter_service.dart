/// Research report PDF exporter service.
///
/// RESEARCH_ONLY: This is an owner-only tool for generating thesis/report
/// PDFs from analytical results. It must:
/// - Run from real data only
/// - Produce deterministic output
/// - Never display charts when data is insufficient
/// - Include provenance and algorithm version
class ResearchReportPdfExporterService {
  const ResearchReportPdfExporterService();

  /// Returns true if the dataset has sufficient records for a report.
  /// Returns false and a reason string otherwise.
  ({bool isSufficient, String? reason}) checkSufficiency({
    required int recordCount,
    int minimum = 10,
  }) {
    if (recordCount < minimum) {
      return (
        isSufficient: false,
        reason: 'ข้อมูลไม่เพียงพอ ($recordCount ระเบียน) '
            'ต้องการอย่างน้อย $minimum ระเบียนเพื่อสร้างรายงาน',
      );
    }
    return (isSufficient: true, reason: null);
  }
}
