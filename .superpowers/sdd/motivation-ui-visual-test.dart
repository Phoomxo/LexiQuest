// Ignored, local visual QA fixture. Not production source or a golden baseline.
// Synthetic-only D2 capture set for Motivation A0-A4.
// Run only after application writers freeze the source snapshot:
// & 'C:/Users/Phet/AppData/Local/Programs/flutter/bin/flutter.bat' test --no-pub --concurrency=1 '.superpowers/sdd/motivation-ui-visual-test.dart' --reporter expanded

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as crypto;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/goals/application/learning_goal_use_cases.dart';
import 'package:vocab_learning_app/features/goals/data/drift_learning_goal_repository.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';
import 'package:vocab_learning_app/features/progress/domain/learning_calendar.dart';
import 'package:vocab_learning_app/features/progress/domain/personal_learning_profile.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/reminders/application/study_reminder_use_cases.dart';
import 'package:vocab_learning_app/features/reminders/data/drift_study_reminder_repository.dart';
import 'package:vocab_learning_app/features/reminders/domain/reminder_scheduler.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/avatar_equipment_screen.dart';
import 'package:vocab_learning_app/screens/learning_goals_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/study_reminder_settings_screen.dart';
import 'package:vocab_learning_app/screens/today_hub_view.dart';

const _boundaryKey = ValueKey<String>('motivation-ui-visual-boundary');
const _output = 'build/verification/motivation-ui-20260908/visual/c1/focused';
const _ownerId = 'synthetic-owner-motivation-d2';
const _checksum =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _now = DateTime.utc(2026, 9, 8, 8);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    timezone_data.initializeTimeZones();
    final thaiFont = FontLoader(M3Theme.thaiFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait<void>([thaiFont.load(), icons.load()]);
  });

  for (final spec in <_VisualSpec>[
    const _VisualSpec('390x844', Size(390, 844), 1),
    const _VisualSpec(
      '360x800-text200-dark-reduced',
      Size(360, 800),
      2,
      dark: true,
      reducedMotion: true,
    ),
    const _VisualSpec(
      '240x640-text200-highcontrast',
      Size(240, 640),
      2,
      highContrast: true,
    ),
  ]) {
    testWidgets('motivation UI focused visual ${spec.name}', (tester) async {
      tester.view.physicalSize = spec.size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 16);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);

      final fixture = await tester.runAsync(_Fixture.create);
      expect(fixture, isNotNull);
      final captures = <String>[];
      try {
        final goal = _goal();
        final actions = _Actions();
        final review = List<TodayHubReviewWorkItem>.generate(
          4,
          (index) => _review(index),
        );
        await _pump(
          tester,
          spec,
          TodayHubView(
            snapshot: _today(goal: goal, review: review),
            actions: actions,
            features: const BuildFeatureRegistry.allEnabled(),
            assessmentAvailable: false,
          ),
        );
        expect(find.text('รายการทบทวน 4 คำ'), findsOneWidget);
        expect(find.text('word 3'), findsNothing);
        await _capture(tester, spec, '01-today-preview', captures);
        await _scrollTo(
          tester,
          find.byKey(const ValueKey('today-hub-expand-review')),
        );
        await tester.tap(find.byKey(const ValueKey('today-hub-expand-review')));
        await _settle(tester);
        await _scrollTo(
          tester,
          find.byKey(const ValueKey('today-hub-review:word:3')),
        );
        expect(find.text('word 3'), findsOneWidget);
        await _capture(tester, spec, '02-today-expanded', captures);
        await _scrollTo(
          tester,
          find.byKey(const ValueKey('today-hub-open-review')),
        );
        await tester.tap(find.byKey(const ValueKey('today-hub-open-review')));
        await tester.pump();
        expect(actions.reviewWork, orderedEquals(review));
        await _scrollTo(
          tester,
          find.byKey(const ValueKey('today-hub-open-planning')),
        );
        final stalePlanning = tester
            .widget<OutlinedButton>(
              find.byKey(const ValueKey('today-hub-open-planning')),
            )
            .onPressed!;
        await _pump(
          tester,
          spec,
          TodayHubView(
            snapshot: _today(
              ownerId: 'synthetic-owner-motivation-d2-b',
              goal: goal,
              review: review,
            ),
            actions: actions,
            features: const BuildFeatureRegistry.allEnabled(),
            assessmentAvailable: false,
          ),
        );
        stalePlanning();
        await tester.pump();
        expect(actions.planningOwner, isNull);
        await _scrollTo(
          tester,
          find.byKey(const ValueKey('today-hub-open-planning')),
        );
        await tester.tap(find.byKey(const ValueKey('today-hub-open-planning')));
        await tester.pump();
        expect(actions.planningOwner, 'synthetic-owner-motivation-d2-b');

        await _pump(
          tester,
          spec,
          LearningGoalsScreen(
            useCases: fixture!.goals,
            reminderUseCases: fixture.reminders,
            reminderRuntimeEnabled: true,
          ),
        );
        expect(find.text(goal.title), findsOneWidget);
        await _capture(tester, spec, '03-goals', captures);
        await _scrollTo(
          tester,
          find.byKey(const ValueKey('learning-goals/add')),
        );
        await tester.tap(find.byKey(const ValueKey('learning-goals/add')));
        await _settle(tester);
        await tester.enterText(
          find.byKey(const ValueKey('learning-goals/title')),
          'เป้าหมายสังเคราะห์',
        );
        await tester.showKeyboard(
          find.byKey(const ValueKey('learning-goals/title')),
        );
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        await tester.pump(const Duration(milliseconds: 300));
        await _settle(tester);
        final titleField = find.byKey(const ValueKey('learning-goals/title'));
        await Scrollable.ensureVisible(
          tester.element(titleField),
          alignment: 0.5,
        );
        await tester.pump();
        expect(titleField.hitTestable(), findsOneWidget);
        await _capture(tester, spec, '04-goal-keyboard', captures);
        tester.testTextInput.hide();
        tester.view.resetViewInsets();
        await tester.pump(const Duration(milliseconds: 300));
        await _settle(tester);
        final date = find.byKey(const ValueKey('learning-goals/deadline/date'));
        await tester.ensureVisible(date);
        await tester.tap(date);
        await _settle(tester);
        expect(find.byType(DatePickerDialog), findsOneWidget);
        await _capture(tester, spec, '05-goal-date-picker', captures);
        await tester.tap(find.widgetWithText(TextButton, 'ยกเลิก').last);
        await _settle(tester);
        expect(find.byType(DatePickerDialog), findsNothing);
        final cancelGoal = find.widgetWithText(TextButton, 'ยกเลิก');
        await tester.ensureVisible(cancelGoal);
        await tester.tap(cancelGoal);
        await _settle(tester);
        expect(find.byType(AlertDialog), findsNothing);

        await _pump(
          tester,
          spec,
          StudyReminderSettingsScreen(
            useCases: fixture.reminders,
            source: StudyReminderSource.goalDeadline(goal.id),
            sourceLabel: goal.title,
          ),
        );
        await _capture(tester, spec, '06-reminder', captures);
        final quietStart = find.byKey(
          const ValueKey('study-reminder/quiet-start'),
        );
        await _scrollTo(tester, quietStart);
        await tester.tap(quietStart);
        await _settle(tester);
        final timeDialog = spec.size.width < 360 || spec.textScale > 1.3
            ? find.byType(AlertDialog)
            : find.byType(TimePickerDialog);
        expect(timeDialog, findsOneWidget);
        final timeInputs = find.descendant(
          of: timeDialog,
          matching: find.byType(TextField),
        );
        expect(timeInputs, findsNWidgets(2));
        await tester.ensureVisible(timeInputs.last);
        await _settle(tester);
        for (final input in [timeInputs.first, timeInputs.last]) {
          final bounds = tester.getRect(input);
          expect(bounds.left, greaterThanOrEqualTo(16));
          expect(bounds.right, lessThanOrEqualTo(spec.size.width - 16));
        }
        final timeConfirm = find.text('ตกลง');
        expect(timeConfirm.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(timeConfirm).right,
          lessThanOrEqualTo(spec.size.width - 16),
        );
        await _capture(tester, spec, '07-reminder-time-picker', captures);
        await tester.tap(find.widgetWithText(TextButton, 'ยกเลิก').last);
        await _settle(tester);

        await _pump(
          tester,
          spec,
          MasteryDashboardScreen(loader: () async => _profile()),
        );
        await _capture(tester, spec, '08-mastery-weekly', captures);

        final beforePreview = await _readWithPumps(
          tester,
          fixture.rewards.load,
        );
        expect(beforePreview, isNotNull);
        final durableBefore = beforePreview!;
        await _pump(
          tester,
          spec,
          const Scaffold(body: Text('Synthetic visual fixture host')),
        );
        Navigator.of(tester.element(find.byType(Scaffold))).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => AvatarEquipmentScreen(rewards: fixture.rewards),
          ),
        );
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('reward-avatar-preview/base')),
          findsOneWidget,
        );
        final preview = find.byKey(
          const ValueKey('reward-preview/headgear_ipa'),
        );
        await _scrollToCenter(tester, preview, delta: 200);
        await tester.tap(preview);
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('reward-avatar-preview/headgear_ipa')),
          findsOneWidget,
        );
        expect(find.text('กำลังลองหมวก IPA'), findsOneWidget);
        expect(find.text('ลองดูเท่านั้น ยังไม่ได้ซื้อหรือสวม'), findsOneWidget);
        final afterPreview = await _readWithPumps(tester, fixture.rewards.load);
        expect(afterPreview, isNotNull);
        expect(afterPreview!.coinBalance, durableBefore.coinBalance);
        expect(afterPreview.transactionCount, durableBefore.transactionCount);
        expect(afterPreview.ownedItemIds, durableBefore.ownedItemIds);
        expect(afterPreview.equippedBySlot, durableBefore.equippedBySlot);
        await _capture(tester, spec, '09-avatar-preview-no-delta', captures);
        final cancelPreview = find.widgetWithText(TextButton, 'เลิกลอง');
        await _scrollToCenter(tester, cancelPreview, delta: -200);
        await tester.tap(cancelPreview);
        await _settle(tester);
        expect(
          find.byKey(const ValueKey('reward-avatar-preview/base')),
          findsOneWidget,
        );
        expect(find.text('กำลังลองหมวก IPA'), findsNothing);
        await tester.pageBack();
        await _settle(tester);
        final afterCancel = await _readWithPumps(tester, fixture.rewards.load);
        expect(afterCancel, isNotNull);
        expect(afterCancel!.coinBalance, durableBefore.coinBalance);
        expect(afterCancel.transactionCount, durableBefore.transactionCount);
        expect(afterCancel.ownedItemIds, durableBefore.ownedItemIds);
        expect(afterCancel.equippedBySlot, durableBefore.equippedBySlot);

        await _pump(
          tester,
          spec,
          TodayHubView(
            snapshot: _today(
              goal: goal,
              review: const [],
              dependencies: _states(
                overrides: const {
                  TodayHubDependency.goals: TodayHubDependencyState.corrupt,
                  TodayHubDependency.reminders:
                      TodayHubDependencyState.unavailable,
                  TodayHubDependency.review:
                      TodayHubDependencyState.unavailable,
                },
              ),
            ),
            actions: actions,
            features: const BuildFeatureRegistry.allEnabled(),
            assessmentAvailable: false,
          ),
        );
        await _scrollTo(tester, find.text('เป้าหมายการเรียนยังไม่พร้อมใช้งาน'));
        expect(find.text('เป้าหมายการเรียนยังไม่พร้อมใช้งาน'), findsOneWidget);
        await _capture(tester, spec, '10-readiness-error-fallback', captures);

        expect(captures, hasLength(10));
        await tester.runAsync(() async {
          final file = File('.superpowers/sdd/motivation-ui-visual-test.dart');
          final metadata = <String, Object?>{
            'fixture': file.path,
            'fixtureSha256': crypto.sha256
                .convert(await file.readAsBytes())
                .toString(),
            'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
            'viewport': [spec.size.width, spec.size.height],
            'textScale': spec.textScale,
            'brightness': spec.dark ? 'dark' : 'light',
            'highContrast': spec.highContrast,
            'reducedMotion': spec.reducedMotion,
            'data':
                'Synthetic local owner and fixtures only; no research or upload',
            'captures': captures,
            'limitations': [
              'Widget renderer; no physical-device, TalkBack, native OS, or UAT claim',
              'Picker captures are Flutter Material picker dialogs',
              'Preview capture creates no reward economy mutation',
              'Every PNG requires human visual inspection; capture is not approval',
            ],
          };
          final out = File('$_output/${spec.name}-capture.json');
          await out.parent.create(recursive: true);
          await out.writeAsString(
            const JsonEncoder.withIndent('  ').convert(metadata),
          );
        });
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (fixture != null) await _closeFixture(tester, fixture);
      }
    });
  }
}

