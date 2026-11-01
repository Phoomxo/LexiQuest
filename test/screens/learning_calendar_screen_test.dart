import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';
import 'package:vocab_learning_app/screens/learning_calendar_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fonts = FontLoader('NotoSansThai')
      ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'));
    await fonts.load();
  });

  testWidgets(
    'calendar keeps answer analytics when time is unavailable and navigates months',
    (tester) async {
      final owners = StreamController<String?>.broadcast();
      addTearDown(owners.close);
      final periods = <LearningCalendarPeriod>[];
      await tester.pumpWidget(
        MaterialApp(
          home: LearningCalendarScreen(
            now: () => DateTime(2026, 11, 7),
            ownerChanges: owners.stream,
            loader:
                ({
                  required period,
                  required expectedOwnerId,
                  required stillCurrent,
                }) async {
                  periods.add(period);
                  return _snapshot(expectedOwnerId, period);
                },
          ),
        ),
      );
      owners.add('synthetic-owner');
      await tester.pumpAndSettle();
      expect(find.text('60 คำตอบ'), findsOneWidget);
      expect(
        find.textContaining('เวลาปฏิสัมพันธ์ที่บันทึก อ่านเวลาไม่ได้'),
        findsOneWidget,
      );
      await tester.tap(find.text('รายเดือน'));
      await tester.pumpAndSettle();
      expect(periods.last.firstDay, DateTime(2026, 11, 1));
      expect(periods.last.dayCount, 30);
      await tester.tap(find.byKey(const ValueKey('calendar-previous')));
      await tester.pumpAndSettle();
      expect(periods.last.firstDay, DateTime(2026, 10, 1));
      expect(periods.last.dayCount, 31);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('calendar hides old owner while a delayed read completes', (
    tester,
  ) async {
    final owners = StreamController<String?>.broadcast();
    addTearDown(owners.close);
    final pending = Completer<LearningCalendarSnapshot>();
    LearningCalendarPeriod? requested;
    await tester.pumpWidget(
      MaterialApp(
        home: LearningCalendarScreen(
          now: () => DateTime(2026, 11, 7),
          ownerChanges: owners.stream,
          loader:
              ({
                required period,
                required expectedOwnerId,
                required stillCurrent,
              }) {
                requested = period;
                return pending.future;
              },
        ),
      ),
    );
    owners.add('synthetic-owner-a');
    await tester.pump();
    owners.add(null);
    await tester.pump();
    pending.complete(_snapshot('synthetic-owner-a', requested!));
    await tester.pumpAndSettle();
    expect(find.text('60 คำตอบ'), findsNothing);
    expect(find.text('ยังไม่มีพื้นที่เรียนที่เปิดอยู่'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('calendar retry reads again after an unavailable answer source', (
    tester,
  ) async {
    final owners = StreamController<String?>.broadcast();
    addTearDown(owners.close);
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LearningCalendarScreen(
          now: () => DateTime(2026, 11, 7),
          ownerChanges: owners.stream,
          loader:
              ({
                required period,
                required expectedOwnerId,
                required stillCurrent,
              }) async {
                if (attempts++ == 0) {
                  throw StateError('synthetic storage outage');
                }
                return _snapshot(expectedOwnerId, period);
              },
        ),
      ),
    );
    owners.add('synthetic-owner');
    await tester.pumpAndSettle();
    expect(find.text('อ่านปฏิทินไม่สำเร็จ โปรดลองใหม่'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('calendar-refresh')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.text('60 คำตอบ'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'paused calendar discards an in-flight read and refreshes on resume',
    (tester) async {
      final owners = StreamController<String?>.broadcast();
      addTearDown(owners.close);
      final pending = Completer<LearningCalendarSnapshot>();
      LearningCalendarPeriod? requested;
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: LearningCalendarScreen(
            now: () => DateTime(2026, 11, 7),
            ownerChanges: owners.stream,
            loader:
                ({
                  required period,
                  required expectedOwnerId,
                  required stillCurrent,
                }) {
                  requested = period;
                  return attempts++ == 0
                      ? pending.future
                      : Future.value(_snapshot(expectedOwnerId, period));
                },
          ),
        ),
      );
      owners.add('synthetic-owner');
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      pending.complete(_snapshot('synthetic-owner', requested!));
      await tester.pump();
      expect(find.text('60 คำตอบ'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.text('60 คำตอบ'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'calendar remains readable at320px200percent with keyboard $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 720);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final owners = StreamController<String?>.broadcast();
        addTearDown(owners.close);
        await tester.pumpWidget(
          MaterialApp(
            theme: brightness == Brightness.light
                ? M3Theme.lightTheme
                : M3Theme.darkTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 260),
              ),
              child: child!,
            ),
            home: LearningCalendarScreen(
              now: () => DateTime(2026, 11, 7),
              ownerChanges: owners.stream,
              loader:
                  ({
                    required period,
                    required expectedOwnerId,
                    required stillCurrent,
                  }) async => _snapshot(expectedOwnerId, period),
            ),
          ),
        );
        owners.add('synthetic-owner');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('calendar-day-2026-11-7')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('7/11/2026'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}

LearningCalendarSnapshot _snapshot(
  String owner,
  LearningCalendarPeriod period,
) => LearningCalendarSnapshot(
  ownerId: owner,
  period: period,
  days: [
    for (var index = 0; index < period.dayCount; index++)
      LearningCalendarDay(
        date: period.dayAt(index),
        answerCount: index == 0 ? 60 : 0,
        correctCount: index == 0 ? 30 : 0,
        completedSessionCount: index == 0 ? 2 : 0,
        recordedTime: const RecordedTimeRead.unavailable(),
      ),
  ],
);
