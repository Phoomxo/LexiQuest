import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/preferences/application/display_preferences_controller.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/data/drift_learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';

void main() {
  testWidgets(
    'BA late acknowledgement failure does not notify a covering route or revoke commit',
    (tester) async {
      final f = _Fixture();
      await f.controller.initialize();
      f.repository.hold = true;
      f.repository.afterCommit = true;
      f.repository.failWrite = true;
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: key,
          home: SettingScreen(displayPreferences: f.controller),
        ),
      );
      await tester.pumpAndSettle();
      final pending = Future<void>.sync(_action(tester, 'menu'));
      await tester.runAsync(() => f.repository.entered.future);
      key.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('cover')),
        ),
      );
      await tester.pumpAndSettle();
      f.repository.release.complete();
      await tester.runAsync(() => pending);
      await tester.pumpAndSettle();
      final notices = find.byType(SnackBar).evaluate().length;
      final saved = await tester.runAsync(
        () => f.repository.inner.read('local:ba-owner'),
      );
      await tester.pumpWidget(const SizedBox());
      f.controller.dispose();
      await tester.runAsync(f.database.close);
      expect(notices, 0);
      expect(saved!.display.themeMode, LearnerThemePreference.dark);
      expect(f.repository.writes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'BA initial pending read disables writes until current snapshot',
    (tester) async {
      final f = _Fixture();
      f.repository.holdRead = true;
      final pending = f.controller.initialize();
      await tester.runAsync(() => f.repository.entered.future);
      await tester.pumpWidget(
        MaterialApp(home: SettingScreen(displayPreferences: f.controller)),
      );
      await tester.pump();
      final disabled =
          tester
              .widget<ChoiceChip>(find.byKey(const ValueKey('theme-dark')))
              .onSelected ==
          null;
      f.repository.release.complete();
      await tester.runAsync(() => pending);
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.sync(_action(tester, 'menu')));
      await tester.pumpAndSettle();
      final theme = f.controller.themeMode;
      await tester.pumpWidget(const SizedBox());
      f.controller.dispose();
      await tester.runAsync(f.database.close);
      expect(disabled, isTrue);
      expect(theme, ThemeMode.dark);
      expect(f.repository.writes, 1);
    },
  );
  testWidgets(
    'BA duplicate explicit selection remains single flight and fresh no-op',
    (tester) async {
      final f = _Fixture();
      await f.controller.initialize();
      f.repository.hold = true;
      await tester.pumpWidget(
        MaterialApp(home: SettingScreen(displayPreferences: f.controller)),
      );
      await tester.pumpAndSettle();
      final action = _action(tester, 'menu');
      final first = Future<void>.sync(action);
      final duplicate = Future<void>.sync(action);
      await tester.runAsync(() => f.repository.entered.future);
      f.repository.release.complete();
      await tester.runAsync(() async {
        await first;
        await duplicate;
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.sync(_action(tester, 'menu')));
      await tester.pumpAndSettle();
      final calls = f.repository.writes;
      await tester.pumpWidget(const SizedBox());
      f.controller.dispose();
      await tester.runAsync(f.database.close);
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final transition in ['rebuild', 'read', 'tab-return']) {
    testWidgets(
      'BA current controls usable and retired controls stay retired after $transition',
      (tester) async {
        final f = _Fixture();
        await f.controller.initialize();
        Widget app(bool visible) => MaterialApp(
          home: TickerMode(
            enabled: visible,
            child: SettingScreen(displayPreferences: f.controller),
          ),
        );
        await tester.pumpWidget(app(true));
        await tester.pumpAndSettle();
        final old = _action(tester, 'menu');
        if (transition == 'tab-return') {
          await tester.pumpWidget(app(false));
          await tester.pumpAndSettle();
        }
        if (transition == 'read') {
          await tester.runAsync(f.controller.initialize);
        }
        await tester.pumpWidget(app(true));
        await tester.pumpAndSettle();
        await tester.runAsync(() => Future<void>.sync(old));
        await tester.pumpAndSettle();
        final afterOld = f.controller.themeMode;
        await tester.runAsync(() => Future<void>.sync(_action(tester, 'menu')));
        await tester.pumpAndSettle();
        final afterNew = f.controller.themeMode;
        await tester.pumpWidget(const SizedBox());
        f.controller.dispose();
        await tester.runAsync(f.database.close);
        expect(
          afterOld,
          transition == 'rebuild' ? ThemeMode.dark : ThemeMode.system,
        );
        expect(afterNew, ThemeMode.dark);
      },
    );
  }

  for (final surface in ['native', 'semantics', 'menu', 'motion']) {
    for (final boundary in [
      'replace',
      'remove',
      'tab',
      'route',
      'lifecycle',
      'dispose',
      'owner',
      'pop',
    ]) {
      testWidgets('BA retained $surface retires after $boundary', (
        tester,
      ) async {
        final fixture = _Fixture();
        await fixture.controller.initialize();
        final second = DisplayPreferencesController(fixture.useCases);
        await second.initialize();
        final key = GlobalKey<NavigatorState>();
        Widget app(DisplayPreferencesController? c, {bool enabled = true}) =>
            MaterialApp(
              navigatorKey: key,
              home: TickerMode(
                enabled: enabled,
                child: SettingScreen(displayPreferences: c),
              ),
            );
        await tester.pumpWidget(app(fixture.controller));
        if (boundary == 'pop') {
          key.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  SettingScreen(displayPreferences: fixture.controller),
            ),
          );
        }
        await tester.pumpAndSettle();
        final callback = _action(tester, surface);
        switch (boundary) {
          case 'owner':
            await tester.runAsync(() async {
              await fixture.database.customUpdate(
                'UPDATE local_owners SET is_active=0',
              );
              await fixture.database.customStatement(
                "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('other-owner','localGuest',1,1)",
              );
            });
          case 'pop':
            key.currentState!.pop();
          case 'replace':
            await tester.pumpWidget(app(second));
          case 'remove':
            await tester.pumpWidget(app(null));
          case 'tab':
            await tester.pumpWidget(app(fixture.controller, enabled: false));
          case 'route':
            key.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('other')),
              ),
            );
          case 'lifecycle':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
        }
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await Future<void>.sync(callback);
        });
        await tester.pumpAndSettle();
        final saved = await tester.runAsync(
          () => fixture.repository.inner.read('local:ba-owner'),
        );
        final exception = tester.takeException();
        // Release/dispose resources before assertions so failures cannot stall cleanup.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox());
        fixture.controller.dispose();
        second.dispose();
        await tester.runAsync(fixture.database.close);
        expect(exception, isNull);
        expect(saved!.display.themeMode, LearnerThemePreference.system);
        expect(saved.display.motionMode, LearnerMotionPreference.system);
      });
    }
  }
  testWidgets('BA initial read failure exposes explicit read retry', (
    tester,
  ) async {
    final f = _Fixture();
    f.repository.failRead = true;
    await expectLater(f.controller.initialize(), throwsStateError);
    await tester.pumpWidget(
      MaterialApp(home: SettingScreen(displayPreferences: f.controller)),
    );
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('display-retry'));
    final found = retry.evaluate().isNotEmpty;
    f.repository.failRead = false;
    if (found) {
      await tester.tap(retry);
      await tester.pumpAndSettle();
    }
    final ready = f.controller.isInitialized;
    await tester.pumpWidget(const SizedBox());
    f.controller.dispose();
    await tester.runAsync(f.database.close);
    expect(found, isTrue);
    expect(ready, isTrue);
  });
  for (final committed in [false, true]) {
    testWidgets(
      'BA uncertain acknowledgement $committed requires read then separate choice',
      (tester) async {
        final f = _Fixture();
        await f.controller.initialize();
        f.repository.failWrite = true;
        f.repository.afterCommit = committed;
        await tester.pumpWidget(
          MaterialApp(home: SettingScreen(displayPreferences: f.controller)),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() => Future<void>.sync(_action(tester, 'menu')));
        await tester.pumpAndSettle();
        final retry = find.byKey(const ValueKey('display-retry'));
        final found = retry.evaluate().isNotEmpty;
        final disabled =
            tester
                .widget<ChoiceChip>(find.byKey(const ValueKey('theme-dark')))
                .onSelected ==
            null;
        f.repository.failWrite = false;
        if (found) {
          await tester.tap(retry);
          for (var i = 0; i < 30 && f.controller.isReading; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 10)),
            );
            await tester.pump();
          }
          await tester.pumpAndSettle();
        }
        final theme = f.controller.themeMode;
        final calls = f.repository.writes;
        await tester.pumpWidget(const SizedBox());
        f.controller.dispose();
        await tester.runAsync(f.database.close);
        expect(found, isTrue);
        expect(disabled, isTrue);
        expect(calls, 1);
        expect(theme, committed ? ThemeMode.dark : ThemeMode.system);
      },
    );
  }
  for (final committed in [false, true]) {
    testWidgets('BA pending write retirement preserves commit=$committed', (
      tester,
    ) async {
      final f = _Fixture();
      await f.controller.initialize();
      f.repository.hold = true;
      f.repository.afterCommit = committed;
      await tester.pumpWidget(
        MaterialApp(home: SettingScreen(displayPreferences: f.controller)),
      );
      await tester.pumpAndSettle();
      final action = _action(tester, 'menu');
      final pending = Future<void>.sync(action);
      await tester.runAsync(() => f.repository.entered.future);
      await tester.pumpWidget(const SizedBox());
      f.repository.release.complete();
      await tester.runAsync(() => pending);
      f.controller.dispose();
      final saved = await tester.runAsync(f.useCases.read);
      await tester.runAsync(f.database.close);
      expect(
        saved!.display.themeMode,
        committed ? LearnerThemePreference.dark : LearnerThemePreference.system,
      );
      expect(tester.takeException(), isNull);
    });
  }
}

