import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';
import 'package:vocab_learning_app/screens/learning_calendar_screen.dart';
import 'package:vocab_learning_app/screens/learning_goals_screen.dart';
import 'package:vocab_learning_app/features/goals/application/learning_goal_use_cases.dart';
import 'package:vocab_learning_app/features/goals/data/drift_learning_goal_repository.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/learning_preference_quiz_screen.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/data/drift_learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/features/achievements/application/achievement_share_card_use_cases.dart';
import 'package:vocab_learning_app/features/progress/domain/personal_learning_profile.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'dart:async';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as domain;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  _profileRecoveryTests();
  _calendarOwnerTests();
  _goalOwnerTests();
  _preferenceOwnerTests();
  _achievementOwnerTests();
  _masteryDependencyTests();
  setUpAll(tz.initializeTimeZones);
  late bool previousWarning;
  setUp(() {
    // Replacement coverage deliberately uses independent in-memory executors.
    previousWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDown(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarning,
  );
  for (final mismatched in [false, true]) {
    testWidgets(
      'bound local profile handles unavailable or mismatched account mismatch=$mismatched',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        try {
          await _finish(tester, _seed(db));
          final gateway = _Gateway()
            ..session = mismatched
                ? const AccountSession(
                    uid: 'uid-b',
                    email: 'b@example.test',
                    isAnonymous: false,
                    emailVerified: true,
                  )
                : null;
          final dependencies = _dependencies(db, gateway);
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: dependencies,
              child: const MaterialApp(
                home: MainNavigationScreen(initialIndex: 99),
              ),
            ),
          );
          await _until(
            tester,
            () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
          );
          expect(find.text('b@example.test'), findsNothing);
          if (mismatched) {
            expect(
              find.text('ไม่สามารถอ่านข้อมูลในเครื่องได้'),
              findsOneWidget,
            );
            expect(find.text('0 คำถึงกำหนด จาก 1 คำ'), findsNothing);
          } else {
            expect(find.text('ผู้เรียนในเครื่อง'), findsOneWidget);
            expect(find.text('0 คำถึงกำหนด จาก 1 คำ'), findsOneWidget);
          }
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _finish(tester, db.close());
        }
      },
    );
  }

  testWidgets(
    'production profile follows committed logout with unchanged dependencies',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final gateway = _Gateway();
        final dependencies = _dependencies(db, gateway);
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: dependencies,
            child: const MaterialApp(
              home: MainNavigationScreen(initialIndex: 99),
            ),
          ),
        );
        await _until(
          tester,
          () => find.text('a@example.test').evaluate().isNotEmpty,
        );
        expect(find.text('0 คำถึงกำหนด จาก 1 คำ'), findsOneWidget);
        await _finish(tester, dependencies.account!.signOutToLocalGuest());
        await tester.pump(const Duration(minutes: 3));
        await _until(
          tester,
          () => find.text('ผู้เรียนในเครื่อง').evaluate().isNotEmpty,
        );
        expect(find.text('a@example.test'), findsNothing);
        expect(find.text('0 คำถึงกำหนด จาก 1 คำ'), findsNothing);
        expect(
          find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
          findsOneWidget,
        );
        expect(
          await _finish(tester, db.select(db.srsStates).get()),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _finish(tester, db.close());
      }
    },
  );

  testWidgets(
    'late production profile load cannot restore retired owner axes',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'fallback',
          nowUtc: () => DateTime.utc(2026, 9, 19),
        );
        final delayed = _DelayedOwners(owners);
        final dependencies = _dependencies(
          db,
          _Gateway(),
          progressOwners: delayed,
        );
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: dependencies,
            child: const MaterialApp(
              home: MainNavigationScreen(initialIndex: 99),
            ),
          ),
        );
        await _until(tester, () => delayed.captured != null);
        await _finish(tester, dependencies.account!.signOutToLocalGuest());
        await tester.pump(const Duration(minutes: 3));
        await _until(
          tester,
          () => find.text('ผู้เรียนในเครื่อง').evaluate().isNotEmpty,
        );
        delayed.release.complete(delayed.captured!);
        await _finish(tester, delayed.release.future);
        for (var i = 0; i < 40; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(find.text('a@example.test'), findsNothing);
        expect(find.text('0 คำถึงกำหนด จาก 1 คำ'), findsNothing);
        expect(
          find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _finish(tester, db.close());
      }
    },
  );

  testWidgets(
    'active production profile invalidates replaced dependency owner',
    (tester) async {
      final first = AppDatabase(NativeDatabase.memory());
      final second = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(first));
        await _finish(
          tester,
          second
              .into(second.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'b',
                  createdAtUtcMs: 1,
                  firebaseUid: const Value('uid-b'),
                ),
              ),
        );
        final a = _dependencies(first, _Gateway());
        final b = _dependencies(
          second,
          _Gateway()
            ..session = const AccountSession(
              uid: 'uid-b',
              email: 'b@example.test',
              isAnonymous: false,
              emailVerified: true,
            ),
        );
        Widget app(AppDependencies dependencies) => AppDependenciesScope(
          dependencies: dependencies,
          child: const MaterialApp(
            home: MainNavigationScreen(initialIndex: 99),
          ),
        );
        await tester.pumpWidget(app(a));
        await _until(
          tester,
          () => find.text('a@example.test').evaluate().isNotEmpty,
        );
        expect(find.text('0 คำถึงกำหนด จาก 1 คำ'), findsOneWidget);
        await tester.pumpWidget(app(b));
        expect(find.text('0 คำถึงกำหนด จาก 1 คำ'), findsNothing);
        await _until(
          tester,
          () => find.text('b@example.test').evaluate().isNotEmpty,
        );
        expect(find.text('0 คำถึงกำหนด จาก 1 คำ'), findsNothing);
        expect(
          find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
          findsOneWidget,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _finish(tester, first.close());
        await _finish(tester, second.close());
      }
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'bounded database/UI completion');
}

