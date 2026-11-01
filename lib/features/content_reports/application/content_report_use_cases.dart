import '../../vocabulary/domain/word_report.dart';
import '../domain/content_report.dart';
import '../domain/content_report_transport.dart';

typedef ContentReportOrdinarySessionGuard =
    Future<void> Function({
      required String expectedOwnerId,
      required String sessionId,
      required bool Function() stillCurrent,
    });

final class ContentReportUseCases {
  const ContentReportUseCases({
    required this.queue,
    required this.generateId,
    required this.nowUtc,
    this.transport = const DisabledContentReportTransport(),
    this.ordinarySessionGuard,
  });

  final ContentReportQueue queue;
  final String Function() generateId;
  final DateTime Function() nowUtc;
  final ContentReportTransport transport;
  final ContentReportOrdinarySessionGuard? ordinarySessionGuard;

  Future<void> requireOrdinarySession({
    required String expectedOwnerId,
    required String sessionId,
    required bool Function() stillCurrent,
  }) async {
    final guard = ordinarySessionGuard;
    if (guard == null || !stillCurrent()) {
      throw const ContentReportException(ContentReportFailureCode.unavailable);
    }
    await guard(
      expectedOwnerId: expectedOwnerId,
      sessionId: sessionId,
      stillCurrent: stillCurrent,
    );
    if (!stillCurrent()) {
      throw const ContentReportException(ContentReportFailureCode.ownerChanged);
    }
  }

  ContentReportPayload prepare({
    required ContentReportTarget target,
    required ReportReason reason,
    String? comment,
  }) {
    final now = nowUtc();
    if (!now.isUtc || now.microsecondsSinceEpoch < 0) {
      throw ArgumentError('Content report clock must be nonnegative UTC');
    }
    final normalized = comment?.trim();
    return ContentReportPayload.create(
      reportId: 'content-report:${generateId()}',
      target: target,
      reason: reason,
      comment: normalized == null || normalized.isEmpty ? null : normalized,
      queuedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        now.millisecondsSinceEpoch,
        isUtc: true,
      ),
    );
  }

  Future<ContentReportRecord> save({
    required String expectedOwnerId,
    required ContentReportPayload payload,
  }) => queue.put(expectedOwnerId: expectedOwnerId, payload: payload);

  Future<ContentReportRecord> mirrorLegacy(StoredWordReport report) => save(
    expectedOwnerId: report.ownerId,
    payload: ContentReportPayload.fromWordReport(report),
  );

  Stream<List<ContentReportRecord>> watchOwner(String expectedOwnerId) =>
      queue.watchOwner(expectedOwnerId);

  ContentReportIdentityBinding _binding(String expectedOwnerId) {
    if (!transport.enabled) {
      throw const ContentReportException(ContentReportFailureCode.disabled);
    }
    final binding = transport.currentBinding;
    if (binding == null || binding.ownerId != expectedOwnerId) {
      throw const ContentReportException(
        ContentReportFailureCode.accountRequired,
      );
    }
    return binding;
  }

  Future<ContentReportRecord> _read(String owner, String id) async {
    final row = await queue.read(expectedOwnerId: owner, reportId: id);
    if (row == null || row.ownerId != owner || row.payload.reportId != id) {
      throw const ContentReportException(ContentReportFailureCode.unavailable);
    }
    return row;
  }

  Future<ContentReportRecord> send({
    required String expectedOwnerId,
    required String reportId,
  }) async {
    final binding = _binding(expectedOwnerId);
    await transport.requireCurrent(binding);
    var row = await _read(expectedOwnerId, reportId);
    await transport.requireCurrent(binding);
    if (row.acknowledgement != null) {
      if (row.acknowledgedFirebaseUid != binding.firebaseUid) {
        throw const ContentReportException(
          ContentReportFailureCode.ownerChanged,
        );
      }
      return row;
    }
    if (row.delivery == ContentReportDelivery.unconfirmed) {
      final existing = await transport.readReceipt(binding, row.payload);
      await transport.requireCurrent(binding);
      if (existing != null) {
        return _acknowledge(binding, row.payload, existing);
      }
    }
    row = await queue.markUnconfirmed(
      expectedOwnerId: expectedOwnerId,
      reportId: reportId,
      expectedReportSha256: row.payload.reportSha256,
    );
    await transport.requireCurrent(binding);
    if (row.acknowledgement != null) {
      if (row.acknowledgedFirebaseUid != binding.firebaseUid) {
        throw const ContentReportException(
          ContentReportFailureCode.ownerChanged,
        );
      }
      return row;
    }
    ContentReportAcknowledgement acknowledgement;
    try {
      acknowledgement = await transport.submit(binding, row.payload);
    } on ContentReportException catch (error) {
      if (error.code != ContentReportFailureCode.unconfirmed &&
          error.code != ContentReportFailureCode.invalidResponse) {
        rethrow;
      }
      await transport.requireCurrent(binding);
      final recovered = await transport.readReceipt(binding, row.payload);
      await transport.requireCurrent(binding);
      if (recovered == null) rethrow;
      acknowledgement = recovered;
    }
    return _acknowledge(binding, row.payload, acknowledgement);
  }

  Future<ContentReportRecord> refresh({
    required String expectedOwnerId,
    required String reportId,
  }) async {
    final binding = _binding(expectedOwnerId);
    await transport.requireCurrent(binding);
    final row = await _read(expectedOwnerId, reportId);
    await transport.requireCurrent(binding);
    if (row.acknowledgedFirebaseUid != null &&
        row.acknowledgedFirebaseUid != binding.firebaseUid) {
      throw const ContentReportException(ContentReportFailureCode.ownerChanged);
    }
    final acknowledgement = await transport.readReceipt(binding, row.payload);
    await transport.requireCurrent(binding);
    return acknowledgement == null
        ? row
        : _acknowledge(binding, row.payload, acknowledgement);
  }

  Future<ContentReportRecord> _acknowledge(
    ContentReportIdentityBinding binding,
    ContentReportPayload payload,
    ContentReportAcknowledgement acknowledgement,
  ) async {
    acknowledgement.requireMatches(payload);
    await transport.requireCurrent(binding);
    final result = await queue.acknowledge(
      expectedOwnerId: binding.ownerId,
      expectedFirebaseUid: binding.firebaseUid,
      expectedReportSha256: payload.reportSha256,
      acknowledgement: acknowledgement,
    );
    await transport.requireCurrent(binding);
    return result;
  }
}
