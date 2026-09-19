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
