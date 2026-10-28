// Synthetic Android route tests. Root owns build/install/driver execution.
// No viewport overrides, native audio, camera capture, cloud or real exports.
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyWord;
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/offline_content/data/voice_pack_download_adapter.dart';
import 'package:vocab_learning_app/features/reminders/domain/reminder_scheduler.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

import '../../integration_test/support/field_trial_external_fakes.dart';

const _suite = 'autonomous-ui-real-viewport-v1';
const _screenshots = bool.fromEnvironment(
  'LEXIQUEST_AUTONOMOUS_SCREENSHOTS',
  defaultValue: true,
);
const _pairs = <(String, String)>[
  ('station', 'สถานี'),
  ('book', 'หนังสือ'),
  ('house', 'บ้าน'),
  ('cat', 'แมว'),
  ('water', 'น้ำ'),
  ('school', 'โรงเรียน'),
];
final _receipts = <Map<String, Object?>>[];
final _cases = <Map<String, Object?>>[];
final _events = <String>[];
late IntegrationTestWidgetsFlutterBinding _binding;

typedef _Body = Future<void> Function(WidgetTester tester, _Fixture fixture);

void main() {
  _binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final specs = <(String, _Body)>[
    ('tabs-progress-profile', _tabs),
    ('vocabulary-form', _vocabulary),
    ('shop-preview-and-quests', _shop),
    ('settings-navigation', _settings),
    ('today-review-history', _today),
    ('planning-goal-cancel', _planning),
    ('goal-reminder-picker-cancel', _reminder),
    ('quiz-selection-submit-result', _quiz),
    ('cloze-mode-and-back', _cloze),
    ('word-scramble-select-reset', _scramble),
    ('speech-unavailable', _speech),
    ('shadowing-unavailable', _shadowing),
    ('camera-unavailable', _camera),
    ('export-recording-store', _export),
    ('srs-reveal', _srs),
    ('associative-first-stage', _associative),
  ];
  setUpAll(() async {
    expect(Platform.isAndroid, isTrue, reason: 'Android-only fixture');
    await _publishService();
    _event('AUTONOMOUS_UI_START suite=$_suite cases=${specs.length}');
    _publish(specs.map((entry) => entry.$1).toList());
  });
  for (final (name, body) in specs) {
    testWidgets('autonomous UI $name', (tester) async {
      final caseReceipt = <String, Object?>{
        'name': name,
        'startedUtc': DateTime.now().toUtc().toIso8601String(),
        'passed': false,
        'cleanupCompleted': false,
        'optInFeatureFlags': _caseOptIns(name).map((f) => f.name).toList(),
        'syntheticReviewedCloze': name == 'cloze-mode-and-back',
        'syntheticPastSrsEvidence': name == 'srs-reveal',
        'simulatedReminderScheduler': name == 'goal-reminder-picker-cancel',
      };
      _cases.add(caseReceipt);
      _Fixture? fixture;
      try {
        await _waitForView(tester);
        fixture = await tester.runAsync(() => _Fixture.create(name));
        expect(fixture, isNotNull);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          MyApp(dependencies: fixture!.dependencies, ownsDependencies: false),
        );
        await _wait(tester, _page('ChooseModeScreen'));
        if (_screenshots) {
          // integration_test reverts the surface in each test's tearDown.
          await _binding.convertFlutterSurfaceToImage();
          await tester.pump();
        }
        _event('AUTONOMOUS_UI_CASE_START $name');
        await _record(tester, '$name-start', 'ChooseModeScreen');
        await body(tester, fixture);
        fixture.verifyNoReminderWrites();
        _checkNoException(tester);
        caseReceipt['passed'] = true;
        _event('AUTONOMOUS_UI_CASE_PASS $name');
      } catch (error) {
        caseReceipt['failure'] = error.toString();
        _event('AUTONOMOUS_UI_CASE_FAIL $name ${error.runtimeType}');
        rethrow;
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          if (fixture != null) await tester.runAsync(fixture.close);
          fixture?.verifyNoReminderWrites();
          caseReceipt['cleanupCompleted'] = true;
          _checkNoException(tester);
        } catch (error) {
          caseReceipt['passed'] = false;
          caseReceipt['cleanupFailure'] = error.toString();
          rethrow;
        } finally {
          if (fixture?.reminderScheduler case final scheduler?) {
            caseReceipt['reminderSchedulerCalls'] = scheduler.callCounts;
          }
          caseReceipt['finishedUtc'] = DateTime.now().toUtc().toIso8601String();
          _publish(specs.map((entry) => entry.$1).toList());
        }
      }
    }, timeout: const Timeout(Duration(seconds: 90)));
  }
  testWidgets('AUTONOMOUS_UI_FINAL_SENTINEL', (tester) async {
    _publish(specs.map((entry) => entry.$1).toList());
    expect(_cases, hasLength(specs.length));
    expect(_cases.every((entry) => entry['cleanupCompleted'] == true), isTrue);
    expect(_cases.every((entry) => entry['passed'] == true), isTrue);
    expect(_receipts, isNotEmpty);
    expect(
      _receipts.every((entry) => entry['viewportMatchesDevice'] == true),
      isTrue,
    );
    _binding.reportData!['sentinelCompleted'] = true;
    _event(
      'AUTONOMOUS_UI_COMPLETE cases=${_cases.length} pages=${_receipts.length}',
    );
    _publish(specs.map((entry) => entry.$1).toList());
  });
}

