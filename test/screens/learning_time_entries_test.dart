import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/learning_time/application/learning_time_use_cases.dart';
import 'package:vocab_learning_app/features/learning_time/presentation/recorded_time_view.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/learning_time_settings_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('settings opens the existing owner-bound local time control', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    await tester.pumpWidget(
      MaterialApp(home: SettingScreen(learningTime: h.time)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-learning-time')));
    await tester.pumpAndSettle();
    final screen = tester.widget<LearningTimeSettingsScreen>(
      find.byType(LearningTimeSettingsScreen),
    );
    expect(identical(screen.time, h.time), isTrue);
    expect(screen.expectedOwnerId, 'owner-a');
    expect(h.repo.preferenceWrites, 0);
    expect(h.repo.admissions, 0);
    await h.close(tester);
  });

  testWidgets('captured settings entry cannot survive owner ABA', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    await tester.pumpWidget(
      MaterialApp(home: SettingScreen(learningTime: h.time)),
    );
    await tester.pumpAndSettle();
    final open = tester
        .widget<ListTile>(find.byKey(const ValueKey('settings-learning-time')))
        .onTap!;
    await tester.runAsync(() async {
      h.owners
        ..add('owner-b')
        ..add('owner-a');
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
    open();
    await tester.pumpAndSettle();
    expect(find.byType(LearningTimeSettingsScreen), findsNothing);
    expect(h.repo.preferenceWrites, 0);
    await h.close(tester);
  });

  testWidgets('settings cannot enter time control through a foreign cover', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: SettingScreen(learningTime: h.time),
      ),
    );
    await tester.pumpAndSettle();
    final open = tester
        .widget<ListTile>(find.byKey(const ValueKey('settings-learning-time')))
        .onTap!;
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('foreign cover')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    open();
    await tester.pumpAndSettle();
    expect(find.text('foreign cover'), findsOneWidget);
    expect(find.byType(LearningTimeSettingsScreen), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    open();
    await tester.pumpAndSettle();
    expect(find.byType(LearningTimeSettingsScreen), findsNothing);
    await h.close(tester);
  });

  for (final failProgress in [false, true]) {
    testWidgets(
      'time totals remain readable with ${failProgress ? 'failed' : 'empty'} progress',
      (tester) async {
        final h = await _Harness.open(tester);
        await tester.pumpWidget(
          MaterialApp(
            home: MasteryDashboardScreen(
              learningTime: h.time,
              ownerChanges: h.owners.stream,
              loader: () async {
                if (failProgress) {
                  throw StateError('synthetic progress failure');
                }
                return _empty;
              },
            ),
          ),
        );
        h.owners.add('owner-a');
        await _flush(tester);
        expect(find.byType(RecordedTimeView), findsOneWidget);
        expect(find.text('2 seconds'), findsOneWidget);
        expect(h.repo.readTargets.whereType<OwnerTimeRead>(), isNotEmpty);
        expect(
          find.textContaining(
            failProgress
                ? 'ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'
                : 'คำนวณจาก 0 คำตอบ',
          ),
          findsOneWidget,
        );
        expect(h.repo.admissions, 0);
        expect(h.repo.preferenceWrites, 0);
        await h.close(tester);
      },
    );
  }

  for (final language in ['th', 'en']) {
    testWidgets(
      'score keeps $language copy consistent and folds time details',
      (tester) async {
        final h = await _Harness.open(tester);
        final thai = language == 'th';
        await tester.pumpWidget(
          MaterialApp(
            home: ScoreScreen(
              correctAnswers: 1,
              wrongAnswers: 0,
              languageCode: language,
              learningTime: h.time,
              resultOwnerId: 'owner-a',
              resultSessionId: 'actual-canonical-session',
            ),
          ),
        );
        await _flush(tester);
        expect(find.text(thai ? 'ผลการเรียน' : 'Results'), findsOneWidget);
        expect(find.text(thai ? 'ตอบถูก' : 'Correct'), findsOneWidget);
        expect(find.text(thai ? '2 วินาที' : '2 seconds'), findsOneWidget);
        expect(
          find.widgetWithText(FilledButton, thai ? 'เสร็จแล้ว' : 'Done'),
          findsOneWidget,
        );
        final explanation = find.textContaining(
          thai ? 'เก็บเฉพาะช่วงการโต้ตอบ' : 'Includes locally saved',
        );
        expect(explanation, findsNothing);
        await tester.tap(
          find.text(thai ? 'วิธีนับเวลา' : 'How time is counted'),
        );
        await tester.pumpAndSettle();
        expect(explanation, findsOneWidget);
        expect(h.repo.admissions, 0);
        expect(h.repo.preferenceWrites, 0);
        await h.close(tester);
      },
    );
  }

  testWidgets('score back returns to its actual history route', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const ScoreScreen(correctAnswers: 4, wrongAnswers: 0),
                ),
              ),
              child: const Text('ประวัติการเรียน'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ประวัติการเรียน'));
    await tester.pumpAndSettle();
    expect(find.text('กลับไปเลือกกิจกรรม'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'เสร็จแล้ว'));
    await tester.pumpAndSettle();
    expect(find.byType(ScoreScreen), findsNothing);
    expect(find.text('ประวัติการเรียน'), findsOneWidget);
  });

  testWidgets('score reads only the actual acknowledged session identity', (
    tester,
  ) async {
    final h = await _Harness.open(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreScreen(
          correctAnswers: 1,
          wrongAnswers: 0,
          learningTime: h.time,
          resultOwnerId: 'owner-a',
          resultSessionId: 'actual-canonical-session',
        ),
      ),
    );
    await _flush(tester);
    expect(find.text('2 วินาที'), findsOneWidget);
    expect(h.repo.readTargets, isNotEmpty);
    expect(
      h.repo.readTargets.every(
        (target) =>
            target is SessionTimeRead &&
            target.sessionId == 'actual-canonical-session',
      ),
      isTrue,
    );
    expect(h.repo.readOwners.toSet(), {'owner-a'});
    expect(h.repo.admissions, 0);
    await h.close(tester);
  });

  testWidgets(
    'score without a session identity cannot turn latency into time',
    (tester) async {
      final h = await _Harness.open(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: ScoreScreen(
            correctAnswers: 1,
            wrongAnswers: 0,
            learningTime: h.time,
          ),
        ),
      );
      await _flush(tester);
      expect(find.byType(RecordedTimeView), findsNothing);
      expect(h.repo.readTargets, isEmpty);
      await h.close(tester);
    },
  );

  testWidgets('old score history disappears on owner change', (tester) async {
    final h = await _Harness.open(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: ScoreScreen(
          correctAnswers: 1,
          wrongAnswers: 0,
          learningTime: h.time,
          resultOwnerId: 'owner-a',
          resultSessionId: 'actual-canonical-session',
        ),
      ),
    );
    await _flush(tester);
    expect(find.text('2 วินาที'), findsOneWidget);
    h.owners.add('owner-b');
    await _flush(tester);
    expect(find.text('2 วินาที'), findsNothing);
    expect(find.text('อ่านเวลาที่บันทึกไม่ได้ในขณะนี้'), findsOneWidget);
    await h.close(tester);
  });
}

