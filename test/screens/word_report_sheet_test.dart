import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/widgets/word_report_sheet.dart';

import '../support/word_reports_ui_harness.dart';

Future<void> mountSheet(
  WidgetTester tester,
  WordReportsUiHarness h, {
  String language = 'th',
  double scale = 1,
  ValueNotifier<AppDependencies>? dependencies,
}) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  Widget app(AppDependencies deps) => AppDependenciesScope(
    dependencies: deps,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => WordReportSheet(
                expectedOwnerId: configuredOwnerId,
                target: h.target,
                ownerChanges: h.ownerChanges,
                languageCode: language,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pumpWidget(
    dependencies == null
        ? app(h.dependencies())
        : ValueListenableBuilder<AppDependencies>(
            valueListenable: dependencies,
            builder: (_, value, _) => app(value),
          ),
  );
  await tester.tap(find.text('open'));
  await reportsUntil(tester, find.byKey(const ValueKey('word-report-comment')));
  await tester.pumpAndSettle();
}

Future<void> review(
  WidgetTester tester, {
  String comment = 'synthetic reviewed issue',
}) async {
  final reason = find.byKey(
    const ValueKey('word-report-reason:incorrectMeaning'),
  );
  await tester.ensureVisible(reason);
  await tester.pump();
  await tester.tap(reason.hitTestable());
  await tester.enterText(
    find.byKey(const ValueKey('word-report-comment')),
    comment,
  );
  final button = find.byKey(const ValueKey('word-report-review'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> confirm(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('word-report-confirm'));
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.tap(button.hitTestable());
  await tester.pump();
}

void main() {
  testWidgets('late IME update cannot change the visible reviewed comment', (
    tester,
  ) async {
    final h = (await tester.runAsync(WordReportsUiHarness.open))!;
    try {
      await mountSheet(tester, h);
      final controller = tester
          .widget<TextField>(find.byKey(const ValueKey('word-report-comment')))
          .controller!;
      await review(tester, comment: 'visible reviewed comment');
      expect(find.text('visible reviewed comment'), findsOneWidget);
      expect(h.allocations, 0);
      expect(h.clockReads, 0);
      controller.text = 'late unreviewed IME update';
      await tester.pump();
      expect(find.text('visible reviewed comment'), findsOneWidget);
      await confirm(tester);
      await reportsUntil(
        tester,
        find.byKey(const ValueKey('word-report-queued')),
      );
      expect(h.fake.commands.single.comment, 'visible reviewed comment');
      expect(h.allocations, 1);
      expect(h.clockReads, 1);
    } finally {
      await closeReportsUi(tester, h);
    }
  });
  testWidgets(
    'other requires a comment before review without command allocation',
    (tester) async {
      final h = (await tester.runAsync(WordReportsUiHarness.open))!;
      try {
        await mountSheet(tester, h);
        final other = find.byKey(const ValueKey('word-report-reason:other'));
        await tester.ensureVisible(other);
        await tester.pump();
        await tester.tap(other.hitTestable());
        final reviewButton = find.byKey(const ValueKey('word-report-review'));
        await tester.ensureVisible(reviewButton);
        await tester.pump();
        await tester.tap(reviewButton.hitTestable());
        await tester.pump();
        expect(find.byKey(const ValueKey('word-report-confirm')), findsNothing);
        expect(h.allocations, 0);
        expect(h.clockReads, 0);
        expect(h.fake.commands, isEmpty);
      } finally {
        await closeReportsUi(tester, h);
      }
    },
  );
  testWidgets(
    'editable review and cancel allocate nothing; confirmation freezes once',
    (tester) async {
      final h = (await tester.runAsync(WordReportsUiHarness.open))!;
      try {
        await mountSheet(tester, h);
        await review(tester);
        expect(find.text('station'), findsOneWidget);
        expect(h.allocations, 0);
        expect(h.clockReads, 0);
        await tester.tap(find.byKey(const ValueKey('word-report-edit')));
        await tester.pumpAndSettle();
        await review(tester, comment: 'changed before confirmation');
        await confirm(tester);
        await reportsUntil(
          tester,
          find.byKey(const ValueKey('word-report-queued')),
        );
        expect(h.allocations, 1);
        expect(h.clockReads, 1);
        expect(h.fake.commands, hasLength(1));
        expect(h.fake.commands.single.comment, 'changed before confirmation');
        expect(find.textContaining('ยังไม่ได้ส่ง'), findsWidgets);
        expect(find.byKey(const ValueKey('word-report-edit')), findsNothing);
      } finally {
        await closeReportsUi(tester, h);
      }
    },
  );
  testWidgets('form review cancel does not enqueue a report', (tester) async {
    final h = (await tester.runAsync(WordReportsUiHarness.open))!;
    try {
      await mountSheet(tester, h);
      await review(tester);
      await tester.tap(find.byKey(const ValueKey('word-report-close')));
      await tester.pumpAndSettle();
      expect(h.allocations, 0);
      expect(h.fake.rows, isEmpty);
    } finally {
      await closeReportsUi(tester, h);
    }
  });
  testWidgets(
    'lost ACK retries original immutable command without editable payload',
    (tester) async {
      final h = (await tester.runAsync(WordReportsUiHarness.open))!;
      try {
        h.fake.loseNextAck = true;
        await mountSheet(tester, h);
        await review(tester);
        await confirm(tester);
        await reportsUntil(
          tester,
          find.byKey(const ValueKey('word-report-retry')),
        );
        final original = h.fake.commands.single;
        expect(find.byKey(const ValueKey('word-report-comment')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('word-report-retry')));
        await reportsUntil(
          tester,
          find.byKey(const ValueKey('word-report-queued')),
        );
        expect(h.fake.commands.last, same(original));
        expect(h.allocations, 1);
        expect(h.clockReads, 1);
        expect(h.fake.rows, hasLength(1));
      } finally {
        await closeReportsUi(tester, h);
      }
    },
  );
  for (final loss in [
    'null',
    'error',
    'done',
    'ABA',
    'cover',
    'paused',
    'dependencies',
    'dispose',
  ]) {
    testWidgets('pending report $loss cannot reveal late local receipt', (
      tester,
    ) async {
      final h = (await tester.runAsync(WordReportsUiHarness.open))!;
      final deps = ValueNotifier(h.dependencies());
      try {
        h.fake.gate = Completer<void>();
        await mountSheet(tester, h, dependencies: deps);
        await review(tester);
        await confirm(tester);
        expect(h.fake.commands, hasLength(1));
        switch (loss) {
          case 'null':
            h.changeOwner(null);
          case 'error':
            h.owners.addError(StateError('synthetic owner read failure'));
          case 'done':
            await tester.runAsync(h.owners.close);
          case 'ABA':
            h.changeOwner(configuredOtherOwnerId);
            h.changeOwner(configuredOwnerId);
          case 'cover':
            final context = tester.element(find.byType(WordReportSheet));
            unawaited(
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => const Scaffold(body: Text('cover')),
                ),
              ),
            );
          case 'paused':
            for (final state in [
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
            ]) {
              tester.binding.handleAppLifecycleStateChanged(state);
            }
            tester.binding.scheduleForcedFrame();
          case 'dependencies':
            deps.value = h.dependencies();
          case 'dispose':
            await tester.pumpWidget(const SizedBox.shrink());
        }
        await tester.pump();
        expect(find.text('station', skipOffstage: false), findsNothing);
        h.fake.release();
        tester.binding.scheduleForcedFrame();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('word-report-queued'), skipOffstage: false),
          findsNothing,
        );
        expect(h.fake.commands, hasLength(1));
        expect(h.allocations, 1);
      } finally {
        if (tester.binding.lifecycleState == AppLifecycleState.paused) {
          for (final state in [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
          }
        }
        await closeReportsUi(tester, h);
        deps.dispose();
      }
    });
  }
  for (final reason in [
    WordReportFailureCode.staleTarget,
    WordReportFailureCode.collision,
  ]) {
    testWidgets('definitive $reason denies auto-reprepare and editing', (
      tester,
    ) async {
      final h = (await tester.runAsync(WordReportsUiHarness.open))!;
      try {
        h.fake.rejectNext = reason;
        await mountSheet(tester, h);
        await review(tester);
        await confirm(tester);
        await tester.pump();
        expect(find.byKey(const ValueKey('word-report-edit')), findsNothing);
        expect(find.byKey(const ValueKey('word-report-retry')), findsNothing);
        expect(h.allocations, 1);
        expect(h.fake.rows, isEmpty);
      } finally {
        await closeReportsUi(tester, h);
      }
    });
  }
  testWidgets('English 320px 200 percent IME review remains reachable', (
    tester,
  ) async {
    final h = (await tester.runAsync(WordReportsUiHarness.open))!;
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    try {
      await mountSheet(tester, h, language: 'en', scale: 2);
      final reason = find.byKey(
        const ValueKey('word-report-reason:incorrectMeaning'),
      );
      await tester.ensureVisible(reason);
      await tester.pumpAndSettle();
      await tester.tap(reason.hitTestable());
      await tester.showKeyboard(
        find.byKey(const ValueKey('word-report-comment')),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      await tester.enterText(
        find.byKey(const ValueKey('word-report-comment')),
        'synthetic reviewed issue with an open IME',
      );
      await tester.pumpAndSettle();
      final reviewButton = find.byKey(const ValueKey('word-report-review'));
      await tester.ensureVisible(reviewButton);
      await tester.pumpAndSettle();
      await tester.tap(reviewButton.hitTestable());
      await tester.pumpAndSettle();
      final confirmButton = find.byKey(const ValueKey('word-report-confirm'));
      await tester.ensureVisible(confirmButton);
      await tester.pump();
      final focus = tester.widget<FilledButton>(confirmButton).focusNode!;
      for (var index = 0; index < 12 && !focus.hasFocus; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(focus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await reportsUntil(
        tester,
        find.byKey(const ValueKey('word-report-queued')),
      );
      expect(find.textContaining('Not sent'), findsWidgets);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
      await closeReportsUi(tester, h);
    }
  });
}
