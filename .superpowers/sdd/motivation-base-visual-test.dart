// Ignored, local visual QA fixture. Not production source or a golden baseline.
// Created 2026-09-08; execute only after implementation writers release Flutter.
// Run from C:/Users/Phet/.codex/worktrees/02fa/LexiQuest after writers stop:
// & 'C:/Users/Phet/AppData/Local/Programs/flutter/bin/flutter.bat' test --no-pub --concurrency=1 '.superpowers/sdd/approved-ui-visual-test.dart' --reporter expanded
// 390x844 only: add --plain-name 'approved UI visual 390x844'
// PNGs + capture metadata: build/verification/ui-implementation-20260908/visual
// Real MyApp/routes/M3Theme/fonts; synthetic in-memory DB, real Drift use cases.
// No cloud bootstrap, phone, participant enrollment, uploads, fabricated scores,
// learned history, earned rewards or personalized recommendation fixtures.
// Captures inspect layout only, not physical-device/TalkBack or learning efficacy.

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
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_session_configuration_store.dart';
import 'package:vocab_learning_app/features/learning/presentation/session_configuration_sheet.dart';
import 'package:vocab_learning_app/features/preferences/application/display_preferences_controller.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/data/drift_learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/screens/avatar_equipment_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/screens/quest_status_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../../test/support/inert_research_dependencies.dart';

