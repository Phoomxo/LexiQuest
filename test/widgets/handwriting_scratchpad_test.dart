import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/widgets/handwriting_scratchpad.dart';

const _toggle = ValueKey('scratchpad-toggle');
const _canvas = ValueKey('scratchpad-canvas');
const _undo = ValueKey('scratchpad-undo');
const _clear = ValueKey('scratchpad-clear');
const _status = ValueKey('scratchpad-status');

final class _Rig {
  bool editable = true;
  double width = 300;
  double inset = 0;
  Object binding = Object();
  final version = ValueNotifier(0);
  final typed = TextEditingController(text: 'typed answer stays unchanged');
  final scroll = ScrollController();
  final boundary = GlobalKey();

  Widget app({String language = 'en', double scale = 1}) =>
      ValueListenableBuilder<int>(
        valueListenable: version,
        builder: (_, value, _) => MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: inset),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: ListView(
              controller: scroll,
              padding: const EdgeInsets.all(16),
              children: [
                const Text('Typed prompt'),
                TextField(controller: typed),
                Center(
                  child: SizedBox(
                    width: width,
                    child: RepaintBoundary(
                      key: boundary,
                      child: HandwritingScratchpad(
                        key: ObjectKey(binding),
                        canEdit: () => editable,
                        languageCode: language,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 1000),
                const Text('Outside scroll target'),
              ],
            ),
          ),
        ),
      );

  void rebuild() => version.value++;
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    typed.dispose();
    scroll.dispose();
    version.dispose();
  }
}

Future<void> _expand(WidgetTester tester) async {
  final toggle = find.byKey(_toggle);
  await tester.ensureVisible(toggle);
  await tester.pump();
  await tester.tap(toggle.hitTestable());
  await tester.pump();
  expect(find.byKey(_canvas), findsOneWidget);
}

String _statusText(WidgetTester tester) {
  final finder = find.byKey(_status);
  final widget = tester.widget(finder);
  if (widget is Text) {
    return widget.data ?? widget.textSpan!.toPlainText();
  }
  return tester
      .widgetList<Text>(
        find.descendant(of: finder, matching: find.byType(Text)),
      )
      .map((text) => text.data ?? text.textSpan!.toPlainText())
      .join(' ');
}

int _strokeCount(WidgetTester tester) {
  final text = _statusText(tester);
  if (text.contains('No strokes') || text.contains('ยังไม่มีเส้น')) return 0;
  return int.parse(RegExp(r'\d+').firstMatch(text)!.group(0)!);
}

Listener _listener(WidgetTester tester) =>
    tester.widget<Listener>(find.byKey(_canvas));
Size _size(WidgetTester tester) => tester.getSize(find.byKey(_canvas));
Offset _local(WidgetTester tester, double x, double y) {
  final size = _size(tester);
  return Offset(size.width * x, size.height * y);
}

VoidCallback? _action(WidgetTester tester, Key key) =>
    switch (tester.widget(find.byKey(key))) {
      final ButtonStyleButton button => button.onPressed,
      final IconButton button => button.onPressed,
      _ => throw StateError('Scratchpad control must expose a button action'),
    };

