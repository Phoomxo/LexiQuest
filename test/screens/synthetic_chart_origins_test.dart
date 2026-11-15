import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/screens/thesis_chart_screen.dart';

void main() {
  testWidgets('all production origins open the synthetic sample at 200%', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpPage(tester, ProfileSettingsScreen(loader: _loadEmptyProgress));
    await _tap(tester, 'ข้อมูลของฉัน');
    final personalData = _routeOf(tester, 'ข้อมูลของฉัน');
    await _tap(tester, 'ข้อมูลสำหรับงานวิจัย');
    expect(find.byType(ThesisChartScreen), findsOneWidget);
    await _tap(tester, 'ข้อมูลนี้มาจากไหน');
    expect(find.text('ตัวเลขทั้งหมดเป็นข้อมูลสมมติ'), findsOneWidget);
    await _tap(tester, 'กลับไปที่ข้อมูลของฉัน');
    expect(_routeOf(tester, 'ข้อมูลของฉัน'), same(personalData));
    expect(find.byType(ThesisChartScreen), findsNothing);

    await _pumpPage(tester, MasteryDashboardScreen(loader: _loadEmptyProgress));
    final history = _routeOf(tester, 'ภาพรวมการเรียน');
    expect(find.textContaining('คำนวณจาก 0 คำตอบ'), findsOneWidget);
    await _tap(tester, 'ดูตัวอย่างกราฟ');
    expect(find.byType(ThesisChartScreen), findsOneWidget);
    await _tap(tester, 'เวลาในการตอบ');
    final latency = find.text('2.4 วินาที  →  1.6 วินาที');
    await _reveal(tester, latency);
    expect(latency.hitTestable(), findsOneWidget);
    await _tap(tester, 'กลับไปที่ประวัติการฝึก');
    expect(_routeOf(tester, 'ภาพรวมการเรียน'), same(history));
    expect(find.textContaining('คำนวณจาก 0 คำตอบ'), findsOneWidget);

    await _pumpPage(tester, const SettingScreen());
    await _tap(tester, 'งานวิจัยและการเรียน');
    final researchInformation = _routeOf(tester, 'งานวิจัยและการเรียน');
    expect(find.text('เรียนได้ตามปกติโดยไม่ต้องเข้าร่วมวิจัย'), findsOneWidget);
    await _tap(tester, 'ดูกราฟตัวอย่าง');
    expect(find.byType(ThesisChartScreen), findsOneWidget);
    await _tap(tester, 'กลับไปที่งานวิจัยและการเรียน');
    expect(_routeOf(tester, 'งานวิจัยและการเรียน'), same(researchInformation));
    expect(find.byType(ThesisChartScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('research options compare the same two synthetic words at 200%', (
    tester,
  ) async {
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await _pumpPage(tester, const SettingScreen());
    await _tap(tester, 'งานวิจัยและการเรียน');
    final options = _routeOf(tester, 'งานวิจัยและการเรียน');
    await _tap(tester, 'เปรียบเทียบสองรอบ');
    final comparison = _routeOf(tester, 'ก่อนและหลังฝึก');
    await _reveal(tester, find.textContaining('ข้อมูลสมมติ').first);
    expect(find.text('ก่อนฝึก'), findsOneWidget);
    expect(find.text('หลังฝึก'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);

    await _tap(tester, 'ดูคำตอบที่ใช้เปรียบเทียบ');
    expect(find.widgetWithText(AppBar, 'เทียบคำตอบรายคำ'), findsOneWidget);
    expect(find.text('station · เลือกความหมาย'), findsOneWidget);
    expect(find.text('หลังฝึก ตอบว่าสถานี'), findsOneWidget);
    final corrected = find.text('หลังฝึก ตอบว่าชานชาลา');
    await _reveal(tester, corrected);
    expect(find.text('platform · เลือกความหมาย'), findsOneWidget);
    expect(find.text('ก่อนฝึก ตอบว่าสถานี'), findsNWidgets(2));
    expect(corrected.hitTestable(), findsOneWidget);

    await _tap(tester, 'กลับไปดูผลเปรียบเทียบ');
    expect(_routeOf(tester, 'ก่อนและหลังฝึก'), same(comparison));
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('2 / 2'), findsOneWidget);
    await _tap(tester, 'กลับไปดูตัวเลือกงานวิจัย');
    expect(_routeOf(tester, 'งานวิจัยและการเรียน'), same(options));
    expect(find.text('เปรียบเทียบสองรอบ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  await tester.pumpWidget(
    MaterialApp(
      key: ValueKey(page.runtimeType),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: page,
    ),
  );
  await tester.pumpAndSettle();
}

ModalRoute<dynamic> _routeOf(WidgetTester tester, String pageTitle) =>
    ModalRoute.of(tester.element(find.widgetWithText(AppBar, pageTitle)))!;

Future<void> _tap(WidgetTester tester, String label) async {
  final target = find.text(label);
  await _reveal(tester, target);
  await tester.tap(target.hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _reveal(WidgetTester tester, Finder target) async {
  if (target.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target,
      160,
      scrollable: find.byType(Scrollable).hitTestable().last,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<ProgressSnapshot> _loadEmptyProgress() async => const ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);
