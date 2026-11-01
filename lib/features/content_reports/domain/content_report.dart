import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../vocabulary/domain/word_report.dart';

const contentReportTargetVersion = 'content-report-target-v2';

enum ContentReportDelivery { queued, unconfirmed, received }

enum ContentReportAiOrigin { generated, fallback, unrecorded }

enum ContentReportDocumentIdentity { supplied, contentDigest }

enum ContentReportModerationStatus { received, resolved, dismissed }

enum ContentReportFailureCode {
  disabled,
  accountRequired,
  ownerChanged,
  unavailable,
  collision,
  invalidResponse,
  unconfirmed,
  rejected,
  retryLater,
}

final class ContentReportException implements Exception {
  const ContentReportException(this.code);
  final ContentReportFailureCode code;
  @override
  String toString() => 'ContentReportException(${code.name})';
}

final class ContentReportTarget {
  ContentReportTarget._(
    this.snapshotJson,
    this.snapshotSha256,
    this.kind,
    this.text,
    this.isExcerpt,
  );

  factory ContentReportTarget.ownedWord(WordReportTarget target) =>
      ContentReportTarget._(
        target.snapshotJson,
        target.snapshotSha256,
        'ownedWord',
        '${target.spelling}\n${target.meaning}\n${target.partOfSpeech}',
        false,
      );

  factory ContentReportTarget.packEntry({
    required String text,
    required bool isExcerpt,
    required String packId,
    required String packVersion,
    required String packageSha256,
    required String entryCode,
    required String entrySha256,
  }) => ContentReportTarget._create('packEntry', text, isExcerpt, {
    'packId': packId,
    'packVersion': packVersion,
    'packageSha256': packageSha256,
    'entryCode': entryCode,
    'entrySha256': entrySha256,
  });

  factory ContentReportTarget.aiOutput({
    required String text,
    required bool isExcerpt,
    required String sessionId,
    required String acceptedPlanId,
    required String contentKind,
    required String modelVersion,
    required bool cached,
    required ContentReportAiOrigin origin,
  }) => ContentReportTarget._create('aiOutput', text, isExcerpt, {
    'sessionId': sessionId,
    'acceptedPlanId': acceptedPlanId,
    'contentKind': contentKind,
    'modelVersion': modelVersion,
    'cached': cached,
    'origin': origin.name,
  });

  factory ContentReportTarget.tutorReply({
    required String text,
    required bool isExcerpt,
    required String replyId,
    required String modelVersion,
    required int generatedAtUtcMs,
  }) => ContentReportTarget._create('tutorReply', text, isExcerpt, {
    'replyId': replyId,
    'modelVersion': modelVersion,
    'generatedAtUtcMs': generatedAtUtcMs,
  });

  factory ContentReportTarget.readingDocument({
    required String text,
    required bool isExcerpt,
    required String documentId,
    required int documentRevision,
    required String documentSha256,
    required ContentReportDocumentIdentity identityKind,
  }) => ContentReportTarget._create('readingDocument', text, isExcerpt, {
    'documentId': documentId,
    'documentRevision': documentRevision,
    'documentSha256': documentSha256,
    'identityKind': identityKind.name,
  });

  static ContentReportTarget _create(
    String kind,
    String text,
    bool excerpt,
    Map<String, Object?> source,
  ) {
    final json = jsonEncode({
      'version': contentReportTargetVersion,
      'kind': kind,
      'text': text,
      'textSha256': contentReportDigest(text),
      'isExcerpt': excerpt,
      'source': source,
    });
    try {
      return ContentReportTarget.fromSnapshot(
        snapshotJson: json,
        snapshotSha256: contentReportDigest(json),
      );
    } on FormatException {
      throw ArgumentError('Invalid content report target or selection');
    }
  }

