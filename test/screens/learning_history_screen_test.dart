import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_history_models.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/learning_history_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/review_center_harness.dart';

void main() {
  for (final (activity, title) in [
    ('wordScramble', 'เกมเรียงตัวอักษร'),
    ('sentenceScramble', 'เกมเรียงประโยค'),
  ]) {
    testWidgets(
      'history labels saved recreational $activity without inventing resume',
      (tester) async {
        final entry = LearningHistoryEntry(
          sessionId: 'synthetic-$activity-history',
          activityType: activity,
          state: 'completed',
          startedAtUtc: DateTime.utc(2026, 10, 30),
          endedAtUtc: DateTime.utc(2026, 10, 30, 0, 1),
          answerCount: 1,
          correctCount: 1,
        );
        await tester.pumpWidget(
          _app(
            LearningHistoryScreen(
              loader: ({before}) async => _history(entries: [entry]),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.text('ฝึกต่อรอบนี้'), findsNothing);
        expect(find.text('ถูก 1 จาก 1 คำตอบ'), findsOneWidget);
      },
    );
  }

  testWidgets('history labels saved Cloze rounds without inventing resume', (
    tester,
  ) async {
    final entry = LearningHistoryEntry(
      sessionId: 'synthetic-cloze-history',
      activityType: 'cloze',
      state: 'completed',
      startedAtUtc: DateTime.utc(2026, 10, 30),
      endedAtUtc: DateTime.utc(2026, 10, 30, 0, 1),
      answerCount: 1,
      correctCount: 1,
    );
    await tester.pumpWidget(
      _app(
        LearningHistoryScreen(
          loader: ({before}) async => _history(entries: [entry]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('เติมคำในบริบท'), findsOneWidget);
    expect(find.text('ฝึกต่อรอบนี้'), findsNothing);
    expect(find.text('ถูก 1 จาก 1 คำตอบ'), findsOneWidget);
  });

  setUpAll(() async {
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
  });

  testWidgets(
    'history shows recorded answers, unfinished rounds and local dates',
    (tester) async {
      await tester.pumpWidget(
        _app(LearningHistoryScreen(loader: ({before}) async => _history())),
      );
      await tester.pumpAndSettle();

      expect(find.text('ประวัติการเรียน'), findsOneWidget);
      expect(find.text('คำตอบ 7 วันล่าสุด'), findsOneWidget);
      expect(find.text('28/10/2026'), findsWidgets);
      expect(find.text('แบบทดสอบ'), findsOneWidget);
      expect(find.text('จบแล้ว'), findsOneWidget);
      expect(find.text('ถูก 2 จาก 3 คำตอบ'), findsOneWidget);
      expect(find.text('ยังไม่จบ'), findsOneWidget);
      expect(find.text('ยังไม่มีคำตอบ'), findsOneWidget);
      expect(find.textContaining('เวลาเรียน'), findsNothing);
      expect(find.textContaining('ต่อเนื่อง'), findsNothing);
      expect(find.textContaining('private-owner'), findsNothing);
    },
  );

  testWidgets('empty history is honest and back navigation works', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LearningHistoryScreen(
                    loader: ({before}) async => _history(entries: []),
                  ),
                ),
              ),
              child: const Text('เปิดประวัติ'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดประวัติ'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีประวัติการเรียน'), findsOneWidget);
    expect(find.text('ถูก 0 จาก 0 คำตอบ'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('เปิดประวัติ'), findsOneWidget);
  });

  testWidgets('read failure hides private errors and retry succeeds', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      _app(
        LearningHistoryScreen(
          loader: ({before}) async {
            if (++reads == 1) {
              throw StateError('PRIVATE_SYNTHETIC_OWNER_CANARY');
            }
            return _history();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
      findsOneWidget,
    );
    expect(find.textContaining('PRIVATE_SYNTHETIC_OWNER_CANARY'), findsNothing);
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pumpAndSettle();
    expect(find.text('ถูก 2 จาก 3 คำตอบ'), findsOneWidget);
    expect(reads, 2);
  });

  testWidgets('load more reaches older rounds without duplicate entries', (
    tester,
  ) async {
    final cursors = <LearningHistoryCursor?>[];
    final cursor = LearningHistoryCursor(
      ownerId: 'private-owner-a',
      startedAtUtc: DateTime.utc(2026, 10, 28),
      sessionId: 'completed',
    );
    await tester.pumpWidget(
      _app(
        LearningHistoryScreen(
          loader: ({before}) async {
            cursors.add(before);
            return before == null
                ? _history(entries: [_completed], nextCursor: cursor)
                : _history(entries: [_completed, _older]);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('โหลดเพิ่ม'), 200);
    await tester.tap(find.text('โหลดเพิ่ม'));
    await tester.pumpAndSettle();
    expect(cursors, [null, cursor]);
    expect(find.text('แบบทดสอบ'), findsOneWidget);
    expect(find.text('แฟลชการ์ด'), findsOneWidget);
    expect(find.text('โหลดเพิ่ม'), findsNothing);
  });

  testWidgets(
    'account change clears history immediately and rejects a pending old page',
    (tester) async {
      final changes = StreamController<String?>.broadcast();
      final oldPage = Completer<LearningHistorySnapshot>();
      final newOwner = Completer<LearningHistorySnapshot>();
      var initialLoads = 0;
      final cursor = LearningHistoryCursor(
        ownerId: 'private-owner-a',
        startedAtUtc: _completed.startedAtUtc,
        sessionId: _completed.sessionId,
      );
      await tester.pumpWidget(
        _app(
          LearningHistoryScreen(
            ownerChanges: changes.stream,
            loader: ({before}) {
              if (before != null) return oldPage.future;
              if (++initialLoads == 1) {
                return Future.value(
                  _history(entries: [_completed], nextCursor: cursor),
                );
              }
              return newOwner.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('โหลดเพิ่ม'), 200);
      await tester.tap(find.text('โหลดเพิ่ม'));
      await tester.pump();
      changes.add('private-owner-b');
      await tester.pump();
      expect(find.text('ถูก 2 จาก 3 คำตอบ'), findsNothing);
      oldPage.complete(_history(entries: [_older]));
      await tester.pump();
      expect(find.text('แฟลชการ์ด'), findsNothing);
      newOwner.complete(_history(ownerId: 'private-owner-b', entries: []));
      await tester.pumpAndSettle();
      expect(find.text('ยังไม่มีประวัติการเรียน'), findsOneWidget);
      expect(find.text('แบบทดสอบ'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await changes.close();
    },
  );

  testWidgets(
    'owner rejection during pagination clears previously visible history',
    (tester) async {
      final cursor = LearningHistoryCursor(
        ownerId: 'private-owner-a',
        startedAtUtc: _completed.startedAtUtc,
        sessionId: _completed.sessionId,
      );
      await tester.pumpWidget(
        _app(
          LearningHistoryScreen(
            loader: ({before}) async {
              if (before != null) throw LearningHistoryOwnerChanged();
              return _history(entries: [_completed], nextCursor: cursor);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('โหลดเพิ่ม'), 200);
      await tester.tap(find.text('โหลดเพิ่ม'));
      await tester.pumpAndSettle();
      expect(find.text('ถูก 2 จาก 3 คำตอบ'), findsNothing);
      expect(
        find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
        findsOneWidget,
      );
      expect(find.text('ลองอีกครั้ง'), findsOneWidget);
    },
  );

  testWidgets('resume reloads while hiding previous evidence', (tester) async {
    var calls = 0;
    final reload = Completer<LearningHistorySnapshot>();
    await tester.pumpWidget(
      _app(
        LearningHistoryScreen(
          loader: ({before}) {
            return ++calls == 1 ? Future.value(_history()) : reload.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('ถูก 2 จาก 3 คำตอบ'), findsNothing);
    reload.complete(_history(entries: []));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีประวัติการเรียน'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('compact Thai layout remains usable at 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _app(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 800),
            textScaler: TextScaler.linear(2),
          ),
          child: LearningHistoryScreen(loader: ({before}) async => _history()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('ถูก 2 จาก 3 คำตอบ'), 200);
    await tester.pumpAndSettle();
    expect(find.text('ถูก 2 จาก 3 คำตอบ').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    final text = tester.widget<Text>(find.text('ถูก 2 จาก 3 คำตอบ'));
    expect(text.overflow, isNot(TextOverflow.ellipsis));
  });

  testWidgets('dashboard opens the history screen through one action', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    late final Zone ioZone;
    final h = (await tester.runAsync(() {
      ioZone = Zone.current;
      return ReviewCenterHarness.open();
    }))!;
    try {
      final before = await tester.runAsync(h.snapshotAllTables);
      expect(before, hasLength(37));
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: AppDependencies(
            runtimeStatus: const AppRuntimeStatus(
              localData: RuntimeAvailability.ready,
              firebase: RuntimeAvailability.unavailable,
              supabase: RuntimeAvailability.unavailable,
              backends: RuntimeAvailability.unavailable,
            ),
            config: null,
            guestSessionService: _HistoryGuest(),
            database: h.database,
            localOwners: h.owners,
            progress: h.progress,
            reviewCenter: h.reviewCenter,
            learning: h.learning,
            savedWords: h.savedWords,
            wordReports: h.wordReports,
          ),
          child: _app(
            MasteryDashboardScreen(
              loader: () async => _emptyProgress,
              ownerChanges: h.ownerChanges,
            ),
          ),
        ),
      );
      final action = find.widgetWithText(OutlinedButton, 'ประวัติการเรียน');
      await _historyReadUntil(
        tester,
        () =>
            action.evaluate().isNotEmpty &&
            tester.widget<OutlinedButton>(action).onPressed != null,
      );
      await tester.pumpAndSettle();
      expect(find.text('ประวัติการเรียน'), findsOneWidget);
      await tester.ensureVisible(action);
      await tester.tap(find.text('ประวัติการเรียน'));
      await _historyReadUntil(tester, () {
        final history = find.byType(LearningHistoryScreen);
        return history.evaluate().isNotEmpty &&
            ModalRoute.of(tester.element(history))?.animation?.status ==
                AnimationStatus.completed &&
            find
                .descendant(
                  of: history,
                  matching: find.byType(CircularProgressIndicator),
                )
                .evaluate()
                .isEmpty;
      });
      await tester.pumpAndSettle();
      expect(find.byType(LearningHistoryScreen), findsOneWidget);
      final history = tester.widget<LearningHistoryScreen>(
        find.byType(LearningHistoryScreen),
      );
      expect(history.ownerChanges, same(h.ownerChanges));
      expect(history.loader, isNotNull);
      expect(await tester.runAsync(h.snapshotAllTables), before);
      await tester.pageBack();
      await _historyReadUntil(
        tester,
        () =>
            find.byType(LearningHistoryScreen).evaluate().isEmpty &&
            find.byType(MasteryDashboardScreen).evaluate().isNotEmpty &&
            find
                .descendant(
                  of: find.byType(MasteryDashboardScreen),
                  matching: find.byType(CircularProgressIndicator),
                )
                .evaluate()
                .isEmpty,
      );
      await tester.pumpAndSettle();
      expect(find.byType(MasteryDashboardScreen), findsOneWidget);
      expect(await tester.runAsync(h.snapshotAllTables), before);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.runAsync(() => ioZone.run(h.close));
    }
  });

  testWidgets(
    'resume opens the exact stored owner and session, then refreshes history',
    (tester) async {
      var reads = 0;
      final activeQuiz = LearningHistoryEntry(
        sessionId: 'synthetic-saved-quiz',
        activityType: 'sourcePractice',
        state: 'active',
        startedAtUtc: _active.startedAtUtc,
        endedAtUtc: null,
        answerCount: 1,
        correctCount: 1,
        hasAcceptedQuiz: true,
      );
      await tester.pumpWidget(
        _app(
          LearningHistoryScreen(
            loader: ({before}) async {
              reads++;
              return _history(entries: [activeQuiz, _completed, _active]);
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('เล่นต่อ'), findsOneWidget);
      await tester.ensureVisible(find.text('เล่นต่อ'));
      await tester.tap(find.text('เล่นต่อ'));
      await tester.pumpAndSettle();
      expect(find.byType(QuizScreen), findsOneWidget);
      final route = tester.widget<QuizScreen>(find.byType(QuizScreen));
      expect(route.resumeSessionId, 'synthetic-saved-quiz');
      expect(route.expectedOwnerId, 'private-owner-a');
      expect(reads, 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(reads, 2);
      expect(find.text('เล่นต่อ'), findsOneWidget);
    },
  );
}

Future<void> _historyReadUntil(
  WidgetTester tester,
  bool Function() ready,
) async {
  for (var frame = 0; frame < 150; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) return;
  }
  fail('Owner-bound History entry did not reach its actual ready state');
}

final class _HistoryGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('History reads cannot create a guest');
}

Widget _app(Widget home) => MaterialApp(theme: M3Theme.lightTheme, home: home);

final _completed = LearningHistoryEntry(
  sessionId: 'completed',
  activityType: 'quiz',
  state: 'completed',
  startedAtUtc: DateTime(2026, 10, 28, 10).toUtc(),
  endedAtUtc: DateTime(2026, 10, 28, 10, 5).toUtc(),
  answerCount: 3,
  correctCount: 2,
);
final _active = LearningHistoryEntry(
  sessionId: 'active',
  activityType: 'listening',
  state: 'active',
  startedAtUtc: DateTime(2026, 10, 28, 11).toUtc(),
  endedAtUtc: null,
  answerCount: 0,
  correctCount: 0,
);
final _older = LearningHistoryEntry(
  sessionId: 'older',
  activityType: 'flashcard',
  state: 'completed',
  startedAtUtc: DateTime(2026, 10, 27, 10).toUtc(),
  endedAtUtc: DateTime(2026, 10, 27, 10, 5).toUtc(),
  answerCount: 1,
  correctCount: 1,
);

LearningHistorySnapshot _history({
  String ownerId = 'private-owner-a',
  List<LearningHistoryEntry>? entries,
  LearningHistoryCursor? nextCursor,
}) => LearningHistorySnapshot(
  ownerId: ownerId,
  entries: entries ?? [_completed, _active],
  nextCursor: nextCursor,
  days: List.generate(
    7,
    (i) => LearningHistoryDay(
      day: DateTime(2026, 10, 22 + i),
      answerCount: i == 6 ? 3 : 0,
    ),
  ),
);

const _emptyProgress = ProgressSnapshot(
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
  gameLevel: 0,
  skills: [],
  weaknesses: [],
  recommendations: [],
);
