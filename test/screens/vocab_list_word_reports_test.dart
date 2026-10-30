import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import 'package:vocab_learning_app/widgets/word_report_sheet.dart';

import '../support/word_reports_ui_harness.dart';

Future<void> mountVocabReports(
  WidgetTester tester,
  WordReportsUiHarness h, {
  bool reports = true,
  bool saved = false,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: h.dependencies(
        includeReports: reports,
        includeSaved: saved,
      ),
      child: MaterialApp(
        home: VocabListScreen(
          categoryId: configuredCategoryId,
          categoryName: 'Synthetic category',
          ownerChanges: h.ownerChanges,
        ),
      ),
    ),
  );
  await reportsUntil(tester, find.text('station'));
}

Future<void> openReport(WidgetTester tester) async {
  await tester.tap(
    find.byKey(ValueKey('vocab-word-menu:${configuredWordIds.first}')),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    find
        .byKey(ValueKey('vocab-report:${configuredWordIds.first}'))
        .hitTestable(),
  );
  await reportsUntil(tester, find.byType(WordReportSheet));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'real owned report is optional without SavedWords and preserves unrelated tables',
    (tester) async {
      final h = (await tester.runAsync(
        () => WordReportsUiHarness.open(real: true),
      ))!;
      try {
        final before = (await tester.runAsync(h.storage.snapshot))!
          ..remove('word_reports');
        await mountVocabReports(tester, h);
        expect(
          find.byKey(ValueKey('vocab-save:${configuredWordIds.first}')),
          findsNothing,
        );
        await openReport(tester);
        await tester.tap(
          find.byKey(const ValueKey('word-report-reason:spelling')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('word-report-comment')),
          'synthetic exact reviewed content',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('word-report-review')),
        );
        await tester.pump();
        await tester.tap(
          find.byKey(const ValueKey('word-report-review')).hitTestable(),
        );
        await tester.pumpAndSettle();
        expect(h.allocations, 0);
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
        final rows = await tester.runAsync(
          () => h.reports.watchOwner(configuredOwnerId).first,
        );
        expect(rows, hasLength(1));
        expect(rows!.single.reason, ReportReason.spelling);
        expect(rows.single.target.wordId, configuredWordIds.first);
        expect(rows.single.target.spelling, 'station');
        expect(h.allocations, 1);
        final after = (await tester.runAsync(h.storage.snapshot))!
          ..remove('word_reports');
        expect(after, before);
      } finally {
        await closeReportsUi(tester, h);
      }
    },
  );
  testWidgets('SavedWords remains independent when reports are absent', (
    tester,
  ) async {
    final h = (await tester.runAsync(WordReportsUiHarness.open))!;
    try {
      await mountVocabReports(tester, h, reports: false, saved: true);
      expect(
        find.byKey(ValueKey('vocab-save:${configuredWordIds.first}')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('saved-words')), findsOneWidget);
      expect(find.byKey(const ValueKey('word-reports-history')), findsNothing);
      await tester.tap(
        find.byKey(ValueKey('vocab-word-menu:${configuredWordIds.first}')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('vocab-report:${configuredWordIds.first}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('vocab-delete:${configuredWordIds.first}')),
        findsOneWidget,
      );
    } finally {
      await closeReportsUi(tester, h);
    }
  });
  testWidgets(
    'report-only binding clears the entire previous-owner vocabulary pane',
    (tester) async {
      final h = (await tester.runAsync(WordReportsUiHarness.open))!;
      try {
        await mountVocabReports(tester, h);
        h.changeOwner(configuredOtherOwnerId);
        h.changeOwner(configuredOwnerId);
        await tester.pump();
        expect(find.text('station', skipOffstage: false), findsNothing);
        expect(
          find.text('Synthetic category', skipOffstage: false),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('word-reports-history')),
          findsNothing,
        );
        expect(h.allocations, 0);
      } finally {
        await closeReportsUi(tester, h);
      }
    },
  );
  for (final accepted in [true, false]) {
    testWidgets(
      'report-only normal delete confirmation accepted=$accepted remains functional',
      (tester) async {
        final h = (await tester.runAsync(WordReportsUiHarness.open))!;
        try {
          await mountVocabReports(tester, h);
          await tester.tap(
            find.byKey(ValueKey('vocab-word-menu:${configuredWordIds.first}')),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            find
                .byKey(ValueKey('vocab-delete:${configuredWordIds.first}'))
                .hitTestable(),
          );
          await tester.pumpAndSettle();
          await tester.tap(
            (accepted
                    ? find.widgetWithText(FilledButton, 'ลบ')
                    : find.widgetWithText(TextButton, 'ยกเลิก'))
                .hitTestable(),
          );
          await tester.pump();
          var deleted = false;
          for (var i = 0; i < 40; i++) {
            deleted = (await tester.runAsync(
              () =>
                  (h.storage.database.select(h.storage.database.vocabularyWords)
                        ..where(
                          (word) => word.id.equals(configuredWordIds.first),
                        ))
                      .getSingle(),
            ))!.isDeleted;
            if (deleted == accepted) {
              break;
            }
            await tester.pump(const Duration(milliseconds: 20));
          }
          expect(deleted, accepted);
          expect(h.allocations, 0);
        } finally {
          await closeReportsUi(tester, h);
        }
      },
    );
  }
}