  factory ContentReportTarget.fromSnapshot({
    required String snapshotJson,
    required String snapshotSha256,
  }) {
    if (!_digest(snapshotSha256) ||
        contentReportDigest(snapshotJson) != snapshotSha256) {
      _invalid();
    }
    final value = contentReportDecodeJson(snapshotJson, maximumBytes: 16384);
    if (value is! Map<String, dynamic>) _invalid();
    if (value['version'] == wordReportSnapshotVersion) {
      return ContentReportTarget.ownedWord(
        WordReportTarget.fromSnapshot(
          snapshotJson: snapshotJson,
          snapshotSha256: snapshotSha256,
        ),
      );
    }
    _keys(value, {
      'version',
      'kind',
      'text',
      'textSha256',
      'isExcerpt',
      'source',
    });
    if (value['version'] != contentReportTargetVersion ||
        value['isExcerpt'] is! bool) {
      _invalid();
    }
    final text = _text(value['text'], maximum: 4096, maximumBytes: 16384);
    if (!_digest(value['textSha256']) ||
        contentReportDigest(text) != value['textSha256']) {
      _invalid();
    }
    final source = value['source'];
    if (source is! Map<String, dynamic>) _invalid();
    final kind = value['kind'];
    switch (kind) {
      case 'packEntry':
        _keys(source, {
          'packId',
          'packVersion',
          'packageSha256',
          'entryCode',
          'entrySha256',
        });
        for (final key in ['packId', 'packVersion', 'entryCode']) {
          _text(source[key]);
        }
        for (final key in ['packageSha256', 'entrySha256']) {
          if (!_digest(source[key])) _invalid();
        }
      case 'aiOutput':
        _keys(source, {
          'sessionId',
          'acceptedPlanId',
          'contentKind',
          'modelVersion',
          'cached',
          'origin',
        });
        for (final key in ['sessionId', 'acceptedPlanId', 'contentKind']) {
          _text(source[key]);
        }
        _text(source['modelVersion'], maximum: 512);
        if (source['cached'] is! bool ||
            !['generated', 'fallback', 'unrecorded'].contains(source['origin'])) {
          _invalid();
        }
      case 'tutorReply':
        _keys(source, {'replyId', 'modelVersion', 'generatedAtUtcMs'});
        _text(source['replyId']);
        _text(source['modelVersion'], maximum: 512);
        _integer(source['generatedAtUtcMs']);
      case 'readingDocument':
        _keys(source, {
          'documentId',
          'documentRevision',
          'documentSha256',
          'identityKind',
        });
        _text(source['documentId']);
        _integer(
          source['documentRevision'],
          minimum: 1,
          maximum: 0x7fffffffffffffff,
        );
        if (!_digest(source['documentSha256']) ||
            !['supplied', 'contentDigest'].contains(source['identityKind'])) {
          _invalid();
        }
      default:
        _invalid();
    }
    return ContentReportTarget._(
      snapshotJson,
      snapshotSha256,
      kind as String,
      text,
      value['isExcerpt'] as bool,
    );
  }

  final String snapshotJson;
  final String snapshotSha256;
  final String kind;
  final String text;
  final bool isExcerpt;
}

final class ContentReportPayload {
  ContentReportPayload._({
    required this.reportId,
    required this.reportJson,
    required this.reportSha256,
    required this.target,
    required this.reason,
    required this.comment,
    required this.queuedAtUtc,
  });

  factory ContentReportPayload.create({
    required String reportId,
    required ContentReportTarget target,
    required ReportReason reason,
    required String? comment,
    required DateTime queuedAtUtc,
  }) {
    if (!queuedAtUtc.isUtc ||
        queuedAtUtc.microsecondsSinceEpoch < 0 ||
        queuedAtUtc.microsecondsSinceEpoch % 1000 != 0) {
      throw ArgumentError(
        'Content report time must be nonnegative UTC milliseconds',
      );
    }
    final json = jsonEncode({
      'schemaVersion': 1,
      'reportId': reportId,
      'snapshotJson': target.snapshotJson,
      'snapshotSha256': target.snapshotSha256,
      'reason': reason.name,
      'comment': comment,
      'queuedAtUtcMs': queuedAtUtc.millisecondsSinceEpoch,
    });
    try {
      return ContentReportPayload.fromStorage(
        reportJson: json,
        reportSha256: contentReportDigest(json),
      );
    } on FormatException {
      throw ArgumentError('Invalid content report payload');
    }
  }

