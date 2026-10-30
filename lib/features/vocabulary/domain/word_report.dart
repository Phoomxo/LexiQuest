import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'vocabulary_word.dart';

const wordReportIdPrefix = 'word-report:';
const wordReportSnapshotVersion = 'owned-word-report-v1';
const wordReportIdMaxBytes = 256;
const wordReportIdentifierMaxRunes = 256;
const wordReportSnapshotMaxBytes = 8192;
const wordReportCommentMaxRunes = 500;
const wordReportCommentMaxBytes = 2048;
const wordReportMaxRevision = 0x7fffffffffffffff;

enum ReportReason {
  incorrectMeaning,
  spelling,
  partOfSpeech,
  inappropriate,
  other,
}

final class WordReportTarget {
  WordReportTarget._({
    required this.wordId,
    required this.categoryId,
    required this.wordRevision,
    required this.spelling,
    required this.meaning,
    required this.partOfSpeech,
    required this.source,
    required this.cefrLevel,
  }) {
    _identifier(wordId);
    _identifier(categoryId);
    if (wordRevision < 1 || wordRevision > wordReportMaxRevision) {
      throw ArgumentError('Invalid word-report revision');
    }
    _content(spelling, 120);
    _content(meaning, 500);
    _content(partOfSpeech, 60);
    _content(source, 60);
    if (cefrLevel case final value?) {
      _content(value, 12);
    }
    _snapshotJson = jsonEncode({
      'version': wordReportSnapshotVersion,
      'wordId': wordId,
      'categoryId': categoryId,
      'wordRevision': wordRevision,
      'spelling': spelling,
      'meaning': meaning,
      'partOfSpeech': partOfSpeech,
      'source': source,
      'cefrLevel': cefrLevel,
    });
    final bytes = utf8.encode(_snapshotJson);
    if (bytes.length > wordReportSnapshotMaxBytes) {
      throw ArgumentError('Word-report snapshot is too large');
    }
    _snapshotSha256 = sha256.convert(bytes).toString();
  }

  factory WordReportTarget.fromWord(VocabularyWord word) => WordReportTarget._(
    wordId: word.id,
    categoryId: word.categoryId,
    wordRevision: word.localRevision,
    spelling: word.spelling,
    meaning: word.meaning,
    partOfSpeech: word.partOfSpeech,
    source: word.source,
    cefrLevel: word.cefrLevel,
  );

  factory WordReportTarget.fromSnapshot({
    required String snapshotJson,
    required String snapshotSha256,
  }) {
    const keys = {
      'version',
      'wordId',
      'categoryId',
      'wordRevision',
      'spelling',
      'meaning',
      'partOfSpeech',
      'source',
      'cefrLevel',
    };
    final snapshotBytes = utf8.encode(snapshotJson);
    if (snapshotBytes.length > wordReportSnapshotMaxBytes ||
        snapshotSha256.length != 64 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(snapshotSha256) ||
        sha256.convert(snapshotBytes).toString() != snapshotSha256) {
      throw const FormatException('Invalid word-report snapshot');
    }
    try {
      final value = jsonDecode(snapshotJson);
      if (value is! Map<String, dynamic> ||
          value.length != keys.length ||
          !value.keys.every(keys.contains) ||
          value['version'] != wordReportSnapshotVersion ||
          value['wordId'] is! String ||
          value['categoryId'] is! String ||
          value['wordRevision'] is! int ||
          value['spelling'] is! String ||
          value['meaning'] is! String ||
          value['partOfSpeech'] is! String ||
          value['source'] is! String ||
          (value['cefrLevel'] != null && value['cefrLevel'] is! String)) {
        throw const FormatException('Invalid word-report snapshot');
      }
      final target = WordReportTarget._(
        wordId: value['wordId'] as String,
        categoryId: value['categoryId'] as String,
        wordRevision: value['wordRevision'] as int,
        spelling: value['spelling'] as String,
        meaning: value['meaning'] as String,
        partOfSpeech: value['partOfSpeech'] as String,
        source: value['source'] as String,
        cefrLevel: value['cefrLevel'] as String?,
      );
      if (target.snapshotJson != snapshotJson ||
          target.snapshotSha256 != snapshotSha256) {
        throw const FormatException('Invalid word-report snapshot');
      }
      return target;
    } on ArgumentError {
      throw const FormatException('Invalid word-report snapshot');
    } on FormatException {
      throw const FormatException('Invalid word-report snapshot');
    }
  }

  final String wordId;
  final String categoryId;
  final int wordRevision;
  final String spelling;
  final String meaning;
  final String partOfSpeech;
  final String source;
  final String? cefrLevel;
  late final String _snapshotJson;
  late final String _snapshotSha256;
  String get snapshotJson => _snapshotJson;
  String get snapshotSha256 => _snapshotSha256;

  bool sameTarget(WordReportTarget other) => snapshotJson == other.snapshotJson;
}

final class WordReportCommand {
  WordReportCommand({
    required this.id,
    required this.expectedOwnerId,
    required this.target,
    required this.reason,
    required this.comment,
    required this.queuedAtUtc,
  }) {
    _reportFields(id, expectedOwnerId, reason, comment, queuedAtUtc);
  }

  final String id;
  final String expectedOwnerId;
  final WordReportTarget target;
  final ReportReason reason;
  final String? comment;
  final DateTime queuedAtUtc;
}

final class StoredWordReport {
  StoredWordReport({
    required this.id,
    required this.ownerId,
    required this.target,
    required this.reason,
    required this.comment,
    required this.queuedAtUtc,
  }) {
    _reportFields(id, ownerId, reason, comment, queuedAtUtc);
  }