Future<void> _pump(WidgetTester tester, _VisualSpec spec, Widget home) async {
  final page = home is TodayHubView
      ? Scaffold(
          appBar: AppBar(title: const Text('วันนี้')),
          body: home,
        )
      : home;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundaryKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: M3Theme.lightTheme,
        darkTheme: M3Theme.darkTheme,
        themeMode: spec.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(spec.textScale),
            highContrast: spec.highContrast,
            disableAnimations: spec.reducedMotion,
          ),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await _settle(tester);
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  expect(app.theme!.useMaterial3, isTrue);
  expect(app.theme!.textTheme.bodyMedium!.fontFamily, M3Theme.thaiFontFamily);
}

Future<void> _capture(
  WidgetTester tester,
  _VisualSpec spec,
  String name,
  List<String> captures,
) async {
  final exception = tester.takeException();
  expect(
    exception,
    isNull,
    reason: 'Unhandled layout/paint exception before $name',
  );
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  final relative = '${spec.name}-$name.png';
  await tester.runAsync(() async {
    ui.Image? image;
    try {
      image = await boundary
          .toImage(pixelRatio: 1)
          .timeout(const Duration(seconds: 8));
      final bytes = await image
          .toByteData(format: ui.ImageByteFormat.png)
          .timeout(const Duration(seconds: 8));
      if (bytes == null)
        throw StateError('PNG encoder returned no bytes for $name');
      final file = File('$_output/$relative');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    } finally {
      image?.dispose();
    }
  });
  captures.add(relative);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 80; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    if (!tester.binding.hasScheduledFrame) return;
  }
  fail('UI did not settle within the bounded visual-fixture wait.');
}