  factory ContentReportPayload.fromWordReport(StoredWordReport report) =>
      ContentReportPayload.create(
        reportId: report.id,
        target: ContentReportTarget.ownedWord(report.target),
        reason: report.reason,
        comment: report.comment,
        queuedAtUtc: report.queuedAtUtc,
      );

  factory ContentReportPayload.fromStorage({
    required String reportJson,
    required String reportSha256,
  }) {
    if (!_digest(reportSha256) ||
        contentReportDigest(reportJson) != reportSha256) {
      _invalid();
    }
    final value =
        _keys(contentReportDecodeJson(reportJson, maximumBytes: 32768), {
          'schemaVersion',
          'reportId',
          'snapshotJson',
          'snapshotSha256',
          'reason',
          'comment',
          'queuedAtUtcMs',
        });
    if (value['schemaVersion'] != 1 || value['schemaVersion'] is! int) {
      _invalid();
    }
    final id = _text(value['reportId'], maximumBytes: 256);
    final prefix = id.startsWith('word-report:')
        ? 'word-report:'
        : 'content-report:';
    if (!id.startsWith(prefix) || id.substring(prefix.length).trim().isEmpty) {
      _invalid();
    }
    final targetJson = value['snapshotJson'];
    final targetDigest = value['snapshotSha256'];
    if (targetJson is! String || targetDigest is! String) _invalid();
    final reason = ReportReason.values
        .where((r) => r.name == value['reason'])
        .firstOrNull;
    if (reason == null) _invalid();
    final comment = value['comment'];
    if (comment != null) {
      _text(comment, maximum: 500, maximumBytes: 2048, trimmed: true);
    }
    if (reason == ReportReason.other && comment == null) _invalid();
    return ContentReportPayload._(
      reportId: id,
      reportJson: reportJson,
      reportSha256: reportSha256,
      target: ContentReportTarget.fromSnapshot(
        snapshotJson: targetJson,
        snapshotSha256: targetDigest,
      ),
      reason: reason,
      comment: comment as String?,
      queuedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        _integer(value['queuedAtUtcMs']),
        isUtc: true,
      ),
    );
  }
  final String reportId;
  final String reportJson;
  final String reportSha256;
  final ContentReportTarget target;
  final ReportReason reason;
  final String? comment;
  final DateTime queuedAtUtc;
  Map<String, Object?> toSubmissionJson() => {
    'schemaVersion': 1,
    'reportJson': reportJson,
    'reportSha256': reportSha256,
  };
}

final class ContentReportReceipt {
  ContentReportReceipt._(
    this.reportId,
    this.reportSha256,
    this.receiptId,
    this.receivedAtUtc,
  );
  factory ContentReportReceipt.fromJson(Object? raw) {
    final value = _keys(raw, {
      'reportId',
      'reportSha256',
      'receiptId',
      'receivedAtUtc',
    });
    final id = _text(value['reportId'], maximumBytes: 256);
    final receipt = _text(value['receiptId']);
    if (!_digest(value['reportSha256']) ||
        receipt.length != 'content-report-receipt:'.length + 64 ||
        !RegExp(r'^content-report-receipt:[a-f0-9]{64}$').hasMatch(receipt)) {
      _invalid();
    }
    return ContentReportReceipt._(
      id,
      value['reportSha256'] as String,
      receipt,
      _utc(value['receivedAtUtc']),
    );
  }
  final String reportId;
  final String reportSha256;
  final String receiptId;
  final DateTime receivedAtUtc;
  Map<String, Object?> toJson() => {
    'reportId': reportId,
    'reportSha256': reportSha256,
    'receiptId': receiptId,
    'receivedAtUtc': receivedAtUtc.toIso8601String(),
  };
  bool sameReceipt(ContentReportReceipt other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());
}