  factory StoredWordReport.fromStorage(Map<String, Object?> row) {
    const fields = {
      'id',
      'owner_id',
      'word_id',
      'category_id',
      'word_revision',
      'snapshot_json',
      'snapshot_sha256',
      'reason',
      'comment',
      'queued_at_utc_ms',
    };
    if (row.length != fields.length || !row.keys.every(fields.contains)) {
      throw const FormatException('Invalid stored word report');
    }
    final id = row['id'];
    final owner = row['owner_id'];
    final word = row['word_id'];
    final category = row['category_id'];
    final revision = row['word_revision'];
    final json = row['snapshot_json'];
    final hash = row['snapshot_sha256'];
    final reasonName = row['reason'];
    final comment = row['comment'];
    final queued = row['queued_at_utc_ms'];
    if (id is! String ||
        owner is! String ||
        word is! String ||
        category is! String ||
        revision is! int ||
        json is! String ||
        hash is! String ||
        reasonName is! String ||
        (comment != null && comment is! String) ||
        queued is! int ||
        queued < 0 ||
        queued > 8640000000000000) {
      throw const FormatException('Invalid stored word report');
    }
    final reason = ReportReason.values
        .where((value) => value.name == reasonName)
        .firstOrNull;
    if (reason == null) {
      throw const FormatException('Invalid stored word report');
    }
    try {
      final target = WordReportTarget.fromSnapshot(
        snapshotJson: json,
        snapshotSha256: hash,
      );
      if (target.wordId != word ||
          target.categoryId != category ||
          target.wordRevision != revision) {
        throw const FormatException('Invalid stored word report');
      }
      return StoredWordReport(
        id: id,
        ownerId: owner,
        target: target,
        reason: reason,
        comment: comment as String?,
        queuedAtUtc: DateTime.fromMillisecondsSinceEpoch(queued, isUtc: true),
      );
    } on ArgumentError {
      throw const FormatException('Invalid stored word report');
    } on FormatException {
      throw const FormatException('Invalid stored word report');
    }
  }

  final String id;
  final String ownerId;
  final WordReportTarget target;
  final ReportReason reason;
  final String? comment;
  final DateTime queuedAtUtc;

  Map<String, Object?> toStorage() => Map<String, Object?>.unmodifiable({
    'id': id,
    'owner_id': ownerId,
    'word_id': target.wordId,
    'category_id': target.categoryId,
    'word_revision': target.wordRevision,
    'snapshot_json': target.snapshotJson,
    'snapshot_sha256': target.snapshotSha256,
    'reason': reason.name,
    'comment': comment,
    'queued_at_utc_ms': queuedAtUtc.millisecondsSinceEpoch,
  });

  bool matchesCommand(WordReportCommand command) =>
      (id, ownerId, target.snapshotJson, reason, comment, queuedAtUtc) ==
      (
        command.id,
        command.expectedOwnerId,
        command.target.snapshotJson,
        command.reason,
        command.comment,
        command.queuedAtUtc,
      );

  bool sameHistoricalPayload(StoredWordReport other) =>
      (
        id,
        target.wordId,
        target.categoryId,
        target.wordRevision,
        target.snapshotJson,
        target.snapshotSha256,
        reason,
        comment,
        queuedAtUtc,
      ) ==
      (
        other.id,
        other.target.wordId,
        other.target.categoryId,
        other.target.wordRevision,
        other.target.snapshotJson,
        other.target.snapshotSha256,
        other.reason,
        other.comment,
        other.queuedAtUtc,
      );

  bool sameFacts(StoredWordReport other) =>
      ownerId == other.ownerId && sameHistoricalPayload(other);
}

enum SubmitStatus { queued, replayed }

final class SubmitResult {
  const SubmitResult({required this.status, required this.report});
  final SubmitStatus status;
  final StoredWordReport report;
}

enum WordReportFailureCode { staleTarget, collision, unavailable }

final class WordReportException implements Exception {
  const WordReportException(this.code);
  final WordReportFailureCode code;

  @override
  String toString() => 'WordReportException(${code.name})';
}

abstract interface class WordReportRepository {
  Future<SubmitResult> submit(WordReportCommand command);
  Stream<List<StoredWordReport>> watchOwner(String expectedOwnerId);
}

void _identifier(String value) {
  if (value.trim().isEmpty ||
      value.runes.length > wordReportIdentifierMaxRunes) {
    throw ArgumentError('Invalid word-report identifier');
  }
}

void _content(String value, int maxLength) {
  if (value.trim().isEmpty || value.length > maxLength) {
    throw ArgumentError('Invalid word-report content');
  }
}

void _reportFields(
  String id,
  String ownerId,
  ReportReason reason,
  String? comment,
  DateTime at,
) {
  if (!id.startsWith(wordReportIdPrefix) ||
      id.substring(wordReportIdPrefix.length).trim().isEmpty ||
      utf8.encode(id).length > wordReportIdMaxBytes) {
    throw ArgumentError('Invalid word-report identity');
  }
  _identifier(ownerId);
  if (comment != null &&
      (comment.trim().isEmpty ||
          comment != comment.trim() ||
          comment.runes.length > wordReportCommentMaxRunes ||
          utf8.encode(comment).length > wordReportCommentMaxBytes)) {
    throw ArgumentError('Invalid word-report comment');
  }
  if (reason == ReportReason.other && comment == null) {
    throw ArgumentError('Other report reason requires a comment');
  }
  if (!at.isUtc ||
      at.microsecondsSinceEpoch < 0 ||
      at.microsecondsSinceEpoch % 1000 != 0) {
    throw ArgumentError(
      'Word-report time must be nonnegative UTC milliseconds',
    );
  }
}