Future<T> _finish<T>(WidgetTester tester, Future<T> future) async {
  var done = false;
  late T result;
  Object? error;
  future.then(
    (value) {
      result = value;
      done = true;
    },
    onError: (Object value) {
      error = value;
      done = true;
    },
  );
  await _until(tester, () => done);
  if (error != null) throw error!;
  return result;
}

AppDependencies _dependencies(
  AppDatabase db,
  _Gateway gateway, {
  LocalOwnerRepository? progressOwners,
  FeatureRegistry features = const BuildFeatureRegistry.fieldDefaults(),
}) {
  final research = InertResearchDependencies(db);
  final owners = DriftLocalOwnerRepository(
    db,
    generateId: () => 'fallback',
    nowUtc: () => DateTime.utc(2026, 9, 19),
  );
  var id = 0;
  final upgrades = DriftOwnerUpgradeRepository(
    db,
    nowUtc: () => DateTime.utc(2026, 9, 19),
    generateConflictId: () => 'conflict-${id++}',
    generateOwnerId: () => 'new-guest-${id++}',
    generateOwnerOperationToken: () => 'operation-${id++}',
    deleteOwnerSecrets: (_) async {},
  );
  return AppDependencies(
    initialRoute: AppRoute.home,
    features: features,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _Guest(),
    quest: testQuestUseCases(),
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    database: db,
    localOwners: owners,
    progress: ProgressUseCases(
      owners: progressOwners ?? owners,
      queries: DriftProgressQueries(db),
      nowUtc: () => DateTime.utc(2026, 9, 19),
    ),
    account: AccountUseCases(
      gateway: gateway,
      owners: owners,
      upgradeGuestOwner: UpgradeGuestOwner(upgrades),
      entryState: _Entry(),
    ),
  );
}

final class _Gateway implements AccountGateway {
  AccountSession? session = const AccountSession(
    uid: 'uid-a',
    email: 'a@example.test',
    isAnonymous: false,
    emailVerified: true,
  );
  @override
  AccountSession? get currentSession => session;
  @override
  Future<void> signOut() async {
    session = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Entry implements AppEntryStateStore {
  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
  @override
  Future<void> clear() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Guest implements GuestSessionService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _seed(AppDatabase db) async {
  await db
      .into(db.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: 'a',
          createdAtUtcMs: 1,
          firebaseUid: const Value('uid-a'),
          accountState: const Value('firebaseBound'),
        ),
      );
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'cat-a',
          ownerId: 'a',
          name: 'A',
          normalizedName: 'a',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await db
      .into(db.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word-a',
          ownerId: 'a',
          categoryId: 'cat-a',
          spelling: 'apple',
          normalizedSpelling: 'apple',
          meaning: 'fruit',
          normalizedMeaning: 'fruit',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await db
      .into(db.srsStates)
      .insert(
        SrsStatesCompanion.insert(
          id: 'srs-a',
          ownerId: 'a',
          wordId: 'word-a',
          dueAtUtcMs: 1,
          algorithmVersion: 1,
        ),
      );
}

final class _DelayedOwners implements LocalOwnerRepository {
  _DelayedOwners(this.delegate);
  final LocalOwnerRepository delegate;
  final release = Completer<domain.LocalOwner>();
  domain.LocalOwner? captured;
  var calls = 0;
  @override
  Future<domain.LocalOwner> getOrCreateActiveOwner() async {
    final owner = await delegate.getOrCreateActiveOwner();
    // First read belongs to the owner observer; hold the actual profile load.
    if (++calls != 2) return owner;
    captured = owner;
    return release.future;
  }

  @override
  Future<domain.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => delegate.bindFirebaseUid(ownerId, firebaseUid);
}

void _masteryDependencyTests() {
  testWidgets(
    'S01-AF explicit loader ignores unrelated dependency replacement',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final first = _dependencies(db, _Gateway());
        final next = _dependencies(db, _Gateway());
        final profile = await _finish(
          tester,
          first.progress!.loadPersonalLearningProfile(),
        );
        var calls = 0;
        Future<PersonalLearningProfile> load() async {
          calls++;
          return profile;
        }

        Widget app(AppDependencies deps) => AppDependenciesScope(
          dependencies: deps,
          child: MaterialApp(home: MasteryDashboardScreen(loader: load)),
        );
        await tester.pumpWidget(app(first));
        await tester.pumpAndSettle();
        await tester.pumpWidget(app(next));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(find.text('ยังไม่มีคำตอบในสัปดาห์นี้'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _finish(tester, db.close());
      }
    },
  );

  for (final lateError in [false, true]) {
    testWidgets(
      'S01-AF retired owner read cannot restore axes error=$lateError',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        try {
          await _finish(tester, _seed(db));
          final owners = DriftLocalOwnerRepository(
            db,
            generateId: () => 'fallback',
            nowUtc: () => DateTime.utc(2026, 9, 19),
          );
          final delayed = _DelayedOwners(owners);
          final deps = _dependencies(db, _Gateway(), progressOwners: delayed);
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: deps,
              child: const MaterialApp(home: MasteryDashboardScreen()),
            ),
          );
          await _until(tester, () => delayed.captured != null);
          await _finish(tester, deps.account!.signOutToLocalGuest());
          await tester.pump(const Duration(minutes: 3));
          await _until(
            tester,
            () => find
                .text('ยังไม่มีหลักฐานการเรียนที่เพียงพอ')
                .evaluate()
                .isNotEmpty,
          );
          if (lateError) {
            delayed.release.completeError(StateError('retired'));
          } else {
            delayed.release.complete(delayed.captured!);
          }
          for (var i = 0; i < 40; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(
            find.text('ยังไม่มีหลักฐานการเรียนที่เพียงพอ'),
            findsOneWidget,
          );
          expect(
            find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _finish(tester, db.close());
        }
      },
    );
  }
  testWidgets('S01-AF failed owner observation can explicitly retry', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await _finish(tester, _seed(db));
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'fallback',
        nowUtc: () => DateTime.utc(2026, 9, 19),
      );
      final delayed = _DelayedOwners(owners)..calls = 1;
      final deps = _dependencies(db, _Gateway(), progressOwners: delayed);
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: deps,
          child: const MaterialApp(home: MasteryDashboardScreen()),
        ),
      );
      await _until(tester, () => delayed.captured != null);
      delayed.release.completeError(StateError('owner read failed'));
      await _until(
        tester,
        () => find.text('ลองอีกครั้ง').evaluate().isNotEmpty,
      );
      final retry = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .onPressed!;
      retry();
      retry();
      await _until(
        tester,
        () => find.text('ยังไม่มีคำตอบในสัปดาห์นี้').evaluate().isNotEmpty,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _finish(tester, db.close());
    }
  });

  testWidgets(
    'S01-AF mastery follows committed owner change with same dependencies',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final deps = _dependencies(db, _Gateway());
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: deps,
            child: const MaterialApp(home: MasteryDashboardScreen()),
          ),
        );
        await _until(
          tester,
          () => find.text('ยังไม่มีคำตอบในสัปดาห์นี้').evaluate().isNotEmpty,
        );
        expect(find.text('ยังไม่มีหลักฐานการเรียนที่เพียงพอ'), findsNothing);
        await _finish(tester, deps.account!.signOutToLocalGuest());
        await tester.pump(const Duration(minutes: 3));
        await _until(
          tester,
          () => find
              .text('ยังไม่มีหลักฐานการเรียนที่เพียงพอ')
              .evaluate()
              .isNotEmpty,
        );
        expect(
          await _finish(tester, db.select(db.srsStates).get()),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _finish(tester, db.close());
      }
    },
  );

  testWidgets(
    'S01-AF mastery replaces real progress authority during pending read',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'fallback',
          nowUtc: () => DateTime.utc(2026, 9, 19),
        );
        final delayed = _DelayedOwners(owners)..calls = 1;
        final old = _dependencies(db, _Gateway(), progressOwners: delayed);
        final next = _dependencies(db, _Gateway());
        Widget app(AppDependencies deps) => AppDependenciesScope(
          dependencies: deps,
          child: const MaterialApp(home: MasteryDashboardScreen()),
        );
        await tester.pumpWidget(app(old));
        await _until(tester, () => delayed.captured != null);
        await tester.pumpWidget(app(next));
        await _until(
          tester,
          () => find.text('ยังไม่มีคำตอบในสัปดาห์นี้').evaluate().isNotEmpty,
        );
        delayed.release.completeError(StateError('retired read'));
        await tester.pump();
        await tester.pump();
        expect(
          find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
          findsNothing,
        );
        expect(find.text('ยังไม่มีคำตอบในสัปดาห์นี้'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await _finish(tester, db.close());
      }
    },
  );
}