final class ContentReportModeration {
  ContentReportModeration._(
    this.revision,
    this.status,
    this.decisionId,
    this.publicNote,
    this.decidedAtUtc,
  );
  factory ContentReportModeration.fromJson(Object? raw) {
    final value = _keys(raw, {
      'revision',
      'status',
      'decisionId',
      'publicNote',
      'decidedAtUtc',
    });
    final status = ContentReportModerationStatus.values
        .where((s) => s.name == value['status'])
        .firstOrNull;
    if (status == null) _invalid();
    final revision = _integer(value['revision'], minimum: 1, maximum: 2);
    if (status == ContentReportModerationStatus.received) {
      if (revision != 1 ||
          value['decisionId'] != null ||
          value['publicNote'] != null ||
          value['decidedAtUtc'] != null) {
        _invalid();
      }
      return ContentReportModeration._(revision, status, null, null, null);
    }
    if (revision != 2) _invalid();
    return ContentReportModeration._(
      revision,
      status,
      _text(value['decisionId'], maximumBytes: 256),
      _text(
        value['publicNote'],
        maximum: 500,
        maximumBytes: 2048,
        trimmed: true,
      ),
      _utc(value['decidedAtUtc']),
    );
  }
  final int revision;
  final ContentReportModerationStatus status;
  final String? decisionId;
  final String? publicNote;
  final DateTime? decidedAtUtc;
  Map<String, Object?> toJson() => {
    'revision': revision,
    'status': status.name,
    'decisionId': decisionId,
    'publicNote': publicNote,
    'decidedAtUtc': decidedAtUtc?.toIso8601String(),
  };
}

final class ContentReportAcknowledgement {
  ContentReportAcknowledgement({
    required this.receipt,
    required this.moderation,
  }) {
    if (moderation.decidedAtUtc?.isBefore(receipt.receivedAtUtc) == true) {
      _invalid();
    }
  }
  factory ContentReportAcknowledgement.fromJson(Object? raw) {
    final value = _keys(raw, {'schemaVersion', 'receipt', 'moderation'});
    if (value['schemaVersion'] is! int || value['schemaVersion'] != 1) {
      _invalid();
    }
    return ContentReportAcknowledgement(
      receipt: ContentReportReceipt.fromJson(value['receipt']),
      moderation: ContentReportModeration.fromJson(value['moderation']),
    );
  }
  factory ContentReportAcknowledgement.fromResponseJson(String json) =>
      ContentReportAcknowledgement.fromJson(
        contentReportDecodeJson(json, maximumBytes: 16384),
      );
  final ContentReportReceipt receipt;
  final ContentReportModeration moderation;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'receipt': receipt.toJson(),
    'moderation': moderation.toJson(),
  };
  void requireMatches(ContentReportPayload payload) {
    if (receipt.reportId != payload.reportId ||
        receipt.reportSha256 != payload.reportSha256) {
      throw const ContentReportException(
        ContentReportFailureCode.invalidResponse,
      );
    }
  }

  void requireSuccessor(ContentReportAcknowledgement previous) {
    if (!receipt.sameReceipt(previous.receipt) ||
        moderation.revision < previous.moderation.revision ||
        (moderation.revision == previous.moderation.revision &&
            jsonEncode(moderation.toJson()) !=
                jsonEncode(previous.moderation.toJson()))) {
      throw const ContentReportException(
        ContentReportFailureCode.invalidResponse,
      );
    }
  }
}

final class ContentReportRecord {
  ContentReportRecord({
    required this.ownerId,
    required this.payload,
    this.delivery = ContentReportDelivery.queued,
    this.acknowledgement,
    this.acknowledgedFirebaseUid,
    this.localRevision = 1,
  }) {
    _text(ownerId);
    if (localRevision < 1 ||
        (delivery == ContentReportDelivery.received) !=
            (acknowledgement != null) ||
        (acknowledgement != null) != (acknowledgedFirebaseUid != null)) {
      _invalid();
    }
    if (acknowledgedFirebaseUid != null) {
      _text(acknowledgedFirebaseUid, maximum: 128, trimmed: true);
    }
    acknowledgement?.requireMatches(payload);
  }
  final String ownerId;
  final ContentReportPayload payload;
  final ContentReportDelivery delivery;
  final ContentReportAcknowledgement? acknowledgement;
  final String? acknowledgedFirebaseUid;
  final int localRevision;
}