Future<void> _closeFixture(WidgetTester tester, _Fixture fixture) async {
  var closed = false;
  Object? closeError;
  fixture.close().then(
    (_) => closed = true,
    onError: (Object error) {
      closeError = error;
      closed = true;
    },
  );
  for (var attempt = 0; attempt < 160 && !closed; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(closeError, isNull, reason: 'Synthetic database disposal failed.');
  expect(closed, isTrue, reason: 'Synthetic database disposal did not finish.');
}

// Drift operations used by widgets cross the test binding's fake clock. Keep
// pumping that clock while awaiting the real synthetic repository, with a bound.
Future<T> _readWithPumps<T>(
  WidgetTester tester,
  Future<T> Function() read,
) async {
  late T result;
  Object? error;
  var completed = false;
  read().then(
    (value) {
      result = value;
      completed = true;
    },
    onError: (Object failure) {
      error = failure;
      completed = true;
    },
  );
  for (var step = 0; step < 160 && !completed; step++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(error, isNull, reason: 'Synthetic repository read failed.');
  expect(
    completed,
    isTrue,
    reason: 'Synthetic repository read did not finish.',
  );
  return result;
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  final scrollable = find.byType(Scrollable).first;
  expect(scrollable, findsOneWidget);
  var position = tester.state<ScrollableState>(scrollable).position;
  position.jumpTo(position.minScrollExtent);
  await tester.pump();
  for (var step = 0; step < 80 && target.evaluate().length != 1; step++) {
    position = tester.state<ScrollableState>(scrollable).position;
    final next = (position.pixels + 160)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (next == position.pixels) break;
    position.jumpTo(next);
    await tester.pump();
  }
  if (target.evaluate().length != 1) {
    position = tester.state<ScrollableState>(scrollable).position;
    fail(
      'Target did not materialize exactly once after bounded scrolling; '
      'pixels=${position.pixels}, min=${position.minScrollExtent}, '
      'max=${position.maxScrollExtent}.',
    );
  }
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget);
}

Future<void> _scrollToCenter(
  WidgetTester tester,
  Finder target, {
  required double delta,
}) async {
  await tester.scrollUntilVisible(target, delta, maxScrolls: 30);
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pump();
  expect(target.hitTestable(), findsOneWidget);
}

final class _VisualSpec {
  const _VisualSpec(
    this.name,
    this.size,
    this.textScale, {
    this.dark = false,
    this.highContrast = false,
    this.reducedMotion = false,
  });
  final String name;
  final Size size;
  final double textScale;
  final bool dark;
  final bool highContrast;
  final bool reducedMotion;
}

final class _Fixture {
  _Fixture(this.database, this.goals, this.reminders, this.rewards);

  static Future<_Fixture> create() async {
    final database = AppDatabase(NativeDatabase.memory());
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => _ownerId,
      nowUtc: () => _now,
    );
    final owner = await owners.getOrCreateActiveOwner();
    final goals = LearningGoalUseCases(
      repository: DriftLearningGoalRepository(database, owners: owners),
      nowUtc: () => _now,
      generateId: () => 'goal:visual-created',
      activeOwnerId: () async => (await owners.getOrCreateActiveOwner()).id,
    );
    await goals.repository.save(_goal(), expectedOwnerId: owner.id);
    final reminders = StudyReminderUseCases(
      repository: DriftStudyReminderRepository(database, owners: owners),
      scheduler: _VisualScheduler(),
      nowUtc: () => _now,
      generateId: () => 'reminder:visual',
    );
    await database
        .into(database.pointsLedgerEntries)
        .insert(
          PointsLedgerEntriesCompanion.insert(
            id: 'synthetic-visual-xp',
            ownerId: owner.id,
            idempotencyKey: 'synthetic-visual-xp',
            entryType: 'quizCorrect',
            amount: 40,
            occurredAtUtcMs: 1,
          ),
        );
    var rewardSequence = 0;
    final rewards = RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(database),
      progress: ProgressUseCases(
        owners: owners,
        queries: DriftProgressQueries(database),
        nowUtc: () => _now,
      ),
      generateId: () => 'synthetic-visual-reward-${rewardSequence++}',
      nowUtc: () => _now,
    );
    await rewards.grantCoins(
      idempotencyKey: 'synthetic-visual-preview-coins',
      amount: 120,
      sourceEventId: 'synthetic-visual-preview-grant',
    );
    return _Fixture(database, goals, reminders, rewards);
  }

  final AppDatabase database;
  final LearningGoalUseCases goals;
  final StudyReminderUseCases reminders;
  final RewardUseCases rewards;
  Future<void> close() => database.close();
}

