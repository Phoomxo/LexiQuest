import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_study_preferences_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/study_preferences.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/cefr_article_reader_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/study_preferences_panel.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets('first reading choice opens the shipped article and persists', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 9, 1);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-owner',
      nowUtc: () => now,
    );
    final owner = (await tester.runAsync(() async {
      final guest = await owners.getOrCreateActiveOwner();
      return owners.bindFirebaseUid(guest.id, 'synthetic-verified-uid');
    }))!;
    final preferences = DriftStudyPreferencesRepository(
      database,
      nowUtc: () => now,
    );
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.ready,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _Guest(),
      database: database,
      localOwners: owners,
      studyPreferences: preferences,
      account: AccountUseCases(
        gateway: _VerifiedGateway(),
        owners: owners,
        upgradeGuestOwner: UpgradeGuestOwner(_UnusedUpgrade()),
      ),
    );
    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 100 && !condition(); i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(condition(), isTrue, reason: 'expected UI state did not appear');
    }

    Future<void> select(String label) async {
      await _tapPanel(tester, label);
    }

    try {
      await tester.pumpWidget(MyApp(dependencies: dependencies));
      await select('เวลาเดินทาง · ฟังประกาศและอ่านป้าย');
      await select('ประมาณ 5 นาทีต่อครั้ง');
      await select('อ่านเรื่องสั้นจากชีวิตประจำวัน');
      await select('บันทึกและเริ่มฝึก');
      await waitFor(
        () => find.byType(CefrArticleReaderScreen).evaluate().isNotEmpty,
      );
      expect(find.text('บทอ่านเริ่มต้น · ที่สถานีรถไฟ'), findsOneWidget);
      expect(find.text('platform'), findsOneWidget);
      expect(find.text('two.'), findsOneWidget);
      final saved = (await tester.runAsync(
        () => preferences.load(ownerId: owner.id),
      ))!;
      expect(saved.onboardingState, OnboardingState.completed);
      expect(saved.purpose, StudyPurpose.travel);
      expect(saved.plannedMinutes, 5);
      expect(saved.method, StudyMethod.reading);
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.pop();
      await waitFor(
        () => find.byType(CefrArticleReaderScreen).evaluate().isEmpty,
      );
      unawaited(
        navigator.pushNamedAndRemoveUntil<void>(
          AppRoute.home.path,
          (_) => false,
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(find.byType(MainNavigationScreen), findsOneWidget);
      expect(find.text('เลือกวิธีฝึกครั้งแรก'), findsNothing);
      final counts = (await tester.runAsync(() async {
        final sessions = await database.select(database.learningSessions).get();
        final answers = await database.select(database.answerAttempts).get();
        return (sessions.length, answers.length);
      }))!;
      expect(counts, (0, 0));
      expect(tester.takeException(), isNull);
    } finally {
      await _closeDatabase(tester, database);
    }
  });

  testWidgets('verified learner can skip first preferences and return home', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 9, 1);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'synthetic-owner',
      nowUtc: () => now,
    );
    final owner = (await tester.runAsync(() async {
      final guest = await owners.getOrCreateActiveOwner();
      return owners.bindFirebaseUid(guest.id, 'synthetic-verified-uid');
    }))!;
    final preferences = DriftStudyPreferencesRepository(
      database,
      nowUtc: () => now,
    );
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.ready,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _Guest(),
      database: database,
      localOwners: owners,
      studyPreferences: preferences,
      account: AccountUseCases(
        gateway: _VerifiedGateway(),
        owners: owners,
        upgradeGuestOwner: UpgradeGuestOwner(_UnusedUpgrade()),
      ),
    );

    Future<void> waitFor(bool Function() condition) async {
      for (var i = 0; i < 100 && !condition(); i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(condition(), isTrue, reason: 'expected UI state did not appear');
    }

    try {
      await tester.pumpWidget(MyApp(dependencies: dependencies));
      await waitFor(
        () => find.text('เลือกวิธีฝึกครั้งแรก').evaluate().isNotEmpty,
      );
      expect(find.byType(MainNavigationScreen), findsOneWidget);
      await _tapPanel(tester, 'ข้ามก่อน');
      await waitFor(() => find.text('เลือกวิธีฝึกครั้งแรก').evaluate().isEmpty);

      final saved = (await tester.runAsync(
        () => preferences.load(ownerId: owner.id),
      ))!;
      expect(saved.onboardingState, OnboardingState.skipped);

      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      unawaited(
        navigator.pushNamedAndRemoveUntil<void>(
          AppRoute.home.path,
          (_) => false,
        ),
      );
      await waitFor(
        () => find.byType(MainNavigationScreen).evaluate().isNotEmpty,
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
      expect(find.text('เลือกวิธีฝึกครั้งแรก'), findsNothing);
      expect(find.text('ข้ามก่อน'), findsNothing);
      final counts = (await tester.runAsync(() async {
        final sessions = await database.select(database.learningSessions).get();
        final answers = await database.select(database.answerAttempts).get();
        return (sessions.length, answers.length);
      }))!;
      expect(counts, (0, 0));
      expect(tester.takeException(), isNull);
    } finally {
      await _closeDatabase(tester, database);
    }
  });
}

Future<void> _tapPanel(WidgetTester tester, String label) async {
  final panel = find.byType(StudyPreferencesPanel);
  final target = find.descendant(of: panel, matching: find.text(label));
  for (var i = 0; i < 100 && target.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(target, findsOneWidget);
  // Complete the sheet's entrance before scrolling within its viewport.
  await tester.pump(const Duration(milliseconds: 400));
  final scroller = find.descendant(
    of: panel,
    matching: find.byType(SingleChildScrollView),
  );
  expect(scroller, findsOneWidget);
  for (var i = 0; i < 12 && target.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(scroller, const Offset(0, -180));
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: '$label must receive taps',
  );
  await tester.tap(target.hitTestable());
  await tester.pump();
}

Future<void> _closeDatabase(WidgetTester tester, AppDatabase database) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  var closed = false;
  Object? closeError;
  database.close().then(
    (_) => closed = true,
    onError: (Object error) {
      closeError = error;
      closed = true;
    },
  );
  for (var i = 0; i < 100 && !closed; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(closed, isTrue, reason: 'database close must finish after unmount');
  expect(closeError, isNull);
}

final class _VerifiedGateway implements AccountGateway {
  @override
  AccountSession get currentSession => const AccountSession(
    uid: 'synthetic-verified-uid',
    email: 'learner@example.test',
    isAnonymous: false,
    emailVerified: true,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('account mutation is unexpected');
}

final class _UnusedUpgrade implements OwnerUpgradeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('owner upgrade is unexpected');
}

final class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('guest startup is unexpected');
}
