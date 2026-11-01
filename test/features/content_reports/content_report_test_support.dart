import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report_transport.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

ContentReportPayload syntheticReport({
  String id = 'content-report:synthetic',
}) => ContentReportPayload.create(
  reportId: id,
  target: ContentReportTarget.tutorReply(
    text: 'Selected synthetic reply',
    isExcerpt: false,
    replyId: 'synthetic-reply',
    modelVersion: 'synthetic-model',
    generatedAtUtcMs: 1,
  ),
  reason: ReportReason.spelling,
  comment: null,
  queuedAtUtc: DateTime.fromMillisecondsSinceEpoch(2, isUtc: true),
);

ContentReportAcknowledgement syntheticAcknowledgement(
  ContentReportPayload payload,
) => ContentReportAcknowledgement.fromJson({
  'schemaVersion': 1,
  'receipt': {
    'reportId': payload.reportId,
    'reportSha256': payload.reportSha256,
    'receiptId': 'content-report-receipt:${'a' * 64}',
    'receivedAtUtc': '2026-11-01T00:00:00.000Z',
  },
  'moderation': {
    'revision': 1,
    'status': 'received',
    'decisionId': null,
    'publicNote': null,
    'decidedAtUtc': null,
  },
});

final class MemoryContentReportQueue implements ContentReportQueue {
  final rows = <String, ContentReportRecord>{};
  String activeOwner = 'owner';
  int acknowledged = 0;
  void check(String owner) {
    if (owner != activeOwner) {
      throw const ContentReportException(ContentReportFailureCode.ownerChanged);
    }
  }

  @override
  Future<ContentReportRecord> put({
    required String expectedOwnerId,
    required ContentReportPayload payload,
  }) async {
    check(expectedOwnerId);
    final existing = rows[payload.reportId];
    if (existing != null &&
        (existing.ownerId != expectedOwnerId ||
            existing.payload.reportJson != payload.reportJson)) {
      throw const ContentReportException(ContentReportFailureCode.collision);
    }
    return rows.putIfAbsent(
      payload.reportId,
      () => ContentReportRecord(ownerId: expectedOwnerId, payload: payload),
    );
  }

  @override
  Future<ContentReportRecord?> read({
    required String expectedOwnerId,
    required String reportId,
  }) async {
    check(expectedOwnerId);
    final row = rows[reportId];
    return row?.ownerId == expectedOwnerId ? row : null;
  }

  @override
  Stream<List<ContentReportRecord>> watchOwner(String expectedOwnerId) async* {
    check(expectedOwnerId);
    yield rows.values.where((r) => r.ownerId == expectedOwnerId).toList();
  }

  @override
  Future<ContentReportRecord> markUnconfirmed({
    required String expectedOwnerId,
    required String reportId,
    required String expectedReportSha256,
  }) async {
    check(expectedOwnerId);
    final row = rows[reportId]!;
    if (row.ownerId != expectedOwnerId ||
        row.payload.reportSha256 != expectedReportSha256) {
      throw const ContentReportException(ContentReportFailureCode.collision);
    }
    if (row.acknowledgement != null) return row;
    return rows[reportId] = ContentReportRecord(
      ownerId: row.ownerId,
      payload: row.payload,
      delivery: ContentReportDelivery.unconfirmed,
      localRevision: row.localRevision + 1,
    );
  }

  @override
  Future<ContentReportRecord> acknowledge({
    required String expectedOwnerId,
    required String expectedFirebaseUid,
    required String expectedReportSha256,
    required ContentReportAcknowledgement acknowledgement,
  }) async {
    check(expectedOwnerId);
    final row = rows[acknowledgement.receipt.reportId]!;
    if (row.ownerId != expectedOwnerId ||
        row.payload.reportSha256 != expectedReportSha256) {
      throw const ContentReportException(ContentReportFailureCode.collision);
    }
    acknowledgement.requireMatches(row.payload);
    if (row.acknowledgedFirebaseUid != null &&
        row.acknowledgedFirebaseUid != expectedFirebaseUid) {
      throw const ContentReportException(ContentReportFailureCode.ownerChanged);
    }
    if (row.acknowledgement case final previous?) {
      acknowledgement.requireSuccessor(previous);
    }
    acknowledged++;
    return rows[row.payload.reportId] = ContentReportRecord(
      ownerId: row.ownerId,
      payload: row.payload,
      delivery: ContentReportDelivery.received,
      acknowledgement: acknowledgement,
      acknowledgedFirebaseUid: expectedFirebaseUid,
      localRevision: row.localRevision + 1,
    );
  }
}

final class FakeContentReportTransport implements ContentReportTransport {
  @override
  bool enabled = true;
  @override
  ContentReportIdentityBinding? currentBinding = ContentReportIdentityBinding(
    ownerId: 'owner',
    firebaseUid: 'synthetic-uid',
    generation: 1,
  );
  int submissions = 0;
  int reads = 0;
  bool loseAcknowledgement = false;
  bool receiptAbsent = false;
  final sentBytes = <String>[];
  void Function()? onRead;
  @override
  Future<void> requireCurrent(ContentReportIdentityBinding binding) async {
    if (currentBinding != binding) {
      throw const ContentReportException(ContentReportFailureCode.ownerChanged);
    }
  }

  @override
  Future<ContentReportAcknowledgement> submit(
    ContentReportIdentityBinding binding,
    ContentReportPayload payload,
  ) async {
    await requireCurrent(binding);
    submissions++;
    sentBytes.add(payload.reportJson);
    if (loseAcknowledgement) {
      throw const ContentReportException(ContentReportFailureCode.unconfirmed);
    }
    return syntheticAcknowledgement(payload);
  }

  @override
  Future<ContentReportAcknowledgement?> readReceipt(
    ContentReportIdentityBinding binding,
    ContentReportPayload payload,
  ) async {
    reads++;
    onRead?.call();
    await requireCurrent(binding);
    return receiptAbsent ? null : syntheticAcknowledgement(payload);
  }
}