void _achievementOwnerTests() {
  for (final failure in [false, true]) {
    testWidgets(
      'AH late canonical owner read cannot restore retired unlock failure=$failure',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        try {
          await _finish(tester, _seed(db));
          await _finish(
            tester,
            db
                .into(db.achievementUnlocks)
                .insert(
                  AchievementUnlocksCompanion.insert(
                    id: 'unlock-a',
                    ownerId: 'a',
                    achievementId: 'first_answer',
                    definitionVersion: 1,
                    sourceEventId: 'event-a',
                    unlockedAtUtcMs: 1,
                  ),
                ),
          );
          final owners = DriftLocalOwnerRepository(
            db,
            generateId: () => 'fallback',
            nowUtc: () => DateTime.utc(2026, 9, 19),
          );
          final delayed = _DelayedOwners(owners);
          final deps = _dependencies(db, _Gateway(), progressOwners: delayed);
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: deps,
              child: const MaterialApp(home: AchievementsScreen()),
            ),
          );
          await _until(tester, () => delayed.captured != null);
          await _finish(tester, deps.account!.signOutToLocalGuest());
          await tester.pump(const Duration(minutes: 3));
          await _until(
            tester,
            () => find.textContaining('จำนวนหลักฐาน: 0').evaluate().isNotEmpty,
          );
          if (failure) {
            delayed.release.completeError(StateError('old owner'));
          } else {
            delayed.release.complete(delayed.captured!);
          }
          await tester.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('achievement-share/first_answer')),
            findsNothing,
          );
          expect(
            find.text('ไม่สามารถอ่านประวัติความสำเร็จในเครื่องได้'),
            findsNothing,
          );
          expect(find.textContaining('จำนวนหลักฐาน: 0'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await _finish(tester, db.close());
        }
      },
    );
  }

  for (final pendingSave in [false, true]) {
    testWidgets(
      'AH canonical owner change retires share pendingSave=$pendingSave',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        final store = _AchievementStore();
        try {
          await _finish(tester, _seed(db));
          await _finish(
            tester,
            db
                .into(db.achievementUnlocks)
                .insert(
                  AchievementUnlocksCompanion.insert(
                    id: 'unlock-a',
                    ownerId: 'a',
                    achievementId: 'first_answer',
                    definitionVersion: 1,
                    sourceEventId: 'event-a',
                    unlockedAtUtcMs: 1,
                  ),
                ),
          );
          final deps = _dependencies(db, _Gateway());
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: deps,
              child: MaterialApp(
                home: AchievementsScreen(
                  shareCards: AchievementShareCardUseCases(store: store),
                ),
              ),
            ),
          );
          await _until(
            tester,
            () => find
                .byKey(const ValueKey('achievement-share/first_answer'))
                .evaluate()
                .isNotEmpty,
          );
          await tester.tap(
            find.byKey(const ValueKey('achievement-share/first_answer')),
          );
          await tester.pumpAndSettle();
          if (pendingSave) {
            await tester.tap(
              find.widgetWithText(FilledButton, 'เลือกตำแหน่งบันทึก'),
            );
            await tester.pump();
            await tester.pump(const Duration(seconds: 1));
            expect(store.calls, 1);
          }
          await _finish(tester, deps.account!.signOutToLocalGuest());
          await tester.pump(const Duration(minutes: 3));
          for (var i = 0; i < 25; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 5)),
            );
            await tester.pump();
          }
          if (pendingSave) {
            store.pending.complete(
              const AchievementShareCardStoreResult.saved(
                destination: 'local.svg',
              ),
            );
          } else {
            await tester.tap(
              find.widgetWithText(FilledButton, 'เลือกตำแหน่งบันทึก'),
            );
          }
          await tester.pumpAndSettle();
          expect(store.calls, pendingSave ? 1 : 0);
          expect(find.text('บันทึกการ์ดความสำเร็จแล้ว'), findsNothing);
          await _until(
            tester,
            () => find.textContaining('จำนวนหลักฐาน: 0').evaluate().isNotEmpty,
          );
          expect(
            find.byKey(const ValueKey('achievement-share/first_answer')),
            findsNothing,
          );
          expect(
            await _finish(tester, db.select(db.achievementUnlocks).get()),
            hasLength(1),
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          await _finish(tester, db.close());
        }
      },
    );
  }
  testWidgets('AH explicit achievement loader ignores unrelated dependencies', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await _finish(tester, _seed(db));
      final first = _dependencies(db, _Gateway());
      final next = _dependencies(db, _Gateway());
      final progress = await _finish(tester, first.progress!.load());
      var calls = 0;

      final loader = () async {
        calls++;
        return progress;
      };
      Widget app(AppDependencies deps) => AppDependenciesScope(
        dependencies: deps,
        child: MaterialApp(home: AchievementsScreen(loader: loader)),
      );
      await tester.pumpWidget(app(first));
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(next));
      await tester.pumpAndSettle();
      expect(calls, 1);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await _finish(tester, db.close());
    }
  });
}

