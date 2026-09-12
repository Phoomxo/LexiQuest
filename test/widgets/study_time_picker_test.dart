import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/widgets/local_study_datetime_field.dart';
import 'package:vocab_learning_app/widgets/study_time_picker.dart';

void main() {
  testWidgets(
    'study time inputs and confirm stay reachable at 240dp and 200%',
    (tester) async {
      final changes = <DateTime?>[];
      await _openClock(tester, changes);

      final inputs = find.byType(TextField);
      expect(inputs, findsNWidgets(2));
      _expectInsideViewport(tester, inputs.at(0));
      _expectInsideViewport(tester, inputs.at(1));
      expect(tester.widget<TextField>(inputs.at(0)).controller!.text, '07');
      expect(tester.widget<TextField>(inputs.at(1)).controller!.text, '15');

      await tester.enterText(inputs.at(0), '23');
      await tester.enterText(inputs.at(1), '45');
      expect(changes, isEmpty);
      await _confirm(tester);

      expect(changes, [DateTime.utc(2026, 9, 8, 16, 45)]);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('out-of-range time remains open until corrected', (tester) async {
    final changes = <DateTime?>[];
    await _openClock(tester, changes);
    final inputs = find.byType(TextField);
    await tester.enterText(inputs.at(0), '24');
    await tester.enterText(inputs.at(1), '60');
    await _confirm(tester);

    expect(changes, isEmpty);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.widget<TextField>(inputs.at(0)).controller!.text, '24');
    expect(tester.widget<TextField>(inputs.at(1)).controller!.text, '60');
    await tester.ensureVisible(inputs.at(0));
    await tester.enterText(inputs.at(0), '23');
    await tester.ensureVisible(inputs.at(1));
    await tester.enterText(inputs.at(1), '45');
    await _confirm(tester);

    expect(changes, [DateTime.utc(2026, 9, 8, 16, 45)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelled clock edits do not change the selected instant', (
    tester,
  ) async {
    final changes = <DateTime?>[];
    await _openClock(tester, changes);
    final inputs = find.byType(TextField);
    await tester.enterText(inputs.at(0), '23');
    await tester.enterText(inputs.at(1), '45');
    final cancel = find.text('ยกเลิก');
    await tester.ensureVisible(cancel);
    _expectInsideViewport(tester, cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(changes, isEmpty);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('07:15'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('minute field and confirm remain reachable above the keyboard', (
    tester,
  ) async {
    final changes = <DateTime?>[];
    await _openClock(tester, changes);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    final inputs = find.byType(TextField);
    await tester.ensureVisible(inputs.at(0));
    await tester.enterText(inputs.at(0), '23');
    await tester.ensureVisible(inputs.at(1));
    await tester.pumpAndSettle();
    _expectInsideViewport(tester, inputs.at(1), bottomInset: 280);
    await tester.enterText(inputs.at(1), '45');
    await _confirm(tester, bottomInset: 280);

    expect(changes, [DateTime.utc(2026, 9, 8, 16, 45)]);
    expect(tester.takeException(), isNull);
  });

  for (final viewport in const [
    (width: 320.0, scale: 1.0),
    (width: 390.0, scale: 2.0),
  ]) {
    testWidgets(
      'picker returns the confirmed time at ${viewport.width}dp scale${viewport.scale}',
      (tester) async {
        var resolved = false;
        TimeOfDay? result;
        await _openPicker(
          tester,
          width: viewport.width,
          scale: viewport.scale,
          onResult: (value) {
            resolved = true;
            result = value;
          },
        );
        final inputs = find.byType(TextField);
        expect(inputs, findsNWidgets(2));
        _expectInsideViewport(tester, inputs.at(0));
        _expectInsideViewport(tester, inputs.at(1));
        await tester.enterText(inputs.at(0), '23');
        await tester.enterText(inputs.at(1), '45');
        expect(resolved, isFalse);
        await _confirm(tester);

        expect(resolved, isTrue);
        expect(result, const TimeOfDay(hour: 23, minute: 45));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('picker cancellation returns null after editing', (tester) async {
    var resolved = false;
    TimeOfDay? result = const TimeOfDay(hour: 7, minute: 15);
    await _openPicker(
      tester,
      width: 240,
      scale: 2,
      onResult: (value) {
        resolved = true;
        result = value;
      },
    );
    final inputs = find.byType(TextField);
    await tester.enterText(inputs.at(0), '23');
    await tester.enterText(inputs.at(1), '45');
    expect(resolved, isFalse);
    final cancel = find.text('ยกเลิก');
    await tester.ensureVisible(cancel);
    _expectInsideViewport(tester, cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();

    expect(resolved, isTrue);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ordinary viewport retains the native 24-hour input picker', (
    tester,
  ) async {
    TimeOfDay? result;
    await _openPicker(
      tester,
      width: 390,
      scale: 1,
      onResult: (value) => result = value,
    );
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.text('ชั่วโมง'), findsOneWidget);
    expect(find.text('นาที'), findsOneWidget);
    final inputs = find.byType(TextField);
    await tester.enterText(inputs.at(0), '23');
    await tester.enterText(inputs.at(1), '45');
    await _confirm(tester);

    expect(result, const TimeOfDay(hour: 23, minute: 45));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openPicker(
  WidgetTester tester, {
  required double width,
  required double scale,
  required ValueChanged<TimeOfDay?> onResult,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 640);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: M3Theme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await showStudyTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 7, minute: 15),
                helpText: 'เลือกเวลา',
              ),
            ),
            child: const Text('เปิดตัวเลือกเวลา'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('เปิดตัวเลือกเวลา'));
  await tester.pumpAndSettle();
}

Future<void> _openClock(WidgetTester tester, List<DateTime?> changes) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(240, 640);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: M3Theme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2), highContrast: true),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: LocalStudyDateTimeField(
            fieldKey: 'responsive-clock',
            referenceUtc: DateTime.utc(2026, 9, 8),
            initialUtc: DateTime.utc(2026, 9, 8, 0, 15),
            onChanged: (instant, _) => changes.add(instant),
          ),
        ),
      ),
    ),
  );
  final timeButton = find.byKey(const ValueKey('responsive-clock/time'));
  await tester.ensureVisible(timeButton);
  await tester.tap(timeButton);
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester, {double bottomInset = 0}) async {
  final confirm = find.text('ตกลง');
  await tester.ensureVisible(confirm);
  await tester.pumpAndSettle();
  _expectInsideViewport(tester, confirm, bottomInset: bottomInset);
  expect(confirm.hitTestable(), findsOneWidget);
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}

void _expectInsideViewport(
  WidgetTester tester,
  Finder target, {
  double bottomInset = 0,
}) {
  final rect = tester.getRect(target);
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(size.width));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.bottom, lessThanOrEqualTo(size.height - bottomInset));
}