void _event(String message) {
  _events.add(message);
  print(message);
}

void _publish(List<String> expected) {
  _binding.reportData = <String, dynamic>{
    ...?_binding.reportData,
    'suite': _suite,
    'events': List<String>.of(_events),
    'expectedCases': expected,
    'cases': _cases,
    'pages': _receipts,
    // This is a testWidgets integration fixture outside the test/ directory.
    // ignore: invalid_use_of_visible_for_testing_member
    'testResults': _binding.results.map(
      (key, value) => MapEntry(key, value.toString()),
    ),
    'scope': {
      'syntheticDatabase': true,
      'optInFeatureFlags': ['dailyContinuity', 'studyPlanning'],
      'featureActivation': 'explicit per-case fixture opt-in, not app defaults',
      'simulatedReminderSchedulerCases': ['goal-reminder-picker-cancel'],
      'nativeReminderPermissionOrScheduling': false,
      'unreviewedClozeEnglishCopy':
          'open; autonomous-ui-corrected-retry/cloze-ready.png retains evidence',
      'realDeviceViewport': true,
      'nativeCameraCapture': false,
      'nativeSpeechOrAudio': false,
      'externalExport': false,
      'humanUat': false,
      'screenshotsRequested': _screenshots,
    },
  };
}

Future<void> _publishService() async {
  final uri = (await developer.Service.getInfo()).serverUri;
  if (uri == null || uri.scheme != 'http' || uri.host != '127.0.0.1') {
    throw StateError('Authenticated loopback VM service required');
  }
  final file = File(
    '${Directory.systemTemp.path}/lexiquest-core-service-20260907.json',
  );
  if (await file.exists())
    throw StateError('Existing service marker requires reconciliation');
  await file.writeAsString(jsonEncode({'uri': uri.toString()}), flush: true);
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));
Finder _page(String type) => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == type,
  description: 'production page $type',
);
Finder _scroll(Finder owner) =>
    find.descendant(of: owner, matching: find.byType(Scrollable)).first;

