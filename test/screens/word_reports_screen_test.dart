import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/word_reports_screen.dart';

import '../support/word_reports_ui_harness.dart';
import 'vocab_list_word_reports_test.dart' show mountVocabReports, openReport;

Future<void> mountHistory(WidgetTester tester, WordReportsUiHarness h) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: h.dependencies(),
      child: MaterialApp(
        home: WordReportsScreen(
          expectedOwnerId: configuredOwnerId,
          ownerChanges: h.ownerChanges,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('history loading empty and read retry never submit a command', (
    tester,
  ) async {
    final h = (await tester.runAsync(WordReportsUiHarness.open))!;
    try {
      h.fake.holdRead = true;
      await mountHistory(tester, h);
      expect(
        find.byKey(const ValueKey('word-reports-loading')),
        findsOneWidget,
      );
      h.fake.changes.add(null);
      await reportsUntil(
        tester,
        find.byKey(const ValueKey('word-reports-empty')),
      );
      expect(h.fake.commands, isEmpty);
    } finally {
      await closeReportsUi(tester, h);
    }
  });
  testWidgets('history read error requires explicit fresh subscription', (
    tester,
  ) async {
    final h = (await tester.runAsync(WordReportsUiHarness.open))!;
    try {
      h.fake.failedReads = 1;
      await mountHistory(tester, h);
      await reportsUntil(
        tester,
        find.byKey(const ValueKey('word-reports-read-retry')),
      );
      await tester.tap(find.byKey(const ValueKey('word-reports-read-retry')));
      await reportsUntil(
        tester,
        find.byKey(const ValueKey('word-reports-empty')),
      );
      expect(h.allocations, 0);
    } finally {
      await closeReportsUi(tester, h);
    }
  });
  testWidgets('history details retain original target and hide on owner loss', (
    tester,
  ) async {
    final h = (await tester.runAsync(WordReportsUiHarness.open))!;
    try {
      final command = h.reports.prepareSubmit(
        expectedOwnerId: configuredOwnerId,
        target: h.target,
        reason: ReportReason.other,
        comment: 'historical synthetic note',
      );
      await h.reports.submit(command);
      await mountHistory(tester, h);
      await reportsUntil(tester, find.text('station'));
      await tester.tap(
        find.byKey(ValueKey('word-report-history-row:${command.id}')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('historical synthetic note'), findsWidgets);
      expect(find.textContaining('ยังไม่ได้ส่ง'), findsWidgets);
      h.changeOwner(null);
      await tester.pumpAndSettle();
      expect(find.text('station', skipOffstage: false), findsNothing);
      expect(
        find.textContaining('historical synthetic note', skipOffstage: false),
        findsNothing,
      );
    } finally {
      await closeReportsUi(tester, h);
    }
  });
  testWidgets(
    'actual file restart preserves local queued report and historical details',
    (tester) async {
      final tempRoot = (await tester.runAsync(
        Directory.systemTemp.resolveSymbolicLinks,
      ))!;
      final directory = (await tester.runAsync(
        () => Directory(tempRoot).createTemp('lexiquest-word-report-ui-'),
      ))!;
      final file = File(
        '${directory.path}${Platform.pathSeparator}reports.sqlite',
      );
      var h = (await tester.runAsync(
        () => WordReportsUiHarness.open(real: true, file: file),
      ))!;
      try {
        await mountVocabReports(tester, h);
        await openReport(tester);
        await tester.tap(
          find.byKey(const ValueKey('word-report-reason:incorrectMeaning')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('word-report-comment')),
          'synthetic persisted review',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('word-report-review')),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('word-report-review')).hitTestable(),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('word-report-confirm')),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('word-report-confirm')).hitTestable(),
        );
        await reportsUntil(
          tester,
          find.byKey(const ValueKey('word-report-queued')),
        );
        final original = (await tester.runAsync(
          () => h.reports.watchOwner(configuredOwnerId).first,
        ))!.single;
        await closeReportsUi(tester, h);
        h = (await tester.runAsync(
          () => WordReportsUiHarness.open(real: true, file: file, seed: false),
        ))!;
        await mountHistory(tester, h);
        await reportsUntil(tester, find.text('station'));
        await tester.tap(
          find.byKey(ValueKey('word-report-history-row:${original.id}')),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('synthetic persisted review'), findsWidgets);
        final restarted = (await tester.runAsync(
          () => h.reports.watchOwner(configuredOwnerId).first,
        ))!.single;
        expect(restarted.sameFacts(original), isTrue);
        expect(h.allocations, 0);
        expect(
          await tester.runAsync(() => h.storage.count('learning_sessions')),
          0,
        );
        expect(
          await tester.runAsync(() => h.storage.count('answer_attempts')),
          0,
        );
      } finally {
        await closeReportsUi(tester, h);
        await tester.runAsync(() async {
          final resolved = await directory.resolveSymbolicLinks();
          expect(
            resolved,
            startsWith(
              '$tempRoot${Platform.pathSeparator}lexiquest-word-report-ui-',
            ),
          );
          expect(resolved, directory.absolute.path);
          await Directory(resolved).delete(recursive: true);
        });
      }
    },
  );
}
