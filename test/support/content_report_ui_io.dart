import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'motivation_presentation_io.dart';

Future<void> reportUiWait(
  WidgetTester tester,
  String stage,
  bool Function() ready,
) async {
  for (var frame = 0; frame < 160; frame++) {
    if (ready()) return;
    await motivationPresentationIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
      stage: 'report-$stage-io',
    );
    await motivationPresentationDeadline(
      tester,
      'report-$stage-frame',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
  }
  fail('Report UI did not reach $stage');
}

Future<void> reportUiReveal(
  WidgetTester tester,
  Finder finder,
  String stage, {
  required Finder scrollable,
}) async {
  for (var step = 0; step < 24; step++) {
    await motivationPresentationIo(
      tester,
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
      stage: 'report-reveal-$stage-io',
    );
    await motivationPresentationDeadline(
      tester,
      'report-reveal-$stage-frame',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
    if (finder.evaluate().isNotEmpty) break;
    final visibleList = scrollable.hitTestable();
    if (visibleList.evaluate().isNotEmpty) {
      await motivationPresentationDeadline(
        tester,
        'report-reveal-$stage-drag',
        () => tester.drag(visibleList.last, const Offset(0, -180)),
      );
      await motivationPresentationDeadline(
        tester,
        'report-reveal-$stage-scroll',
        () => tester.pump(const Duration(milliseconds: 80)),
      );
    }
  }
  expect(finder, findsOneWidget, reason: 'User scrolling must reveal $stage');
  if (finder.hitTestable().evaluate().isEmpty) {
    await motivationPresentationIo(
      tester,
      () => Scrollable.ensureVisible(tester.element(finder), alignment: 0.5),
      stage: 'report-reveal-$stage-center',
    );
  }
  await reportUiWait(
    tester,
    'revealed-$stage',
    () => finder.hitTestable().evaluate().length == 1,
  );
}

Future<void> reportUiTap(
  WidgetTester tester,
  Finder finder,
  String stage,
) async {
  await reportUiWait(tester, stage, () {
    if (finder.evaluate().length != 1) return false;
    final widget = tester.widget(finder);
    if (widget is ButtonStyleButton) return widget.onPressed != null;
    if (widget is IconButton) return widget.onPressed != null;
    if (widget is ChoiceChip) return widget.onSelected != null;
    if (widget is ListTile) return widget.onTap != null;
    return true;
  });
  await motivationPresentationDeadline(
    tester,
    'report-transition-$stage',
    () => tester.pump(const Duration(milliseconds: 350)),
  );
  if (finder.hitTestable().evaluate().isEmpty) {
    await motivationPresentationIo(
      tester,
      () => Scrollable.ensureVisible(tester.element(finder), alignment: 0.5),
      stage: 'report-scroll-$stage',
    );
  }
  await reportUiWait(
    tester,
    'hit-testable-$stage',
    () => finder.hitTestable().evaluate().length == 1,
  );
  await tester.pump();
  await tester.tap(finder.hitTestable());
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> reportUiTapKey(WidgetTester tester, String key) =>
    reportUiTap(tester, find.byKey(ValueKey(key)), key);
