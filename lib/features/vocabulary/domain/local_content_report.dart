enum LocalContentReportReason { translationMismatch, exampleSpellingError }

final class LocalContentReportDraft {
  const LocalContentReportDraft({
    required this.id,
    required this.sourceKind,
    required this.sourceId,
    required this.sourceRevision,
    required this.spelling,
    required this.meaning,
    required this.sentence,
    required this.reason,
    required this.createdAtUtc,
  });

  final String id, sourceKind, sourceId, spelling, meaning;
  final int sourceRevision;
  final String? sentence;
  final LocalContentReportReason reason;
  final DateTime createdAtUtc;
}
