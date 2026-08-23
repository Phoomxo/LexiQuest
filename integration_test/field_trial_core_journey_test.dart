import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/screens/associative_reading_launcher_screen.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/screens/quest_status_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/score_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/screens/shop_page.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/vocab_list_screen.dart';
import 'package:vocab_learning_app/screens/export_center_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import 'support/field_trial_external_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'guest completes the production learning loop and keeps evidence on restart',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-field-core-',
      );
      final databasePath =
          '${directory.path}${Platform.pathSeparator}lexiquest.sqlite';
      final entryStatePath =
          '${directory.path}${Platform.pathSeparator}entry-state.txt';
      final entryState = _FileEntryStateStore(entryStatePath);
      final accountGateway = _FakeAccountGateway();
      final guestGateway = _FakeGuestSession(accountGateway);
      final exportStore = _RecordingExportStore(
        '${directory.path}${Platform.pathSeparator}field-export.csv',
      );
      AppDependencies? mountedDependencies;

      try {
        final first = await _bootstrap(
          databasePath,
          entryState: entryState,
          accountGateway: accountGateway,
          guestGateway: guestGateway,
          exportStore: exportStore,
        ).initialize();
        mountedDependencies = first;
        expect(first.initialRoute, AppRoute.login);
        await first.researchConsent!.withdraw();

        await tester.pumpWidget(MyApp(dependencies: first));
        await _pumpUntilFound(tester, find.byType(LoginScreen));
        await tester.tap(find.byKey(const ValueKey('guest-mode-button')));
        await _pumpUntilFound(tester, find.byType(MainNavigationScreen));
        expect(await entryState.read(), AppEntryMode.guest);

        await tester.tap(find.byKey(const ValueKey('add-category')));
        await _pumpUntilFound(
          tester,
          find.byKey(const ValueKey('category-name-field')),
        );
        await tester.enterText(
          find.byKey(const ValueKey('category-name-field')),
          'Field travel',
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('save-category')));
        await _pumpUntilGone(
          tester,
          find.byKey(const ValueKey('category-name-field')),
        );
        await _pumpUntilFound(tester, find.text('Field travel'));
        await tester.tap(find.text('Field travel'));
        await _pumpUntilFound(tester, find.byKey(const ValueKey('add-word')));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.ensureVisible(find.byKey(const ValueKey('add-word')));
        await tester.tap(find.byKey(const ValueKey('add-word')));
        await _pumpUntilFound(tester, find.byKey(const ValueKey('word-field')));
        await tester.enterText(
          find.byKey(const ValueKey('word-field')),
          'station',
        );
        await tester.enterText(
          find.byKey(const ValueKey('meaning-field')),
          'transport stop',
        );
        await tester.enterText(
          find.byKey(const ValueKey('part-of-speech-field')),
          'noun',
        );
        await tester.tap(find.byKey(const ValueKey('save-word')));
        await _pumpUntilFound(tester, find.text('station'));

        Navigator.of(tester.element(find.byType(VocabListScreen))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('home/learn')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('home/learn/quiz')));
        await _pumpUntilFound(tester, find.text('station'));
        await tester.tap(find.text('transport stop'));
        final quizButtons = find.descendant(
          of: find.byType(QuizScreen),
          matching: find.byType(FilledButton),
        );
        await _pumpUntilEnabled(tester, quizButtons.last);
        await tester.tap(quizButtons.last);
        await _pumpUntilFound(tester, find.byType(ScoreScreen));
        await tester.tap(
          find.descendant(
            of: find.byType(ScoreScreen),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        await _pumpUntilFound(
          tester,
          find.byKey(const ValueKey('home/learn/srs')),
        );

        await tester.runAsync(
          () => first.database!.customStatement(
            'UPDATE srs_states SET due_at_utc_ms = 0',
          ),
        );
        await tester.ensureVisible(
          find.byKey(const ValueKey('home/learn/srs')),
        );
        await tester.tap(find.byKey(const ValueKey('home/learn/srs')));
        await _pumpUntilFound(tester, find.byType(SrsFlashcardsScreen));
        await _pumpUntilFound(tester, find.text('station'));
        final cardWord = find.descendant(
          of: find.byType(SrsFlashcardsScreen),
          matching: find.text('station'),
        );
        expect(cardWord, findsOneWidget);
        await tester.tap(cardWord);
        await tester.pump(const Duration(milliseconds: 450));
        await _pumpUntilFound(
          tester,
          find.descendant(
            of: find.byType(SrsFlashcardsScreen),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.tap(
          find
              .descendant(
                of: find.byType(SrsFlashcardsScreen),
                matching: find.byType(FilledButton),
              )
              .last,
        );
        await _pumpUntilGone(tester, find.byType(SrsFlashcardsScreen));
        await tester.drag(find.byType(ListView).first, const Offset(0, 600));
        await tester.pumpAndSettle();
        await _pumpUntilFound(
          tester,
          find.byKey(const ValueKey('home/learn/associative-reading')),
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('home/learn/associative-reading')),
        );
        await tester.tap(
          find.byKey(const ValueKey('home/learn/associative-reading')),
        );
        await _pumpUntilFound(tester, find.text('Start reading'));
        await tester.tap(find.text('Start reading'));
        await _pumpUntilFound(
          tester,
          find.byType(AssociativeReadingSessionScreen),
        );
        final completeAndContinueButton = find.widgetWithText(
          FilledButton,
          'Complete & Continue',
        );
        for (final title in const <String>[
          'Stage 2: Cue Fading',
          'Stage 3: Active Recall',
        ]) {
          await _tapVisibleTop(tester, completeAndContinueButton);
          await _pumpUntilFound(tester, find.text(title));
        }
        await tester.enterText(find.byType(TextField).first, 'station');
        await _tapVisibleTop(tester, completeAndContinueButton);
        await _pumpUntilFound(tester, find.text('Stage 4: Memory Association'));
        await tester.enterText(find.byType(TextField).first, 'train platform');
        await _tapVisibleTop(tester, completeAndContinueButton);
        await _pumpUntilFound(tester, find.text('Stage 5: Context Transfer'));
        await tester.enterText(
          find.byType(TextField).first,
          'Meet me at the station.',
        );
        await _tapVisibleTop(tester, completeAndContinueButton);
        await _pumpUntilFound(tester, find.text('Stage 6: Finish'));
        await _tapVisibleTop(
          tester,
          find.widgetWithText(FilledButton, 'Finish Session'),
        );
        await _pumpUntilFound(tester, find.text('Start reading'));

        await tester.runAsync(first.learningReconciliation!.drain);
        final beforeRestart = await tester.runAsync(first.progress!.load);
        expect(beforeRestart!.sampleSize, greaterThanOrEqualTo(2));
        expect(beforeRestart.completedSessions, greaterThanOrEqualTo(2));
        expect(beforeRestart.totalXp, greaterThan(0));
        expect(beforeRestart.streakDays, greaterThanOrEqualTo(1));
        final categoriesBefore = await first.vocabulary!
            .watchCategories()
            .first;
        final fieldCategoryBefore = categoriesBefore.singleWhere(
          (category) => category.name == 'Field travel',
        );
        final wordsBefore = await first.vocabulary!
            .watchWords(fieldCategoryBefore.id)
            .first;
        expect(wordsBefore.map((word) => word.spelling), contains('station'));
        final srsBefore = await _countRows(
          first.database!,
          'SELECT COUNT(*) AS count FROM srs_states '
          'WHERE last_review_at_utc_ms IS NOT NULL',
        );
        final readingBefore = await _countRows(
          first.database!,
          'SELECT COUNT(*) AS count FROM reading_progress_entries '
          'WHERE is_completed = 1',
        );
        expect(srsBefore, greaterThan(0));
        expect(readingBefore, greaterThan(0));
        final rewardBefore = await first.rewards!.load();
        final questsBefore = await first.quest.getAllInstancesForCurrentOwner();
        expect(questsBefore, isNotEmpty);

        Navigator.of(
          tester.element(find.byType(AssociativeReadingLauncherScreen)),
        ).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('home/mastery')));
        await _pumpUntilFound(tester, find.byType(MasteryDashboardScreen));
        await _pumpUntilFound(
          tester,
          find.descendant(
            of: find.byType(MasteryDashboardScreen),
            matching: find.text('XP'),
          ),
        );
        expect(
          find.descendant(
            of: find.byType(MasteryDashboardScreen),
            matching: find.text('Streak'),
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('home/achievements')));
        await _pumpUntilFound(tester, find.byType(AchievementsScreen));
        await _pumpUntilFound(
          tester,
          find.descendant(
            of: find.byType(AchievementsScreen),
            matching: find.byType(ListTile),
          ),
        );
        await tester.tap(find.byKey(const ValueKey('home/profile')));
        await _pumpUntilFound(tester, find.byType(ProfileSettingsScreen));
        await _pumpUntilFound(
          tester,
          find.descendant(
            of: find.byType(ProfileSettingsScreen),
            matching: find.text('Streak'),
          ),
        );
        await _openDrawer(tester);
        await _scrollDrawerTo(
          tester,
          find.byKey(const ValueKey('drawer/rewards/shop')),
        );
        await tester.tap(find.byKey(const ValueKey('drawer/rewards/shop')));
        await _pumpUntilFound(tester, find.byType(ShopPage));
        await _pumpUntilGone(
          tester,
          find.descendant(
            of: find.byType(ShopPage),
            matching: find.byType(CircularProgressIndicator),
          ),
        );
        expect(
          find.descendant(
            of: find.byType(ShopPage),
            matching: find.text('${rewardBefore.balance}'),
          ),
          findsOneWidget,
        );
        await tester.pageBack();
        await _pumpUntilGone(tester, find.byType(ShopPage));
        await _openDrawer(tester);
        await _scrollDrawerTo(
          tester,
          find.byKey(const ValueKey('drawer/rewards/quests')),
        );
        await tester.tap(find.byKey(const ValueKey('drawer/rewards/quests')));
        await _pumpUntilFound(tester, find.byType(QuestStatusScreen));
        await _pumpUntilGone(tester, find.byType(QuestStatusLoading));
        expect(find.byType(QuestStatusEmpty), findsNothing);
        expect(find.byType(QuestStatusFailure), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(first.dispose);
        mountedDependencies = null;

        final reopenedEntryState = _FileEntryStateStore(entryStatePath);
        final reopened = await _bootstrap(
          databasePath,
          entryState: reopenedEntryState,
          accountGateway: accountGateway,
          guestGateway: guestGateway,
          exportStore: exportStore,
        ).initialize();
        mountedDependencies = reopened;
        expect(reopened.initialRoute, AppRoute.home);
        final afterRestart = await reopened.progress!.load();
        expect(afterRestart.sampleSize, beforeRestart.sampleSize);
        expect(afterRestart.completedSessions, beforeRestart.completedSessions);
        expect(afterRestart.totalXp, beforeRestart.totalXp);
        expect(afterRestart.streakDays, beforeRestart.streakDays);
        final categoriesAfter = await reopened.vocabulary!
            .watchCategories()
            .first;
        final fieldCategoryAfter = categoriesAfter.singleWhere(
          (category) => category.name == 'Field travel',
        );
        final wordsAfter = await reopened.vocabulary!
            .watchWords(fieldCategoryAfter.id)
            .first;
        expect(wordsAfter.map((word) => word.spelling), contains('station'));
        expect(
          await _countRows(
            reopened.database!,
            'SELECT COUNT(*) AS count FROM srs_states '
            'WHERE last_review_at_utc_ms IS NOT NULL',
          ),
          srsBefore,
        );
        expect(
          await _countRows(
            reopened.database!,
            'SELECT COUNT(*) AS count FROM reading_progress_entries '
            'WHERE is_completed = 1',
          ),
          readingBefore,
        );
        final rewardAfter = await reopened.rewards!.load();
        expect(rewardAfter.balance, rewardBefore.balance);
        expect(rewardAfter.transactionCount, rewardBefore.transactionCount);
        final questsAfter = await reopened.quest
            .getAllInstancesForCurrentOwner();
        expect(questsAfter.length, questsBefore.length);

        await tester.pumpWidget(MyApp(dependencies: reopened));
        await _pumpUntilFound(tester, find.byType(MainNavigationScreen));
        expect(find.byType(CategoriesPage), findsOneWidget);
        await _pumpUntilFound(tester, find.text('Field travel'));
        await tester.tap(find.text('Field travel'));
        await _pumpUntilFound(tester, find.text('station'));
        await tester.pageBack();
        await _pumpUntilFound(tester, find.byType(CategoriesPage));
        await _openDrawer(tester);
        await _scrollDrawerTo(
          tester,
          find.byKey(const ValueKey('drawer/export/center')),
        );
        await tester.tap(find.byKey(const ValueKey('drawer/export/center')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, 'สร้างและบันทึกไฟล์'),
        );
        await _pumpUntilFound(
          tester,
          find.byKey(const ValueKey('export-status')),
        );
        await _pumpUntil(
          tester,
          () => exportStore.artifact != null,
          description: 'owner export artifact save',
        );
        expect(exportStore.artifact, isNotNull);
        expect(exportStore.artifact!.recordCount, greaterThan(0));
        expect(utf8.decode(exportStore.artifact!.bytes), contains('station'));

        await tester.pageBack();
        await _pumpUntilGone(tester, find.byType(ExportCenterScreen));
        await _openDrawer(tester);
        await _scrollDrawerTo(tester, find.text('ตั้งค่า'));
        await tester.tap(find.text('ตั้งค่า'));
        await _pumpUntilFound(tester, find.byType(SettingScreen));
        await tester.tap(find.text('ออกจากระบบ'));
        await _pumpUntilFound(tester, find.byType(LoginScreen));
        expect(accountGateway.signOutCalls, 1);
        expect(await reopenedEntryState.read(), AppEntryMode.signedOut);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (mountedDependencies case final dependencies?) {
          await tester.runAsync(dependencies.dispose);
        }
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

AppBootstrap _bootstrap(
  String databasePath, {
  required _FileEntryStateStore entryState,
  required _FakeAccountGateway accountGateway,
  required _FakeGuestSession guestGateway,
  required ExportArtifactStore exportStore,
}) => AppBootstrap(
  initializeFirebase: () async {},
  initializeSupabase: () async => throw StateError('supabase unavailable'),
  loadConfig: () => throw StateError('backend config unavailable'),
  guestSessionService: guestGateway,
  createDatabase: () => AppDatabase(NativeDatabase(File(databasePath))),
  createEntryStateStore: () async => entryState,
  bindGuestOwnership: true,
  learningTimezoneId: () => 'Asia/Bangkok',
  accountGatewayFactory: () => accountGateway,
  exportStoreFactory: () => exportStore,
  cameraGatewayFactory: HostFakeCameraGateway.new,
  speechRecognitionGatewayFactory: HostFakeSpeechRecognitionGateway.new,
  buildAiTutor: (_) => throw StateError('host fake: AI unavailable'),
  buildVoice: (_) => throw StateError('host fake: voice unavailable'),
);

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 250,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  final visibleText = tester
      .widgetList<Text>(find.byType(Text))
      .map((widget) => widget.data)
      .whereType<String>()
      .where((value) => value.isNotEmpty)
      .take(20)
      .join(' | ');
  fail(
    'Widget did not appear after $maxPumps bounded pumps: $finder. '
    'Visible text: $visibleText',
  );
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 250,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Widget remained after $maxPumps bounded pumps: $finder');
}

Future<void> _pumpUntilEnabled(WidgetTester tester, Finder finder) async {
  for (var index = 0; index < 250; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty &&
        tester.widget<FilledButton>(finder).onPressed != null) {
      return;
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Button did not enable after bounded pumps: $finder');
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  required String description,
}) async {
  for (var index = 0; index < 250; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (predicate()) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('$description did not complete after bounded pumps');
}

Future<int> _countRows(AppDatabase database, String sql) async {
  final row = await database.customSelect(sql).getSingle();
  return row.read<int>('count');
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('legacy-drawer-button')));
  await tester.pumpAndSettle();
  expect(find.byType(Drawer), findsOneWidget);
}

