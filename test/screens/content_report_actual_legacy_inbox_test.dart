import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/vocabulary/application/word_report_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_word_report_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';
import 'package:vocab_learning_app/screens/word_reports_screen.dart';

import '../support/configured_quiz_harness.dart';
import '../support/content_report_caller_harness.dart';
import '../support/content_report_ui_io.dart';
import '../support/motivation_presentation_io.dart';

void main() {
  testWidgets(
    'old historical report enters queue only through explicit inbox preparation and keeps exact bytes',
    (tester) async {
      final h = await motivationPresentationIo(
        tester,
        ContentReportCallerHarness.open,
        stage: 'historical-report-fixture',
      );
      try {
        final report = await motivationPresentationIo(
          tester,
          () => _oldReport(h),
          stage: 'historical-original',
        );
        final before = await motivationPresentationIo(
          tester,
          h.storage.snapshot,
        );
        await _mount(tester, h);
        await reportUiWait(
          tester,
          'historical-row',
          () => find
              .byKey(ValueKey('word-report-history-row:${report.id}'))
              .evaluate()
              .isNotEmpty,
        );
        expect(
          await motivationPresentationIo(
            tester,
            () => h.storage.count('content_reports'),
          ),
          0,
        );
        expect(
          await motivationPresentationIo(tester, h.storage.snapshot),
          before,
        );
        await reportUiTap(
          tester,
          find.byKey(ValueKey('word-report-history-row:${report.id}')),
          'historical-expand',
        );
        await reportUiReveal(
          tester,
          find.byKey(ValueKey('content-report-legacy-mirror:${report.id}')),
          'historical-explicit-mirror',
          scrollable: find.byType(ListView),
        );
        await reportUiTapKey(
          tester,
          'content-report-legacy-mirror:${report.id}',
        );
        await reportUiWait(
          tester,
          'historical-inbox',
          () => find
              .byKey(ValueKey('content-report-row-${report.id}'))
              .evaluate()
              .isNotEmpty,
        );
        final mirrored = await motivationPresentationIo(
          tester,
          () => h.queue.read(
            expectedOwnerId: configuredOwnerId,
            reportId: report.id,
          ),
        );
        expect(mirrored!.payload.reportId, report.id);
        expect(
          mirrored.payload.target.snapshotJson,
          report.target.snapshotJson,
        );
        expect(
          mirrored.payload.target.snapshotSha256,
          report.target.snapshotSha256,
        );
        expect(mirrored.payload.queuedAtUtc, report.queuedAtUtc);
        final legacy = await motivationPresentationIo(
          tester,
          () => h.wordReports.watchOwner(configuredOwnerId).first,
        );
        expect(legacy.single.sameFacts(report), isTrue);
      } finally {
        await closeMotivationPresentation(tester, h.close);
      }
    },
  );

  testWidgets(
    'legacy history never claims not sent after a persisted synthetic receipt exists',
    (tester) async {
      final h = await motivationPresentationIo(
        tester,
        ContentReportCallerHarness.open,
        stage: 'received-history-fixture',
      );
      try {
        final legacy = await motivationPresentationIo(
          tester,
          () => _oldReport(h),
        );
        final record = await motivationPresentationIo(
          tester,
          () => h.reports.mirrorLegacy(legacy),
        );
        final key = contentReportDigest(
          jsonEncode([configuredFirebaseUid, legacy.id]),
        );
        await motivationPresentationIo(
          tester,
          () => h.queue.acknowledge(
            expectedOwnerId: configuredOwnerId,
            expectedFirebaseUid: configuredFirebaseUid,
            expectedReportSha256: record.payload.reportSha256,
            acknowledgement: ContentReportAcknowledgement.fromJson({
              'schemaVersion': 1,
              'receipt': {
                'reportId': legacy.id,
                'reportSha256': record.payload.reportSha256,
                'receiptId': 'content-report-receipt:$key',
                'receivedAtUtc': '2026-11-01T00:00:00.000Z',
              },
              'moderation': {
                'revision': 1,
                'status': 'received',
                'decisionId': null,
                'publicNote': null,
                'decidedAtUtc': null,
              },
            }),
          ),
          stage: 'synthetic-received-receipt',
        );
        await _mount(tester, h);
        await reportUiWait(
          tester,
          'received-legacy-row',
          () => find
              .byKey(ValueKey('word-report-history-row:${legacy.id}'))
              .evaluate()
              .isNotEmpty,
        );
        await reportUiTap(
          tester,
          find.byKey(ValueKey('word-report-history-row:${legacy.id}')),
          'received-legacy-expand',
        );
        expect(find.textContaining('Not sent'), findsNothing);
        expect(find.textContaining('not sent'), findsNothing);
        await reportUiTap(
          tester,
          find.byKey(const ValueKey('content-report-inbox')),
          'received-inbox',
        );
        await reportUiWait(
          tester,
          'received-inbox-row',
          () => find
              .byKey(ValueKey('content-report-row-${legacy.id}'))
              .evaluate()
              .isNotEmpty,
        );
        await reportUiTap(
          tester,
          find.byKey(ValueKey('content-report-row-${legacy.id}')),
          'received-inbox-expand',
        );
        expect(find.text('Received by the server.'), findsOneWidget);
        expect(find.text('Awaiting moderation.'), findsOneWidget);
      } finally {
        await closeMotivationPresentation(tester, h.close);
      }
    },
  );
}

Future<StoredWordReport> _oldReport(ContentReportCallerHarness h) async {
  final words = await h.vocabulary.vocabulary
      .watchWords(configuredOwnerId, configuredCategoryId)
      .first;
  final oldWriter = WordReportUseCases(
    repository: DriftWordReportRepository(
      database: h.storage.database,
      ownerWriteCoordinator: h.storage.ownerWrites,
    ),
    generateId: () => 'synthetic-historical',
    nowUtc: () => h.storage.now,
  );
  return (await oldWriter.submit(
    oldWriter.prepareSubmit(
      expectedOwnerId: configuredOwnerId,
      target: WordReportTarget.fromWord(words.first),
      reason: ReportReason.spelling,
    ),
  )).report;
}

Future<void> _mount(WidgetTester tester, ContentReportCallerHarness h) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    h.app(
      const WordReportsScreen(
        expectedOwnerId: configuredOwnerId,
        languageCode: 'en',
      ),
    ),
  );
}