final class _AchievementStore implements AchievementShareCardStore {
  final pending = Completer<AchievementShareCardStoreResult>();
  var calls = 0;
  @override
  Future<AchievementShareCardStoreResult> selectDestinationAndSave(
    AchievementShareCardArtifact artifact,
  ) {
    calls++;
    return pending.future;
  }
}

void _preferenceOwnerTests() {
  testWidgets(
    'AJ temporary owner observation error preserves draft behind retry',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final owners = _PreferenceFlakyOwners(
          DriftLocalOwnerRepository(
            db,
            generateId: () => 'fallback',
            nowUtc: () => DateTime.utc(2026),
          ),
        );
        final deps = _dependencies(
          db,
          _Gateway(),
          progressOwners: owners,
          features: const BuildFeatureRegistry.allEnabled(),
        );
        final cases = LearnerPreferencesUseCases(
          repository: DriftLearnerPreferencesRepository(db),
          owners: owners,
          nowUtc: () => DateTime.utc(2026),
        );
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: deps,
            child: MaterialApp(
              home: LearningPreferenceQuizScreen(useCases: cases),
            ),
          ),
        );
        await _until(
          tester,
          () => find.byType(TextField).evaluate().isNotEmpty,
        );
        await tester.enterText(find.byType(TextField), '79');
        owners.fail = true;
        await _finish(
          tester,
          db
              .update(db.localOwners)
              .write(
                const LocalOwnersCompanion(firebaseUid: Value('changed-uid')),
              ),
        );
        await _until(tester, () => find.text('ลองใหม่').evaluate().isNotEmpty);
        expect(find.byType(TextField), findsNothing);
        owners.fail = false;
        await tester.tap(find.text('ลองใหม่'));
        await _until(
          tester,
          () => find.byType(TextField).evaluate().isNotEmpty,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '79',
        );
        expect(
          await _finish(tester, db.select(db.learnerPreferences).get()),
          isEmpty,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _finish(tester, db.close());
      }
    },
  );
  testWidgets(
    'AJ committed owner change clears visible preference draft and old callbacks',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final deps = _dependencies(
          db,
          _Gateway(),
          features: const BuildFeatureRegistry.allEnabled(),
        );
        final cases = LearnerPreferencesUseCases(
          repository: DriftLearnerPreferencesRepository(db),
          owners: deps.localOwners!,
          nowUtc: () => DateTime.utc(2026, 9, 24),
        );
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: deps,
            child: MaterialApp(
              home: LearningPreferenceQuizScreen(useCases: cases),
            ),
          ),
        );
        await _until(
          tester,
          () => find.byType(TextField).evaluate().isNotEmpty,
        );
        await tester.enterText(find.byType(TextField), '79');
        final goal = tester
            .widget<DropdownButtonFormField<LearnerPreferenceGoal>>(
              find.byKey(const ValueKey('learning-preferences/goal')),
            )
            .onChanged!;
        final save = tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('learning-preferences/save')),
            )
            .onPressed!;
        await _finish(tester, deps.account!.signOutToLocalGuest());
        await tester.pump(const Duration(minutes: 3));
        await _until(
          tester,
          () =>
              find.byType(TextField).evaluate().isNotEmpty &&
              tester
                      .widget<TextField>(find.byType(TextField))
                      .controller!
                      .text ==
                  '20',
        );
        goal(LearnerPreferenceGoal.examPreparation);
        save();
        await tester.pumpAndSettle();
        expect(
          await _finish(tester, db.select(db.learnerPreferences).get()),
          isEmpty,
        );
        expect(
          tester
              .widget<DropdownButtonFormField<LearnerPreferenceGoal>>(
                find.byKey(const ValueKey('learning-preferences/goal')),
              )
              .initialValue,
          LearnerPreferenceGoal.balancedGrowth,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _finish(tester, db.close());
      }
    },
  );
  testWidgets('AJ owner change during open dropdown retires picker and draft', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await _finish(tester, _seed(db));
      final deps = _dependencies(
        db,
        _Gateway(),
        features: const BuildFeatureRegistry.allEnabled(),
      );
      final cases = LearnerPreferencesUseCases(
        repository: DriftLearnerPreferencesRepository(db),
        owners: deps.localOwners!,
        nowUtc: () => DateTime.utc(2026, 9, 24),
      );
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: deps,
          child: MaterialApp(
            home: LearningPreferenceQuizScreen(useCases: cases),
          ),
        ),
      );
      await _until(tester, () => find.byType(TextField).evaluate().isNotEmpty);
      await tester.enterText(find.byType(TextField), '79');
      final goal = tester
          .widget<DropdownButtonFormField<LearnerPreferenceGoal>>(
            find.byKey(const ValueKey('learning-preferences/goal')),
          )
          .onChanged!;
      final save = tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('learning-preferences/save')),
          )
          .onPressed!;
      await tester.tap(find.byKey(const ValueKey('learning-preferences/goal')));
      await tester.pumpAndSettle();
      await _finish(tester, deps.account!.signOutToLocalGuest());
      await tester.pump(const Duration(minutes: 3));
      await _until(
        tester,
        () =>
            find.byType(TextField).evaluate().isNotEmpty &&
            tester.widget<TextField>(find.byType(TextField)).controller!.text ==
                '20',
      );
      goal(LearnerPreferenceGoal.examPreparation);
      save();
      await tester.pumpAndSettle();
      expect(
        await _finish(tester, db.select(db.learnerPreferences).get()),
        isEmpty,
      );
      expect(
        tester
            .widget<DropdownButtonFormField<LearnerPreferenceGoal>>(
              find.byKey(const ValueKey('learning-preferences/goal')),
            )
            .initialValue,
        LearnerPreferenceGoal.balancedGrowth,
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      await _finish(tester, db.close());
    }
  });
  for (final lostAck in [false, true]) {
    testWidgets(
      'AJ real Drift explicit save preserves home display and deduplicates lostAck=$lostAck',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        try {
          await _finish(tester, _seed(db));
          final deps = _dependencies(
            db,
            _Gateway(),
            features: const BuildFeatureRegistry.allEnabled(),
          );
          var notifications = 0;
          final cases = LearnerPreferencesUseCases(
            repository: DriftLearnerPreferencesRepository(
              db,
              onLocalMutation: () async {
                notifications++;
                if (lostAck) throw StateError('ack lost');
              },
            ),
            owners: deps.localOwners!,
            nowUtc: () => DateTime.utc(2026, 9, 24),
          );
          final seedCases = LearnerPreferencesUseCases(
            repository: DriftLearnerPreferencesRepository(db),
            owners: deps.localOwners!,
            nowUtc: () => DateTime.utc(2026, 9, 23),
          );
          final owner = await _finish(
            tester,
            deps.localOwners!.getOrCreateActiveOwner(),
          );
          await _finish(
            tester,
            seedCases.saveHomeExperience(
              expectedOwnerId: owner.id,
              homeExperience: HomeExperience.adventure,
            ),
          );
          await _finish(
            tester,
            seedCases.saveDisplayPreferences(
              expectedOwnerId: owner.id,
              themeMode: LearnerThemePreference.dark,
              motionMode: LearnerMotionPreference.reduced,
            ),
          );
          final before = await _finish(tester, seedCases.read());
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: deps,
              child: MaterialApp(
                home: LearningPreferenceQuizScreen(useCases: cases),
              ),
            ),
          );
          await _until(
            tester,
            () => find.byType(TextField).evaluate().isNotEmpty,
          );
          await tester.enterText(find.byType(TextField), '51');
          final save = tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('learning-preferences/save')),
              )
              .onPressed!;
          save();
          save();
          await _until(
            tester,
            () =>
                find.text('บันทึกการตั้งค่าการเรียนแล้ว').evaluate().isNotEmpty,
          );
          final after = await _finish(tester, seedCases.read());
          expect(after.availableMinutesPerDay, 51);
          expect(after.homeExperience, before.homeExperience);
          expect(after.display, before.display);
          expect(notifications, 1);
          final outbox = (await _finish(
            tester,
            db.select(db.outboxOperations).get(),
          )).map((r) => r.toJson()).toList();
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('learning-preferences/save')),
              )
              .onPressed!();
          await _until(
            tester,
            () =>
                find.text('บันทึกการตั้งค่าการเรียนแล้ว').evaluate().isNotEmpty,
          );
          expect(notifications, 1);
          expect(
            (await _finish(
              tester,
              db.select(db.outboxOperations).get(),
            )).map((r) => r.toJson()).toList(),
            outbox,
          );
        } finally {
          await tester.pumpWidget(const SizedBox());
          await _finish(tester, db.close());
        }
      },
    );
  }
}