Future<void> _waitForView(WidgetTester tester) async {
  for (var index = 0; index < 100; index++) {
    final view = _binding.platformDispatcher.implicitView;
    if (view != null && !view.physicalSize.isEmpty && view.devicePixelRatio > 0)
      return;
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Actual Android view did not arrive');
}

Future<void> _wait(
  WidgetTester tester,
  Finder target, {
  bool gone = false,
}) async {
  for (var index = 0; index < 200; index++) {
    await tester.pump(const Duration(milliseconds: 25));
    if (target.evaluate().isEmpty == gone) return;
    _checkNoException(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Bounded wait failed: gone=$gone target=$target');
}

void _checkNoException(WidgetTester tester) {
  expect(
    tester.takeException(),
    isNull,
    reason: 'No swallowed Flutter exception',
  );
}

Future<void> _tap(
  WidgetTester tester,
  Finder target, {
  Finder? scrollable,
  double delta = 220,
}) async {
  if (scrollable != null) {
    await tester.scrollUntilVisible(
      target,
      delta,
      scrollable: scrollable,
      maxScrolls: 40,
      continuous: true,
    );
  } else {
    await _wait(tester, target);
    await tester.ensureVisible(target);
  }
  await tester.pump(const Duration(milliseconds: 250));
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: 'Real tap target must be visible',
  );
  await tester.tap(target);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pump();
  _checkNoException(tester);
}

Future<void> _back(WidgetTester tester, String destination) async {
  await tester.pageBack();
  await _wait(tester, _page(destination));
  await tester.pump(const Duration(milliseconds: 250));
  _checkNoException(tester);
}

Future<void> _record(WidgetTester tester, String state, String page) async {
  await _wait(tester, _page(page));
  await tester.pump(const Duration(milliseconds: 250));
  _checkNoException(tester);
  final actual = _binding.platformDispatcher.implicitView!;
  final same =
      tester.view.physicalSize == actual.physicalSize &&
      tester.view.devicePixelRatio == actual.devicePixelRatio;
  expect(same, isTrue, reason: 'Test view must equal real Android view');
  final receipt = <String, Object?>{
    'state': state,
    'page': page,
    'viewportMatchesDevice': same,
    'physicalWidth': actual.physicalSize.width,
    'physicalHeight': actual.physicalSize.height,
    'devicePixelRatio': actual.devicePixelRatio,
    'logicalWidth': actual.physicalSize.width / actual.devicePixelRatio,
    'logicalHeight': actual.physicalSize.height / actual.devicePixelRatio,
    'textScale':
        MediaQuery.textScalerOf(tester.element(_page(page).first)).scale(16) /
        16,
    'insetsBottom': actual.viewInsets.bottom,
    'paddingTop': actual.padding.top,
    'utc': DateTime.now().toUtc().toIso8601String(),
    'exceptionChecked': true,
  };
  _receipts.add(receipt);
  _event('AUTONOMOUS_UI_PAGE ${jsonEncode(receipt)}');
  if (_screenshots) {
    final bytes = await _binding.takeScreenshot(state);
    expect(bytes, isNotEmpty);
    receipt['screenshotName'] = state;
    receipt['screenshotBytes'] = bytes.length;
  }
}

Future<void> _drawer(WidgetTester tester, String key, String page) async {
  await _tap(tester, _key('legacy-drawer-button'));
  await _wait(tester, find.byType(Drawer));
  await _tap(tester, _key(key), scrollable: _scroll(find.byType(Drawer)));
  await _wait(tester, _page(page));
}

Future<void> _mode(WidgetTester tester, String key, String page) async {
  await _tap(tester, _key(key), scrollable: _scroll(_page('ChooseModeScreen')));
  await _wait(tester, _key('session-configuration-sheet'));
  await _tap(tester, _key('session-options-toggle'));
  final count = _key('session-item-count');
  await tester.ensureVisible(count);
  await tester.enterText(count, '1');
  // Keep the real IME/view insets; scroll to the real start button below.
  await _tap(tester, _key('session-config-start'));
  await _wait(tester, _page(page));
}

Future<void> _tabs(WidgetTester t, _Fixture f) async {
  for (final (key, page) in <(String, String)>[
    ('home/mastery', 'MasteryDashboardScreen'),
    ('home/achievements', 'AchievementsScreen'),
    ('home/profile', 'ProfileSettingsScreen'),
  ]) {
    await _tap(t, _key(key));
    await _record(t, 'tabs-$key'.replaceAll('/', '-'), page);
  }
  await _tap(
    t,
    _key('profile-learning-details'),
    scrollable: _scroll(_page('ProfileSettingsScreen')),
  );
  await _record(t, 'profile-expanded', 'ProfileSettingsScreen');
  await _tap(
    t,
    _key('profile-open-mastery'),
    scrollable: _scroll(_page('ProfileSettingsScreen')),
    delta: -220,
  );
  await _wait(t, _page('MasteryDashboardScreen'));
  await _tap(
    t,
    _key('home/weakness'),
    scrollable: _scroll(_page('MasteryDashboardScreen')),
  );
  await _record(t, 'weakness-empty', 'WeaknessClinicScreen');
  await _back(t, 'MasteryDashboardScreen');
  await _tap(
    t,
    _key('learning-calendar-action'),
    scrollable: _scroll(_page('MasteryDashboardScreen')),
  );
  await _record(t, 'calendar-empty', 'LearningCalendarScreen');
  await _back(t, 'MasteryDashboardScreen');
}

Future<void> _vocabulary(WidgetTester t, _Fixture f) async {
  await _tap(t, _key('home/vocabulary'));
  await _record(t, 'categories-ready', 'CategoriesPage');
  await _tap(t, _key('add-category'));
  await _wait(t, _key('category-name-field'));
  await t.enterText(_key('category-name-field'), 'Autonomous extra');
  await _tap(t, _key('save-category'));
  await _wait(t, find.text('Autonomous extra'));
  await _tap(t, find.text('Autonomous extra'));
  await _tap(t, _key('add-word'));
  await _wait(t, _key('word-field'));
  await t.enterText(_key('word-field'), 'pencil');
  await t.enterText(_key('meaning-field'), 'ดินสอ');
  await t.enterText(_key('part-of-speech-field'), 'noun');
  await _tap(t, _key('save-word'));
  await _wait(t, find.text('pencil'));
  await _record(t, 'vocabulary-saved', 'VocabListScreen');
  await _back(t, 'CategoriesPage');
}

Future<void> _shop(WidgetTester t, _Fixture f) async {
  await _drawer(t, 'drawer/rewards/shop', 'AvatarEquipmentScreen');
  await _record(t, 'shop-ready', 'AvatarEquipmentScreen');
  final preview = _key('reward-preview/headgear_ipa');
  await _tap(t, preview, scrollable: _scroll(_page('AvatarEquipmentScreen')));
  await _wait(t, find.text('ลองดูเท่านั้น ยังไม่ได้ซื้อหรือสวม'));
  await _record(t, 'shop-preview', 'AvatarEquipmentScreen');
  final cancel = find.widgetWithText(TextButton, 'เลิกลอง');
  await _tap(
    t,
    cancel,
    scrollable: _scroll(_page('AvatarEquipmentScreen')),
    delta: -220,
  );
  expect(_key('reward-avatar-preview/base'), findsOneWidget);
  await _back(t, 'ChooseModeScreen');
  await _drawer(t, 'drawer/rewards/quests', 'QuestStatusScreen');
  await _record(t, 'quests-ready', 'QuestStatusScreen');
  await _back(t, 'ChooseModeScreen');
}

Future<void> _settings(WidgetTester t, _Fixture f) async {
  await _drawer(t, 'drawer/settings', 'SettingScreen');
  await _record(t, 'settings-ready', 'SettingScreen');
  // The fixture is an anonymous guest, so account logout is correctly absent.
  expect(find.widgetWithText(ListTile, 'ออกจากระบบ'), findsNothing);
  final footer = _key('erase-local-data');
  await t.scrollUntilVisible(
    footer,
    220,
    scrollable: _scroll(_page('SettingScreen')),
    maxScrolls: 40,
    continuous: true,
  );
  expect(footer.hitTestable(), findsOneWidget);
  expect(t.widget<ListTile>(footer).onTap, isNotNull);
  // Prove the guest footer is reachable without invoking destructive erasure.
  await _record(t, 'settings-footer', 'SettingScreen');
  await _back(t, 'ChooseModeScreen');
}

Future<void> _today(WidgetTester t, _Fixture f) async {
  await _tap(
    t,
    _key('home/today'),
    scrollable: _scroll(_page('ChooseModeScreen')),
  );
  await _record(t, 'today-ready', 'TodayHubScreen');
  await _tap(
    t,
    _key('today-hub-open-history'),
    scrollable: _scroll(_page('TodayHubScreen')),
  );
  await _record(t, 'history-empty', 'LearningHistoryScreen');
  await _back(t, 'TodayHubScreen');
  await _tap(
    t,
    _key('today-hub-open-review'),
    scrollable: _scroll(_page('TodayHubScreen')),
    delta: -220,
  );
  await _record(t, 'review-empty', 'ReviewCenterScreen');
  await _back(t, 'TodayHubScreen');
}

Future<void> _openGoals(WidgetTester t) async {
  await _tap(
    t,
    _key('home/study-planning'),
    scrollable: _scroll(_page('ChooseModeScreen')),
  );
  await _wait(t, _page('StudyPlanningHubScreen'));
  await _tap(t, _key('study-planning/open-goals'));
  await _wait(t, _page('LearningGoalsScreen'));
}

Future<void> _planning(WidgetTester t, _Fixture f) async {
  await _openGoals(t);
  await _record(t, 'goals-empty', 'LearningGoalsScreen');
  await _tap(t, _key('learning-goals/add'));
  await _wait(t, _key('learning-goals/title'));
  await t.enterText(_key('learning-goals/title'), 'เป้าหมายทดสอบที่ยกเลิก');
  await _tap(t, find.widgetWithText(TextButton, 'ยกเลิก'));
  await _wait(t, find.byType(AlertDialog), gone: true);
  expect(find.text('เป้าหมายทดสอบที่ยกเลิก'), findsNothing);
  await _back(t, 'StudyPlanningHubScreen');
  await _record(t, 'planning-return', 'StudyPlanningHubScreen');
  await _back(t, 'ChooseModeScreen');
}

Future<void> _reminder(WidgetTester t, _Fixture f) async {
  await _openGoals(t);
  await _tap(t, _key('learning-goals/add'));
  await _wait(t, _key('learning-goals/title'));
  await t.enterText(_key('learning-goals/title'), 'ฝึกคำศัพท์ทดสอบ');
  await _tap(t, _key('learning-goals/deadline/date'));
  await _wait(t, find.byType(DatePickerDialog));
  final dateDialog = find.byType(DatePickerDialog);
  final dateInput = find.descendant(
    of: dateDialog,
    matching: find.byType(TextFormField),
  );
  final dateText = MaterialLocalizations.of(
    t.element(dateDialog),
  ).formatCompactDate(DateTime.now().add(const Duration(days: 7)));
  await t.enterText(dateInput, dateText);
  await _tap(t, find.widgetWithText(TextButton, 'ตกลง'));
  await _wait(t, dateDialog, gone: true);
  await _tap(t, _key('learning-goals/deadline/time'));
  final timePicker = find.byWidgetPredicate(
    (widget) =>
        widget is TimePickerDialog ||
        widget is AlertDialog &&
            widget.title is Text &&
            (widget.title as Text).data == 'เลือกเวลา',
  );
  await _wait(t, timePicker);
  await _tap(t, find.descendant(of: timePicker, matching: find.text('ตกลง')));
  await _wait(t, timePicker, gone: true);
  await _tap(t, _key('learning-goals/create'));
  await _wait(t, find.byType(AlertDialog), gone: true);
  await _wait(t, find.text('ฝึกคำศัพท์ทดสอบ'));
  final reminder = find.byWidgetPredicate(
    (w) =>
        w.key is ValueKey<String> &&
        (w.key! as ValueKey<String>).value.startsWith('learning-goal/') &&
        (w.key! as ValueKey<String>).value.endsWith('/reminder'),
  );
  await _tap(t, reminder, scrollable: _scroll(_page('LearningGoalsScreen')));
  await _record(t, 'reminder-ready', 'StudyReminderSettingsScreen');
  await _tap(
    t,
    _key('study-reminder/quiet-start'),
    scrollable: _scroll(_page('StudyReminderSettingsScreen')),
  );
  await _wait(t, find.text('ยกเลิก'));
  await _tap(t, find.widgetWithText(TextButton, 'ยกเลิก'));
  await _record(t, 'reminder-picker-cancelled', 'StudyReminderSettingsScreen');
  // No opt-in: the fixture never requests OS notification permission/scheduling.
  await _back(t, 'LearningGoalsScreen');
}

Future<void> _quiz(WidgetTester t, _Fixture f) async {
  await _mode(t, 'home/learn/quiz', 'QuizScreen');
  await _record(t, 'quiz-ready', 'QuizScreen');
  final word = _pairs.singleWhere(
    (pair) => find.text(pair.$1).evaluate().isNotEmpty,
  );
  await _tap(t, find.text(word.$2));
  await _tap(t, _key('meaning-quiz-next'));
  await _wait(t, _page('ScoreScreen'));
  await _record(t, 'quiz-score', 'ScoreScreen');
  expect(find.text('100%'), findsOneWidget);
  await _tap(t, find.widgetWithText(FilledButton, 'กลับไปเลือกกิจกรรม'));
  await _wait(t, _page('ChooseModeScreen'));
}

Future<void> _cloze(WidgetTester t, _Fixture f) async {
  await _mode(t, 'home/learn/quiz/cloze', 'FillInTheBlanksScreen');
  await _wait(t, _key('cloze-mode-typed'));
  await _record(t, 'cloze-ready', 'FillInTheBlanksScreen');
  await _tap(
    t,
    _key('cloze-mode-typed'),
    scrollable: _scroll(_page('FillInTheBlanksScreen')),
  );
  await _wait(t, _key('cloze-typed-answer'));
  await _record(t, 'cloze-typed-mode', 'FillInTheBlanksScreen');
  await t.pageBack();
  await _wait(t, find.text('ออกจากกิจกรรมเติมคำหรือไม่'));
  await _tap(t, find.widgetWithText(FilledButton, 'ออกจากกิจกรรม'));
  await _wait(t, _page('FillInTheBlanksScreen'), gone: true);
  await _wait(t, _page('ChooseModeScreen'));
  await _record(t, 'cloze-return', 'ChooseModeScreen');
}

Future<void> _scramble(WidgetTester t, _Fixture f) async {
  await _mode(t, 'home/learn/quiz/word-scramble', 'WordScrambleScreen');
  await _record(t, 'scramble-ready', 'WordScrambleScreen');
  await _tap(
    t,
    _key('word-letter-0'),
    scrollable: _scroll(_page('WordScrambleScreen')),
  );
  expect(
    find.textContaining(RegExp(r'^ใส่แล้ว 1 จาก \d+ ตัวอักษร$')),
    findsOneWidget,
  );
  await _record(t, 'scramble-selected', 'WordScrambleScreen');
  await _tap(
    t,
    find.widgetWithText(OutlinedButton, 'เริ่มใหม่'),
    scrollable: _scroll(_page('WordScrambleScreen')),
  );
  expect(
    find.textContaining(RegExp(r'^ใส่แล้ว 0 จาก \d+ ตัวอักษร$')),
    findsOneWidget,
  );
  await _record(t, 'scramble-reset', 'WordScrambleScreen');
}

Future<void> _speech(WidgetTester t, _Fixture f) async {
  await _mode(t, 'home/learn/speech/speaking', 'SpeakToTextScreen');
  await _record(t, 'speech-ready', 'SpeakToTextScreen');
  await _tap(
    t,
    _key('speech-listen-button'),
    scrollable: _scroll(_page('SpeakToTextScreen')),
  );
  await _wait(t, _key('speech-error'));
  expect(find.textContaining('100%'), findsNothing);
  await _record(t, 'speech-unavailable', 'SpeakToTextScreen');
}

Future<void> _shadowing(WidgetTester t, _Fixture f) async {
  await _mode(t, 'home/learn/speech/shadowing', 'ShadowingChallengeScreen');
  await _record(t, 'shadowing-ready', 'ShadowingChallengeScreen');
  await _tap(
    t,
    _key('shadowing-listen-button'),
    scrollable: _scroll(_page('ShadowingChallengeScreen')),
  );
  await _wait(t, find.text('ระบบรู้จำเสียงไม่พร้อมใช้งาน'));
  await _record(t, 'shadowing-unavailable', 'ShadowingChallengeScreen');
}

Future<void> _camera(WidgetTester t, _Fixture f) async {
  await _drawer(t, 'drawer/practice/object-scanner', 'ObjectScannerScreen');
  await _wait(t, _key('object-scanner-error'));
  await _record(t, 'camera-unavailable', 'ObjectScannerScreen');
  final capture = t.widget<FilledButton>(_key('object-scanner-capture-button'));
  expect(capture.onPressed, isNull);
  await _back(t, 'ChooseModeScreen');
}

Future<void> _export(WidgetTester t, _Fixture f) async {
  await _drawer(t, 'drawer/export/center', 'ExportCenterScreen');
  await _record(t, 'export-ready', 'ExportCenterScreen');
  await _tap(
    t,
    find.widgetWithText(FilledButton, 'สร้างและบันทึกไฟล์'),
    scrollable: _scroll(_page('ExportCenterScreen')),
  );
  for (var i = 0; i < 200 && f.export.artifact == null; i++) {
    await t.pump(const Duration(milliseconds: 25));
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  expect(f.export.artifact, isNotNull);
  expect(f.export.artifact!.bytes, isNotEmpty);
  await t.scrollUntilVisible(
    _key('export-status'),
    220,
    scrollable: _scroll(_page('ExportCenterScreen')),
    maxScrolls: 40,
    continuous: true,
  );
  expect(_key('export-status').hitTestable(), findsOneWidget);
  await _record(t, 'export-fake-store-saved', 'ExportCenterScreen');
  await _back(t, 'ChooseModeScreen');
}

Future<void> _srs(WidgetTester t, _Fixture f) async {
  await _mode(t, 'home/learn/srs', 'SrsFlashcardsScreen');
  await _wait(t, _key('flashcard-reveal-answer'));
  await _record(t, 'srs-front', 'SrsFlashcardsScreen');
  final word = _pairs.singleWhere(
    (pair) => find.text(pair.$1).evaluate().isNotEmpty,
  );
  await _tap(t, find.text(word.$1));
  await _wait(t, find.text(word.$2));
  await _record(t, 'srs-revealed', 'SrsFlashcardsScreen');
}

Future<void> _associative(WidgetTester t, _Fixture f) async {
  await _mode(
    t,
    'home/learn/associative-reading',
    'AssociativeReadingLauncherScreen',
  );
  await _record(t, 'associative-launcher', 'AssociativeReadingLauncherScreen');
  await _tap(
    t,
    find.widgetWithText(FilledButton, 'เริ่มอ่าน'),
    scrollable: _scroll(_page('AssociativeReadingLauncherScreen')),
  );
  await _record(t, 'associative-stage-one', 'AssociativeReadingSessionScreen');
  final next = find.widgetWithText(FilledButton, 'เสร็จแล้ว ไปขั้นถัดไป');
  await _tap(
    t,
    next,
    scrollable: _scroll(_page('AssociativeReadingSessionScreen')),
  );
  await _wait(t, find.text('ขั้นที่ 2: อ่านโดยลดตัวช่วย'));
  expect(find.text('ขั้นที่ 1: อ่านพร้อมตัวช่วย'), findsNothing);
  await _record(t, 'associative-stage-two', 'AssociativeReadingSessionScreen');
}

Set<Feature> _caseOptIns(String name) => switch (name) {
  'today-review-history' => {Feature.dailyContinuity},
  'planning-goal-cancel' ||
  'goal-reminder-picker-cancel' => {Feature.studyPlanning},
  _ => <Feature>{},
};

// Approved examples are synthetic QA content confined to this case's temp DB.
// Real core/artifact SHA256 and the production manifest verifier remain active.
Future<void> _seedReviewedCloze(
  AppDependencies dependencies,
  VocabularyWord word,
  Map<ContentIdentity, Uint8List> artifacts,
) async {
  const examples = <String, String>{
    'station': 'The station is nearby.',
    'book': 'The book is on the table.',
    'house': 'That house is blue.',
    'cat': 'The cat is sleeping.',
    'water': 'Please drink some water.',
    'school': 'The school is open.',
  };
  final identity = ContentIdentity(
    type: ContentType.lexicalMetadata,
    id: word.id,
    revision: 1,
  );
  final bytes = Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'schemaVersion': 1,
        'wordId': word.id,
        'contentRevision': 1,
        'ipa': null,
        'examples': [examples[word.spelling]!],
        'synonyms': <String>[],
        'antonyms': <String>[],
        'audio': null,
      }),
    ),
  );
  artifacts[identity] = bytes;
  const source = 'synthetic-qa:cloze';
  final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: word.categoryId,
    spelling: word.spelling,
    normalizedSpelling: word.normalizedSpelling,
    meaning: word.meaning,
    normalizedMeaning: word.normalizedMeaning,
    partOfSpeech: word.partOfSpeech,
    cefrLevel: word.cefrLevel,
    source: source,
    isGlobal: true,
  );
  final database = dependencies.database!;
  await (database.update(
    database.vocabularyWords,
  )..where((row) => row.id.equals(word.id))).write(
    VocabularyWordsCompanion(
      source: const Value(source),
      isGlobal: const Value(true),
      contentRevision: const Value(1),
      contentChecksumSha256: Value(checksum),
      contentProvenance: Value(ContentProvenance.packaged.name),
      contentReviewState: Value(ContentReviewState.approved.name),
      contentPublicationState: Value(ContentPublicationState.published.name),
    ),
  );
  final now = DateTime.now().toUtc().millisecondsSinceEpoch;
  await database
      .into(database.contentManifests)
      .insert(
        ContentManifestsCompanion.insert(
          id: 'synthetic-qa:lexical:${word.id}:r1',
          contentType: identity.type.name,
          contentId: word.id,
          revision: identity.revision,
          checksumSha256: sha256.convert(bytes).toString(),
          byteLength: bytes.length,
          provenance: ContentProvenance.packaged.name,
          sourceUri: 'fixture://autonomous-ui/lexical/${word.id}/r1.json',
          reviewState: ContentReviewState.approved.name,
          publicationState: ContentPublicationState.published.name,
          createdAtUtcMs: now,
          reviewedAtUtcMs: Value(now),
          publishedAtUtcMs: Value(now),
        ),
      );
  await dependencies.contentManifests!.requireVerified(identity);
  final pinned = await dependencies.vocabulary!.readPinnedByIds([word.id]);
  expect(pinned.single.richMetadata!.examples, [examples[word.spelling]!]);
}