FutureOr<void> Function() _action(WidgetTester tester, String surface) {
  if (surface == 'motion') {
    final w = tester.widget<SwitchListTile>(find.byType(SwitchListTile).first);
    return () => w.onChanged!(true);
  }
  if (surface == 'native') {
    final w = tester.widget<ChoiceChip>(
      find.byWidgetPredicate(
        (w) => w is ChoiceChip && w.key == const ValueKey<String>('theme-dark'),
      ),
    );
    return () => w.onSelected!(true);
  }
  if (surface == 'menu') {
    final w = tester.widget<MenuActionBinding>(
      find.byWidgetPredicate(
        (w) => w is MenuActionBinding && w.id == 'theme-dark',
      ),
    );
    return () => w.onInvoke!();
  }
  final w = tester.widget<Semantics>(
    find.byWidgetPredicate(
      (w) => w is Semantics && w.properties.label == 'ใช้รูปแบบมืด',
    ),
  );
  return () => w.properties.onTap!();
}

class _Fixture {
  final database = AppDatabase(NativeDatabase.memory());
  late final repository = _Repository(
    DriftLearnerPreferencesRepository(database),
  );
  late final useCases = LearnerPreferencesUseCases(
    repository: repository,
    owners: DriftLocalOwnerRepository(
      database,
      generateId: () => 'ba-owner',
      nowUtc: () => DateTime.utc(2026, 9, 25),
    ),
    nowUtc: () => DateTime.utc(2026, 9, 25),
  );
  late final controller = DisplayPreferencesController(useCases);
}

