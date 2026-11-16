import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';
import 'package:vocab_learning_app/screens/learning_calendar_screen.dart';

void main() {
  _recoveryTests();
  testWidgets('labels effort accuracy skills and trend as separate axes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(home: LearningCalendarScreen(loader: () async => _calendar)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ปฏิทินการเรียน'), findsOneWidget);
    expect(find.text('ความพยายาม (เวลาที่เรียนจริง)'), findsOneWidget);
    expect(find.text('ความแม่นยำ'), findsOneWidget);
    expect(find.text('การกระจายทักษะ'), findsOneWidget);
    expect(find.text('แนวโน้มความแม่นยำ'), findsOneWidget);
    expect(find.text('75 วินาที'), findsOneWidget);
    expect(find.text('ตอบถูก 1 จาก 1 คำตอบ · 100%'), findsOneWidget);
    expect(find.bySemanticsLabel('แกนความพยายาม'), findsOneWidget);
    expect(find.bySemanticsLabel('แกนความแม่นยำ'), findsOneWidget);
    expect(find.bySemanticsLabel('แกนการกระจายทักษะ'), findsOneWidget);
    expect(find.bySemanticsLabel('แกนแนวโน้มความแม่นยำ'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('empty calendar states preserve separate null accuracy', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LearningCalendarScreen(loader: () async => _emptyCalendar),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('0 วินาที'), findsOneWidget);
    expect(find.text('ยังไม่มีคำตอบที่นับความแม่นยำได้'), findsOneWidget);
    expect(find.text('ยังไม่มีทักษะจากคำตอบในสัปดาห์นี้'), findsOneWidget);
  });
}

final _calendar = LearningCalendarSnapshot(
  timezoneId: 'Asia/Bangkok',
  weekStart: DateTime(2026, 8, 24),
  days: [
    LearningCalendarDay(
      day: DateTime(2026, 8, 24),
      effort: LearningEffortAxis(activeDuration: Duration(seconds: 75)),
      accuracy: LearningAccuracyAxis(sampleSize: 1, correctCount: 1),
      skillDistribution: [
        LearningSkillDistribution(
          skillId: 'listening',
          sampleSize: 1,
          correctCount: 1,
        ),
      ],
    ),
  ],
  weekly: WeeklyLearningAnalytics(
    effort: LearningEffortAxis(activeDuration: Duration(seconds: 75)),
    accuracy: LearningAccuracyAxis(sampleSize: 1, correctCount: 1),
    skillDistribution: [
      LearningSkillDistribution(
        skillId: 'listening',
        sampleSize: 1,
        correctCount: 1,
      ),
    ],
    accuracyTrend: [
      LearningAccuracyTrendPoint(
        day: DateTime(2026, 8, 24),
        accuracy: LearningAccuracyAxis(sampleSize: 1, correctCount: 1),
      ),
    ],
  ),
);

final _emptyCalendar = LearningCalendarSnapshot(
  timezoneId: 'Asia/Bangkok',
  weekStart: DateTime(2026, 8, 24),
  days: [
    LearningCalendarDay(
      day: DateTime(2026, 8, 24),
      effort: LearningEffortAxis(activeDuration: Duration.zero),
      accuracy: LearningAccuracyAxis(sampleSize: 0, correctCount: 0),
      skillDistribution: [],
    ),
  ],
  weekly: WeeklyLearningAnalytics(
    effort: LearningEffortAxis(activeDuration: Duration.zero),
    accuracy: LearningAccuracyAxis(sampleSize: 0, correctCount: 0),
    skillDistribution: [],
    accuracyTrend: [
      LearningAccuracyTrendPoint(
        day: DateTime(2026, 8, 24),
        accuracy: LearningAccuracyAxis(sampleSize: 0, correctCount: 0),
      ),
    ],
  ),
);

