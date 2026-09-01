import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/learning/presentation/session_configuration_sheet.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/screens/associative_reading_launcher_screen.dart';
import 'package:vocab_learning_app/screens/associative_reading_session_screen.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
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

final class _JourneyPhaseTrace {
  String _current = 'not-started';
  String _lastCompleted = 'none';
  var _transitionCount = 0;
  var _cleanupStarted = false;

  void begin(String phase) {
    _current = phase;
    _transitionCount++;
    debugPrintSynchronously(
      '[DNP-NX9] phase-start=$_current '
      'last-completed=$_lastCompleted transition=$_transitionCount',
    );
  }

  void complete(String phase) {
    if (_current != phase) {
      debugPrintSynchronously(
        '[DNP-NX9] phase-mismatch current=$_current completed=$phase',
      );
    }
    _lastCompleted = phase;
    _current = 'between-phases';
    _transitionCount++;
    debugPrintSynchronously(
      '[DNP-NX9] phase-complete=$phase transition=$_transitionCount',
    );
  }

  void markCleanupStarted() {
    _cleanupStarted = true;
    debugPrintSynchronously(
      '[DNP-NX9] cleanup-started current=$_current '
      'last-completed=$_lastCompleted',
    );
  }

  void reportFinal() {
    debugPrintSynchronously(
      '[DNP-NX9] final current=$_current last-completed=$_lastCompleted '
      'cleanup-started=$_cleanupStarted transitions=$_transitionCount',
    );
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'guest completes the production learning loop and keeps evidence on restart',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final phaseTrace = _JourneyPhaseTrace();
      addTearDown(phaseTrace.reportFinal);
      phaseTrace.begin('01-fixture-setup');
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
      phaseTrace.complete('01-fixture-setup');

      try {
        phaseTrace.begin('02-bootstrap');
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
        phaseTrace.complete('02-bootstrap');

        phaseTrace.begin('03-guest-login');
        await tester.pumpWidget(MyApp(dependencies: first));
        await _pumpUntilFound(tester, find.byType(LoginScreen));
        await tester.tap(find.byKey(const ValueKey('guest-mode-button')));
        await _pumpUntilFound(tester, find.byType(MainNavigationScreen));
        expect(await entryState.read(), AppEntryMode.guest);
        phaseTrace.complete('03-guest-login');

        phaseTrace.begin('04-vocabulary-create');
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
        phaseTrace.complete('04-vocabulary-create');

        phaseTrace.begin('05-quiz');
        Navigator.of(tester.element(find.byType(VocabListScreen))).pop();
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('home/learn')));
        await tester.pumpAndSettle();
        await _openConfiguredMode(tester, 'home/learn/quiz');
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
        final afterRecognition = await _readSrsVocabularyInventory(
          tester,
          first.database!,
        );
        _expectStationWithoutSrs(afterRecognition);
        phaseTrace.complete('05-quiz');