abstract interface class ContentReportQueue {
  Future<ContentReportRecord> put({
    required String expectedOwnerId,
    required ContentReportPayload payload,
  });
  Future<ContentReportRecord?> read({
    required String expectedOwnerId,
    required String reportId,
  });
  Stream<List<ContentReportRecord>> watchOwner(String expectedOwnerId);
  Future<ContentReportRecord> markUnconfirmed({
    required String expectedOwnerId,
    required String reportId,
    required String expectedReportSha256,
  });
  Future<ContentReportRecord> acknowledge({
    required String expectedOwnerId,
    required String expectedFirebaseUid,
    required String expectedReportSha256,
    required ContentReportAcknowledgement acknowledgement,
  });
}

String contentReportDigest(String value) {
  _unicode(value);
  return sha256.convert(utf8.encode(value)).toString();
}

Object? contentReportDecodeJson(String text, {required int maximumBytes}) {
  _unicode(text);
  if (utf8.encode(text).length > maximumBytes) _invalid();
  // Match the pack codec's duplicate-key protection before jsonDecode loses keys.
  final containers = <_JsonKeys?>[];
  var quote = -1;
  var escaped = false;
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if (quote >= 0) {
      if (escaped) {
        escaped = false;
      } else if (unit == 92) {
        escaped = true;
      } else if (unit == 34) {
        final object = containers.isEmpty ? null : containers.last;
        if (object != null && object.expectingKey) {
          final key = jsonDecode(text.substring(quote, index + 1)) as String;
          if (!object.keys.add(key)) _invalid();
          object.expectingKey = false;
        }
        quote = -1;
      }
    } else if (unit == 34) {
      quote = index;
    } else if (unit == 91 || unit == 123) {
      if (containers.length == 16) _invalid();
      containers.add(unit == 123 ? _JsonKeys() : null);
    } else if (unit == 93 || unit == 125) {
      if (containers.isEmpty || (unit == 125) != (containers.last != null)) {
        _invalid();
      }
      containers.removeLast();
    } else if (unit == 44 && containers.isNotEmpty) {
      containers.last?.expectingKey = true;
    }
  }
  if (quote >= 0 || containers.isNotEmpty) _invalid();
  final decoded = jsonDecode(text);
  var nodes = 0;
  void inspect(Object? value) {
    if (++nodes > 2048) _invalid();
    if (value is String) _unicode(value);
    if (value is Map) {
      for (final entry in value.entries) {
        _unicode(entry.key as String);
        inspect(entry.value);
      }
    }
    if (value is List) {
      for (final child in value) {
        inspect(child);
      }
    }
  }

  inspect(decoded);
  return decoded;
}

final class _JsonKeys {
  final keys = <String>{};
  bool expectingKey = true;
}

Map<String, dynamic> _keys(Object? value, Set<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !value.keys.every(keys.contains)) {
    _invalid();
  }
  return value;
}

String _text(
  Object? value, {
  int maximum = 256,
  int? maximumBytes,
  bool trimmed = false,
}) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.runes.length > maximum ||
      (trimmed && value != value.trim()) ||
      (maximumBytes != null && utf8.encode(value).length > maximumBytes)) {
    _invalid();
  }
  _unicode(value);
  return value;
}

int _integer(Object? value, {int minimum = 0, int maximum = 8640000000000000}) {
  if (value is! int || value < minimum || value > maximum) _invalid();
  return value;
}

bool _digest(Object? value) =>
    value is String &&
    value.length == 64 &&
    RegExp(r'^[a-f0-9]{64}$').hasMatch(value);
DateTime _utc(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$').hasMatch(value)) {
    _invalid();
  }
  final parsed = DateTime.parse(value);
  if (parsed.millisecondsSinceEpoch < 0 || parsed.toIso8601String() != value) {
    _invalid();
  }
  return parsed;
}

void _unicode(String value) {
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index >= value.length) _invalid();
      final low = value.codeUnitAt(index);
      if (low < 0xdc00 || low > 0xdfff) _invalid();
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      _invalid();
    }
  }
}

Never _invalid() => throw const FormatException('Invalid content report data');