final class _VisualScheduler implements ReminderScheduler {
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> isSupported() async => true;
  @override
  Future<ReminderPermissionState> permissionState() async =>
      ReminderPermissionState.unknown;
  @override
  Future<ReminderPermissionState> requestPermission() async =>
      ReminderPermissionState.granted;
  @override
  Future<List<ReminderPlatformEntry>> pendingEntries() async => const [];
  @override
  Future<void> schedule(ReminderScheduleRequest request) async {}
  @override
  Future<void> cancel(int platformId) async {}
}

LearningGoal _goal() => LearningGoal(
  id: 'goal:visual',
  kind: LearningGoalKind.personal,
  title: 'ฝึกคำศัพท์สำหรับการเดินทาง',
  deadlineAtUtc: DateTime.utc(2026, 9, 15, 10),
  timezone: const LearningGoalTimezoneContext(
    timezoneId: 'Asia/Bangkok',
    utcOffsetMinutes: 420,
  ),
  status: LearningGoalStatus.active,
  createdAtUtc: _now,
  updatedAtUtc: _now,
);

TodayHubSnapshot _today({
  String ownerId = _ownerId,
  required LearningGoal goal,
  required List<TodayHubReviewWorkItem> review,
  Map<TodayHubDependency, TodayHubDependencyState>? dependencies,
}) => TodayHubSnapshot(
  ownerId: ownerId,
  evaluatedAtUtc: _now,
  sectionOrder: TodayHubSectionKind.values,
  resumableSession: null,
  assignedAssessment: null,
  reviewWork: review,
  recommendation: TodayHubRecommendation(
    result: RecommendationPanelResult.unavailable(
      ownerId: ownerId,
      reason: RecommendationPanelReason.noEligibleActivity,
      freshness: RecommendationEvidenceFreshness.missing,
      protocolConstraint: RecommendationProtocolConstraint.open,
    ),
    isAuthoritative: false,
    mergedInto: null,
  ),
  goals: [goal],
  reminders: const [],
  quests: const [],
  gentleStreak: GentleStreakSnapshot(
    ownerId: ownerId,
    currentStreakDays: 14,
    longestStreakDays: 21,
    freezeCount: 0,
    phase: GentleStreakPhase.recovery,
    policyVersion: StreakPolicy.version,
  ),
  dependencyStates: dependencies ?? _states(),
);

