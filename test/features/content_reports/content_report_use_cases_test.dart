import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/application/content_report_use_cases.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report_transport.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

import 'content_report_test_support.dart';

void main() {
  late MemoryContentReportQueue queue;
  late FakeContentReportTransport transport;
  late ContentReportUseCases useCases;
  setUp(() {
    queue = MemoryContentReportQueue();
    transport = FakeContentReportTransport();
    useCases = ContentReportUseCases(
      queue: queue,
      transport: transport,
      generateId: () => 'synthetic',
      nowUtc: () => DateTime.utc(2026),
    );
  });

  test(
    'legacy mirror preserves original ID nine snapshot bytes and timestamp',
    () async {
      final snapshot = jsonEncode({
        'version': 'owned-word-report-v1',
        'wordId': 'synthetic-word',
        'categoryId': 'synthetic-category',
        'wordRevision': 4,
        'spelling': 'word',
        'meaning': 'คำ',
        'partOfSpeech': 'noun',
        'source': 'manual',
        'cefrLevel': null,
      });
      final legacy = StoredWordReport(
        id: 'word-report:original',
        ownerId: 'owner',
        target: WordReportTarget.fromSnapshot(
          snapshotJson: snapshot,
          snapshotSha256: sha256.convert(utf8.encode(snapshot)).toString(),
        ),
        reason: ReportReason.other,
        comment: 'Original comment',
        queuedAtUtc: DateTime.fromMillisecondsSinceEpoch(7, isUtc: true),
      );
      final row = await useCases.mirrorLegacy(legacy);
      expect(row.payload.reportId, legacy.id);
      expect(row.payload.target.snapshotJson, snapshot);
      expect(row.payload.target.snapshotSha256, legacy.target.snapshotSha256);
      expect(jsonDecode(row.payload.target.snapshotJson).length, 9);
      expect(row.payload.queuedAtUtc, legacy.queuedAtUtc);
      expect(transport.submissions, 0);
      expect(transport.reads, 0);
    },
  );

  test('save and watch remain local and refresh never submits', () async {
    final payload = syntheticReport();
    transport.receiptAbsent = true;
    await useCases.save(expectedOwnerId: 'owner', payload: payload);
    final rows = await useCases.watchOwner('owner').first;
    expect(rows.single.delivery, ContentReportDelivery.queued);
    expect(transport.reads, 0);
    expect(transport.submissions, 0);
    await useCases.refresh(
      expectedOwnerId: 'owner',
      reportId: payload.reportId,
    );
    expect(transport.reads, 1);
    expect(transport.submissions, 0);
  });

  test(
    'lost POST acknowledgement reconciles through GET and never duplicates report',
    () async {
      final payload = syntheticReport();
      transport.loseAcknowledgement = true;
      await useCases.save(expectedOwnerId: 'owner', payload: payload);
      final row = await useCases.send(
        expectedOwnerId: 'owner',
        reportId: payload.reportId,
      );
      expect(row.delivery, ContentReportDelivery.received);
      expect(row.acknowledgedFirebaseUid, 'synthetic-uid');
      expect(transport.submissions, 1);
      expect(transport.reads, 1);
      await useCases.send(expectedOwnerId: 'owner', reportId: payload.reportId);
      expect(transport.submissions, 1);
      expect(transport.sentBytes, [payload.reportJson]);
    },
  );

  test(
    'unknown result persists and explicit retry checks GET then reuses exact bytes',
    () async {
      final payload = syntheticReport();
      transport.loseAcknowledgement = true;
      transport.receiptAbsent = true;
      await useCases.save(expectedOwnerId: 'owner', payload: payload);
      await expectLater(
        useCases.send(expectedOwnerId: 'owner', reportId: payload.reportId),
        throwsA(isA<ContentReportException>()),
      );
      expect(
        queue.rows[payload.reportId]!.delivery,
        ContentReportDelivery.unconfirmed,
      );
      transport.loseAcknowledgement = false;
      final row = await useCases.send(
        expectedOwnerId: 'owner',
        reportId: payload.reportId,
      );
      expect(row.delivery, ContentReportDelivery.received);
      expect(transport.reads, 2);
      expect(transport.sentBytes, [payload.reportJson, payload.reportJson]);
    },
  );

  test(
    'owner ABA during reconciliation rejects and never installs receipt',
    () async {
      final payload = syntheticReport();
      await useCases.save(expectedOwnerId: 'owner', payload: payload);
      await queue.markUnconfirmed(
        expectedOwnerId: 'owner',
        reportId: payload.reportId,
        expectedReportSha256: payload.reportSha256,
      );
      transport.onRead = () =>
          transport.currentBinding = ContentReportIdentityBinding(
            ownerId: 'owner',
            firebaseUid: 'synthetic-uid',
            generation: 3,
          );
      await expectLater(
        useCases.send(expectedOwnerId: 'owner', reportId: payload.reportId),
        throwsA(
          isA<ContentReportException>().having(
            (e) => e.code,
            'code',
            ContentReportFailureCode.ownerChanged,
          ),
        ),
      );
      expect(queue.acknowledged, 0);
      expect(transport.submissions, 0);
    },
  );

  test('persisted receipt from another Firebase UID fails closed', () async {
    final payload = syntheticReport();
    queue.rows[payload.reportId] = ContentReportRecord(
      ownerId: 'owner',
      payload: payload,
      delivery: ContentReportDelivery.received,
      acknowledgement: syntheticAcknowledgement(payload),
      acknowledgedFirebaseUid: 'different-synthetic-uid',
    );
    await expectLater(
      useCases.send(expectedOwnerId: 'owner', reportId: payload.reportId),
      throwsA(
        isA<ContentReportException>().having(
          (e) => e.code,
          'code',
          ContentReportFailureCode.ownerChanged,
        ),
      ),
    );
    expect(transport.submissions, 0);
    expect(transport.reads, 0);
  });
}
