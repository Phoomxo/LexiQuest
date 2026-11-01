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
      expect(find.text('Selected synthetic reply'), findsOneWidget);
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