Map<TodayHubDependency, TodayHubDependencyState> _states({
  Map<TodayHubDependency, TodayHubDependencyState> overrides = const {},
}) => {
  for (final dependency in TodayHubDependency.values)
    dependency: overrides[dependency] ?? TodayHubDependencyState.ready,
};

TodayHubReviewWorkItem _review(int index) {
  final id = 'word:$index';
  return TodayHubReviewWorkItem(
    item: ReviewQueueItem(
      snapshot: ReviewedLexicalContentSnapshot(
        identity: ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: id,
          revision: 1,
        ),
        categoryId: 'category:travel',
        spelling: 'word $index',
        normalizedSpelling: 'word $index',
        meaning: 'คำสังเคราะห์ $index',
        normalizedMeaning: 'คำสังเคราะห์ $index',
        partOfSpeech: 'noun',
        cefrLevel: 'A1',
        source: 'synthetic-pack',
        isGlobal: true,
        coreChecksumSha256: _checksum,
        provenance: ContentProvenance.packaged,
        reviewState: ContentReviewState.approved,
        publicationState: ContentPublicationState.published,
        artifact: null,
      ),
      provenance: [
        ReviewReasonProvenance.due(
          sourceId: 'synthetic-srs:$index',
          dueAtUtc: _now.subtract(Duration(hours: index + 1)),
        ),
      ],
    ),
    recommendation: null,
  );
}

