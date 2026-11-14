import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/widgets/handwriting_scratchpad.dart';

const _surface = Key('scratch-test-surface');
final _board = find.bySemanticsLabel('พื้นที่ฝึกเขียน');

Future<void> _show(
  WidgetTester tester, {
  required VoidCallback done,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: RepaintBoundary(
            key: _surface,
            child: SingleChildScrollView(
              child: HandwritingScratchpad(
                spelling: 'ticket',
                meaning: 'ตั๋ว',
                onDone: done,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _press(WidgetTester tester, String label) async {
  // A preceding pen-up or text edit schedules a frame that enables Compare.
  // Deliver the next gesture against the rebuilt, scrolled control.
  await tester.pumpAndSettle();
  final button = find.ancestor(
    of: find.text(label),
    matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  );
  expect(button, findsOneWidget, reason: label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  expect(
    tester.widget<ButtonStyleButton>(button).onPressed,
    isNotNull,
    reason: label,
  );
  expect(button.hitTestable(), findsOneWidget, reason: label);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

// Sample visible pixels around each stroke; the test knows nothing about how
// the widget stores points, how many painters it uses, or the current ink color.
Future<List<List<int>>> _ink(WidgetTester tester) async {
  await tester.ensureVisible(_board);
  await tester.pumpAndSettle();
  final surface = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_surface),
  );
  final boundary = tester.getRect(_board);
  final points = [
    for (final y in [0.25, 0.5, 0.75])
      surface.globalToLocal(
        Offset(boundary.center.dx, boundary.top + boundary.height * y),
      ),
  ];
  return (await tester.runAsync(() async {
    final image = await surface.toImage(pixelRatio: 1);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      return [
        for (final point in points)
          [
            for (var y = point.dy.floor() - 3; y <= point.dy.floor() + 3; y++)
              for (var x = point.dx.floor() - 3; x <= point.dx.floor() + 3; x++)
                bytes.getUint32((y * image.width + x) * 4),
          ],
      ];
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  testWidgets(
    'two drawn strokes and a dot can be undone independently or cleared',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await _show(tester, done: () {});
        expect(_board, findsOneWidget);
        final empty = await _ink(tester);
        final rect = tester.getRect(_board);
        for (final y in [0.25, 0.5]) {
          final start = Offset(
            rect.left + rect.width * 0.25,
            rect.top + rect.height * y,
          );
          final pointer = await tester.startGesture(start);
          await pointer.moveTo(Offset(rect.center.dx, start.dy));
          await pointer.moveTo(
            Offset(rect.right - rect.width * 0.25, start.dy),
          );
          await pointer.up();
        }
        await tester.tapAt(
          Offset(rect.center.dx, rect.top + rect.height * 0.75),
        );
        final drawn = await _ink(tester);
        for (var i = 0; i < 3; i++) {
          expect(
            drawn[i],
            isNot(equals(empty[i])),
            reason: 'mark ${i + 1} must be visible',
          );
        }
        await _press(tester, 'ย้อนการเขียนครั้งล่าสุด');
        expect(await _ink(tester), [drawn[0], drawn[1], empty[2]]);
        await _press(tester, 'ย้อนการเขียนครั้งล่าสุด');
        expect(await _ink(tester), [drawn[0], empty[1], empty[2]]);
        await _press(tester, 'ล้างกระดาน');
        expect(await _ink(tester), empty);
        final freshRect = tester.getRect(_board);
        await tester.tapAt(freshRect.center);
        expect((await _ink(tester))[1], isNot(equals(empty[1])));
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'the example is separate from ink and the learner decides after comparing',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        var done = 0;
        await _show(tester, done: () => done++);
        expect(find.textContaining('ตั๋ว'), findsWidgets);
        expect(find.text('ticket'), findsNothing);
        final empty = await _ink(tester);
        await _press(tester, 'ดูตัวอย่างการเขียน');
        expect(find.text('ticket'), findsOneWidget);
        expect(await _ink(tester), empty);
        await tester.tapAt(tester.getCenter(_board));
        await _press(tester, 'เทียบกับคำเฉลย');
        expect(find.text('ticket'), findsWidgets);
        expect(done, 0);
        await _press(tester, 'ลองเขียนอีกครั้ง');
        await _press(tester, 'เทียบกับคำเฉลย');
        await _press(tester, 'ฉันสะกดตรงกับเฉลย');
        expect(find.text('คุณประเมินว่าตรงกับเฉลย'), findsOneWidget);
        expect(done, 0);
        await _press(tester, 'เลือกรูปแบบโจทย์อื่น');
        expect(done, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await _show(tester, done: () => done++);
        expect(find.text('ticket'), findsNothing);
        expect(await _ink(tester), empty);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'typed alternative and self-check controls remain reachable at 200 percent',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(360, 640);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var done = 0;
        await _show(tester, done: () => done++, scale: 2);
        await _press(tester, 'ใช้ข้อความแทน');
        final input = find.byType(TextField);
        await tester.ensureVisible(input);
        await tester.enterText(input, 'tikcet');
        await _press(tester, 'เทียบกับคำเฉลย');
        expect(find.text('ticket'), findsWidgets);
        expect(find.text('tikcet'), findsOneWidget);
        expect(done, 0);
        await _press(tester, 'ลองเขียนอีกครั้ง');
        expect(find.text('tikcet'), findsOneWidget);
        await tester.enterText(input, 'ticket');
        await _press(tester, 'เทียบกับคำเฉลย');
        await _press(tester, 'ฉันสะกดตรงกับเฉลย');
        await _press(tester, 'เลือกรูปแบบโจทย์อื่น');
        expect(done, 1);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
