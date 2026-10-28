import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/time_tracking/application/active_learning_time_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/application/focus_timer_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/focus_timer.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';
import 'package:vocab_learning_app/features/time_tracking/presentation/focus_timer_widget.dart';

void main() {
  testWidgets('G4.3 replaced timer rejects captured actions and old failures', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 9, 13);
    FocusTimerController controller() {
      final time = ActiveLearningTimeController(
        repository: _MemoryLearningTimeRepository(),
        monotonicMicros: () => 0,
        nowUtc: () => now,
        timezoneContext: (_) => const LearningTimeZoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
      );
      addTearDown(time.dispose);
      final timer = FocusTimerController(timeAuthority: time);
      addTearDown(timer.dispose);
      return timer;
    }

    final old = controller();
    final next = controller();
    final oldPending = Completer<void>();
    final nextPending = Completer<void>();
    addTearDown(() {
      if (!oldPending.isCompleted) oldPending.complete();
      if (!nextPending.isCompleted) nextPending.complete();
    });
    var nextCalls = 0;
    Widget app(FocusTimerController timer) => MaterialApp(
      home: Scaffold(
        body: FocusTimerWidget(
          controller: timer,
          nowUtc: () => now,
          onStart: (_) {
            if (identical(timer, old)) return oldPending.future;
            nextCalls++;
            return nextPending.future;
          },
          onPause: (_) async {},
          onResume: (_) async {},
          onFinish: (_) async {},
        ),
      ),
    );
    await tester.pumpWidget(app(old));
    final key = find.byKey(const ValueKey('focus-timer/start'));
    final captured = tester.widget<FilledButton>(key).onPressed!;
    await tester.tap(key);
    await tester.pump();
    await tester.pumpWidget(app(next));
    captured();
    await tester.pump();
    expect(nextCalls, 0);
    await tester.tap(key);
    await tester.pump();
    oldPending.completeError(StateError('old owner failed'));
    await tester.pump();
    expect(find.byKey(const ValueKey('focus-timer/error')), findsNothing);
    expect(tester.widget<FilledButton>(key).onPressed, isNull);
    nextPending.complete();
    await tester.pump();
    expect(nextCalls, 1);
    expect(tester.widget<FilledButton>(key).onPressed, isNotNull);
  });

  testWidgets(
    'narrow 200 percent text keeps the timer heading duration and action visible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(240, 640);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final now = DateTime.utc(2026, 8, 24, 9);
      final activeTime = ActiveLearningTimeController(
        repository: _MemoryLearningTimeRepository(),
        monotonicMicros: () => 0,
        nowUtc: () => now,
        timezoneContext: (_) => const LearningTimeZoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
      );
      await activeTime.start(sessionId: 'widget-session', occurredAtUtc: now);
      final focusTimer = FocusTimerController(timeAuthority: activeTime)
        ..attachSession('widget-session');
      var acceptedStartCalls = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(240, 640),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: FocusTimerWidget(
                controller: focusTimer,
                nowUtc: () => now,
                onStart: (_) async {
                  acceptedStartCalls += 1;
                },
                onPause: (_) async {},
                onResume: (_) async {},
                onFinish: (_) async {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('จับเวลาเรียน'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('focus-timer/duration')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('focus-timer/start')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey<String>('focus-timer/start')));
      await tester.pump();
      expect(acceptedStartCalls, 1);
      expect(focusTimer.snapshot.status, FocusTimerStatus.notStarted);
      await tester.pumpWidget(const SizedBox.shrink());
      focusTimer.dispose();
      activeTime.dispose();
    },
  );
}

final class _MemoryLearningTimeRepository implements LearningTimeRepository {
  @override
  Future<Duration> activeDuration(String sessionId) async => Duration.zero;

  @override
  Future<void> append(LearningTimeSegment segment) async {}
}