class _Repository implements LearnerPreferencesRepository {
  _Repository(this.inner);
  final LearnerPreferencesRepository inner;
  bool hold = false,
      afterCommit = false,
      holdRead = false,
      failRead = false,
      failWrite = false;
  int writes = 0;
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<LearnerPreferences> read(String ownerId) async {
    if (holdRead) {
      holdRead = false;
      entered.complete();
      await release.future;
    }
    if (failRead) throw StateError('read unavailable');
    return inner.read(ownerId);
  }

  @override
  Future<void> save(
    LearnerPreferences value, {
    LearnerPreferencesWriteScope scope = LearnerPreferencesWriteScope.all,
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) => inner.save(value, scope: scope, mutationAllowed: mutationAllowed);
  @override
  Future<void> saveDisplayPreferences(
    String ownerId,
    LearnerDisplayPreferences value, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    writes++;
    if (failWrite && !afterCommit) throw StateError('ack unknown');
    if (hold && !afterCommit) {
      entered.complete();
      await release.future;
    }
    await inner.saveDisplayPreferences(
      ownerId,
      value,
      mutationAllowed: mutationAllowed,
    );
    if (hold && afterCommit) {
      entered.complete();
      await release.future;
    }
    if (failWrite && afterCommit) throw StateError('ack unknown');
  }
}