Future<void> _scrollDrawerTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    ),
  );
}

Future<void> _tapVisibleTop(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pump(const Duration(milliseconds: 20));
  final rect = tester.getRect(target);
  // The retained production shell can cover the bottom edge during a bounded
  // host frame; use a real hit-tested point near the visible top of the button.
  await tester.tapAt(Offset(rect.center.dx, rect.top + 8));
}

final class _FileEntryStateStore implements AppEntryStateStore {
  _FileEntryStateStore(this.path);

  final String path;

  @override
  Future<void> clear() => File(path).writeAsString('signedOut', flush: true);

  @override
  Future<void> markGuest() => File(path).writeAsString('guest', flush: true);

  @override
  Future<AppEntryMode> read() async {
    final file = File(path);
    if (!await file.exists()) return AppEntryMode.signedOut;
    return (await file.readAsString()).trim() == 'guest'
        ? AppEntryMode.guest
        : AppEntryMode.signedOut;
  }
}

final class _FakeGuestSession implements GuestSessionService {
  _FakeGuestSession(this.accounts);

  final _FakeAccountGateway accounts;

  @override
  Future<GuestSessionResult> start() async {
    accounts.session = const AccountSession(
      uid: 'field-guest-owner',
      email: 'field@example.test',
      isAnonymous: false,
      emailVerified: true,
    );
    return const GuestSessionStarted(uid: 'field-guest-owner');
  }
}

final class _FakeAccountGateway implements AccountGateway {
  AccountSession? session;
  int signOutCalls = 0;

  @override
  AccountSession? get currentSession => session;

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    session = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RecordingExportStore implements ExportArtifactStore {
  _RecordingExportStore(this.path);

  final String path;
  ExportArtifact? artifact;

  @override
  Future<ExportSaveResult> save(
    ExportArtifact value, {
    required ExportCancellation cancellation,
  }) async {
    cancellation.throwIfCancelled();
    artifact = value;
    return ExportSaveResult(path: path, bytesWritten: value.bytes.length);
  }
}