void _recoveryTests() {
  testWidgets(
    'AM app inactivity hides private snapshot and refreshes on resume',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LearningCalendarScreen(
            loader: () async => ++calls == 1 ? _calendar : _emptyCalendar,
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('75 วินาที'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('0 วินาที'), findsOneWidget);
      expect(calls, 2);
    },
  );
  for (final lateError in [false, true]) {
    testWidgets(
      'AM disposed pending calendar ignores completion error=$lateError',
      (tester) async {
        final pending = Completer<LearningCalendarSnapshot>();
        await tester.pumpWidget(
          MaterialApp(
            home: LearningCalendarScreen(loader: () => pending.future),
          ),
        );
        await tester.pumpWidget(const SizedBox());
        if (lateError) {
          pending.completeError(StateError('retired'));
        } else {
          pending.complete(_calendar);
        }
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final synchronous in [false, true]) {
    testWidgets(
      'AM immediate failure and repeated bounded retry sync=$synchronous',
      (tester) async {
        var calls = 0;
        final pending = Completer<LearningCalendarSnapshot>();
        Future<LearningCalendarSnapshot> load() {
          calls++;
          if (calls <= 2) {
            if (synchronous) throw StateError('unavailable');
            return Future.error(StateError('unavailable'));
          }
          return pending.future;
        }

        await tester.pumpWidget(
          MaterialApp(home: LearningCalendarScreen(loader: load)),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(calls, 1);
        var retry = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'ลองอีกครั้ง'),
            )
            .onPressed!;
        retry();
        retry();
        await tester.pumpAndSettle();
        expect(calls, 2);
        retry = tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'ลองอีกครั้ง'),
            )
            .onPressed!;
        retry();
        retry();
        await tester.pump();
        expect(calls, 3);
        pending.complete(_calendar);
        await tester.pumpAndSettle();
        expect(find.text('75 วินาที'), findsOneWidget);
        retry();
        await tester.pump();
        expect(calls, 3);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('AM loader replacement hides old data and ignores late result', (
    tester,
  ) async {
    final old = Completer<LearningCalendarSnapshot>();
    final next = Completer<LearningCalendarSnapshot>();
    Widget app(LearningCalendarLoader loader) =>
        MaterialApp(home: LearningCalendarScreen(loader: loader));
    await tester.pumpWidget(app(() => old.future));
    await tester.pumpWidget(app(() => next.future));
    old.complete(_calendar);
    await tester.pump();
    expect(find.text('75 วินาที'), findsNothing);
    next.complete(_emptyCalendar);
    await tester.pumpAndSettle();
    expect(find.text('0 วินาที'), findsOneWidget);
  });
  testWidgets('AM inactive calendar retires data and rereads on return', (
    tester,
  ) async {
    var calls = 0;
    Future<LearningCalendarSnapshot> load() async =>
        ++calls == 1 ? _calendar : _emptyCalendar;
    Widget app(bool active) => MaterialApp(
      home: TickerMode(
        enabled: active,
        child: LearningCalendarScreen(loader: load),
      ),
    );
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(find.text('75 วินาที'), findsOneWidget);
    await tester.pumpWidget(app(false));
    expect(find.text('75 วินาที'), findsNothing);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('0 วินาที'), findsOneWidget);
  });
  testWidgets('AM cover retires snapshot and rereads after return', (
    tester,
  ) async {
    var calls = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: LearningCalendarScreen(
          loader: () async => ++calls == 1 ? _calendar : _emptyCalendar,
        ),
      ),
    );
    await tester.pumpAndSettle();
    nav.currentState!.push(
      DialogRoute<void>(
        context: nav.currentContext!,
        builder: (_) => const AlertDialog(content: Text('cover')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('75 วินาที', skipOffstage: false), findsNothing);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('0 วินาที'), findsOneWidget);
  });
  testWidgets('AM popped retry and disposed pending read stay retired', (
    tester,
  ) async {
    var calls = 0;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(navigatorKey: nav, home: const Scaffold()),
    );
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => LearningCalendarScreen(
          loader: () {
            calls++;
            return Future.error(StateError('read'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final retry = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลองอีกครั้ง'))
        .onPressed!;
    nav.currentState!.pop();
    retry();
    await tester.pumpAndSettle();
    retry();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('AM Thai recovery is reachable at 360px and 200 percent', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.physicalSize = const Size(360, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: LearningCalendarScreen(
          loader: () async => throw StateError('read'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ลองอีกครั้ง'));
    expect(find.bySemanticsLabel('ลองอีกครั้ง'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
