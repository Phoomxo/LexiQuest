import '../domain/word_report.dart';

final class WordReportUseCases {
  const WordReportUseCases({
    required this.repository,
    required this.generateId,
    required this.nowUtc,
  });

  final WordReportRepository repository;
  final String Function() generateId;
  final DateTime Function() nowUtc;

  WordReportCommand prepareSubmit({
    required String expectedOwnerId,
    required WordReportTarget target,
    required ReportReason reason,
    String? comment,
  }) {
    final now = nowUtc();
    if (!now.isUtc || now.microsecondsSinceEpoch < 0) {
      throw ArgumentError('Word-report clock must be nonnegative UTC');
    }
    final normalized = comment?.trim();
    return WordReportCommand(
      id: '$wordReportIdPrefix${generateId()}',
      expectedOwnerId: expectedOwnerId,
      target: target,
      reason: reason,
      comment: normalized == null || normalized.isEmpty ? null : normalized,
      queuedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch,
        isUtc: true,
      ),
    );
  }

  Future<SubmitResult> submit(WordReportCommand command) =>
      repository.submit(command);
  Stream<List<StoredWordReport>> watchOwner(String expectedOwnerId) =>
      repository.watchOwner(expectedOwnerId);
}