const _captureKey = ValueKey<String>('approved-ui-visual-boundary');
const _output = 'build/verification/motivation-ui-20260908/visual/c1/base';
final _fixtureNow = DateTime.utc(2026, 9, 8, 8);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    timezone_data.initializeTimeZones();
    // Same asset-loading pattern as existing Adventure/Pair golden tests.
    final thaiFont = FontLoader(M3Theme.thaiFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait<void>([thaiFont.load(), icons.load()]);
  });

  for (final spec in <({String name, Size size, double scale})>[
    (name: '390x844', size: const Size(390, 844), scale: 1),
    (name: '360x800-text200', size: const Size(360, 800), scale: 2),
  ]) {
    testWidgets('approved UI visual ${spec.name}', (tester) async {
      final previousShadowDebug = debugDisableShadows;
      addTearDown(() => debugDisableShadows = previousShadowDebug);
      tester.view.physicalSize = spec.size;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 16);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 16);
      tester.platformDispatcher.textScaleFactorTestValue = spec.scale;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final fixture = await tester.runAsync(_VisualFixture.create);
      expect(fixture, isNotNull);
      final captured = <String>[];
      try {
        debugDisableShadows = false;
        await tester.pumpWidget(
          RepaintBoundary(
            key: _captureKey,
            child: MyApp(
              dependencies: fixture!.dependencies,
              ownsDependencies: false,
            ),
          ),
        );
        await _settle(tester);
        expect(find.byType(MainNavigationScreen), findsOneWidget);
        final primaryRoute = ModalRoute.of(
          tester.element(find.byType(MainNavigationScreen)),
        );
        final material = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(material.theme!.useMaterial3, isTrue);
        expect(
          material.theme!.textTheme.bodyMedium!.fontFamily,
          M3Theme.thaiFontFamily,
        );

        // Capture actual initial destination separately; do not mask a bad
        // default by first tapping Learning. Works before/after Task3 changes.
        await _capture(tester, '${spec.name}-00-initial', spec.size, captured);
        await _tapKey(tester, 'home/learn');
        expect(find.byType(ChooseModeScreen), findsOneWidget);
        await _capture(tester, '${spec.name}-01-learning', spec.size, captured);

        final mode = find.byKey(const ValueKey<String>('home/learn/quiz'));
        await tester.scrollUntilVisible(
          mode,
          130,
          scrollable: find
              .descendant(
                of: find.byType(ChooseModeScreen),
                matching: find.byType(Scrollable),
              )
              .first,
          maxScrolls: 24,
        );
        await tester.ensureVisible(mode);
        // ensureVisible updates the scroll position; render its new frame
        // before deriving tap coordinates (especially for tall Thai tiles).
        await _settle(tester);
        expect(mode.hitTestable(), findsOneWidget);
        await tester.tap(mode);
        await _settle(tester);
        expect(find.byType(SessionConfigurationSheet), findsOneWidget);
        await _capture(tester, '${spec.name}-02-session', spec.size, captured);

        // Final accepted UI must expose the optional configuration controls.
        final advanced = find.text('ปรับตัวเลือก');
        expect(advanced, findsOneWidget);
        await tester.ensureVisible(advanced);
        await tester.tap(advanced);
        await _settle(tester);
        await _capture(
          tester,
          '${spec.name}-03-session-options',
          spec.size,
          captured,
        );
        final start = find.byKey(const ValueKey('session-config-start'));
        await tester.ensureVisible(start);
        await _settle(tester);
        expect(start.hitTestable(), findsOneWidget);
        await _capture(
          tester,
          '${spec.name}-04-session-start-reachable',
          spec.size,
          captured,
        );

        // Exercise the real modal with simulated IME occlusion. This verifies
        // Flutter layout/taps, not a native keyboard or physical-device result.
        final countInput = find.byKey(const ValueKey('session-item-count'));
        await tester.ensureVisible(countInput);
        await tester.showKeyboard(countInput);
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        await _settle(tester);
        await Scrollable.ensureVisible(tester.element(start), alignment: 0);
        await _settle(tester);
        expect(start.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(start).bottom,
          lessThanOrEqualTo(spec.size.height - 300),
        );

        // Close the real route, do not start a learning activity or manufacture
        // progress to make reward/mastery pages look populated.
        final close = find
            .descendant(
              of: find.byType(SessionConfigurationSheet),
              matching: find.byIcon(Icons.close),
            )
            .first;
        await tester.ensureVisible(close);
        expect(
          tester.getRect(close).bottom,
          lessThanOrEqualTo(spec.size.height - 300),
        );
        await tester.tap(close);
        await _settle(tester);
        expect(find.byType(SessionConfigurationSheet), findsNothing);
        tester.testTextInput.hide();
        tester.view.resetViewInsets();
        await _settle(tester);

        await _tapKey(tester, 'home/mastery');
        expect(find.byType(MasteryDashboardScreen), findsOneWidget);
        expect(
          find.text('ไม่สามารถอ่านประวัติการเรียนในเครื่องได้'),
          findsNothing,
        );
        await _capture(
          tester,
          '${spec.name}-05-mastery-no-evidence',
          spec.size,
          captured,
        );
        await _tapKey(tester, 'home/achievements');
        expect(find.byType(AchievementsScreen), findsOneWidget);
        await _capture(
          tester,
          '${spec.name}-06-rewards-no-evidence',
          spec.size,
          captured,
        );
        await _tapScrollKey(
          tester,
          'rewards-open-quests',
          find.byType(AchievementsScreen),
        );
        expect(find.byType(QuestStatusScreen), findsOneWidget);
        expect(find.byType(QuestStatusEmpty), findsOneWidget);
        expect(find.byType(QuestStatusFailure), findsNothing);
        expect(find.byType(QuestStatusUnavailable), findsNothing);
        expect(
          ModalRoute.of(
            tester.element(find.byType(QuestStatusScreen)),
          )!.settings.name,
          'rewards/quests',
        );
        await _capture(tester, '${spec.name}-06a-quests', spec.size, captured);
        await tester.pageBack();
        await _settle(tester);
        await _tapScrollKey(
          tester,
          'rewards-open-shop',
          find.byType(AchievementsScreen),
        );
        expect(find.byType(AvatarEquipmentScreen), findsOneWidget);
        expect(
          find.text('ไม่สามารถอ่านข้อมูลรางวัลในเครื่องได้'),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.label == 'เหรียญคงเหลือ 0 เหรียญ',
          ),
          findsOneWidget,
        );
        expect(
          ModalRoute.of(
            tester.element(find.byType(AvatarEquipmentScreen)),
          )!.settings.name,
          'rewards/shop',
        );
        await _capture(tester, '${spec.name}-06b-shop', spec.size, captured);
        await tester.pageBack();
        await _settle(tester);
        await _tapKey(tester, 'home/profile');
        expect(find.byType(ProfileSettingsScreen), findsOneWidget);
        expect(find.text('ไม่สามารถอ่านข้อมูลในเครื่องได้'), findsNothing);
        await _capture(tester, '${spec.name}-07-profile', spec.size, captured);
        await _tapScrollKey(
          tester,
          'profile-open-mastery',
          find.byType(ProfileSettingsScreen),
        );
        expect(find.byType(MasteryDashboardScreen), findsOneWidget);
        expect(find.byType(ProfileSettingsScreen), findsNothing);
        expect(
          ModalRoute.of(tester.element(find.byType(MasteryDashboardScreen))),
          same(primaryRoute),
          reason:
              'Profile must select the retained primary page, not push a duplicate.',
        );
        expect(
          find.byKey(const ValueKey('mastery-open-review')),
          findsNothing,
          reason:
              'This fixture deliberately has no composed Today/review authority.',
        );
        await _capture(
          tester,
          '${spec.name}-07a-profile-to-mastery',
          spec.size,
          captured,
        );
        await _tapScrollKey(
          tester,
          'home/weakness',
          find.byType(MasteryDashboardScreen),
        );
        expect(find.byType(WeaknessClinicScreen), findsOneWidget);
        expect(
          ModalRoute.of(
            tester.element(find.byType(WeaknessClinicScreen)),
          )!.settings.name,
          'home/weakness',
        );
        await _capture(
          tester,
          '${spec.name}-07b-weakness',
          spec.size,
          captured,
        );
        await tester.pageBack();
        await _settle(tester);

        await _tapKey(tester, 'legacy-drawer-button');
        await _capture(tester, '${spec.name}-08-drawer', spec.size, captured);
        final settings = find.byKey(const ValueKey<String>('drawer/settings'));
        await tester.scrollUntilVisible(
          settings,
          150,
          scrollable: find
              .descendant(
                of: find.byType(Drawer),
                matching: find.byType(Scrollable),
              )
              .first,
          maxScrolls: 24,
        );
        await tester.ensureVisible(settings);
        await tester.tap(settings);
        await _settle(tester);
        expect(find.byType(SettingScreen), findsOneWidget);
        await _capture(tester, '${spec.name}-09-settings', spec.size, captured);

        await tester.runAsync(() async {
          final metadata = <String, Object?>{
            'fixture': 'approved-ui-visual-test.dart',
            'fixtureSha256': crypto.sha256
                .convert(
                  await File(
                    '.superpowers/sdd/approved-ui-visual-test.dart',
                  ).readAsBytes(),
                )
                .toString(),
            'capturedAtUtc': DateTime.now().toUtc().toIso8601String(),
            'viewport': [spec.size.width, spec.size.height],
            'textScale': spec.scale,
            'data':
                'Synthetic local owner and vocabulary; no learning evidence',
            'shell':
                'Actual MyApp/MainNavigationScreen and real routed screens',
            'fonts': ['NotoSansThai asset', 'MaterialIcons asset'],
            'network':
                'No external bootstrap, sync or research runtime composed',
            'limitations': [
              'Widget renderer, not physical-device or assistive-technology UAT',
              'No Today/Adventure/research enrollment/offline downloads composed',
              'No screenshot implies a reward was earned or a lesson completed',
              'Inspect all PNGs; successful capture alone is not visual approval',
            ],
            'captures': captured,
          };
          await File(
            '$_output/${spec.name}-capture.json',
          ).writeAsString(const JsonEncoder.withIndent('  ').convert(metadata));
        });
      } finally {
        try {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          if (fixture != null) await _closeFixture(tester, fixture);
        } finally {
          // Flutter verifies painting flags before registered tearDown hooks.
          debugDisableShadows = previousShadowDebug;
        }
      }
    });
  }
}

