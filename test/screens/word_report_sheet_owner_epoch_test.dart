import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/widgets/word_report_sheet.dart';

import '../support/word_reports_ui_harness.dart';

void main() {
  testWidgets(
    'coalesced owner null to same owner during build invalidates reviewed report',
    (tester) async {
      final h = (await tester.runAsync(WordReportsUiHarness.open))!;
      final owners = StreamController<String?>.broadcast(sync: true);
      final interrupt = ValueNotifier(false);
      final dependencies = h.dependencies();
      var emitted = false;
      SchedulerPhase? observedPhase;
      try {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final app = AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => WordReportSheet(
                      expectedOwnerId: configuredOwnerId,
                      target: h.target,
                      ownerChanges: owners.stream,
                    ),
                  ),
                  child: const Text('open epoch report'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(
          ValueListenableBuilder<bool>(
            valueListenable: interrupt,
            child: app,
            builder: (_, requested, child) {
              if (requested && !emitted) {
                emitted = true;
                observedPhase = SchedulerBinding.instance.schedulerPhase;
                owners.add(null);
                owners.add(configuredOwnerId);
              }
              return child!;
            },
          ),
        );
        await tester.tap(find.text('open epoch report'));
        await tester.pump();
        owners.add(configuredOwnerId);
        await reportsUntil(
          tester,
          find.byKey(const ValueKey('word-report-comment')),
        );
        await tester.pumpAndSettle();
        final reason = find.byKey(
          const ValueKey('word-report-reason:incorrectMeaning'),
        );
        await tester.ensureVisible(reason);
        await tester.pump();
        await tester.tap(reason.hitTestable());
        await tester.enterText(
          find.byKey(const ValueKey('word-report-comment')),
          'synthetic reviewed owner epoch issue',
        );
        final review = find.byKey(const ValueKey('word-report-review'));
        await tester.ensureVisible(review);
        await tester.pump();
        await tester.tap(review.hitTestable());
        await tester.pumpAndSettle();
        expect(
          find.text('synthetic reviewed owner epoch issue'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('word-report-confirm')),
          findsOneWidget,
        );
        expect(h.allocations, 0);
        expect(h.clockReads, 0);
        expect(h.fake.commands, isEmpty);

        interrupt.value = true;
        await tester.pump();
        await tester.pump();
        expect(emitted, isTrue);
        expect(observedPhase, SchedulerPhase.persistentCallbacks);
        expect(
          find.text('รายงานนี้ไม่พร้อมใช้งาน กรุณากลับแล้วเปิดใหม่'),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('word-report-confirm')), findsNothing);
        expect(find.text('synthetic reviewed owner epoch issue'), findsNothing);
        expect(h.allocations, 0);
        expect(h.clockReads, 0);
        expect(h.fake.commands, isEmpty);
        expect(h.fake.rows, isEmpty);
      } finally {
        await closeReportsUi(tester, h);
        await owners.close();
        interrupt.dispose();
      }
    },
  );
}