PersonalLearningProfile _profile() => PersonalLearningProfile(
  ownerId: _ownerId,
  mastery: PersonalLearningMastery(
    availability: ProfileAxisAvailability.available,
    masteredWordCount: 2,
    observedPracticeCount: 10,
    skills: [
      SkillEvidence(
        key: 'listening',
        label: 'การฟัง',
        sampleSize: 4,
        accuracy: .75,
      ),
    ],
  ),
  srs: const PersonalLearningSrs(
    availability: ProfileAxisAvailability.available,
    trackedWordCount: 3,
    dueReviewCount: 1,
  ),
  effort: PersonalLearningEffort(
    availability: ProfileAxisAvailability.available,
    activeDuration: Duration(minutes: 25),
  ),
  accuracy: const PersonalLearningAccuracy(
    availability: ProfileAxisAvailability.available,
    sampleSize: 10,
    correctCount: 8,
  ),
  weakness: PersonalLearningWeakness(
    availability: ProfileAxisAvailability.available,
    items: [],
  ),
  engagement: const PersonalLearningEngagement(
    availability: ProfileAxisAvailability.available,
    totalXp: 42,
    avatarLevel: 3,
    completedSessionCount: 2,
    currentStreakDays: 7,
    longestStreakDays: 9,
    activeQuestCount: 1,
    completedQuestCount: 2,
    achievementCount: 1,
    ownedRewardItemCount: 2,
  ),
  calendar: LearningCalendarSnapshot(
    timezoneId: 'Asia/Bangkok',
    weekStart: DateTime(2026, 9, 7),
    days: const [],
    weekly: WeeklyLearningAnalytics(
      effort: LearningEffortAxis(activeDuration: Duration(minutes: 25)),
      accuracy: LearningAccuracyAxis(sampleSize: 10, correctCount: 8),
      skillDistribution: [],
      accuracyTrend: [],
    ),
  ),
);

final class _Actions implements TodayHubActionDelegate {
  List<TodayHubReviewWorkItem> reviewWork = const [];
  String? planningOwner;
  @override
  Future<void> openPlanning({required String ownerId}) async {
    planningOwner = ownerId;
  }

  @override
  Future<void> openReview(List<TodayHubReviewWorkItem> work) async {
    reviewWork = List.unmodifiable(work);
  }

  @override
  Future<void> openHistory() async {}
  @override
  Future<void> resume(LearningSessionSummary session) async {}
  @override
  Future<void> startRecommendation(
    TodayHubRecommendation recommendation,
  ) async {}
  @override
  Future<void> startAssessment(TodayHubAssignedAssessment assessment) async {}
}