Future<void> _seedDueReview(AppDependencies dependencies) async {
  // The existing learning authority creates evidence and derives its SRS row.
  // Only this synthetic seed clock is historical; device time is unchanged.
  var seedClock = DateTime.now().toUtc().subtract(const Duration(days: 2));
  var sequence = 0;
  final repository = DriftLearningRepository(dependencies.database!);
  final seedLearning = LearningUseCases(
    owners: dependencies.localOwners!,
    repository: repository,
    generateId: () => 'autonomous-srs-seed-${++sequence}',
    nowUtc: () => seedClock,
    buildInfo: const AppBuildInfo(
      version: 'synthetic',
      buildId: 'autonomous-ui',
    ),
  );
  final session = await seedLearning.startQuiz(limit: 1);
  final word = session.questions.single.word;
  seedClock = seedClock.add(const Duration(seconds: 1));
  await seedLearning.recordEvidence(
    sourceEvidenceId: 'attempt:autonomous-srs-seed',
    occurredAtUtc: seedClock,
    sessionId: session.id,
    wordId: word.id,
    promptMode: 'srsRecall',
    isCorrect: true,
    responseTimeMs: 200,
    attemptNumber: 1,
    evidenceContext: EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'srs-recall',
      hintLevel: 0,
      contentRevision: 'built-in-v1',
      engagementAllowed: true,
    ),
  );
  seedClock = seedClock.add(const Duration(seconds: 1));
  await seedLearning.finishSession(session.id);
  final due = await repository.listDueWords(
    ownerId: session.ownerId!,
    nowUtc: DateTime.now().toUtc(),
    limit: 10,
  );
  expect(due.map((entry) => entry.id), [word.id]);
}

