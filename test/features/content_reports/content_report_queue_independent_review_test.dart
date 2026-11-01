import 'dart:convert';

import 'package:drift/drift.dart'
    show QueryExecutor, QueryInterceptor, TableUpdate;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/content_reports/data/drift_content_report_queue.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_word_report_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

import '../../support/configured_quiz_harness.dart';
import 'content_report_test_support.dart';

void main() {
  late ConfiguredQuizHarness h;
  late DriftContentReportQueue queue;
  late ContentReportPayload payload;

  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    queue = DriftContentReportQueue(
      database: h.database,
      ownerWrites: h.ownerWrites,
    );
    payload = syntheticReport(id: 'content-report:synthetic-probe-scope');
    await queue.put(expectedOwnerId: configuredOwnerId, payload: payload);
  });
  tearDown(() => h.close());

  test(
    'owner ABA during the first probe cannot mark the old report unconfirmed',
    () async {
      final before = await h.snapshot();
      final interference = _OwnerProbe(h.database, invalidate: true);
      await expectLater(
        h.database.runWithInterceptor(
          () => queue.markUnconfirmed(
            expectedOwnerId: configuredOwnerId,
            reportId: payload.reportId,
            expectedReportSha256: payload.reportSha256,
          ),
          interceptor: interference,
        ),
        throwsA(isA<ContentReportException>()),
      );
      expect(interference.fired, isTrue);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'owner ABA during the first probe cannot install a retired response receipt',
    () async {
      await queue.markUnconfirmed(
        expectedOwnerId: configuredOwnerId,
        reportId: payload.reportId,
        expectedReportSha256: payload.reportSha256,
      );
      final before = await h.snapshot();
      final interference = _OwnerProbe(h.database, invalidate: true);
      await expectLater(
        h.database.runWithInterceptor(
          () => queue.acknowledge(
            expectedOwnerId: configuredOwnerId,
            expectedFirebaseUid: configuredFirebaseUid,
            expectedReportSha256: payload.reportSha256,
            acknowledgement: _ack(payload),
          ),
          interceptor: interference,
        ),
        throwsA(isA<ContentReportException>()),
      );
      expect(interference.fired, isTrue);
      expect(await h.snapshot(), before);
    },
  );

  test(
    'the same actual probe with an unchanged owner accepts the exact response',
    () async {
      await queue.markUnconfirmed(
        expectedOwnerId: configuredOwnerId,
        reportId: payload.reportId,
        expectedReportSha256: payload.reportSha256,
      );
      final probe = _OwnerProbe(h.database, invalidate: false);
      final received = await h.database.runWithInterceptor(
        () => queue.acknowledge(
          expectedOwnerId: configuredOwnerId,
          expectedFirebaseUid: configuredFirebaseUid,
          expectedReportSha256: payload.reportSha256,
          acknowledgement: _ack(payload),
        ),
        interceptor: probe,
      );
      expect(probe.fired, isTrue);
      expect(received.delivery, ContentReportDelivery.received);
      expect(received.acknowledgedFirebaseUid, configuredFirebaseUid);
      expect(received.payload.reportJson, payload.reportJson);
      expect(received.localRevision, 3);
    },
  );

  test(
    'legacy submit without a runtime callback rejects owner ABA during its first probe without changing any table',
    () async {
      final words = await DriftVocabularyRepository(
        h.database,
      ).watchWords(configuredOwnerId, configuredCategoryId).first;
      final command = WordReportCommand(
        id: 'word-report:synthetic-first-probe',
        expectedOwnerId: configuredOwnerId,
        target: WordReportTarget.fromWord(words.first),
        reason: ReportReason.spelling,
        comment: null,
        queuedAtUtc: h.now,
      );
      expect(command.revalidate, isNull);
      final repository = DriftWordReportRepository(
        database: h.database,
        ownerWriteCoordinator: h.ownerWrites,
        contentReports: queue,
      );
      final before = await h.snapshot();
      final interference = _OwnerProbe(h.database, invalidate: true);
      await expectLater(
        h.database.runWithInterceptor(
          () => repository.submit(command),
          interceptor: interference,
        ),
        throwsA(isA<WordReportException>()),
      );
      expect(interference.fired, isTrue);
      expect(await h.snapshot(), before);
    },
  );
}

ContentReportAcknowledgement _ack(ContentReportPayload payload) {
  final value = syntheticAcknowledgement(payload).toJson();
  (value['receipt'] as Map)['receiptId'] =
      'content-report-receipt:'
      '${contentReportDigest(jsonEncode([configuredFirebaseUid, payload.reportId]))}';
  return ContentReportAcknowledgement.fromJson(value);
}

final class _OwnerProbe extends QueryInterceptor {
  _OwnerProbe(this.database, {required this.invalidate});
  final AppDatabase database;
  final bool invalidate;
  var fired = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    if (!fired && statement.contains('owner_transaction_probe')) {
      fired = true;
      if (invalidate) {
        for (var step = 0; step < 2; step++) {
          await executor.runUpdate(
            'UPDATE local_owners SET is_active = 1 - is_active',
            const [],
          );
          database.notifyUpdates({const TableUpdate('local_owners')});
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
    return result;
  }
}