final class _PreferenceFlakyOwners implements LocalOwnerRepository {
  _PreferenceFlakyOwners(this.delegate);
  final LocalOwnerRepository delegate;
  bool fail = false;
  @override
  Future<domain.LocalOwner> getOrCreateActiveOwner() {
    if (fail) return Future.error(StateError('owner temporarily unavailable'));
    return delegate.getOrCreateActiveOwner();
  }

  @override
  Future<domain.LocalOwner> bindFirebaseUid(String id, String uid) =>
      delegate.bindFirebaseUid(id, uid);
}

void _goalOwnerTests() {
  testWidgets(
    'AK transient owner observation hides and restores same-owner goal draft',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final owners = _PreferenceFlakyOwners(
          DriftLocalOwnerRepository(
            db,
            generateId: () => 'fallback',
            nowUtc: () => DateTime.utc(2026),
          ),
        );
        final deps = _dependencies(
          db,
          _Gateway(),
          progressOwners: owners,
          features: const BuildFeatureRegistry.allEnabled(),
        );
        final cases = LearningGoalUseCases(
          repository: DriftLearningGoalRepository(db, owners: owners),
          activeOwnerId: () async => (await owners.getOrCreateActiveOwner()).id,
          nowUtc: () => DateTime.utc(2026, 9, 24),
          generateId: () => 'goal:owner',
        );
        await _finish(
          tester,
          cases.create(
            kind: LearningGoalKind.personal,
            title: 'Private goal owner A',
            deadlineAtUtc: DateTime.utc(2026, 10, 1),
            timezone: const LearningGoalTimezoneContext(
              timezoneId: 'UTC',
              utcOffsetMinutes: 0,
            ),
          ),
        );
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: deps,
            child: MaterialApp(home: LearningGoalsScreen(useCases: cases)),
          ),
        );
        await _until(
          tester,
          () => find.text('Private goal owner A').evaluate().isNotEmpty,
        );
        await tester.tap(
          find.byKey(const ValueKey('learning-goal/goal:owner/edit')),
        );
        await _until(
          tester,
          () => find.byType(TextField).evaluate().isNotEmpty,
        );
        await tester.enterText(
          find.byKey(const ValueKey('learning-goals/title')),
          'Retain private draft',
        );
        owners.fail = true;
        await _finish(
          tester,
          db
              .update(db.localOwners)
              .write(
                const LocalOwnersCompanion(firebaseUid: Value('changed-uid')),
              ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Retain private draft'), findsNothing);
        expect(
          find.byKey(const ValueKey('learning-goals/editor-retry')),
          findsOneWidget,
        );
        owners.fail = false;
        await tester.tap(
          find.byKey(const ValueKey('learning-goals/editor-retry')),
        );
        await _until(
          tester,
          () => find.text('Retain private draft').evaluate().isNotEmpty,
        );
        final rows = await _finish(tester, db.select(db.learningGoals).get());
        expect(rows.single.title, 'Private goal owner A');
        expect(rows.single.localRevision, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _finish(tester, db.close());
      }
    },
  );

  testWidgets(
    'AK committed owner change hides goal editor and retires callbacks',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final deps = _dependencies(
          db,
          _Gateway(),
          features: const BuildFeatureRegistry.allEnabled(),
        );
        final cases = LearningGoalUseCases(
          repository: DriftLearningGoalRepository(
            db,
            owners: deps.localOwners!,
          ),
          activeOwnerId: () async =>
              (await deps.localOwners!.getOrCreateActiveOwner()).id,
          nowUtc: () => DateTime.utc(2026, 9, 24),
          generateId: () => 'goal:owner',
        );
        await _finish(
          tester,
          cases.create(
            kind: LearningGoalKind.personal,
            title: 'Private goal owner A',
            deadlineAtUtc: DateTime.utc(2026, 10, 1),
            timezone: const LearningGoalTimezoneContext(
              timezoneId: 'UTC',
              utcOffsetMinutes: 0,
            ),
          ),
        );
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: deps,
            child: MaterialApp(home: LearningGoalsScreen(useCases: cases)),
          ),
        );
        await _until(
          tester,
          () => find.text('Private goal owner A').evaluate().isNotEmpty,
        );
        await tester.tap(
          find.byKey(const ValueKey('learning-goal/goal:owner/edit')),
        );
        await _until(
          tester,
          () => find.byType(TextField).evaluate().isNotEmpty,
        );
        await tester.enterText(
          find.byKey(const ValueKey('learning-goals/title')),
          'Private unsaved A draft',
        );
        final save = tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('learning-goals/save')),
            )
            .onPressed!;
        await _finish(tester, deps.account!.signOutToLocalGuest());
        await tester.pump(const Duration(minutes: 3));
        await tester.pumpAndSettle();
        expect(find.text('Private unsaved A draft'), findsNothing);
        expect(find.text('Private goal owner A'), findsNothing);
        save();
        await tester.pumpAndSettle();
        final rows = await _finish(tester, db.select(db.learningGoals).get());
        expect(rows.single.title, 'Private goal owner A');
        expect(rows.single.localRevision, 1);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _finish(tester, db.close());
      }
    },
  );
}