void _down(
  Listener listener,
  Offset point, {
  int pointer = 1,
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) => listener.onPointerDown!(
  PointerDownEvent(pointer: pointer, position: point, kind: kind),
);
void _move(Listener listener, Offset point, {int pointer = 1}) =>
    listener.onPointerMove!(
      PointerMoveEvent(pointer: pointer, position: point),
    );
void _up(Listener listener, {int pointer = 1}) =>
    listener.onPointerUp!(PointerUpEvent(pointer: pointer));

final class _Pixels {
  const _Pixels(this.width, this.height, this.bytes);
  final int width;
  final int height;
  final Uint8List bytes;
}

Future<_Pixels> _pixels(WidgetTester tester, _Rig rig) async {
  await tester.pump();
  expect(
    find.descendant(
      of: find.byKey(_canvas),
      matching: find.byType(CustomPaint),
    ),
    findsWidgets,
  );
  final boundary =
      rig.boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final canvas = tester.renderObject<RenderBox>(find.byKey(_canvas));
  final origin = canvas.localToGlobal(Offset.zero, ancestor: boundary);
  final image = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: 1).timeout(const Duration(seconds: 3)),
  ))!;
  try {
    final data = (await tester.runAsync<ByteData?>(
      () => image
          .toByteData(format: ui.ImageByteFormat.rawRgba)
          .timeout(const Duration(seconds: 3)),
    ))!;
    final left = (origin.dx + 2).ceil();
    final top = (origin.dy + 2).ceil();
    final width = (origin.dx + canvas.size.width - 2).floor() - left;
    final height = (origin.dy + canvas.size.height - 2).floor() - top;
    expect(width > 0 && height > 0, isTrue);
    expect(left >= 0 && top >= 0, isTrue);
    expect(left + width <= image.width && top + height <= image.height, isTrue);
    final rgba = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final cropped = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      final start = ((top + y) * image.width + left) * 4;
      cropped.setRange(y * width * 4, (y + 1) * width * 4, rgba, start);
    }
    return _Pixels(width, height, cropped);
  } finally {
    image.dispose();
  }
}

void _same(_Pixels a, _Pixels b) {
  expect((b.width, b.height), (a.width, a.height));
  expect(listEquals(a.bytes, b.bytes), isTrue, reason: 'Canvas ink changed');
}

Rect _difference(_Pixels a, _Pixels b) {
  expect((b.width, b.height), (a.width, a.height));
  var left = a.width;
  var top = a.height;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < a.height; y++) {
    for (var x = 0; x < a.width; x++) {
      final i = (y * a.width + x) * 4;
      if (a.bytes[i] == b.bytes[i] &&
          a.bytes[i + 1] == b.bytes[i + 1] &&
          a.bytes[i + 2] == b.bytes[i + 2] &&
          a.bytes[i + 3] == b.bytes[i + 3]) {
        continue;
      }
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < top) top = y;
      if (y > bottom) bottom = y;
    }
  }
  expect(
    right >= left && bottom >= top,
    isTrue,
    reason: 'No painted ink delta',
  );
  return Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

bool _changedNear(_Pixels a, _Pixels b, double x, double y) {
  final cx = (x * a.width).round();
  final cy = (y * a.height).round();
  for (var py = cy - 6; py <= cy + 6; py++) {
    for (var px = cx - 6; px <= cx + 6; px++) {
      if (px < 0 || py < 0 || px >= a.width || py >= a.height) continue;
      final i = (py * a.width + px) * 4;
      for (var channel = 0; channel < 4; channel++) {
        if (a.bytes[i + channel] != b.bytes[i + channel]) return true;
      }
    }
  }
  return false;
}

