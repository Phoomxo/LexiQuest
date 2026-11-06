import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/content_reports/application/content_report_use_cases.dart';
import 'package:vocab_learning_app/features/content_reports/domain/content_report.dart';
import 'package:vocab_learning_app/features/content_reports/presentation/content_report_inbox.dart';
import 'package:vocab_learning_app/features/content_reports/presentation/content_report_sheet.dart';

import '../features/content_reports/content_report_test_support.dart';

void main() {
  late MemoryContentReportQueue queue;
  late FakeContentReportTransport transport;
  late ContentReportUseCases reports;
  late StreamController<String?> owners;
  setUp(() {
    queue = MemoryContentReportQueue();
    transport = FakeContentReportTransport();
    reports = ContentReportUseCases(
      queue: queue,
      transport: transport,
      generateId: () => 'synthetic-ui',
      nowUtc: () => DateTime.utc(2026),
    );
    owners = StreamController<String?>.broadcast(sync: true);
  });
  tearDown(() async {
    await owners.close();
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double scale = 1,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: child),
      ),
    );
    owners.add('owner');
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder.hitTestable());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'review and local save never send; explicit Send receives separate status',
    (tester) async {
      await mount(
        tester,
        ContentReportSheet(
          expectedOwnerId: 'owner',
          target: syntheticReport().target,
          reports: reports,
          ownerChanges: owners.stream,
          languageCode: 'en',
        ),
      );
      await tapKey(tester, 'content-report-reason:spelling');
      expect(find.text('Selected synthetic reply'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('content-report-review')),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const ValueKey('content-report-comment')),
        'Reviewed comment',
      );
      await tapKey(tester, 'content-report-review');
      expect(
        find.text('Save locally first. Sending requires a separate action.'),
        findsOneWidget,
      );
      expect(transport.submissions, 0);
      expect(queue.rows, isEmpty);
      await tapKey(tester, 'content-report-save');
      expect(queue.rows.length, 1);
      expect(transport.submissions, 0);
      expect(transport.reads, 0);
      expect(find.text('Saved locally. No server receipt.'), findsOneWidget);
      await tapKey(tester, 'content-report-send');
      expect(transport.submissions, 1);
      expect(find.text('Received by the server.'), findsOneWidget);
      expect(find.text('Awaiting moderation.'), findsOneWidget);
      expect(
        find.text(
          'A review status does not confirm that source content changed.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final saveFirst in [false, true]) {
    testWidgets(
      'hidden pane rejects retained ${saveFirst ? 'Send' : 'Save'} callback',
      (tester) async {
        final visible = ValueNotifier(true);
        addTearDown(visible.dispose);
        await mount(
          tester,
          ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, shown, _) => Visibility(
              visible: shown,
              maintainState: true,
              child: ContentReportSheet(
                expectedOwnerId: 'owner',
                target: syntheticReport().target,
                reports: reports,
                ownerChanges: owners.stream,
                languageCode: 'en',
              ),
            ),
          ),
        );
        await tapKey(tester, 'content-report-reason:spelling');
        await tapKey(tester, 'content-report-review');
        if (saveFirst) await tapKey(tester, 'content-report-save');
        final key = saveFirst ? 'content-report-send' : 'content-report-save';
        final retained = tester
            .widget<FilledButton>(find.byKey(ValueKey(key)))
            .onPressed!;
        visible.value = false;
        await tester.pumpAndSettle();
        retained();
        await tester.pumpAndSettle();
        expect(queue.rows.length, saveFirst ? 1 : 0);
        expect(transport.submissions, 0);
        expect(transport.reads, 0);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'long source requires explicit excerpt and persists only chosen text',
    (tester) async {
      final source = 'selected ${'x' * 4100} excluded synthetic tail';
      await mount(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showContentReportComposer(
              context,
              expectedOwnerId: 'owner',
              sourceText: source,
              targetForSelection: (text, excerpt) =>
                  ContentReportTarget.tutorReply(
                    text: text,
                    isExcerpt: excerpt,
                    replyId: 'synthetic-reply',
                    modelVersion: 'synthetic-model',
                    generatedAtUtcMs: 1,
                  ),
              reports: reports,
              ownerChanges: owners.stream,
              languageCode: 'en',
            ),
            child: const Text('open composer'),
          ),
        ),
      );
      await tester.tap(find.text('open composer'));
      await tester.pumpAndSettle();
      owners.add('owner');
      await tester.pumpAndSettle();
      final field = find.byKey(const ValueKey('content-report-selection'));
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.enterText(field, 'selected');
      await tapKey(tester, 'content-report-selection-review');
      expect(find.text('Selected excerpt'), findsOneWidget);
      await tapKey(tester, 'content-report-reason:spelling');
      await tapKey(tester, 'content-report-review');
      await tapKey(tester, 'content-report-save');
      final row = queue.rows.values.single;
      expect(row.payload.target.text, 'selected');
      expect(row.payload.target.isExcerpt, isTrue);
      expect(
        row.payload.reportJson,
        isNot(contains('excluded synthetic tail')),
      );
      expect(transport.submissions, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('owner ABA removes selected content and never saves or sends', (
    tester,
  ) async {
    await mount(
      tester,
      ContentReportSheet(
        expectedOwnerId: 'owner',
        target: syntheticReport().target,
        reports: reports,
        ownerChanges: owners.stream,
        languageCode: 'en',
      ),
    );
    expect(find.text('Selected synthetic reply'), findsOneWidget);
    owners.add(null);
    owners.add('owner');
    await tester.pumpAndSettle();
    expect(
      find.text('Selected synthetic reply', skipOffstage: false),
      findsNothing,
    );
    expect(queue.rows, isEmpty);
    expect(transport.submissions, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'inbox open performs no remote read or send and hides on owner loss',
    (tester) async {
      final payload = syntheticReport();
      await reports.save(expectedOwnerId: 'owner', payload: payload);
      await mount(
        tester,
        ContentReportInbox(
          expectedOwnerId: 'owner',
          reports: reports,
          ownerChanges: owners.stream,
          languageCode: 'en',
        ),
      );
      expect(transport.submissions, 0);
      expect(transport.reads, 0);
      await tester.tap(
        find.byKey(ValueKey('content-report-row-${payload.reportId}')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Selected synthetic reply'), findsNWidgets(2));
      owners.add('other-owner');
      await tester.pumpAndSettle();
      expect(
        find.text('Selected synthetic reply', skipOffstage: false),
        findsNothing,
      );
      expect(transport.submissions, 0);
      expect(transport.reads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final language in ['th', 'en']) {
    testWidgets(
      'collapsed reports identify their target and status in $language',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final semantics = tester.ensureSemantics();
        try {
          final texts = [
            'cat',
            'dog',
            List.filled(40, 'ข้อความสังเคราะห์').join('\n'),
          ];
          final payloads = <ContentReportPayload>[];
          for (var index = 0; index < texts.length; index++) {
            final original = syntheticReport(
              id: 'content-report:preview-$index',
            );
            final payload = ContentReportPayload.create(
              reportId: original.reportId,
              target: ContentReportTarget.tutorReply(
                text: texts[index],
                isExcerpt: false,
                replyId: 'synthetic-reply-$index',
                modelVersion: 'synthetic-model',
                generatedAtUtcMs: 1,
              ),
              reason: original.reason,
              comment: null,
              queuedAtUtc: original.queuedAtUtc,
            );
            payloads.add(payload);
            await reports.save(expectedOwnerId: 'owner', payload: payload);
          }
          await mount(
            tester,
            ContentReportInbox(
              expectedOwnerId: 'owner',
              reports: reports,
              ownerChanges: owners.stream,
              languageCode: language,
            ),
            scale: 2,
          );
          final status = language == 'th'
              ? 'บันทึกในเครื่อง ยังไม่มีใบรับเรื่องจากเซิร์ฟเวอร์'
              : 'Saved locally. No server receipt.';
          for (final payload in payloads) {
            final row = find.byKey(
              ValueKey('content-report-row-${payload.reportId}'),
            );
            await tester.scrollUntilVisible(
              row,
              100,
              scrollable: find.byType(Scrollable).first,
            );
            final tile = tester.widget<ExpansionTile>(row);
            expect(tile.initiallyExpanded, isFalse);
            expect(
              find.descendant(of: row, matching: find.text(status)),
              findsOneWidget,
            );
            final preview = tile.title as Text;
            expect(
              preview.data,
              startsWith(payload.target.text.split('\n').first),
            );
            expect(preview.data!.characters.length, lessThanOrEqualTo(120));
            expect(
              tester
                  .getSemantics(
                    find.descendant(of: row, matching: find.byWidget(preview)),
                  )
                  .label,
              contains(preview.data!),
            );
            expect(find.text(payload.target.snapshotJson), findsNothing);
            expect(
              queue.rows[payload.reportId]!.payload.reportJson,
              payload.reportJson,
            );
          }
          final last = payloads.last;
          expect(find.text(last.target.text), findsNothing);
          await tapKey(tester, 'content-report-row-${last.reportId}');
          expect(find.text(last.target.text), findsOneWidget);
          expect(transport.submissions, 0);
          expect(transport.reads, 0);
          expect(tester.takeException(), isNull);
          owners.add('other-owner');
          await tester.pumpAndSettle();
          expect(find.byType(ExpansionTile), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'inbox shows local time and keeps source evidence behind details in $language',
      (tester) async {
        final original = syntheticReport();
        final queuedAt = DateTime(2026, 11, 3, 9, 5).toUtc();
        final payload = ContentReportPayload.create(
          reportId: original.reportId,
          target: original.target,
          reason: original.reason,
          comment: original.comment,
          queuedAtUtc: queuedAt,
        );
        await reports.save(expectedOwnerId: 'owner', payload: payload);
        final savedJson = queue.rows.values.single.payload.reportJson;
        await mount(
          tester,
          ContentReportInbox(
            expectedOwnerId: 'owner',
            reports: reports,
            ownerChanges: owners.stream,
            languageCode: language,
          ),
        );
        expect(
          find.text(
            language == 'th'
                ? 'คำตอบจากผู้ช่วย AI\nบันทึกวันที่ 03/11/2026 เวลา 09:05 · เวลาบนอุปกรณ์'
                : 'AI tutor reply\nSaved 03/11/2026 at 09:05 · device time',
          ),
          findsOneWidget,
        );
        expect(find.text(payload.target.snapshotJson), findsNothing);
        await tapKey(tester, 'content-report-row-${payload.reportId}');
        expect(find.text('Selected synthetic reply'), findsNWidgets(2));
        expect(find.text(payload.target.snapshotJson), findsNothing);
        expect(find.text(payload.reportId), findsNothing);
        await tapKey(tester, 'content-report-source-${payload.reportId}');
        expect(find.text(payload.reportId), findsOneWidget);
        expect(
          tester
              .widget<SelectableText>(
                find.ancestor(
                  of: find.text(payload.reportId),
                  matching: find.byType(SelectableText),
                ),
              )
              .data,
          payload.reportId,
        );
        expect(find.text(payload.target.snapshotJson), findsOneWidget);
        expect(
          find.text(
            '${language == 'th' ? 'เวลาที่บันทึก' : 'Saved at'} (UTC) ${queuedAt.toIso8601String()}',
          ),
          findsOneWidget,
        );
        expect(queue.rows.values.single.payload.reportJson, savedJson);
        expect(transport.submissions, 0);
        expect(transport.reads, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('offline inbox keeps local status without remote controls', (
    tester,
  ) async {
    transport.enabled = false;
    final payload = syntheticReport();
    await reports.save(expectedOwnerId: 'owner', payload: payload);
    await mount(
      tester,
      ContentReportInbox(
        expectedOwnerId: 'owner',
        reports: reports,
        ownerChanges: owners.stream,
        languageCode: 'en',
      ),
    );
    await tapKey(tester, 'content-report-row-${payload.reportId}');
    expect(find.text('Sending is unavailable.'), findsOneWidget);
    expect(find.text('Saved locally. No server receipt.'), findsOneWidget);
    expect(
      find.byKey(ValueKey('content-report-send-${payload.reportId}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('content-report-refresh-${payload.reportId}')),
      findsNothing,
    );
    expect(transport.submissions, 0);
    expect(transport.reads, 0);
    expect(queue.rows.values.single.payload.reportJson, payload.reportJson);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'connected inbox sends only explicitly and refresh preserves report',
    (tester) async {
      final payload = syntheticReport();
      await reports.save(expectedOwnerId: 'owner', payload: payload);
      await mount(
        tester,
        ContentReportInbox(
          expectedOwnerId: 'owner',
          reports: reports,
          ownerChanges: owners.stream,
          languageCode: 'en',
        ),
      );
      await tapKey(tester, 'content-report-row-${payload.reportId}');
      expect(transport.submissions, 0);
      expect(transport.reads, 0);
      await tapKey(tester, 'content-report-send-${payload.reportId}');
      expect(transport.submissions, 1);
      expect(find.text('Received by the server.'), findsOneWidget);
      expect(
        find.byKey(ValueKey('content-report-send-${payload.reportId}')),
        findsNothing,
      );
      final readsAfterSend = transport.reads;
      await tapKey(tester, 'content-report-refresh-${payload.reportId}');
      expect(transport.submissions, 1);
      expect(transport.reads, readsAfterSend + 1);
      expect(queue.rows.values.single.payload.reportJson, payload.reportJson);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('offline sheet saves and retains report ID without send action', (
    tester,
  ) async {
    transport.enabled = false;
    await mount(
      tester,
      ContentReportSheet(
        expectedOwnerId: 'owner',
        target: syntheticReport().target,
        reports: reports,
        ownerChanges: owners.stream,
        languageCode: 'en',
      ),
    );
    await tapKey(tester, 'content-report-reason:spelling');
    await tapKey(tester, 'content-report-review');
    expect(
      find.text(
        'Sending is unavailable. The report stays on this device and the organizer will not receive it.',
      ),
      findsOneWidget,
    );
    await tapKey(tester, 'content-report-save');
    expect(queue.rows.length, 1);
    expect(
      find.text(queue.rows.values.single.payload.reportId),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('content-report-send')), findsNothing);
    expect(
      find.text('Sending is unavailable. Your report remains on this device.'),
      findsOneWidget,
    );
    await tapKey(tester, 'content-report-saved-details');
    final details = find.byKey(const ValueKey('content-report-saved-details'));
    expect(
      find.descendant(
        of: details,
        matching: find.text(queue.rows.values.single.payload.target.text),
      ),
      findsOneWidget,
    );
    owners.add('another-owner');
    await tester.pumpAndSettle();
    expect(details, findsNothing);
    expect(find.text('Selected synthetic reply'), findsNothing);
    expect(transport.submissions, 0);
    expect(transport.reads, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('compact 200 percent sheet remains scrollable without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(
      tester,
      Scaffold(
        body: ContentReportSheet(
          expectedOwnerId: 'owner',
          target: syntheticReport().target,
          reports: reports,
          ownerChanges: owners.stream,
          languageCode: 'en',
        ),
      ),
      scale: 2,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(
      find.byKey(const ValueKey('content-report-review')),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
