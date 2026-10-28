import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_appearance_preferences.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'appearance-test');
}

void main() {
  testWidgets(
    'restores appearance after reopen and switches owner without resetting navigation',
    (tester) async {
      late Directory directory;
      late AppDatabase database;
      late String ownerId;
      late AppDependencies dependencies;
      late AppAppearanceController appAppearance;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'lexiquest-appearance-',
        );
        final file = File('${directory.path}/test.db');
        database = AppDatabase(NativeDatabase(file));
        final firstOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'owner-a',
          nowUtc: () => DateTime.utc(2026, 10, 21),
        );
        final firstRewards = RewardUseCases(
          owners: firstOwners,
          repository: DriftRewardRepository(database),
          generateId: _ids(<String>[
            'buy-theme',
            'equip-theme',
            'buy-wall',
            'equip-wall',
          ]),
          nowUtc: () => DateTime.utc(2026, 10, 21, 1),
        );
        final owner = await firstOwners.getOrCreateActiveOwner();
        ownerId = owner.id;
        await database.customInsert(
          'INSERT INTO points_ledger_entries '
          '(id, owner_id, idempotency_key, entry_type, amount, occurred_at_utc_ms) '
          "VALUES ('appearance-seed', '${owner.id}', 'appearance-seed', 'learning', 200, 1)",
        );
        await firstRewards.purchase(
          expectedOwnerId: owner.id,
          itemId: 'theme_ocean',
          catalogVersion: 1,
          idempotencyKey: 'purchase-theme',
        );
        await firstRewards.equip(
          expectedOwnerId: owner.id,
          itemId: 'theme_ocean',
          idempotencyKey: 'equip-theme-intent',
        );
        await firstRewards.purchase(
          expectedOwnerId: owner.id,
          itemId: 'wallpaper_focus',
          catalogVersion: 1,
          idempotencyKey: 'purchase-wall',
        );
        await firstRewards.equip(
          expectedOwnerId: owner.id,
          itemId: 'wallpaper_focus',
          idempotencyKey: 'equip-wall-intent',
        );
        await database.close();

        database = AppDatabase(NativeDatabase(file));
        final reopenedOwners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'unused',
          nowUtc: () => DateTime.utc(2026, 10, 21),
        );
        final reopenedRewards = RewardUseCases(
          owners: reopenedOwners,
          repository: DriftRewardRepository(database),
          generateId: () => 'unused',
          nowUtc: () => DateTime.utc(2026, 10, 21, 2),
        );
        dependencies = AppDependencies(
          runtimeStatus: const AppRuntimeStatus(
            localData: RuntimeAvailability.ready,
            firebase: RuntimeAvailability.ready,
            supabase: RuntimeAvailability.ready,
            backends: RuntimeAvailability.ready,
          ),
          config: null,
          guestSessionService: _GuestSession(),
          buildInfo: const AppBuildInfo.fromEnvironment(),
          rewards: reopenedRewards,
          disposeResources: database.close,
        );
        appAppearance = await AppAppearanceController.load(
          _AppearancePreferences(AppAppearanceMode.light),
        );
      });
      addTearDown(appAppearance.dispose);
      await tester.pumpWidget(
        MyApp(dependencies: dependencies, appearance: appAppearance),
      );
      await _pumpUntil(
        tester,
        () =>
            _materialApp(tester).theme?.colorScheme.primary ==
            const Color(0xFF075985),
      );
      expect(
        _materialApp(tester).theme?.scaffoldBackgroundColor,
        const Color(0xFFEFF8FA),
      );
      expect(
        _materialApp(tester).darkTheme?.scaffoldBackgroundColor,
        const Color(0xFF0E2027),
      );

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('navigation-marker')),
        ),
      );
      await tester.pumpAndSettle();

      expect(_materialApp(tester).themeMode, ThemeMode.light);
      await appAppearance.apply(AppAppearanceMode.dark);
      await tester.pumpAndSettle();
      expect(_materialApp(tester).themeMode, ThemeMode.dark);
      expect(find.text('navigation-marker'), findsOneWidget);
      expect(
        _materialApp(tester).darkTheme?.scaffoldBackgroundColor,
        const Color(0xFF0E2027),
      );

      await tester.runAsync(
        () => database.transaction(() async {
          await (database.update(database.localOwners)
                ..where((row) => row.id.equals(ownerId)))
              .write(const LocalOwnersCompanion(isActive: Value(false)));
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(id: 'owner-b', createdAtUtcMs: 2),
              );
        }),
      );
      await _pumpUntil(
        tester,
        () =>
            _materialApp(tester).theme?.colorScheme.primary == M3Theme.primary,
      );

      expect(find.text('navigation-marker'), findsOneWidget);
      expect(
        _materialApp(tester).theme?.scaffoldBackgroundColor,
        M3Theme.background,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      await tester.runAsync(dependencies.dispose);
      await tester.runAsync(() => directory.delete(recursive: true));
    },
  );
}

final class _AppearancePreferences implements AppAppearancePreferences {
  _AppearancePreferences(this.mode);

  AppAppearanceMode mode;
  bool reducedMotion = false;

  @override
  Future<AppAppearanceSettings> load() async =>
      (mode: mode, reducedMotion: reducedMotion);

  @override
  Future<bool> save(
    AppAppearanceMode mode, {
    required bool reducedMotion,
  }) async {
    this.mode = mode;
    this.reducedMotion = reducedMotion;
    return true;
  }
}

String Function() _ids(List<String> values) {
  var index = 0;
  return () => values[index++];
}

MaterialApp _materialApp(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var attempt = 0; attempt < 60; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (condition()) return;
  }
  fail('Timed out waiting for appearance update');
}