Future<void> _flush(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

const _empty = ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);

final class _Harness {
  final zone = Zone.current;
  final owners = StreamController<String?>.broadcast(sync: true);
  final repo = _Repository();
  late final LearningTimeUseCases time;

  static Future<_Harness> open(WidgetTester tester) async =>
      (await tester.runAsync(() async {
        final h = _Harness();
        h.time = LearningTimeUseCases(
          repository: h.repo,
          ownerChanges: h.owners.stream,
          monotonicMicros: () => 0,
          nowUtc: () => DateTime.utc(2026, 11, 1),
          generateId: () => 'unused-time-id',
        );
        h.owners.add('owner-a');
        await Future<void>.delayed(Duration.zero);
        return h;
      }))!;

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => zone.run(() async {
        await time.dispose();
        await owners.close();
        await repo.preferences.close();
      }),
    );
  }
}

final class _Repository implements LearningTimeRepository {
  final preferences = StreamController<LearningTimePreference?>.broadcast(
    sync: true,
  );
  final readTargets = <TimeReadTarget>[];
  final readOwners = <String>[];
  var preferenceWrites = 0;
  var admissions = 0;

  @override
  Stream<LearningTimePreference?> watchPreference(String ownerId) async* {
    yield LearningTimePreference(
      ownerId: ownerId,
      enabled: false,
      revision: 0,
      updatedAtUtcMs: 0,
    );
    yield* preferences.stream;
  }

  @override
  Future<RecordedTimeRead> read({
    required TimeReadTarget target,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) async {
    readTargets.add(target);
    readOwners.add(expectedOwnerId);
    return isCurrent()
        ? const RecordedTimeRead.recorded(
            activeDurationUs: 2300000,
            segmentCount: 1,
          )
        : const RecordedTimeRead.unavailable();
  }

  @override
  Future<LearningTimePreference> readPreference({
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) => throw UnimplementedError();
  @override
  Future<LearningTimePreference> commitPreference(
    LearningTimePreferenceIntent intent,
  ) {
    preferenceWrites++;
    throw StateError('readback must not change capture choice');
  }

  @override
  Future<TimeSourceAdmission> admitSource({
    required TimeSource source,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) {
    admissions++;
    throw StateError('readback must not start capture');
  }

  @override
  Future<void> commitSegment(ClosedTimeSegmentIntent intent) =>
      throw UnimplementedError();
  @override
  Future<TimeSessionLinkAdmission> prepareSessionLink({
    required LearningTimeScope scope,
    required CanonicalLearningTimeSessionLinkReceipt proof,
    required String expectedOwnerId,
    required bool Function() isCurrent,
  }) => throw UnimplementedError();
  @override
  Future<void> commitSessionLink(TimeSessionLinkIntent intent) =>
      throw UnimplementedError();
}
