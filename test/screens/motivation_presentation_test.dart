import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/motivation/presentation/achievement_share_composer.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );
  testWidgets('stored achievements offer an explicit private card preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AchievementsScreen(loader: () async => earnedProgress)),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('achievement-preview-first_session')),
      findsOneWidget,
    );
    expect(find.textContaining('synthetic-private-event'), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'private card save/share/cancel at 320px 200 percent ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final saved = <Uint8List>[];
        final shared = <Uint8List>[];
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? M3Theme.darkTheme : M3Theme.lightTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: AchievementsScreen(
              loader: () async => earnedProgress,
              saveImage: (bytes, cancellation, revalidate) async {
                await revalidate();
                cancellation.throwIfCancelled();
                saved.add(bytes);
              },
              shareImage: (bytes, revalidate) async {
                await revalidate();
                shared.add(bytes);
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        await _keyboard(tester, 'achievement-preview-first_session');
        await _wait(
          tester,
          () => find
              .byKey(const ValueKey('achievement-card-preview'))
              .evaluate()
              .isNotEmpty,
        );
        final route = ModalRoute.of(
          tester.element(find.byType(AchievementShareComposer)),
        )!;
        expect(route.transitionDuration, Duration.zero);
        expect(saved, isEmpty);
        expect(shared, isEmpty);
        final date = tester.widget<CheckboxListTile>(
          find.byKey(const ValueKey('achievement-include-date')),
        );
        expect(date.value, isFalse);
        expect(find.textContaining('synthetic-private-event'), findsNothing);
        await _keyboard(tester, 'achievement-save-image');
        await _wait(tester, () => saved.isNotEmpty);
        expect(saved.single.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        await _keyboard(tester, 'achievement-share-image');
        await _wait(tester, () => shared.isNotEmpty);
        expect(shared.single, orderedEquals(saved.single));
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(
          find.byKey(const ValueKey('achievement-cancel')),
        );
        await tester.tap(find.byKey(const ValueKey('achievement-cancel')));
        await tester.pumpAndSettle();
        expect(find.byType(AchievementShareComposer), findsNothing);
        expect(saved, hasLength(1));
        expect(shared, hasLength(1));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'owner ABA clears a retained card and denies retained external callbacks',
    (tester) async {
      final owners = StreamController<String?>.broadcast(sync: true);
      var outputs = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AchievementsScreen(
            loader: () async => earnedProgress,
            ownerChanges: owners.stream,
            saveImage: (_, _, revalidate) async {
              await revalidate();
              outputs++;
            },
            shareImage: (_, revalidate) async {
              await revalidate();
              outputs++;
            },
          ),
        ),
      );
      owners.add('synthetic-a');
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
      final retained = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('achievement-save-image')),
          )
          .onPressed!;
      owners.add('synthetic-b');
      owners.add('synthetic-a');
      await tester.pumpAndSettle();
      retained();
      await tester.pumpAndSettle();
      expect(outputs, 0);
      expect(
        find.byKey(const ValueKey('achievement-card-preview')),
        findsNothing,
      );
      expect(
        find.textContaining('ข้อมูลหรือหน้าจอเปลี่ยนแล้ว'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await owners.close();
    },
  );

  testWidgets('a failed authority recheck produces no external image', (
    tester,
  ) async {
    var reads = 0;
    var outputs = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AchievementsScreen(
          loader: () async {
            if (reads++ > 0) {
              throw StateError('synthetic authority unavailable');
            }
            return earnedProgress;
          },
          saveImage: (_, _, revalidate) async {
            await revalidate();
            outputs++;
          },
        ),
      ),
    );
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
    await tester.ensureVisible(
      find.byKey(const ValueKey('achievement-save-image')),
    );
    await tester.tap(find.byKey(const ValueKey('achievement-save-image')));
    await tester.pumpAndSettle();
    expect(outputs, 0);
    expect(find.textContaining('ยังบันทึกหรือแชร์ภาพไม่ได้'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (done()) return;
  }
  fail('Actual achievement preview did not become ready');
}

Future<void> _keyboard(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find.byType(Scrollable).last,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 16));
  final focusTrace = <String>[];
  for (var i = 0; i < 30; i++) {
    final target = finder.evaluate().firstOrNull;
    final focused = FocusManager.instance.primaryFocus?.context;
    var within = target != null && identical(focused, target);
    final ancestors = <String>[];
    focused?.visitAncestorElements((element) {
      if (ancestors.length < 8) {
        ancestors.add('${element.widget.runtimeType}:${element.widget.key}');
      }
      if (identical(element, target)) {
        within = true;
        return false;
      }
      return true;
    });
    final targetWidget = target?.widget;
    final node = FocusManager.instance.primaryFocus;
    final scope = focused == null ? null : ModalRoute.of(focused);
    final targetRoute = target == null ? null : ModalRoute.of(target);
    focusTrace.add(
      '$i ${focused?.widget.runtimeType} target=${targetWidget?.runtimeType} '
      'enabled=${targetWidget is ButtonStyleButton ? targetWidget.enabled : null} '
      'focusRoute=${scope?.settings.name}/${scope?.isCurrent}/${scope?.offstage} '
      'targetRoute=${targetRoute?.settings.name}/${targetRoute?.isCurrent}/${targetRoute?.offstage} '
      'canFocus=${node?.canRequestFocus} skip=${node?.skipTraversal} '
      'descFocus=${node?.descendantsAreFocusable} descTraverse=${node?.descendantsAreTraversable} '
      'traversal=${node?.traversalDescendants.length} '
      'nextAction=${focused == null ? null : Actions.maybeFind<NextFocusIntent>(focused)?.runtimeType} '
      'keys=${HardwareKeyboard.instance.logicalKeysPressed.map((key) => key.debugName).join(',')} '
      'ancestors=${ancestors.join('>')}',
    );
    if (within) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail(
    'Achievement control $key is not keyboard reachable. ${focusTrace.join(' | ')}',
  );
}

final earnedProgress = ProgressSnapshot(
  sampleSize: 2,
  correctCount: 2,
  wrongCount: 0,
  accuracy: 1,
  totalXp: 42,
  completedSessions: 1,
  streakDays: 1,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 1,
  gameLevel: 3,
  skills: [],
  weaknesses: [],
  recommendations: [],
  achievements: [
    AchievementEvidence(
      id: 'first_session',
      definitionVersion: 1,
      sourceEventId: 'synthetic-private-event',
      unlockedAtUtc: DateTime.utc(2026, 10, 28),
    ),
  ],
);