final class _ReadOnlyReminderScheduler implements ReminderScheduler {
  int permissionRequests = 0;
  int scheduleCalls = 0;
  int cancelCalls = 0;

  Map<String, int> get callCounts => {
    'requestPermission': permissionRequests,
    'schedule': scheduleCalls,
    'cancel': cancelCalls,
  };

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<ReminderPermissionState> permissionState() async =>
      ReminderPermissionState.unknown;

  @override
  Future<List<ReminderPlatformEntry>> pendingEntries() async => const [];

  @override
  Future<ReminderPermissionState> requestPermission() async {
    permissionRequests++;
    throw StateError('UI fixture must not request notification permission');
  }

  @override
  Future<void> schedule(ReminderScheduleRequest request) async {
    scheduleCalls++;
    throw StateError('UI fixture must not schedule notifications');
  }

  @override
  Future<void> cancel(int platformId) async {
    cancelCalls++;
    throw StateError('UI fixture must not cancel notifications');
  }
}

final class _Fixture {
  _Fixture(
    this.directory,
    this.dependencies,
    this.export,
    this.reminderScheduler,
  );
  final Directory directory;
  final AppDependencies dependencies;
  final HostFakeExportStore export;
  final _ReadOnlyReminderScheduler? reminderScheduler;

  void verifyNoReminderWrites() {
    if (reminderScheduler case final scheduler?) {
      expect(scheduler.permissionRequests, 0);
      expect(scheduler.scheduleCalls, 0);
      expect(scheduler.cancelCalls, 0);
    }
  }

