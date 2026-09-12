import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/widgets/local_study_datetime_field.dart';

void main() {
  testWidgets('selected study clock is independent of a host DST gap', (
    tester,
  ) async {
    // Run also on an America/New_York host to expose the old host-local
    // DateTime carrier. This regular run does not claim that host setting.
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalStudyDateTimeField(
            fieldKey: 'test-clock',
            referenceUtc: DateTime.utc(2026, 3, 8),
            onChanged: (instant, zone) => result = instant,
          ),
        ),
      ),
    );
    await _date(tester, '03/08/2026');
    await _time(tester, '02', '30');
    // This clock is valid in Bangkok even when the host's same clock is not.
    expect(result, DateTime.utc(2026, 3, 7, 19, 30));
    expect(find.textContaining('เวลา 02:30'), findsOneWidget);
  });

  testWidgets('cancel and date-only selection never invent a time', (
    tester,
  ) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalStudyDateTimeField(
            fieldKey: 'test-clock',
            referenceUtc: DateTime.utc(2026, 9, 1),
            onChanged: (instant, zone) => result = instant,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('test-clock/date')));
    await tester.pumpAndSettle();
    expect(find.text('เลือกวันที่ · ใช้ปี ค.ศ. เช่น 2026'), findsOneWidget);
    expect(find.text('วันที่ (ปี ค.ศ.)'), findsOneWidget);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    await _date(tester, '09/01/2026');
    expect(result, isNull);
    await _time(tester, '00', '30');
    expect(result, DateTime.utc(2026, 8, 31, 17, 30));
    await tester.tap(find.byKey(const ValueKey('test-clock/time')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(result, DateTime.utc(2026, 8, 31, 17, 30));
  });

  testWidgets('fold requires explicit offset and gap remains unselected', (
    tester,
  ) async {
    DateTime? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalStudyDateTimeField(
            fieldKey: 'test-clock',
            referenceUtc: DateTime.utc(2026, 11, 1),
            initialTimezoneId: 'America/New_York',
            onChanged: (instant, zone) => result = instant,
          ),
        ),
      ),
    );
    await _date(tester, '11/01/2026');
    await _time(tester, '01', '30');
    expect(result, isNull);
    expect(find.textContaining('เกิดขึ้นสองครั้ง'), findsOneWidget);
    final lateFold = find.byKey(
      const ValueKey('test-clock/fold/2026-11-01T06:30:00.000Z'),
    );
    await tester.ensureVisible(lateFold);
    await tester.tap(lateFold);
    await tester.pumpAndSettle();
    expect(result, DateTime.utc(2026, 11, 1, 6, 30));
    await _date(tester, '03/08/2026');
    await _time(tester, '02', '30');
    expect(result, isNull);
    expect(find.textContaining('เวลานี้ไม่มี'), findsOneWidget);
  });

  testWidgets('reopen unchanged preserves initial instant without callback', (
    tester,
  ) async {
    var callbacks = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LocalStudyDateTimeField(
            fieldKey: 'test-clock',
            referenceUtc: DateTime.utc(2026, 11, 1),
            initialUtc: DateTime.utc(2026, 11, 1, 6, 30, 15),
            initialTimezoneId: 'America/New_York',
            onChanged: (instant, zone) => callbacks++,
          ),
        ),
      ),
    );
    expect(find.textContaining('UTC-05:00'), findsOneWidget);
    expect(callbacks, 0);
    await tester.tap(find.byKey(const ValueKey('test-clock/time')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(callbacks, 0);
    expect(find.textContaining('UTC-05:00'), findsOneWidget);
  });
}

Future<void> _date(WidgetTester tester, String date) async {
  final button = find.byKey(const ValueKey('test-clock/date'));
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pumpAndSettle();
  await tester.enterText(
    find
        .descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(TextField),
        )
        .first,
    date,
  );
  await tester.tap(find.widgetWithText(TextButton, 'ตกลง').last);
  await tester.pumpAndSettle();
}

Future<void> _time(WidgetTester tester, String hour, String minute) async {
  await tester.tap(find.byKey(const ValueKey('test-clock/time')));
  await tester.pumpAndSettle();
  final inputs = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(inputs.at(0), hour);
  await tester.enterText(inputs.at(1), minute);
  await tester.tap(find.widgetWithText(TextButton, 'ตกลง').last);
  await tester.pumpAndSettle();
}
