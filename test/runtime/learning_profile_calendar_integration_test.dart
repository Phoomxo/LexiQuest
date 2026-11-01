import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning_profile/application/learning_profile_use_cases.dart';
import 'package:vocab_learning_app/features/learning_profile/data/drift_learning_profile_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/presentation/learning_pack_catalog_screen.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/learning_calendar_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/populated_owner_migration_fixture.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'actual Mastery calendar reads SQLite while aggregate Progress fails without changing any table',
    (tester) async {
      final fixture = (await tester.runAsync(
        () => _Fixture.open(seedLearning: true),
      ))!;
      final before = (await tester.runAsync(
        () => ownerMigrationRows(fixture.database),
      ))!;
      expect(before, hasLength(45));
      try {
        await tester.pumpWidget(
          _app(
            fixture,
            MasteryDashboardScreen(
              loader: _failedProgress,
              ownerChanges: fixture.ownerChanges,
            ),
          ),
        );
        const calendar = ValueKey('mastery-learning-calendar');
        await _until(tester, () {
          final element = find.byKey(calendar).evaluate();
          return element.isNotEmpty &&
              (element.single.widget as IconButton).onPressed != null;
        });
        await tester.tap(find.byKey(calendar));
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('calendar-total-answers'))
              .evaluate()
              .isNotEmpty,
        );
        expect(find.byType(LearningCalendarScreen), findsOneWidget);
        expect(
          tester
              .widget<Text>(
                find.byKey(const ValueKey('calendar-total-answers')),
              )
              .data,
          '1 คำตอบ',
        );
        expect(find.text('ตอบถูก 1 คำตอบ'), findsOneWidget);
        expect(find.text('จบช่วงฝึก 1 ครั้ง'), findsWidgets);
        expect(
          (await tester.runAsync(() => ownerMigrationRows(fixture.database)))!,
          before,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _closeFixture(tester, fixture);
      }
    },
  );

  for (final entry in <String, Widget>{
    'settings-learning-packs': const SettingScreen(),
    'learning-packs-entry': ChooseModeScreen(loader: _failedProgress),
  }.entries) {
    testWidgets('${entry.key} opens local packs despite failed Progress', (
      tester,
    ) async {
      final fixture = (await tester.runAsync(_Fixture.open))!;
      final before = (await tester.runAsync(
        () => ownerMigrationRows(fixture.database),
      ))!;
      try {
        await tester.pumpWidget(_app(fixture, entry.value));
        final tile = find.byKey(ValueKey(entry.key));
        await tester.scrollUntilVisible(
          tile,
          200,
          scrollable: find.byType(Scrollable).first,
          maxScrolls: 30,
        );
        await tester.tap(tile);
        await _until(
          tester,
          () => find.byType(LearningPackCatalogScreen).evaluate().isNotEmpty,
        );
        await _until(tester, () {
          final import = find.byKey(const ValueKey('pack-import'));
          return import.evaluate().isNotEmpty &&
              tester.widget<FilledButton>(import).onPressed != null;
        });
        expect(
          (await tester.runAsync(() => ownerMigrationRows(fixture.database)))!,
          before,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _closeFixture(tester, fixture);
      }
    });
  }

  testWidgets(
    'Profile entry saves and reloads an actual SQLite learning profile despite failed Progress',
    (tester) async {
      final fixture = (await tester.runAsync(_Fixture.open))!;
      final before = (await tester.runAsync(
        () => ownerMigrationRows(fixture.database),
      ))!;
      try {
        await tester.pumpWidget(
          _app(fixture, const ProfileSettingsScreen(loader: _failedProgress)),
        );
        await _until(
          tester,
          () => find
              .text('ไม่สามารถอ่านข้อมูลในเครื่องได้')
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(
          find.byKey(const ValueKey('profile-learning-preferences')),
        );
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('learning-profile-goal'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.enterText(
          find.byKey(const ValueKey('learning-profile-goal')),
          'Synthetic caller goal',
        );
        await tester.enterText(
          find.byKey(const ValueKey('learning-profile-date')),
          '2026-12-31',
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('learning-profile-save')),
        );
        await tester.tap(find.byKey(const ValueKey('learning-profile-save')));
        await _until(
          tester,
          () => find.text('บันทึกแผนการเรียนแล้ว').evaluate().isNotEmpty,
        );
        final after = (await tester.runAsync(
          () => ownerMigrationRows(fixture.database),
        ))!;
        expect(after['learning_profiles'], hasLength(1));
        expect(
          after['learning_profiles']!.single['goal_text'],
          'Synthetic caller goal',
        );
        expect(after['learning_profiles']!.single['target_date'], '2026-12-31');
        for (final table in before.keys.where(
          (table) => table != 'learning_profiles',
        )) {
          expect(after[table], before[table], reason: table);
        }
        await tester.pageBack();
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('profile-learning-preferences'))
              .hitTestable()
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(
          find.byKey(const ValueKey('profile-learning-preferences')),
        );
        await _until(
          tester,
          () => find.text('Synthetic caller goal').evaluate().isNotEmpty,
        );
        expect(find.text('2026-12-31'), findsOneWidget);
        expect(
          (await tester.runAsync(() => ownerMigrationRows(fixture.database)))!,
          after,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await _closeFixture(tester, fixture);
      }
    },
  );

  testWidgets(
    'replacing the dependency scope retires an already open Profile editor before a save',
    (tester) async {
      final first = (await tester.runAsync(_Fixture.open))!;
      final second = (await tester.runAsync(_Fixture.open))!;
      final navigator = GlobalKey<NavigatorState>();
      try {
        await tester.pumpWidget(
          _app(
            first,
            const ProfileSettingsScreen(loader: _failedProgress),
            navigator: navigator,
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('profile-learning-preferences')),
        );
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('learning-profile-goal'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.enterText(
          find.byKey(const ValueKey('learning-profile-goal')),
          'Retired dependency draft',
        );
        await tester.pumpWidget(
          _app(
            second,
            const ProfileSettingsScreen(loader: _failedProgress),
            navigator: navigator,
          ),
        );
        await _flush(tester, 20);
        final save = find.byKey(const ValueKey('learning-profile-save'));
        if (save.evaluate().isNotEmpty &&
            tester.widget<FilledButton>(save).onPressed != null) {
          await tester.ensureVisible(save);
          await tester.tap(save);
        }
        await _flush(tester, 120);
        final retired = (await tester.runAsync(
          () => first.database
              .customSelect('SELECT * FROM learning_profiles')
              .get(),
        ))!;
        final current = (await tester.runAsync(
          () => second.database
              .customSelect('SELECT * FROM learning_profiles')
              .get(),
        ))!;
        expect(
          retired,
          isEmpty,
          reason:
              'An old open route must not save through the replaced service',
        );
        expect(
          current,
          isEmpty,
          reason:
              'A retired draft must not transfer to the replacement owner scope',
        );
        expect(find.text('บันทึกแผนการเรียนแล้ว'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          await first.close().timeout(const Duration(seconds: 10));
          await second.close().timeout(const Duration(seconds: 10));
        });
      }
    },
  );
}

Future<ProgressSnapshot> _failedProgress() => Future<ProgressSnapshot>.error(
  StateError('synthetic aggregate unavailable'),
);

Widget _app(
  _Fixture fixture,
  Widget home, {
  GlobalKey<NavigatorState>? navigator,
}) => AppDependenciesScope(
  dependencies: fixture.dependencies,
  child: MaterialApp(navigatorKey: navigator, home: home),
);

Future<void> _until(WidgetTester tester, bool Function() complete) async {
  for (var attempt = 0; attempt < 600; attempt++) {
    await _flush(tester, 1);
    if (complete()) return;
  }
  fail('Actual SQLite caller did not reach the expected visible state');
}

Future<void> _flush(WidgetTester tester, int count) async {
  for (var index = 0; index < count; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _closeFixture(WidgetTester tester, _Fixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
  await tester.runAsync(
    () => fixture.close().timeout(const Duration(seconds: 10)),
  );
}

final class _Fixture {
  _Fixture(this.database, this.profile, this.dependencies, this.ownerChanges);
  final AppDatabase database;
  final LearningProfileUseCases profile;
  final AppDependencies dependencies;
  final Stream<String?> ownerChanges;

  static Future<_Fixture> open({bool seedLearning = false}) async {
    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.now().toUtc();
    await database.customStatement(
      "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('synthetic-owner','localGuest',1,1)",
    );
    if (seedLearning) {
      final at = now
          .subtract(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      await database.customStatement(
        "INSERT INTO vocabulary_categories (id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES ('synthetic-category','synthetic-owner','Synthetic','synthetic',1,1)",
      );
      await database.customStatement(
        "INSERT INTO vocabulary_words (id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) VALUES ('synthetic-word','synthetic-owner','synthetic-category','sample','sample','example','example','noun',1,1)",
      );
      await database.customStatement(
        "INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,ended_at_utc_ms,app_version,build_id) VALUES ('synthetic-session','synthetic-owner','quiz','completed',?,?,'synthetic','synthetic')",
        [at - 1000, at],
      );
      await database.customStatement(
        "INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,attempt_number,occurred_at_utc_ms) VALUES ('synthetic-answer','synthetic-owner','synthetic-session','synthetic-word','meaningChoice',1,1,?)",
        [at],
      );
    }
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => throw StateError('Read must not create another owner'),
      nowUtc: () => now,
    );
    final progress = ProgressUseCases(
      owners: owners,
      queries: DriftProgressQueries(database),
      nowUtc: () => now,
    );
    final profile = LearningProfileUseCases(
      repository: DriftLearningProfileRepository(
        database: database,
        ownerWrites: DriftOwnerWriteCoordinator(database, nowUtc: () => now),
      ),
      nowUtc: () => now,
    );
    final packs = LearningPackUseCases(
      repository: DriftLearningPackRepository(
        database: database,
        ownerWrites: DriftOwnerWriteCoordinator(database, nowUtc: () => now),
      ),
      nowUtc: () => now,
      generateId: () => throw StateError('Browsing packs must not write'),
    );
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _UnusedGuest(),
      database: database,
      localOwners: owners,
      progress: progress,
      learningProfile: profile,
      learningPacks: packs,
    );
    final io = Zone.current;
    final ownerChanges = Stream<String?>.multi((events) {
      final source = io.run(
        () => progress.watchActiveOwnerId().listen(
          events.add,
          onError: events.addError,
          onDone: events.close,
        ),
      );
      events.onCancel = () => io.run(source.cancel);
    }, isBroadcast: true);
    return _Fixture(database, profile, dependencies, ownerChanges);
  }

  Future<void> close() async {
    await profile.dispose();
    await dependencies.learningPacks!.dispose();
    await database.close();
  }
}

final class _UnusedGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => throw StateError(
    'No authentication request belongs in these local callers',
  );
}
