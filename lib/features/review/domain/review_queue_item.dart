import '../../learning_packs/domain/content_manifest.dart';
import 'content_quality_report.dart';

enum ReviewQueueReason { dueSrs, incorrectAnswer, reported, saved }

extension ReviewQueueReasonPriority on ReviewQueueReason {
  int get priority => switch (this) {
    ReviewQueueReason.dueSrs => 0,
    ReviewQueueReason.incorrectAnswer => 1,
    ReviewQueueReason.reported => 2,
    ReviewQueueReason.saved => 3,
  };
}

enum ReviewQueueAuthority {
  srs,
  answerAttempts,
  contentQualityReports,
  savedLearningItems,
}

final class ReviewReasonProvenance {
  ReviewReasonProvenance._({
    required this.reason,
    required this.authority,
    required this.sourceId,
    required this.occurredAtUtc,
    required this.dueAtUtc,
    required this.reportReason,
  }) {
    _requireCanonicalText(sourceId, 'sourceId');
    _requireUtc(occurredAtUtc, 'occurredAtUtc');
    if (dueAtUtc != null) _requireUtc(dueAtUtc!, 'dueAtUtc');
    final expectedAuthority = switch (reason) {
      ReviewQueueReason.dueSrs => ReviewQueueAuthority.srs,
      ReviewQueueReason.incorrectAnswer => ReviewQueueAuthority.answerAttempts,
      ReviewQueueReason.reported => ReviewQueueAuthority.contentQualityReports,
      ReviewQueueReason.saved => ReviewQueueAuthority.savedLearningItems,
    };
    if (authority != expectedAuthority ||
        (reason == ReviewQueueReason.dueSrs) != (dueAtUtc != null) ||
        (reason == ReviewQueueReason.reported) != (reportReason != null)) {
      throw ArgumentError('review reason provenance is inconsistent');
    }
  }

  factory ReviewReasonProvenance.due({
    required String sourceId,
    required DateTime dueAtUtc,
  }) => ReviewReasonProvenance._(
    reason: ReviewQueueReason.dueSrs,
    authority: ReviewQueueAuthority.srs,
    sourceId: sourceId,
    occurredAtUtc: dueAtUtc,
    dueAtUtc: dueAtUtc,
    reportReason: null,
  );

  factory ReviewReasonProvenance.incorrect({
    required String sourceId,
    required DateTime occurredAtUtc,
  }) => ReviewReasonProvenance._(
    reason: ReviewQueueReason.incorrectAnswer,
    authority: ReviewQueueAuthority.answerAttempts,
    sourceId: sourceId,
    occurredAtUtc: occurredAtUtc,
    dueAtUtc: null,
    reportReason: null,
  );

  factory ReviewReasonProvenance.reported({
    required String sourceId,
    required DateTime occurredAtUtc,
    required ContentReportReason reportReason,
  }) => ReviewReasonProvenance._(
    reason: ReviewQueueReason.reported,
    authority: ReviewQueueAuthority.contentQualityReports,
    sourceId: sourceId,
    occurredAtUtc: occurredAtUtc,
    dueAtUtc: null,
    reportReason: reportReason,
  );

  factory ReviewReasonProvenance.saved({
    required String sourceId,
    required DateTime occurredAtUtc,
  }) => ReviewReasonProvenance._(
    reason: ReviewQueueReason.saved,
    authority: ReviewQueueAuthority.savedLearningItems,
    sourceId: sourceId,
    occurredAtUtc: occurredAtUtc,
    dueAtUtc: null,
    reportReason: null,
  );

  final ReviewQueueReason reason;
  final ReviewQueueAuthority authority;
  final String sourceId;
  final DateTime occurredAtUtc;
  final DateTime? dueAtUtc;
  final ContentReportReason? reportReason;

  bool get isReport => reason == ReviewQueueReason.reported;
  DateTime get priorityTimeUtc => dueAtUtc ?? occurredAtUtc;
}

final class ReviewQueueItem {
  ReviewQueueItem({
    required this.snapshot,
    required Iterable<ReviewReasonProvenance> provenance,
  }) : provenance = _canonicalProvenance(provenance) {
    if (identity.type != ContentType.lexicalMetadata ||
        identity.revision <= 0) {
      throw ArgumentError.value(
        identity,
        'identity',
        'must be a positive lexical metadata identity',
      );
    }
    _requireCanonicalText(identity.id, 'identity.id');
    _requireCanonicalText(spelling, 'spelling');
    _requireCanonicalText(meaning, 'meaning');
  }

