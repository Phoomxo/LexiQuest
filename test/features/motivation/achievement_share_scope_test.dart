import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_achievement_share_reader.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../quest/support/quest_repository_harness.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  test(
    'share reader rejects a coordinator for another real database',
    () async {
      final a = await QuestHarness.open();
      final b = await QuestHarness.open();
      try {
        expect(
          () => DriftAchievementShareReader(a.database, b.storage.ownerWrites),
          throwsArgumentError,
        );
      } finally {
        await a.close();
        await b.close();
      }
    },
  );

  testWidgets(
    'covering the composer invalidates retained output after returning',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      var outputs = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: AchievementsScreen(
            loader: _progress,
            saveImage: (_, _, revalidate) async {
              await revalidate();
              outputs++;
            },
          ),
        ),
      );
      await _open(tester);
      final retained = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('achievement-save-image')),
          )
          .onPressed!;
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) =>
              const Scaffold(body: Text('Synthetic covering route')),
        ),
      );
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      retained();
      await tester.pumpAndSettle();
      expect(outputs, 0);
      expect(
        find.byKey(const ValueKey('achievement-card-preview')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'dependency replacement removes an already prepared public card',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      const screen = AchievementsScreen(loader: _progress);
      Widget app(AppDependencies dependencies) => AppDependenciesScope(
        dependencies: dependencies,
        child: MaterialApp(navigatorKey: navigator, home: screen),
      );
      await tester.pumpWidget(app(_dependencies()));
      await _open(tester);
      expect(
        find.byKey(const ValueKey('achievement-card-preview')),
        findsOneWidget,
      );
      await tester.pumpWidget(app(_dependencies()));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('achievement-card-preview')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'changing the chosen card privacy clears the previous save receipt',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            loader: _progress,
            saveImage: (_, _, revalidate) async {
              await revalidate();
            },
          ),
        ),
      );
      await _open(tester);
      await tester.tap(find.byKey(const ValueKey('achievement-save-image')));
      await tester.pumpAndSettle();
      expect(find.text('บันทึกภาพในตำแหน่งที่เลือกแล้ว'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('achievement-include-date')));
      await _wait(
        tester,
        () => find
            .byKey(const ValueKey('achievement-card-preview'))
            .evaluate()
            .isNotEmpty,
      );
      expect(find.text('บันทึกภาพในตำแหน่งที่เลือกแล้ว'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

Future<void> _open(WidgetTester tester) async {
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
  if (save.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      save,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(save);
  await tester.pump();
}

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (done()) return;
  }
  fail('Actual achievement scope did not settle');
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
      sourceEventId: 'synthetic-private-scope-source',
      unlockedAtUtc: DateTime.utc(2026, 10, 28),
    ),
  ],
);

AppDependencies _dependencies() => AppDependencies(
  runtimeStatus: const AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: RuntimeAvailability.unavailable,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: _NoGuest(),
);

class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('Synthetic share preview cannot authenticate');
}