void _calendarOwnerTests() {
  testWidgets(
    'AM custom calendar remains independent of unrelated dependency replacement',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final first = _dependencies(db, _Gateway());
        final next = _dependencies(db, _Gateway());
        final profile = await _finish(
          tester,
          first.progress!.loadPersonalLearningProfile(),
        );
        var calls = 0;
        Future<LearningCalendarSnapshot> load() async {
          calls++;
          return profile.calendar;
        }

        Widget app(AppDependencies deps) => AppDependenciesScope(
          dependencies: deps,
          child: MaterialApp(home: LearningCalendarScreen(loader: load)),
        );
        await tester.pumpWidget(app(first));
        await tester.pumpAndSettle();
        await tester.pumpWidget(app(next));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(find.text('0 วินาที'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _finish(tester, db.close());
      }
    },
  );

  testWidgets(
    'AM calendar replaces private effort after committed owner change',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        await _finish(tester, _seedCalendarEffort(db));
        final deps = _dependencies(db, _Gateway());
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: deps,
            child: const MaterialApp(home: LearningCalendarScreen()),
          ),
        );
        await _until(
          tester,
          () => find.text('75 วินาที').evaluate().isNotEmpty,
        );
        await _finish(tester, deps.account!.signOutToLocalGuest());
        await tester.pump(const Duration(minutes: 3));
        await _until(tester, () => find.text('0 วินาที').evaluate().isNotEmpty);
        expect(find.text('75 วินาที'), findsNothing);
        expect(
          await _finish(tester, db.select(db.learningTimeSegments).get()),
          hasLength(1),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _finish(tester, db.close());
      }
    },
  );
  for (final error in [false, true]) {
    testWidgets(
      'AM late owner calendar read cannot restore old effort error=$error',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        try {
          await _finish(tester, _seed(db));
          await _finish(tester, _seedCalendarEffort(db));
          final delayed = _DelayedOwners(
            DriftLocalOwnerRepository(
              db,
              generateId: () => 'fallback',
              nowUtc: () => DateTime.utc(2026),
            ),
          );
          final deps = _dependencies(db, _Gateway(), progressOwners: delayed);
          await tester.pumpWidget(
            AppDependenciesScope(
              dependencies: deps,
              child: const MaterialApp(home: LearningCalendarScreen()),
            ),
          );
          await _until(tester, () => delayed.captured != null);
          await _finish(tester, deps.account!.signOutToLocalGuest());
          await tester.pump(const Duration(minutes: 3));
          await _until(
            tester,
            () => find.text('0 วินาที').evaluate().isNotEmpty,
          );
          if (error) {
            delayed.release.completeError(StateError('old read'));
          } else {
            delayed.release.complete(delayed.captured!);
          }
          for (var i = 0; i < 40; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(find.text('75 วินาที'), findsNothing);
          expect(find.text('0 วินาที'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await _finish(tester, db.close());
        }
      },
    );
  }
  testWidgets('AM calendar replaces pending production authority', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await _finish(tester, _seed(db));
      await _finish(tester, _seedCalendarEffort(db));
      final delayed = _DelayedOwners(
        DriftLocalOwnerRepository(
          db,
          generateId: () => 'fallback',
          nowUtc: () => DateTime.utc(2026),
        ),
      );
      final first = _dependencies(db, _Gateway(), progressOwners: delayed);
      final next = _dependencies(db, _Gateway());
      Widget app(AppDependencies deps) => AppDependenciesScope(
        dependencies: deps,
        child: const MaterialApp(home: LearningCalendarScreen()),
      );
      await tester.pumpWidget(app(first));
      await _until(tester, () => delayed.captured != null);
      await tester.pumpWidget(app(next));
      await _until(tester, () => find.text('75 วินาที').evaluate().isNotEmpty);
      delayed.release.completeError(StateError('old dependency'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(find.text('75 วินาที'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await _finish(tester, db.close());
    }
  });

  testWidgets(
    'AM open calendar observes owner failure and recovers read only',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final owners = _PreferenceFlakyOwners(
          DriftLocalOwnerRepository(
            db,
            generateId: () => 'fallback',
            nowUtc: () => DateTime.utc(2026),
          ),
        );
        final deps = _dependencies(db, _Gateway(), progressOwners: owners);
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: deps,
            child: const MaterialApp(home: MasteryDashboardScreen()),
          ),
        );
        await _until(
          tester,
          () => find.text('ยังไม่มีคำตอบในสัปดาห์นี้').evaluate().isNotEmpty,
        );
        await tester.scrollUntilVisible(
          find.byKey(const Key('learning-calendar-action')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('learning-calendar-action')));
        await _until(tester, () => find.text('0 วินาที').evaluate().isNotEmpty);
        await tester.pumpAndSettle();
        owners.fail = true;
        await _finish(
          tester,
          db
              .update(db.localOwners)
              .write(
                const LocalOwnersCompanion(firebaseUid: Value('changed-uid')),
              ),
        );
        await _until(
          tester,
          () => find
              .text('ไม่สามารถอ่านข้อมูลการเรียนในเครื่องได้')
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('0 วินาที'), findsNothing);
        owners.fail = false;
        await tester.tap(find.text('ลองอีกครั้ง'));
        await _until(tester, () => find.text('0 วินาที').evaluate().isNotEmpty);
        expect(
          await _finish(tester, db.select(db.srsStates).get()),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _finish(tester, db.close());
      }
    },
  );
  testWidgets('AM open calendar follows dependency feature withdrawal', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      await _finish(tester, _seed(db));
      final deps = _dependencies(db, _Gateway());
      final off = _dependencies(
        db,
        _Gateway(),
        features: const BuildFeatureRegistry({
          Feature.mastery: FeatureState.emergencyOff,
        }),
      );
      Widget app(AppDependencies d) => AppDependenciesScope(
        dependencies: d,
        child: const MaterialApp(home: MasteryDashboardScreen()),
      );
      await tester.pumpWidget(app(deps));
      await _until(
        tester,
        () => find.text('ยังไม่มีคำตอบในสัปดาห์นี้').evaluate().isNotEmpty,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('learning-calendar-action')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('learning-calendar-action')));
      await _until(tester, () => find.text('0 วินาที').evaluate().isNotEmpty);
      await tester.pumpAndSettle();
      await tester.pumpWidget(app(off));
      await tester.pumpAndSettle();
      expect(find.text('ยังเปิดหน้านี้ไม่ได้'), findsOneWidget);
      expect(find.text('0 วินาที'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox());
      await _finish(tester, db.close());
    }
  });
}

