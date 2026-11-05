import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/screens/learning_calendar_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/review_center_screen.dart';
import 'package:vocab_learning_app/screens/saved_words_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/review_center_harness.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'Dashboard review saved back retains the review and opens calendar',
    (tester) async {
      final harness = (await tester.runAsync(ReviewCenterHarness.open))!;
      try {
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: AppDependencies(
              runtimeStatus: _runtime,
              config: null,
              guestSessionService: _NoGuest(),
              progress: harness.progress,
              reviewCenter: harness.reviewCenter,
              savedWords: harness.savedWords,
              learning: harness.learning,
              wordReports: harness.wordReports,
            ),
            child: MaterialApp(
              home: MasteryDashboardScreen(
                ownerChanges: harness.ownerChanges,
                loader: _progress,
              ),
            ),
          ),
        );
        await _wait(
          tester,
          () => find.text('คะแนนประสบการณ์').evaluate().isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('review-center-entry')));
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('review-center-tools'))
              .evaluate()
              .isNotEmpty,
        );
        final reviewState = tester.state(find.byType(ReviewCenterScreen));
        final tools = find.byKey(const ValueKey('review-center-tools'));
        await tester.ensureVisible(tools);
        await tester.tap(tools);
        await tester.pumpAndSettle();
        final saved = find.byKey(const ValueKey('review-center-manage-saved'));
        await tester.ensureVisible(saved);
        await tester.pumpAndSettle();
        await tester.tap(saved);
        await _routeReady(tester, SavedWordsScreen);
        expect(find.byType(SavedWordsScreen), findsOneWidget);
        Navigator.of(tester.element(find.byType(SavedWordsScreen))).pop();
        await _routeReady(tester, ReviewCenterScreen);
        expect(find.byType(ReviewCenterScreen), findsOneWidget);
        expect(
          tester.state(find.byType(ReviewCenterScreen)),
          same(reviewState),
        );
        expect(find.text('กิจกรรมไม่พร้อมใช้งาน'), findsNothing);
        Navigator.of(tester.element(find.byType(ReviewCenterScreen))).pop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.tap(
          find.byKey(const ValueKey('mastery-learning-calendar')),
        );
        await _routeReady(tester, LearningCalendarScreen);
        expect(find.byType(LearningCalendarScreen), findsOneWidget);
        expect(find.text('กิจกรรมไม่พร้อมใช้งาน'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(harness.close);
      }
    },
  );

  testWidgets(
    'Dashboard achievement preview retains scope and rejects owner ABA',
    (tester) async {
      final owners = StreamController<String?>.broadcast(sync: true);
      String? owner = 'synthetic-nested-owner';
      final ownerChanges = Stream<String?>.multi((events) {
        events.addSync(owner);
        final subscription = owners.stream.listen(events.addSync);
        events.onCancel = subscription.cancel;
      }, isBroadcast: true);
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: MasteryDashboardScreen(
              loader: _progress,
              ownerChanges: ownerChanges,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('ความสำเร็จ'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('achievement-preview-first_session')),
        );
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('achievement-card-preview'))
              .evaluate()
              .isNotEmpty,
        );
        final save = find.byKey(const ValueKey('achievement-save-image'));
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        expect(tester.widget<OutlinedButton>(save).onPressed, isNotNull);
        expect(find.text('กิจกรรมไม่พร้อมใช้งาน'), findsNothing);
        Navigator.of(tester.element(save)).pop();
        await tester.pumpAndSettle();
        expect(find.byType(AchievementsScreen), findsOneWidget);
        await tester.tap(
          find.byKey(const ValueKey('achievement-preview-first_session')),
        );
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('achievement-card-preview'))
              .evaluate()
              .isNotEmpty,
        );
        owner = null;
        owners.add(owner);
        owner = 'synthetic-nested-owner';
        owners.add(owner);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('achievement-card-preview')),
          findsNothing,
        );
        if (save.evaluate().isNotEmpty) {
          expect(tester.widget<OutlinedButton>(save).onPressed, isNull);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await owners.close();
      }
    },
  );

  for (final outcome in ['return', 'owner ABA', 'ordinary background']) {
    testWidgets('Dashboard achievement chooser handles $outcome', (
      tester,
    ) async {
      final owners = StreamController<String?>.broadcast(sync: true);
      String? owner = 'synthetic-share-owner';
      final ownerChanges = Stream<String?>.multi((events) {
        events.addSync(owner);
        final subscription = owners.stream.listen(events.addSync);
        events.onCancel = subscription.cancel;
      }, isBroadcast: true);
      const channel = MethodChannel('com.lexiquest.app/achievement_share');
      final messenger = tester.binding.defaultBinaryMessenger;
      final returned = Completer<void>();
      var launched = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'prepareAchievementShare') return 'synthetic-share';
        if (call.method == 'launchAchievementShare') {
          launched = true;
          await returned.future;
        }
        return null;
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: MasteryDashboardScreen(
              loader: _progress,
              ownerChanges: ownerChanges,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('ความสำเร็จ'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('achievement-preview-first_session')),
        );
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('achievement-card-preview'))
              .evaluate()
              .isNotEmpty,
        );
        final share = find.byKey(const ValueKey('achievement-share-image'));
        await tester.ensureVisible(share);
        await tester.pumpAndSettle();
        if (outcome != 'ordinary background') {
          await tester.tap(share);
          await _wait(tester, () => launched);
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        if (outcome == 'owner ABA') {
          owner = null;
          owners.add(owner);
          owner = 'synthetic-share-owner';
          owners.add(owner);
          await tester.pump();
        }
        returned.complete();
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        if (outcome == 'return') {
          expect(
            find.byKey(const ValueKey('achievement-card-preview')),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(
            share,
            200,
            scrollable: find.byType(Scrollable).last,
          );
          await tester.ensureVisible(share);
          await tester.pumpAndSettle();
          expect(share.hitTestable(), findsOneWidget);
          expect(tester.widget<FilledButton>(share).onPressed, isNotNull);
          Navigator.of(tester.element(share)).pop();
          await tester.pumpAndSettle();
          expect(find.byType(AchievementsScreen), findsOneWidget);
          Navigator.of(tester.element(find.byType(AchievementsScreen))).pop();
          await tester.pumpAndSettle();
          expect(find.text('กิจกรรมไม่พร้อมใช้งาน'), findsNothing);
          expect(find.text('คะแนนประสบการณ์'), findsOneWidget);
        } else {
          expect(
            find.byKey(const ValueKey('achievement-card-preview')),
            findsNothing,
          );
          if (outcome == 'owner ABA') {
            expect(
              find.text('คำขอนี้สิ้นสุดแล้ว กลับไปเลือกความสำเร็จอีกครั้ง'),
              findsOneWidget,
            );
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        if (!returned.isCompleted) returned.complete();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        messenger.setMockMethodCallHandler(channel, null);
        await owners.close();
      }
    });
  }
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 150; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) return;
  }
  fail('Nested Dashboard route did not become ready');
}

Future<void> _routeReady(WidgetTester tester, Type screen) => _wait(tester, () {
  final route = find.byType(screen);
  if (route.evaluate().isEmpty) return false;
  return ModalRoute.of(tester.element(route))?.animation?.status ==
          AnimationStatus.completed &&
      find
          .descendant(
            of: route,
            matching: find.byType(CircularProgressIndicator),
          )
          .evaluate()
          .isEmpty;
});

const _runtime = AppRuntimeStatus(
  localData: RuntimeAvailability.ready,
  firebase: RuntimeAvailability.unavailable,
  supabase: RuntimeAvailability.unavailable,
  backends: RuntimeAvailability.unavailable,
);

class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('No authentication in synthetic route test');
}

Future<ProgressSnapshot> _progress() async => ProgressSnapshot(
  sampleSize: 1,
  correctCount: 1,
  wrongCount: 0,
  accuracy: 1,
  totalXp: 1,
  completedSessions: 1,
  streakDays: 1,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 1,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
  achievements: [
    AchievementEvidence(
      id: 'first_session',
      definitionVersion: 1,
      sourceEventId: 'synthetic-nested-achievement',
      unlockedAtUtc: DateTime.utc(2026, 10, 28),
    ),
  ],
);