  static Future<_Fixture> create(String caseName) async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-autonomous-ui-',
    );
    final export = HostFakeExportStore();
    final lexicalBytes = <ContentIdentity, Uint8List>{};
    final optIns = _caseOptIns(caseName);
    final reminderScheduler = caseName == 'goal-reminder-picker-cancel'
        ? _ReadOnlyReminderScheduler()
        : null;
    AppDependencies? dependencies;
    try {
      dependencies = await AppBootstrap(
        initializeFirebase: () async =>
            throw StateError('Synthetic QA cloud disabled'),
        initializeSupabase: () async =>
            throw StateError('Synthetic QA cloud disabled'),
        loadConfig: () =>
            throw StateError('Synthetic QA remote config disabled'),
        guestSessionService: _GuestSession(),
        createDatabase: () => AppDatabase(
          NativeDatabase(File('${directory.path}/learning.sqlite')),
        ),
        createEntryStateStore: () async => _GuestEntry(),
        applicationSupportDirectoryProvider: () async =>
            Directory('${directory.path}/support')..createSync(),
        learningTimezoneId: () => 'Asia/Bangkok',
        reminderSchedulerFactory: reminderScheduler == null
            ? null
            : () => reminderScheduler,
        buildFeatureRegistry: BuildFeatureRegistry({
          for (final feature in Feature.values)
            feature: optIns.contains(feature)
                ? FeatureState.enabled
                : const BuildFeatureRegistry.fieldDefaults().stateOf(feature),
        }),
        loadContentArtifactBytes: caseName == 'cloze-mode-and-back'
            ? (identity) async {
                final lexical = lexicalBytes[identity];
                if (lexical != null) return lexical;
                final catalog = OfflineVoicePackManifestCatalog.production;
                return identity.type == ContentType.offlineArtifact &&
                        catalog.resolve(identity) != null
                    ? catalog.requireReceiptBytes(identity)
                    : null;
              }
            : null,
        exportStoreFactory: () => export,
        cameraGatewayFactory: HostFakeCameraGateway.new,
        speechRecognitionGatewayFactory: HostFakeSpeechRecognitionGateway.new,
        cloudSyncEnabled: false,
        buildAiTutor: (_) => throw StateError('Synthetic QA AI disabled'),
        buildVoice: (_) => _SilentVoice(),
      ).initialize();
      final category = await dependencies.vocabulary!.createCategory(
        'Autonomous words',
      );
      for (final (word, meaning) in _pairs) {
        final created = await dependencies.vocabulary!.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: word,
            meaning: meaning,
            partOfSpeech: 'noun',
          ),
        );
        if (caseName == 'cloze-mode-and-back') {
          await _seedReviewedCloze(dependencies, created, lexicalBytes);
        }
      }
      if (caseName == 'srs-reveal') await _seedDueReview(dependencies);
      return _Fixture(directory, dependencies, export, reminderScheduler);
    } catch (_) {
      if (dependencies != null) await dependencies.dispose();
      await _removeCreated(directory);
      rethrow;
    }
  }

  Future<void> close() async {
    await dependencies.dispose();
    await _removeCreated(directory);
  }

  static Future<void> _removeCreated(Directory directory) async {
    if (!await directory.exists()) return;
    final temp = await Directory.systemTemp.resolveSymbolicLinks();
    final resolved = await directory.resolveSymbolicLinks();
    if (!resolved.startsWith(
          '$temp${Platform.pathSeparator}lexiquest-autonomous-ui-',
        ) ||
        Directory(resolved).parent.path != temp) {
      throw StateError('Refuse cleanup outside this fixture temp child');
    }
    await directory.delete(recursive: true);
  }
}

final class _GuestEntry implements AppEntryStateStore {
  @override
  Future<void> clear() async {}
  @override
  Future<void> markGuest() async {}
  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.firebaseUnavailable);
}

final class _SilentVoice implements ManagedVoiceProvider {
  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async =>
      const VoicePlaybackResult(
        requestedEngine: VoiceEngine.nativeTts,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: false,
        cacheHit: false,
      );
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
