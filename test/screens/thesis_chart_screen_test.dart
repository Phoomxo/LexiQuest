import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/thesis_chart_screen.dart';

void main() {
  testWidgets('sample shows the same score in text and bars at 200%', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final semantics = tester.ensureSemantics();
    const returnLabel = 'กลับไปที่ข้อมูลของฉัน';
    await _openFrom(tester, returnLabel, textScale: 2);

    expect(find.text('อ่านกราฟตัวอย่าง'), findsOneWidget);
    expect(find.text('ผู้เรียนสมมติหนึ่งคน · ชุดคำเดียวกัน'), findsOneWidget);
    final bars = tester.widgetList<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bars.map((bar) => bar.value), [0.4, 0.6]);
    expect(find.bySemanticsLabel('ก่อนฝึก 2 จาก 5 ข้อ'), findsOneWidget);
    expect(find.bySemanticsLabel('หลังฝึก 3 จาก 5 ข้อ'), findsOneWidget);

    await _tap(tester, 'เวลาในการตอบ');
    expect(find.text('เปรียบเทียบสองรอบ'), findsOneWidget);
    expect(find.text('2 จาก 5  →  3 จาก 5'), findsOneWidget);
    expect(find.text('ข้อที่ตอบถูกคิดเป็น 40% และ 60%'), findsOneWidget);
    final latency = find.text('2.4 วินาที  →  1.6 วินาที');
    await _reveal(tester, latency);
    expect(latency.hitTestable(), findsOneWidget);
    await _tap(tester, 'ดูกราฟอีกครั้ง');
    expect(find.text('อ่านกราฟตัวอย่าง'), findsOneWidget);

    await _tap(tester, 'ข้อมูลนี้มาจากไหน');
    expect(find.text('ที่มาของตัวเลข'), findsOneWidget);
    expect(find.text('ตัวเลขทั้งหมดเป็นข้อมูลสมมติ'), findsOneWidget);
    expect(
      find.text('ตัวอย่างนี้ไม่ลงทะเบียนหรือส่งข้อมูลวิจัย'),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('อ่านกราฟตัวอย่าง'), findsOneWidget);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  for (final (origin, detail) in [
    ('ข้อมูลของฉัน', null),
    ('ประวัติการฝึก', 'เวลาในการตอบ'),
    ('งานวิจัยและการเรียน', 'ข้อมูลนี้มาจากไหน'),
  ]) {
    testWidgets('return from sample reaches the same $origin route', (
      tester,
    ) async {
      final returnLabel = 'กลับไปที่$origin';
      final originState = await _openFrom(tester, returnLabel);
      if (detail != null) await _tap(tester, detail);
      await _tap(tester, returnLabel);

      expect(tester.state(find.byType(_Origin)), same(originState));
      expect(find.byType(ThesisChartScreen), findsNothing);
      expect(find.text('Open parent'), findsNothing);
    });
  }
}

Future<State<_Origin>> _openFrom(
  WidgetTester tester,
  String returnLabel, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => _Origin(returnLabel: returnLabel),
              ),
            ),
            child: const Text('Open parent'),
          ),
        ),
      ),
    ),
  );
  await _tap(tester, 'Open parent');
  final state = tester.state<_OriginState>(find.byType(_Origin));
  await _tap(tester, 'เปิดกราฟตัวอย่าง');
  return state;
}

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      150,
      scrollable: find.byType(Scrollable).hitTestable().last,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

class _Origin extends StatefulWidget {
  const _Origin({required this.returnLabel});

  final String returnLabel;

  @override
  State<_Origin> createState() => _OriginState();
}

class _OriginState extends State<_Origin> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextButton(
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ThesisChartScreen(returnLabel: widget.returnLabel),
        ),
      ),
      child: const Text('เปิดกราฟตัวอย่าง'),
    ),
  );
}