Future<void> _seedCalendarEffort(AppDatabase db) async {
  final start = DateTime.utc(2026, 9, 18).millisecondsSinceEpoch;
  await db
      .into(db.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'am-session',
          ownerId: 'a',
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: start,
          appVersion: 'test',
          buildId: 'test',
        ),
      );
  await db
      .into(db.learningTimeSegments)
      .insert(
        LearningTimeSegmentsCompanion.insert(
          id: 'am-time',
          ownerId: 'a',
          sessionId: 'am-session',
          activeStartOffsetMs: 0,
          activeDurationMs: 75000,
          startedAtUtcMs: start,
          endedAtUtcMs: start + 75000,
          timezoneId: 'Asia/Bangkok',
          timezoneOffsetMinutes: 420,
          captureSource: 'automaticLesson',
        ),
      );
}

void _profileRecoveryTests() {
  for (final lateError in [false, true]) {
    testWidgets(
      'AN retired observer cannot replace reactivated same dependency error=$lateError',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        try {
          await _finish(tester, _seed(db));
          final owners = _ProfileHeldObserver(
            DriftLocalOwnerRepository(
              db,
              generateId: () => 'fallback',
              nowUtc: () => DateTime.utc(2026),
            ),
          );
          final deps = _dependencies(db, _Gateway(), progressOwners: owners);
          Widget app(bool active) => AppDependenciesScope(
            dependencies: deps,
            child: MaterialApp(
              home: TickerMode(
                enabled: active,
                child: const ProfileSettingsScreen(),
              ),
            ),
          );
          await tester.pumpWidget(app(true));
          await _until(tester, () => owners.captured != null);
          await tester.pumpWidget(app(false));
          await tester.pumpWidget(app(true));
          await _until(
            tester,
            () => find.text('a@example.test').evaluate().isNotEmpty,
          );
          if (lateError) {
            owners.release.completeError(StateError('retired observer'));
          } else {
            owners.release.complete(owners.captured!);
          }
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(find.text('a@example.test'), findsOneWidget);
          expect(find.text('ไม่สามารถอ่านข้อมูลในเครื่องได้'), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await _finish(tester, db.close());
        }
      },
    );
    testWidgets(
      'AN custom to canonical replacement ignores old completion error=$lateError',
      (tester) async {
        final db = AppDatabase(NativeDatabase.memory());
        try {
          await _finish(tester, _seed(db));
          final deps = _dependencies(db, _Gateway());
          final oldProfile = await _finish(
            tester,
            deps.progress!.loadPersonalLearningProfile(),
          );
          final pending = Completer<PersonalLearningProfile>();
          Widget app(ProfileSettingsProfileLoader? loader) =>
              AppDependenciesScope(
                dependencies: deps,
                child: MaterialApp(home: ProfileSettingsScreen(loader: loader)),
              );
          await tester.pumpWidget(app(() => pending.future));
          await tester.pumpWidget(app(null));
          await _until(
            tester,
            () => find.text('a@example.test').evaluate().isNotEmpty,
          );
          if (lateError) {
            pending.completeError(StateError('retired loader'));
          } else {
            pending.complete(oldProfile);
          }
          await tester.pumpAndSettle();
          expect(find.text('a@example.test'), findsOneWidget);
          expect(find.text('0 คำถึงกำหนด จาก 1 คำ'), findsOneWidget);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          await _finish(tester, db.close());
        }
      },
    );
  }

  testWidgets(
    'AN custom profile stays independent and never borrows unrelated account email',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final first = _dependencies(db, _Gateway());
        final second = _dependencies(db, _Gateway());
        final profile = await _finish(
          tester,
          first.progress!.loadPersonalLearningProfile(),
        );
        var calls = 0;
        Future<PersonalLearningProfile> load() async {
          calls++;
          return profile;
        }

        Widget app(AppDependencies deps) => AppDependenciesScope(
          dependencies: deps,
          child: MaterialApp(home: ProfileSettingsScreen(loader: load)),
        );
        await tester.pumpWidget(app(first));
        await tester.pumpAndSettle();
        expect(find.text('a@example.test'), findsNothing);
        expect(find.text('ผู้เรียนในเครื่อง'), findsOneWidget);
        await tester.pumpWidget(app(second));
        await tester.pumpAndSettle();
        expect(calls, 1);
        expect(find.text('0 คำถึงกำหนด จาก 1 คำ'), findsOneWidget);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _finish(tester, db.close());
      }
    },
  );
  testWidgets(
    'AN owner observation errors hide identity and retry reads without mutations',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await _finish(tester, _seed(db));
        final owners = _PreferenceFlakyOwners(
          DriftLocalOwnerRepository(
            db,
            generateId: () => 'fallback',
            nowUtc: () => DateTime.utc(2026),
          ),
        );
        final deps = _dependencies(db, _Gateway(), progressOwners: owners);
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: deps,
            child: const MaterialApp(home: ProfileSettingsScreen()),
          ),
        );
        await _until(
          tester,
          () => find.text('a@example.test').evaluate().isNotEmpty,
        );
        owners.fail = true;
        await _finish(
          tester,
          db
              .update(db.localOwners)
              .write(const LocalOwnersCompanion(firebaseUid: Value('uid-a'))),
        );
        await _until(
          tester,
          () => find
              .text('ไม่สามารถอ่านข้อมูลในเครื่องได้')
              .evaluate()
              .isNotEmpty,
        );
        expect(find.text('a@example.test'), findsNothing);
        expect(find.text('0 คำถึงกำหนด จาก 1 คำ'), findsNothing);
        owners.fail = false;
        await tester.tap(find.text('ลองอีกครั้ง'));
        await _until(
          tester,
          () => find.text('a@example.test').evaluate().isNotEmpty,
        );
        expect(
          await _finish(tester, db.select(db.srsStates).get()),
          hasLength(1),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await _finish(tester, db.close());
      }
    },
  );
}

final class _ProfileHeldObserver implements LocalOwnerRepository {
  _ProfileHeldObserver(this.delegate);
  final LocalOwnerRepository delegate;
  final release = Completer<domain.LocalOwner>();
  domain.LocalOwner? captured;
  var calls = 0;
  @override
  Future<domain.LocalOwner> getOrCreateActiveOwner() async {
    final owner = await delegate.getOrCreateActiveOwner();
    if (++calls != 1) return owner;
    captured = owner;
    return release.future;
  }

  @override
  Future<domain.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => delegate.bindFirebaseUid(ownerId, firebaseUid);
}