  final ReviewedLexicalContentSnapshot snapshot;
  final List<ReviewReasonProvenance> provenance;

  ContentIdentity get identity => snapshot.identity;
  String get spelling => snapshot.spelling;
  String get meaning => snapshot.meaning;

  List<ReviewQueueReason> get reasons => List<ReviewQueueReason>.unmodifiable(
    provenance.map((source) => source.reason).toSet(),
  );

  ReviewQueueReason get primaryReason => provenance.first.reason;
  DateTime get primarySortAtUtc => provenance.first.priorityTimeUtc;

  bool hasAnyReason(Set<ReviewQueueReason> included) =>
      provenance.any((source) => included.contains(source.reason));

  static int compare(ReviewQueueItem left, ReviewQueueItem right) {
    var result = left.primaryReason.priority.compareTo(
      right.primaryReason.priority,
    );
    if (result != 0) return result;
    result = left.primarySortAtUtc.compareTo(right.primarySortAtUtc);
    if (result != 0) return result;
    result = left.spelling.toLowerCase().compareTo(
      right.spelling.toLowerCase(),
    );
    if (result != 0) return result;
    result = left.identity.type.name.compareTo(right.identity.type.name);
    if (result != 0) return result;
    result = left.identity.id.compareTo(right.identity.id);
    if (result != 0) return result;
    return left.identity.revision.compareTo(right.identity.revision);
  }
}

final class ReviewQueueFilter {
  ReviewQueueFilter({
    required this.ownerId,
    required this.evaluatedAtUtc,
    required this.timezoneId,
    Set<ReviewQueueReason> includeReasons = allReasons,
    this.limit,
  }) : includeReasons = Set<ReviewQueueReason>.unmodifiable(includeReasons) {
    _requireCanonicalText(ownerId, 'ownerId');
    _requireUtc(evaluatedAtUtc, 'evaluatedAtUtc');
    _requireCanonicalText(timezoneId, 'timezoneId');
    if (limit != null && limit! <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
  }

  static const Set<ReviewQueueReason> allReasons = {
    ReviewQueueReason.dueSrs,
    ReviewQueueReason.incorrectAnswer,
    ReviewQueueReason.reported,
    ReviewQueueReason.saved,
  };

  final String ownerId;
  final DateTime evaluatedAtUtc;
  final String timezoneId;
  final Set<ReviewQueueReason> includeReasons;
  final int? limit;
}

abstract interface class ReviewCenterReader {
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter);
}

abstract interface class ReviewOwnerIdentityReader {
  Future<String> requireSingleActiveOwnerId();
}

List<ReviewReasonProvenance> _canonicalProvenance(
  Iterable<ReviewReasonProvenance> values,
) {
  final result = values.toList(growable: false);
  if (result.isEmpty) {
    throw ArgumentError.value(values, 'provenance', 'must not be empty');
  }
  final identities = <String>{};
  for (final source in result) {
    final identity = '${source.authority.name}:${source.sourceId}';
    if (!identities.add(identity)) {
      throw ArgumentError.value(
        identity,
        'provenance',
        'contains a duplicate authority identity',
      );
    }
  }
  result.sort(_compareProvenance);
  return List<ReviewReasonProvenance>.unmodifiable(result);
}

int _compareProvenance(
  ReviewReasonProvenance left,
  ReviewReasonProvenance right,
) {
  var result = left.reason.priority.compareTo(right.reason.priority);
  if (result != 0) return result;
  result = left.priorityTimeUtc.compareTo(right.priorityTimeUtc);
  if (result != 0) return result;
  result = left.authority.index.compareTo(right.authority.index);
  if (result != 0) return result;
  return left.sourceId.compareTo(right.sourceId);
}

void _requireCanonicalText(String value, String name) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.runes.length > 256 ||
      _controlText.hasMatch(value)) {
    throw ArgumentError.value(value, name, 'must be canonical nonblank text');
  }
}

void _requireUtc(DateTime value, String name) {
  if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
    throw ArgumentError.value(value, name, 'must be a nonnegative UTC time');
  }
}

final RegExp _controlText = RegExp(
  r'[\u0000-\u001f\u007f-\u009f]',
  unicode: true,
);