Future<void> _closeFixture(WidgetTester tester, _VisualFixture fixture) async {
  var closed = false;
  Object? closeError;
  fixture.close().then(
    (_) => closed = true,
    onError: (Object error) {
      closeError = error;
      closed = true;
    },
  );
  // Native database completion may cross the real and fake test clocks.
  // Pump both while closing, and fail with evidence instead of hanging.
  for (var attempt = 0; attempt < 160 && !closed; attempt++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(closeError, isNull, reason: 'Synthetic database disposal failed.');
  expect(closed, isTrue, reason: 'Synthetic database disposal did not finish.');
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey<String>(key));
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _tapScrollKey(
  WidgetTester tester,
  String key,
  Finder screen,
) async {
  final target = find.byKey(ValueKey<String>(key));
  await tester.scrollUntilVisible(
    target,
    150,
    scrollable: find
        .descendant(of: screen, matching: find.byType(Scrollable))
        .first,
    maxScrolls: 30,
  );
  await tester.ensureVisible(target);
  await _settle(tester);
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  // Real Drift native IO may complete outside the fake test clock. Bound both
  // frame and IO waits; a spinner/error fails capture rather than being hidden.
  var quietFrames = 0;
  for (var index = 0; index < 160; index++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    expect(tester.takeException(), isNull);
    final loading = find
        .byType(CircularProgressIndicator)
        .evaluate()
        .isNotEmpty;
    quietFrames = !loading && !tester.binding.hasScheduledFrame
        ? quietFrames + 1
        : 0;
    if (quietFrames >= 3) return;
  }
  fail('Visual fixture did not settle within 160 bounded frames.');
}

Future<void> _capture(
  WidgetTester tester,
  String name,
  Size expected,
  List<String> captured,
) async {
  await tester.pump();
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final path = '$_output/$name.png';
  await tester.runAsync(() async {
    final bitmap = await boundary.toImage(pixelRatio: 1);
    try {
      expect(bitmap.width, expected.width.toInt());
      expect(bitmap.height, expected.height.toInt());
      final png = await bitmap.toByteData(format: ui.ImageByteFormat.png);
      expect(png, isNotNull);
      await Directory(_output).create(recursive: true);
      await File(path).writeAsBytes(png!.buffer.asUint8List());
    } finally {
      bitmap.dispose();
    }
  });
  captured.add(path);
}

final class _VisualFixture {
  _VisualFixture(this.database, this.display, this.dependencies);
  final AppDatabase database;
  final DisplayPreferencesController display;
  final AppDependencies dependencies;
  bool _closed = false;

  static Future<_VisualFixture> create() async {
    final database = AppDatabase(NativeDatabase.memory());
    var sequence = 0;
    String nextId() => 'synthetic:visual:${++sequence}';
    DateTime now() => _fixtureNow;
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: nextId,
      nowUtc: now,
    );
    final vocabularyRepository = DriftVocabularyRepository(database);
    final vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: vocabularyRepository,
      generateId: nextId,
      nowUtc: now,
    );
    final category = await vocabulary.createCategory(
      'คำศัพท์ตัวอย่างสำหรับตรวจหน้าจอ',
    );
    for (final pair in const <(String, String)>[
      ('book', 'หนังสือ'),
      ('learn', 'เรียนรู้'),
      ('friend', 'เพื่อน'),
    ]) {
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: pair.$1,
          meaning: pair.$2,
          partOfSpeech: 'ตัวอย่าง',
          source: 'synthetic-visual-qa',
        ),
      );
    }
    const build = AppBuildInfo(
      version: '1.0.0',
      buildId: 'synthetic-visual-qa',
    );
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(
        database,
        lexicalVocabulary: vocabularyRepository,
      ),
      generateId: nextId,
      nowUtc: now,
      buildInfo: build,
    );
    final progress = ProgressUseCases(
      owners: owners,
      queries: DriftProgressQueries(database),
      nowUtc: now,
    );
    try {
      expect((await progress.loadPersonalLearningProfile()).isEmpty, isTrue);
    } catch (_) {
      await database.close();
      rethrow;
    }
    final preferences = LearnerPreferencesUseCases(
      repository: DriftLearnerPreferencesRepository(database),
      owners: owners,
      nowUtc: now,
    );
    final display = DisplayPreferencesController(preferences);
    await display.initialize();
    await display.selectThemeMode(ThemeMode.light);
    final research = InertResearchDependencies(database);
    final dependencies = AppDependencies(
      initialRoute: AppRoute.home,
      buildInfo: build,
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
        aiTutor: RuntimeAvailability.unavailable,
        voice: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: const _SyntheticGuestSession(),
      features: const BuildFeatureRegistry(<Feature, FeatureState>{
        Feature.vocabulary: FeatureState.enabled,
        Feature.quiz: FeatureState.enabled,
        Feature.srs: FeatureState.enabled,
        Feature.reading: FeatureState.enabled,
        Feature.mastery: FeatureState.enabled,
        Feature.weakness: FeatureState.enabled,
        Feature.achievements: FeatureState.enabled,
        Feature.shop: FeatureState.enabled,
        Feature.questV2: FeatureState.enabled,
      }),
      experiments: research.experiments,
      consents: research.consents,
      experimentAssignments: research.experimentAssignments,
      assignedLearningEventContext: research.assignedLearningEventContext,
      evidencePolicyRolloutModeProvider:
          research.evidencePolicyRolloutModeProvider,
      database: database,
      localOwners: owners,
      vocabulary: vocabulary,
      learning: learning,
      lessonModes: buildLessonModeRegistry(),
      createLessonController: (adapter) =>
          UnifiedLessonController(learning: learning, adapter: adapter),
      currentActivityEvidence: CurrentActivityEvidenceAdapter(
        learning: learning,
      ),
      sessionConfigurations: DriftSessionConfigurationStore(database),
      associativeLearning: InMemoryAssociativeLearningAdapter(),
      progress: progress,
      learnerPreferences: preferences,
      displayPreferences: display,
      researchConsent: ResearchConsentUseCases(
        owners: owners,
        repository: DriftResearchConsentRepository(database),
        nowUtc: now,
      ),
      quest: QuestUseCases(
        repository: DriftQuestRepository(database),
        owners: owners,
        generateId: nextId,
        nowUtc: now,
        timezoneId: 'Asia/Bangkok',
      ),
      rewards: RewardUseCases(
        owners: owners,
        repository: DriftRewardRepository(database),
        progress: progress,
        generateId: nextId,
        nowUtc: now,
      ),
    );
    return _VisualFixture(database, display, dependencies);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    display.dispose();
    await database.close();
  }
}

final class _SyntheticGuestSession implements GuestSessionService {
  const _SyntheticGuestSession();
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-visual-qa');
}