bool _focusInside(Finder target) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context is! Element) return false;
  final elements = target.evaluate().toSet();
  if (elements.contains(context)) return true;
  var inside = false;
  context.visitAncestorElements((element) {
    if (elements.contains(element)) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  for (var i = 0; i < 20; i++) {
    if (_focusInside(target)) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('Keyboard focus did not reach scratchpad control');
}

void main() {
  testWidgets('initial collapsed memory-only aid has no drawing surface', (
    tester,
  ) async {
    final rig = _Rig();
    try {
      await tester.pumpWidget(rig.app());
      expect(find.byKey(_toggle), findsOneWidget);
      expect(find.byKey(_canvas), findsNothing);
      expect(find.byKey(_undo), findsNothing);
      expect(find.byKey(_clear), findsNothing);
      expect(_strokeCount(tester), 0);
      expect(rig.typed.text, 'typed answer stays unchanged');
    } finally {
      await rig.close(tester);
    }
  });

  testWidgets(
    'actual dot and subsequent line repaint canvas without a status-count change',
    (tester) async {
      final rig = _Rig();
      try {
        await tester.pumpWidget(rig.app());
        await _expand(tester);
        final empty = await _pixels(tester, rig);
        final rect = tester.getRect(find.byKey(_canvas));
        final gesture = await tester.startGesture(
          rect.topLeft + Offset(rect.width * .2, rect.height * .4),
        );
        final dot = await _pixels(tester, rig);
        expect(_strokeCount(tester), 1);
        _difference(empty, dot);
        await gesture.moveTo(
          rect.topLeft + Offset(rect.width * .7, rect.height * .4),
        );
        final line = await _pixels(tester, rig);
        expect(_strokeCount(tester), 1);
        _difference(dot, line);
        expect(_changedNear(empty, line, .6, .4), isTrue);
        await gesture.up();
      } finally {
        await rig.close(tester);
      }
    },
  );

  testWidgets('Undo and Clear erase only ink and repaint the real canvas', (
    tester,
  ) async {
    final rig = _Rig();
    try {
      await tester.pumpWidget(rig.app());
      await _expand(tester);
      final empty = await _pixels(tester, rig);
      _down(_listener(tester), _local(tester, .25, .5));
      _up(_listener(tester));
      await tester.pump();
      _difference(empty, await _pixels(tester, rig));
      _action(tester, _undo)!();
      await tester.pump();
      expect(_strokeCount(tester), 0);
      _same(empty, await _pixels(tester, rig));
      _down(_listener(tester), _local(tester, .6, .4));
      _up(_listener(tester));
      await tester.pump();
      _action(tester, _clear)!();
      await tester.pump();
      _same(empty, await _pixels(tester, rig));
      expect(rig.typed.text, 'typed answer stays unchanged');
    } finally {
      await rig.close(tester);
    }
  });

  testWidgets(
    'normalized dot stays in the same relative position after resize',
    (tester) async {
      final rig = _Rig();
      try {
        await tester.pumpWidget(rig.app());
        await _expand(tester);
        _down(_listener(tester), _local(tester, .25, .5));
        _up(_listener(tester));
        await tester.pump();
        rig.width = 440;
        rig.rebuild();
        await tester.pump();
        expect(_strokeCount(tester), 1);
        final ink = await _pixels(tester, rig);
        _action(tester, _clear)!();
        await tester.pump();
        final empty = await _pixels(tester, rig);
        final bounds = _difference(empty, ink);
        expect(bounds.center.dx / ink.width, closeTo(.25, .035));
        expect(bounds.center.dy / ink.height, closeTo(.5, .035));
      } finally {
        await rig.close(tester);
      }
    },
  );

  testWidgets('secondary pointer cannot draw or retire the primary stroke', (
    tester,
  ) async {
    final rig = _Rig();
    try {
      await tester.pumpWidget(rig.app());
      await _expand(tester);
      final empty = await _pixels(tester, rig);
      final listener = _listener(tester);
      _down(listener, _local(tester, .2, .3), pointer: 11);
      _down(listener, _local(tester, .8, .8), pointer: 12);
      _move(listener, _local(tester, .8, .2), pointer: 12);
      _up(listener, pointer: 12);
      _move(listener, _local(tester, .45, .3), pointer: 11);
      _up(listener, pointer: 11);
      final ink = await _pixels(tester, rig);
      expect(_strokeCount(tester), 1);
      expect(_changedNear(empty, ink, .4, .3), isTrue);
      expect(_changedNear(empty, ink, .8, .8), isFalse);
      expect(_changedNear(empty, ink, .8, .2), isFalse);
    } finally {
      await rig.close(tester);
    }
  });

  testWidgets('finite outliers clamp while NaN and infinity never change ink', (
    tester,
  ) async {
    final rig = _Rig();
    try {
      await tester.pumpWidget(rig.app());
      await _expand(tester);
      final empty = await _pixels(tester, rig);
      final listener = _listener(tester);
      _down(listener, _local(tester, .5, .5));
      final size = _size(tester);
      _move(listener, Offset(size.width * 2, size.height * .7));
      final clamped = await _pixels(tester, rig);
      expect(_changedNear(empty, clamped, .96, .68), isTrue);
      _move(listener, const Offset(double.nan, 10));
      _move(listener, const Offset(10, double.infinity));
      _up(listener);
      _down(listener, const Offset(double.nan, 10), pointer: 2);
      _up(listener, pointer: 2);
      _same(clamped, await _pixels(tester, rig));
      expect(_strokeCount(tester), 1);
      expect(tester.takeException(), isNull);
    } finally {
      await rig.close(tester);
    }
  });

  testWidgets(
    'touch stylus and mouse draw dots without a recognition callback',
    (tester) async {
      final rig = _Rig();
      try {
        await tester.pumpWidget(rig.app());
        await _expand(tester);
        final empty = await _pixels(tester, rig);
        var pointer = 0;
        for (final kind in [
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.mouse,
        ]) {
          pointer++;
          _down(
            _listener(tester),
            _local(tester, .2 * pointer, .5),
            pointer: pointer,
            kind: kind,
          );
          _up(_listener(tester), pointer: pointer);
        }
        await tester.pump();
        expect(_strokeCount(tester), 3);
        _difference(empty, await _pixels(tester, rig));
      } finally {
        await rig.close(tester);
      }
    },
  );

  testWidgets('64 strokes bound memory and Undo frees capacity', (
    tester,
  ) async {
    final rig = _Rig();
    try {
      await tester.pumpWidget(rig.app());
      await _expand(tester);
      final listener = _listener(tester);
      for (var i = 0; i < 64; i++) {
        final x = .1 + (i % 8) * .07;
        final y = .1 + (i ~/ 8) * .1;
        _down(listener, _local(tester, x, y), pointer: i + 1);
        _up(listener, pointer: i + 1);
      }
      final full = await _pixels(tester, rig);
      expect(_strokeCount(tester), 64);
      _down(listener, _local(tester, .9, .5), pointer: 65);
      _up(listener, pointer: 65);
      _same(full, await _pixels(tester, rig));
      expect(_strokeCount(tester), 64);
      expect(
        find.textContaining(RegExp('limit', caseSensitive: false)),
        findsWidgets,
      );
      _action(tester, _undo)!();
      await tester.pump();
      expect(_strokeCount(tester), 63);
      _down(_listener(tester), _local(tester, .9, .5), pointer: 66);
      _up(_listener(tester), pointer: 66);
      await tester.pump();
      expect(_strokeCount(tester), 64);
      _difference(full, await _pixels(tester, rig));
    } finally {
      await rig.close(tester);
    }
  });

  testWidgets(
    '4096 accepted points stop extra paint and Clear frees capacity',
    (tester) async {
      final rig = _Rig();
      try {
        await tester.pumpWidget(rig.app());
        await _expand(tester);
        final empty = await _pixels(tester, rig);
        final listener = _listener(tester);
        final point = _local(tester, .2, .5);
        _down(listener, point);
        for (var i = 0; i < 4095; i++) {
          _move(listener, point);
        }
        final full = await _pixels(tester, rig);
        _difference(empty, full);
        _move(listener, _local(tester, .9, .5));
        _up(listener);
        _same(full, await _pixels(tester, rig));
        expect(_strokeCount(tester), 1);
        expect(
          find.textContaining(RegExp('limit', caseSensitive: false)),
          findsWidgets,
        );
        _action(tester, _clear)!();
        await tester.pump();
        expect(_strokeCount(tester), 0);
        _down(_listener(tester), _local(tester, .9, .5), pointer: 2);
        _up(_listener(tester), pointer: 2);
        await tester.pump();
        expect(_strokeCount(tester), 1);
        _difference(full, await _pixels(tester, rig));
      } finally {
        await rig.close(tester);
      }
    },
  );

  testWidgets(
    'live canEdit false blocks retained pointers and controls before a frame',
    (tester) async {
      final rig = _Rig();
      try {
        await tester.pumpWidget(rig.app());
        await _expand(tester);
        final listener = _listener(tester);
        _down(listener, _local(tester, .2, .4));
        _move(listener, _local(tester, .4, .4));
        final before = await _pixels(tester, rig);
        final undo = _action(tester, _undo)!;
        final clear = _action(tester, _clear)!;
        rig.editable = false;
        _move(listener, _local(tester, .9, .9));
        undo();
        clear();
        _down(listener, _local(tester, .8, .8), pointer: 2);
        rig.editable = true;
        _move(listener, _local(tester, .8, .3));
        _move(listener, _local(tester, .8, .7), pointer: 2);
        _up(listener);
        _up(listener, pointer: 2);
        _same(before, await _pixels(tester, rig));
        expect(_strokeCount(tester), 1);
        _down(_listener(tester), _local(tester, .7, .7), pointer: 3);
        _up(_listener(tester), pointer: 3);
        await tester.pump();
        expect(_strokeCount(tester), 2);
      } finally {
        await rig.close(tester);
      }
    },
  );

  testWidgets('collapse retains ink but retires the active pointer', (
    tester,
  ) async {
    final rig = _Rig();
    try {
      await tester.pumpWidget(rig.app());
      await _expand(tester);
      final listener = _listener(tester);
      _down(listener, _local(tester, .2, .5));
      final before = await _pixels(tester, rig);
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      expect(find.byKey(_canvas), findsNothing);
      await _expand(tester);
      _move(listener, _local(tester, .8, .5));
      _up(listener);
      _same(before, await _pixels(tester, rig));
      expect(_strokeCount(tester), 1);
    } finally {
      await rig.close(tester);
    }
  });

  testWidgets('collapsed retained pointer and Undo Clear callbacks are inert', (
    tester,
  ) async {
    final rig = _Rig();
    try {
      await tester.pumpWidget(rig.app());
      await _expand(tester);
      final listener = _listener(tester);
      _down(listener, _local(tester, .3, .5));
      _up(listener);
      final before = await _pixels(tester, rig);
      final undo = _action(tester, _undo)!;
      final clear = _action(tester, _clear)!;
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      _down(listener, const Offset(200, 100), pointer: 2);
      _move(listener, const Offset(250, 120), pointer: 2);
      _up(listener, pointer: 2);
      undo();
      clear();
      await _expand(tester);
      _same(before, await _pixels(tester, rig));
      expect(_strokeCount(tester), 1);
    } finally {
      await rig.close(tester);
    }
  });

  testWidgets('new canEdit closure and IME rebuild keep the same local draft', (
    tester,
  ) async {
    final rig = _Rig();
    try {
      await tester.pumpWidget(rig.app());
      await _expand(tester);
      _down(_listener(tester), _local(tester, .3, .5));
      _up(_listener(tester));
      final before = await _pixels(tester, rig);
      rig.inset = 180;
      rig.rebuild();
      await tester.pump();
      await tester.ensureVisible(find.byKey(_canvas));
      await tester.pump();
      expect(_strokeCount(tester), 1);
      _same(before, await _pixels(tester, rig));
      expect(rig.typed.text, 'typed answer stays unchanged');
    } finally {
      await rig.close(tester);
    }
  });

  testWidgets('read-only draft can expand for comparison without editing ink', (
    tester,
  ) async {
    final rig = _Rig();
    try {
      await tester.pumpWidget(rig.app());
      await _expand(tester);
      _down(_listener(tester), _local(tester, .3, .5));
      _up(_listener(tester));
      final before = await _pixels(tester, rig);
      rig.editable = false;
      rig.rebuild();
      await tester.pump();
      expect(find.textContaining('Read-only draft'), findsWidgets);
      expect(_action(tester, _undo), isNull);
      expect(_action(tester, _clear), isNull);
      await tester.tap(find.byKey(_toggle));
      await tester.pump();
      await _expand(tester);
      _down(_listener(tester), _local(tester, .8, .5), pointer: 2);
      _up(_listener(tester), pointer: 2);
      _same(before, await _pixels(tester, rig));
      expect(_strokeCount(tester), 1);
    } finally {
      await rig.close(tester);
    }
  });

  testWidgets(
    'only the canvas claims pan and outside dragging scrolls the page',
    (tester) async {
      final rig = _Rig();
      try {
        await tester.pumpWidget(rig.app());
        await _expand(tester);
        final rect = tester.getRect(find.byKey(_canvas));
        final scrollBeforeDrawing = rig.scroll.offset;
        await tester.dragFrom(rect.center, const Offset(0, -60));
        await tester.pump();
        expect(rig.scroll.offset, closeTo(scrollBeforeDrawing, .1));
        expect(_strokeCount(tester), 1);
        final strokes = _strokeCount(tester);
        final outside = Offset(rect.left - 8, rect.center.dy);
        await tester.dragFrom(outside, const Offset(0, -100));
        await tester.pump();
        expect(rig.scroll.offset, greaterThan(scrollBeforeDrawing));
        expect(_strokeCount(tester), strokes);
      } finally {
        await rig.close(tester);
      }
    },
  );

  for (final language in ['th', 'en']) {
    testWidgets(
      '$language 320px 200 percent IME controls work by Tab and Enter',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final rig = _Rig()..width = 288;
        try {
          await tester.pumpWidget(rig.app(language: language, scale: 2));
          await _tabTo(tester, find.byKey(_toggle));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(find.byKey(_canvas), findsOneWidget);
          _down(_listener(tester), _local(tester, .3, .5));
          _up(_listener(tester));
          await tester.pump();
          expect(_strokeCount(tester), 1);
          rig.inset = 220;
          rig.rebuild();
          await tester.pump();
          await _tabTo(tester, find.byKey(_undo));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(_strokeCount(tester), 0);
          await tester.ensureVisible(find.byKey(_canvas));
          await tester.pump();
          _down(_listener(tester), _local(tester, .6, .5));
          _up(_listener(tester));
          await tester.pump();
          await _tabTo(tester, find.byKey(_clear));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pump();
          expect(_strokeCount(tester), 0);
          expect(rig.typed.text, 'typed answer stays unchanged');
          expect(tester.takeException(), isNull);
        } finally {
          await rig.close(tester);
        }
      },
    );
  }

  testWidgets('new ObjectKey and actual disposal start with no retained ink', (
    tester,
  ) async {
    final rig = _Rig();
    try {
      await tester.pumpWidget(rig.app());
      await _expand(tester);
      _down(_listener(tester), _local(tester, .3, .5));
      _up(_listener(tester));
      await tester.pump();
      expect(_strokeCount(tester), 1);
      rig.binding = Object();
      rig.rebuild();
      await tester.pump();
      expect(find.byKey(_canvas), findsNothing);
      expect(_strokeCount(tester), 0);
      await _expand(tester);
      _down(_listener(tester), _local(tester, .4, .5));
      _up(_listener(tester));
      await tester.pump();
      final retired = _listener(tester);
      final undo = _action(tester, _undo)!;
      final clear = _action(tester, _clear)!;
      await tester.pumpWidget(const SizedBox.shrink());
      _down(retired, const Offset(20, 20), pointer: 99);
      _move(retired, const Offset(40, 40), pointer: 99);
      _up(retired, pointer: 99);
      undo();
      clear();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(rig.app());
      expect(find.byKey(_canvas), findsNothing);
      expect(_strokeCount(tester), 0);
    } finally {
      await rig.close(tester);
    }
  });
}