        phaseTrace.begin('06-associative-launch-to-stage-3');
        await _openConfiguredMode(tester, 'home/learn/associative-reading');
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
          await _tapVisibleCenter(tester, completeAndContinueButton);
          await _pumpUntilFound(tester, find.text(title));
        }
        phaseTrace.complete('06-associative-launch-to-stage-3');

        phaseTrace.begin('07-associative-stage-3-recall');
        await _enterAssociativeStageText(
          tester,
          hintText: 'Type from memory',
          value: 'station',
        );
        await _tapAssociativeContinue(tester);
        await _pumpUntilFound(tester, find.text('Stage 4: Memory Association'));
        phaseTrace.complete('07-associative-stage-3-recall');

        phaseTrace.begin('08-associative-stage-4-association');
        await _enterAssociativeStageText(
          tester,
          hintText: 'Keyword, story, or image...',
          value: 'train platform',
        );
        await _tapAssociativeContinue(tester);
        await _pumpUntilAssociativeStage4Outcome(tester);
        phaseTrace.complete('08-associative-stage-4-association');

        phaseTrace.begin('09-associative-stage-5-transfer');
        await _enterAssociativeStageText(
          tester,
          hintText: 'Enter a new sentence',
          value: 'Meet me at the station.',
        );
        await _tapAssociativeContinue(tester);
        await _pumpUntilFound(tester, find.text('Stage 6: Finish'));
        phaseTrace.complete('09-associative-stage-5-transfer');

        phaseTrace.begin('10-associative-finish');
        await _tapAssociativeFinish(tester);
        await _pumpUntilAssociativeFinishOutcome(tester);

        final afterAssociativeRecall = await _readSrsVocabularyInventory(
          tester,
          first.database!,
        );
        final srsIdentity = _expectStationWithSrs(afterAssociativeRecall);
        Navigator.of(
          tester.element(find.byType(AssociativeReadingLauncherScreen)),
        ).pop();
        await tester.pumpAndSettle();
        phaseTrace.complete('10-associative-finish');

        phaseTrace.begin('11-srs-due-and-review');
        await tester.runAsync(
          () => first.database!.customStatement(
            'UPDATE srs_states SET due_at_utc_ms = 0 '
            'WHERE owner_id = ? AND word_id = ?',
            <Object>[srsIdentity.ownerId, srsIdentity.wordId],
          ),
        );
        final dueInventory = await _readSrsVocabularyInventory(
          tester,
          first.database!,
        );
        final dueSrs = _expectStationWithSrs(dueInventory);
        expect(dueSrs.dueAtUtcMs, 0, reason: dueSrs.diagnostic);

        await _openConfiguredMode(tester, 'home/learn/srs');
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
        phaseTrace.complete('11-srs-due-and-review');

        phaseTrace.begin('12-progress-and-reward-snapshot');
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
        phaseTrace.complete('12-progress-and-reward-snapshot');

        phaseTrace.begin('13-mastery');
        await tester.tap(find.byKey(const ValueKey('home/mastery')));
        await _pumpUntilFound(tester, find.byType(MasteryDashboardScreen));
        final masteryDashboard = find.byType(MasteryDashboardScreen);
        final masteryScrollable = find.descendant(
          of: masteryDashboard,
          matching: find.byType(Scrollable),
        );
        expect(masteryScrollable, findsOneWidget);
        await tester.scrollUntilVisible(
          find.descendant(
            of: masteryDashboard,
            matching: find.text('Engagement'),
          ),
          240,
          scrollable: masteryScrollable,
        );
        await tester.pump();
        expect(
          find.descendant(of: masteryDashboard, matching: find.text('XP')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: masteryDashboard, matching: find.text('Streak')),
          findsOneWidget,
        );
        phaseTrace.complete('13-mastery');

        phaseTrace.begin('14-achievements');
        await tester.tap(find.byKey(const ValueKey('home/achievements')));
        await _pumpUntilFound(tester, find.byType(AchievementsScreen));
        await _pumpUntilFound(
          tester,
          find.descendant(
            of: find.byType(AchievementsScreen),
            matching: find.byType(ListTile),
          ),
        );
        phaseTrace.complete('14-achievements');

        phaseTrace.begin('15-profile');
        await tester.tap(find.byKey(const ValueKey('home/profile')));
        await _pumpUntilFound(tester, find.byType(ProfileSettingsScreen));
        final profileSettings = find.byType(ProfileSettingsScreen);
        final profileScrollable = find.descendant(
          of: profileSettings,
          matching: find.byType(Scrollable),
        );
        expect(profileScrollable, findsOneWidget);
        await tester.scrollUntilVisible(
          find.descendant(
            of: profileSettings,
            matching: find.text('Engagement'),
          ),
          240,
          scrollable: profileScrollable,
        );
        await tester.pump();
        expect(
          find.descendant(
            of: profileSettings,
            matching: find.text('Engagement'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: profileSettings,
            matching: find.text(
              '${beforeRestart.totalXp} XP · '
              'Streak ${beforeRestart.streakDays} วัน',
            ),
          ),
          findsOneWidget,
        );
        phaseTrace.complete('15-profile');

        phaseTrace.begin('16-shop');
        await _openDrawer(tester);
        final shopEntry = find.byKey(const ValueKey('drawer/rewards/shop'));
        await _scrollDrawerTo(tester, shopEntry);
        await _tapVisibleCenter(tester, shopEntry);
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
        phaseTrace.complete('16-shop');

        phaseTrace.begin('17-quest');
        await _openDrawer(tester);
        final questEntry = find.byKey(const ValueKey('drawer/rewards/quests'));
        await _scrollDrawerTo(tester, questEntry);
        await _tapVisibleCenter(tester, questEntry);
        await _pumpUntilFound(tester, find.byType(QuestStatusScreen));
        await _pumpUntilGone(tester, find.byType(QuestStatusLoading));
        expect(find.byType(QuestStatusEmpty), findsNothing);
        expect(find.byType(QuestStatusFailure), findsNothing);
        phaseTrace.complete('17-quest');

        phaseTrace.begin('18-dispose-before-reopen');
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(first.dispose);
        mountedDependencies = null;
        phaseTrace.complete('18-dispose-before-reopen');

        phaseTrace.begin('19-reopen-bootstrap');
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
        phaseTrace.complete('19-reopen-bootstrap');

        phaseTrace.begin('20-reopen-state-validation');
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
        phaseTrace.complete('20-reopen-state-validation');

        phaseTrace.begin('21-reopen-ui');
        await tester.pumpWidget(MyApp(dependencies: reopened));
        await _pumpUntilFound(tester, find.byType(MainNavigationScreen));
        expect(find.byType(CategoriesPage), findsOneWidget);
        await _pumpUntilFound(tester, find.text('Field travel'));
        await tester.tap(find.text('Field travel'));
        await _pumpUntilFound(tester, find.text('station'));
        await tester.pageBack();
        await _pumpUntilFound(tester, find.byType(CategoriesPage));
        phaseTrace.complete('21-reopen-ui');

        phaseTrace.begin('22-export');
        await _openDrawer(tester);
        final exportEntry = find.byKey(const ValueKey('drawer/export/center'));
        await _scrollDrawerTo(tester, exportEntry);
        await _tapVisibleCenter(tester, exportEntry);
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
        phaseTrace.complete('22-export');

        phaseTrace.begin('23-sign-out');
        await tester.pageBack();
        await _pumpUntilGone(tester, find.byType(ExportCenterScreen));
        await _openDrawer(tester);
        final settingsEntry = find.byKey(
          const ValueKey<String>('drawer/settings'),
        );
        await _scrollDrawerTo(tester, settingsEntry);
        await _tapVisibleCenter(tester, settingsEntry);
        await _pumpUntilFound(tester, find.byType(SettingScreen));
        await tester.tap(find.text('ออกจากระบบ'));
        await _pumpUntilFound(tester, find.byType(LoginScreen));
        expect(accountGateway.signOutCalls, 1);
        expect(await reopenedEntryState.read(), AppEntryMode.signedOut);
        phaseTrace.complete('23-sign-out');
      } finally {
        phaseTrace.markCleanupStarted();
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

typedef _SrsVocabularyInventory = ({
  List<Map<String, Object?>> activeOwners,
  List<Map<String, Object?>> vocabularyRows,
});

typedef _StationSrsState = ({
  String ownerId,
  String wordId,
  String? srsId,
  String? srsOwnerId,
  String? srsWordId,
  int? dueAtUtcMs,
  String diagnostic,
});

Future<_SrsVocabularyInventory> _readSrsVocabularyInventory(
  WidgetTester tester,
  AppDatabase database,
) async => (await tester.runAsync<_SrsVocabularyInventory>(() async {
  final activeOwners = await database.customSelect('''
        SELECT id, firebase_uid, account_state, is_active
        FROM local_owners
        WHERE is_active = 1
        ORDER BY id
      ''').get();
  final vocabularyRows = await database.customSelect('''
        SELECT
          w.id AS word_id,
          w.owner_id AS word_owner_id,
          w.spelling AS spelling,
          w.is_deleted AS is_deleted,
          s.id AS srs_id,
          s.owner_id AS srs_owner_id,
          s.word_id AS srs_word_id,
          s.due_at_utc_ms AS due_at_utc_ms
        FROM vocabulary_words AS w
        LEFT JOIN srs_states AS s ON s.word_id = w.id
        ORDER BY w.id, s.id
      ''').get();
  return (
    activeOwners: activeOwners
        .map(
          (row) => <String, Object?>{
            'id': row.read<String>('id'),
            'firebaseUid': row.readNullable<String>('firebase_uid'),
            'accountState': row.read<String>('account_state'),
            'isActive': row.read<int>('is_active'),
          },
        )
        .toList(growable: false),
    vocabularyRows: vocabularyRows
        .map(
          (row) => <String, Object?>{
            'wordId': row.read<String>('word_id'),
            'wordOwnerId': row.read<String>('word_owner_id'),
            'spelling': row.read<String>('spelling'),
            'isDeleted': row.read<int>('is_deleted'),
            'srsId': row.readNullable<String>('srs_id'),
            'srsOwnerId': row.readNullable<String>('srs_owner_id'),
            'srsWordId': row.readNullable<String>('srs_word_id'),
            'dueAtUtcMs': row.readNullable<int>('due_at_utc_ms'),
          },
        )
        .toList(growable: false),
  );
}))!;

_StationSrsState _expectStationInventory(_SrsVocabularyInventory inventory) {
  final diagnostic =
      'active=${inventory.activeOwners}, '
      'vocabulary=${inventory.vocabularyRows}';
  expect(inventory.activeOwners, hasLength(1), reason: diagnostic);
  expect(inventory.vocabularyRows, hasLength(1), reason: diagnostic);
  final activeOwner = inventory.activeOwners.single;
  final station = inventory.vocabularyRows.single;
  expect(activeOwner['isActive'], 1, reason: diagnostic);
  expect(station['spelling'], 'station', reason: diagnostic);
  expect(station['wordOwnerId'], activeOwner['id'], reason: diagnostic);
  expect(station['isDeleted'], 0, reason: diagnostic);
  return (
    ownerId: activeOwner['id']! as String,
    wordId: station['wordId']! as String,
    srsId: station['srsId'] as String?,
    srsOwnerId: station['srsOwnerId'] as String?,
    srsWordId: station['srsWordId'] as String?,
    dueAtUtcMs: station['dueAtUtcMs'] as int?,
    diagnostic: diagnostic,
  );
}

void _expectStationWithoutSrs(_SrsVocabularyInventory inventory) {
  final station = _expectStationInventory(inventory);
  expect(station.srsId, isNull, reason: station.diagnostic);
  expect(station.srsOwnerId, isNull, reason: station.diagnostic);
  expect(station.srsWordId, isNull, reason: station.diagnostic);
  expect(station.dueAtUtcMs, isNull, reason: station.diagnostic);
}

_StationSrsState _expectStationWithSrs(_SrsVocabularyInventory inventory) {
  final station = _expectStationInventory(inventory);
  expect(station.srsId, isNotNull, reason: station.diagnostic);
  expect(station.srsOwnerId, station.ownerId, reason: station.diagnostic);
  expect(station.srsWordId, station.wordId, reason: station.diagnostic);
  expect(station.dueAtUtcMs, isNotNull, reason: station.diagnostic);
  return station;
}

Future<void> _openConfiguredMode(WidgetTester tester, String entryKey) async {
  await _dismissPhysicalIme(tester);
  final chooseMode = find.byType(ChooseModeScreen);
  await _pumpUntilFound(tester, chooseMode);
  expect(chooseMode, findsOneWidget);
  final entry = find.descendant(
    of: chooseMode,
    matching: find.byKey(ValueKey<String>(entryKey)),
  );
  final scrollable = find.descendant(
    of: chooseMode,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  final scrollPosition = tester.state<ScrollableState>(scrollable).position;
  await _pumpUntilScrollableHasViewport(
    tester,
    scrollPosition,
    description: 'ChooseModeScreen mode list',
  );
  scrollPosition.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(entry, 240, scrollable: scrollable);
  await tester.pump();
  await tester.ensureVisible(entry);
  await tester.tap(entry);

  final sheet = find.byKey(const ValueKey('session-configuration-sheet'));
  await _pumpUntilFound(tester, sheet);
  expect(sheet, findsOneWidget);
  expect(find.byType(SessionConfigurationSheet), findsOneWidget);
  final itemCount = find.byKey(const ValueKey('session-item-count'));
  await _pumpUntilFound(tester, itemCount);
  await tester.enterText(itemCount, '1');
  await _dismissPhysicalIme(tester);

  final start = find.byKey(const ValueKey('session-config-start'));
  await _pumpUntilFound(tester, start);
  await tester.ensureVisible(start);
  await tester.tap(start);
  await tester.pump();
}

Future<void> _dismissPhysicalIme(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  Object? hideRequestError;
  unawaited(() async {
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (error) {
      hideRequestError = error;
    }
  }());
  var lastPhysicalBottomInset = tester.view.viewInsets.bottom;
  for (var index = 0; index < 250; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    lastPhysicalBottomInset = tester.view.viewInsets.bottom;
    if (lastPhysicalBottomInset == 0) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  final devicePixelRatio = tester.view.devicePixelRatio;
  final physicalSize = tester.view.physicalSize;
  final logicalSize = Size(
    physicalSize.width / devicePixelRatio,
    physicalSize.height / devicePixelRatio,
  );
  fail(
    'Physical IME did not close after the bounded view-inset wait. '
    'physicalBottomInset=$lastPhysicalBottomInset, '
    'logicalBottomInset=${lastPhysicalBottomInset / devicePixelRatio}, '
    'physicalSize=$physicalSize, '
    'logicalSize=$logicalSize, '
    'hideRequestError=$hideRequestError.',
  );
}

Future<void> _pumpUntilScrollableHasViewport(
  WidgetTester tester,
  ScrollPosition position, {
  required String description,
}) async {
  var lastViewportDimension = position.hasViewportDimension
      ? position.viewportDimension
      : 0.0;
  for (var index = 0; index < 250; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    lastViewportDimension = position.hasViewportDimension
        ? position.viewportDimension
        : 0.0;
    if (lastViewportDimension > 0) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  final extents = position.hasContentDimensions
      ? '[${position.minScrollExtent}, ${position.maxScrollExtent}]'
      : '<unavailable>';
  fail(
    '$description retained a zero viewport after physical IME dismissal. '
    'viewportDimension=$lastViewportDimension, '
    'pixels=${position.hasPixels ? position.pixels : '<unavailable>'}, '
    'scrollExtents=$extents, '
    'physicalBottomInset=${tester.view.viewInsets.bottom}.',
  );
}

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
  final drawer = find.byType(Drawer);
  expect(drawer, findsOneWidget);
  final scrollable = find.descendant(
    of: drawer,
    matching: find.byType(Scrollable),
  );
  expect(scrollable, findsOneWidget);
  final position = tester.state<ScrollableState>(scrollable).position;
  if (position.hasContentDimensions &&
      position.pixels != position.minScrollExtent) {
    position.jumpTo(position.minScrollExtent);
  }

  for (var index = 0; index < 50; index++) {
    await tester.pump();
    final targetCount = target.evaluate().length;
    if (targetCount == 1) return;
    if (targetCount > 1) {
      fail('Drawer target is ambiguous: $target');
    }
    if (!position.hasContentDimensions) continue;
    final nextPixels = (position.pixels + 180)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (nextPixels == position.pixels) break;
    position.jumpTo(nextPixels);
  }

  final maxScrollExtent = position.hasContentDimensions
      ? position.maxScrollExtent
      : '<unavailable>';
  fail(
    'Drawer target did not materialize during the bounded lazy-list scroll. '
    'target=$target, pixels=${position.pixels}, '
    'maxScrollExtent=$maxScrollExtent.',
  );
}

Future<void> _tapVisibleCenter(WidgetTester tester, Finder target) async {
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  final scrollableAncestors = find.ancestor(
    of: target,
    matching: find.byType(Scrollable),
  );
  final ancestorCount = scrollableAncestors.evaluate().length;
  if (ancestorCount != 1) {
    fail(
      'Expected one scrollable ancestor for the visible action, '
      'found $ancestorCount. targetRect=${tester.getRect(target)}.',
    );
  }
  final scrollPosition = tester
      .state<ScrollableState>(scrollableAncestors)
      .position;
  final targetRenderObject = tester.renderObject(target);
  await _pumpUntilTargetCenterIsHitTestable(
    tester,
    target,
    scrollPosition: scrollPosition,
    targetRenderObject: targetRenderObject,
    scrollableAncestorCount: ancestorCount,
  );
  await tester.tap(target);
}

Future<void> _pumpUntilTargetCenterIsHitTestable(
  WidgetTester tester,
  Finder target, {
  required ScrollPosition scrollPosition,
  required Object targetRenderObject,
  required int scrollableAncestorCount,
}) async {
  final physicalSize = tester.view.physicalSize;
  final devicePixelRatio = tester.view.devicePixelRatio;
  final viewport =
      Offset.zero &
      Size(
        physicalSize.width / devicePixelRatio,
        physicalSize.height / devicePixelRatio,
      );
  Rect? lastRect;
  var lastHitTargetTypes = const <String>[];
  for (var index = 0; index < 250; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    final rect = tester.getRect(target);
    lastRect = rect;
    final center = rect.center;
    final hitPath = viewport.contains(center)
        ? tester.hitTestOnBinding(center).path
        : null;
    lastHitTargetTypes =
        hitPath
            ?.map((entry) => entry.target.runtimeType.toString())
            .toSet()
            .take(8)
            .toList(growable: false) ??
        const <String>[];
    if (hitPath != null &&
        hitPath.any((entry) => identical(entry.target, targetRenderObject))) {
      return;
    }
    final desiredPixels =
        (scrollPosition.pixels + (center.dy - viewport.center.dy))
            .clamp(
              scrollPosition.minScrollExtent,
              scrollPosition.maxScrollExtent,
            )
            .toDouble();
    if ((desiredPixels - scrollPosition.pixels).abs() > 0.01) {
      scrollPosition.jumpTo(desiredPixels);
      await tester.pump();
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail(
    'Target center did not become hit-testable within the bounded viewport '
    'wait. scrollableAncestorCount=$scrollableAncestorCount, '
    'targetRect=$lastRect, viewport=$viewport, '
    'scrollPixels=${scrollPosition.pixels}, '
    'scrollExtents=[${scrollPosition.minScrollExtent}, '
    '${scrollPosition.maxScrollExtent}], '
    'hitTargets=$lastHitTargetTypes.',
  );
}

Finder _associativeStageTextField(String hintText) => find.descendant(
  of: find.byType(AssociativeReadingSessionScreen),
  matching: find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.hintText == hintText,
    description: 'associative reading text field with hint "$hintText"',
  ),
);

TextEditingController _effectiveTextController(
  WidgetTester tester,
  Finder field,
) {
  final explicitController = tester.widget<TextField>(field).controller;
  if (explicitController != null) return explicitController;
  final editable = find.descendant(
    of: field,
    matching: find.byType(EditableText),
  );
  expect(editable, findsOneWidget);
  return tester.widget<EditableText>(editable).controller;
}

Future<void> _enterAssociativeStageText(
  WidgetTester tester, {
  required String hintText,
  required String value,
}) async {
  final field = _associativeStageTextField(hintText);
  expect(field, findsOneWidget);
  await tester.enterText(field, value);
  expect(_effectiveTextController(tester, field).text, value);
}

Finder _associativeContinueButton() => find.descendant(
  of: find.byType(AssociativeReadingSessionScreen),
  matching: find.widgetWithText(FilledButton, 'Complete & Continue'),
);

Future<void> _tapAssociativeContinue(WidgetTester tester) async {
  await _dismissPhysicalIme(tester);
  final button = _associativeContinueButton();
  expect(button, findsOneWidget);
  expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  await _tapVisibleCenter(tester, button);
}

Finder _associativeFinishButton() => find.descendant(
  of: find.byType(AssociativeReadingSessionScreen),
  matching: find.widgetWithText(FilledButton, 'Finish Session'),
);

Future<void> _tapAssociativeFinish(WidgetTester tester) async {
  await _dismissPhysicalIme(tester);
  final button = _associativeFinishButton();
  expect(button, findsOneWidget);
  expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  await _tapVisibleCenter(tester, button);
}

Future<void> _pumpUntilAssociativeStage4Outcome(WidgetTester tester) async {
  final stageFive = find.text('Stage 5: Context Transfer');
  final associationRetry = find.byKey(
    const ValueKey<String>('current-association-retry'),
  );
  final checkpointRetry = find.byKey(
    const ValueKey<String>('current-reading-checkpoint-retry'),
  );
  const cueRequired =
      'Create a memory cue for every target word before '
      'continuing.';
  const associationSaveFailed =
      'Could not save the memory association. Try again.';

  for (var index = 0; index < 250; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (stageFive.evaluate().isNotEmpty) return;

    final failure = switch ((
      associationRetry.evaluate().isNotEmpty,
      checkpointRetry.evaluate().isNotEmpty,
      find.text(cueRequired).evaluate().isNotEmpty,
      find.text(associationSaveFailed).evaluate().isNotEmpty,
    )) {
      (true, _, _, _) => 'association retry is required',
      (_, true, _, _) => 'reading checkpoint retry is required',
      (_, _, true, _) => 'the Stage 4 cue was rejected as empty',
      (_, _, _, true) => 'the Stage 4 association save failed',
      _ => null,
    };
    if (failure != null) {
      fail(_associativeStage4Diagnostic(tester, failure));
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail(_associativeStage4Diagnostic(tester, 'timed out without an outcome'));
}

Future<void> _pumpUntilAssociativeFinishOutcome(WidgetTester tester) async {
  final launcherStart = find.descendant(
    of: find.byType(AssociativeReadingLauncherScreen),
    matching: find.widgetWithText(FilledButton, 'Start reading'),
  );
  final closeRetry = find.byKey(
    const ValueKey<String>('current-session-close-retry'),
  );
  final progressRetry = find.byKey(
    const ValueKey<String>('current-reading-progress-retry'),
  );
  const sessionCloseFailed =
      'Could not finish the learning session. Try again.';
  const progressSaveFailed = 'บันทึกตำแหน่งอ่านไม่สำเร็จ กรุณาลองอีกครั้ง';

  for (var index = 0; index < 250; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (launcherStart.evaluate().isNotEmpty) return;

    final failure = switch ((
      closeRetry.evaluate().isNotEmpty,
      progressRetry.evaluate().isNotEmpty,
      find.text(sessionCloseFailed).evaluate().isNotEmpty,
      find.text(progressSaveFailed).evaluate().isNotEmpty,
    )) {
      (true, _, _, _) => 'session-close retry is required',
      (_, true, _, _) => 'completion-progress retry is required',
      (_, _, true, _) => 'the learning-session close failed',
      (_, _, _, true) => 'completion-progress save failed',
      _ => null,
    };
    if (failure != null) {
      fail(_associativeFinishDiagnostic(tester, failure));
    }

    final action = _associativeCurrentAction(tester);
    if (action.label != '<missing or ambiguous>' &&
        action.label != 'Finish Session') {
      fail(
        _associativeFinishDiagnostic(
          tester,
          'unexpected Stage 6 action label "${action.label}"',
        ),
      );
    }
    if (action.label == 'Finish Session' && action.enabled == true) {
      fail(
        _associativeFinishDiagnostic(
          tester,
          'Finish Session remained enabled after the physical tap',
        ),
      );
    }
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail(_associativeFinishDiagnostic(tester, 'timed out without an outcome'));
}

String _associativeStage4Diagnostic(WidgetTester tester, String outcome) {
  final action = _associativeCurrentAction(tester);
  return 'Stage 4 did not advance: $outcome. '
      'action="${action.label}", enabled=${action.enabled}, '
      'progressIndicators=${action.progressCount}.';
}

String _associativeFinishDiagnostic(WidgetTester tester, String outcome) {
  final action = _associativeCurrentAction(tester);
  return 'Stage 6 did not finish: $outcome. '
      'action="${action.label}", enabled=${action.enabled}, '
      'progressIndicators=${action.progressCount}.';
}

({String label, bool? enabled, int progressCount}) _associativeCurrentAction(
  WidgetTester tester,
) {
  final session = find.byType(AssociativeReadingSessionScreen);
  final buttons = find.descendant(
    of: session,
    matching: find.byType(FilledButton),
  );
  final action = buttons.evaluate().length == 1
      ? tester.widget<FilledButton>(buttons)
      : null;
  final actionLabel = action == null
      ? '<missing or ambiguous>'
      : tester
            .widgetList<Text>(
              find.descendant(of: buttons, matching: find.byType(Text)),
            )
            .map((text) => text.data)
            .whereType<String>()
            .join(' | ');
  final progressCount = find
      .descendant(of: session, matching: find.byType(LinearProgressIndicator))
      .evaluate()
      .length;
  return (
    label: actionLabel,
    enabled: action?.onPressed != null,
    progressCount: progressCount,
  );
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
