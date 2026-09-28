import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/screens/today_hub_screen.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/recommendation/data/drift_recommendation_reader.dart';
import 'package:vocab_learning_app/features/recommendation/domain/active_recall_ladder.dart';
import 'package:vocab_learning_app/features/review/data/drift_review_center_reader.dart';
import 'package:vocab_learning_app/features/today_hub/application/today_hub_use_cases.dart';
import 'package:vocab_learning_app/features/today_hub/data/drift_today_hub_reader.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';

import '../../integration_test/support/native_baseline_cases.dart';
import '../../integration_test/support/native_baseline_fixture.dart';

// Records component delegation only, not routed navigation authority.
class HostTodayActions implements TodayHubActionDelegate {
  int reviews = 0;
  int histories = 0;
  @override
  Future<void> openReview(List<TodayHubReviewWorkItem> work) async {
    expect(work, isEmpty);
    reviews++;
  }

  @override
  Future<void> openHistory() async {
    histories++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected host action: ${invocation.memberName}');
}

class FailOnceToday implements TodayHubSnapshotLoader {
  FailOnceToday(this.delegate);
  final TodayHubSnapshotLoader delegate;
  int calls = 0;
  @override
  Future<TodayHubSnapshot> load() {
    if (++calls == 1) return Future.error(StateError('Synthetic read failure'));
    return delegate.load();
  }
}

// HOST SYNTHETIC only. Uses canonical readers and catalog, never bootstrap,
// native plugins, enrollment, providers or new instructional content.
AppDependencies composeHost(NativeBaselineFixture fixture) {
  final base = baselineDependencies(fixture);
  final modes = buildLessonModeRegistry();
  final identities = DriftReviewOwnerIdentityReader(fixture.database);
  DateTime now() => DateTime.utc(2026, 9, 27);
  final today = TodayHubUseCases(
    activeOwnerId: identities.requireSingleActiveOwnerId,
    reader: DriftTodayHubReader(
      fixture.database,
      reviewReader: DriftReviewCenterReader(fixture.database),
      recommendationUseCases: RecommendationUseCases(
        reader: DriftRecommendationReader(fixture.database),
        nowUtc: now,
        timezoneId: 'Asia/Bangkok',
        activeOwnerId: identities.requireSingleActiveOwnerId,
        modeAvailabilityFor: (mode) => switch (modes.find(mode)) {
          null => RecallLadderModeAvailability.missing,
          final entry when !entry.isDeliverable =>
            RecallLadderModeAvailability.implementedOff,
          final entry when !base.features.isEnabled(entry.feature) =>
            RecallLadderModeAvailability.liveOff,
          _ => RecallLadderModeAvailability.available,
        },
      ),
    ),
    nowUtc: now,
    timezoneId: 'Asia/Bangkok',
  );
  return AppDependencies(
    initialRoute: base.initialRoute,
    runtimeStatus: base.runtimeStatus,
    config: base.config,
    guestSessionService: base.guestSessionService,
    quest: base.quest,
    features: base.features,
    experiments: base.experiments,
    consents: base.consents,
    experimentAssignments: base.experimentAssignments,
    assignedLearningEventContext: base.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider: base.evidencePolicyRolloutModeProvider,
    database: fixture.database,
    localOwners: fixture.owners,
    vocabulary: fixture.vocabulary,
    learnerPreferences: fixture.preferences,
    displayPreferences: fixture.display,
    offlineContent: fixture.offline,
    learning: base.learning,
    lessonModes: modes,
    createLessonController: (adapter) =>
        UnifiedLessonController(learning: base.learning!, adapter: adapter),
    todayHub: today,
    activeOwnerIdentities: identities,
    progress: ProgressUseCases(
      owners: fixture.owners,
      queries: DriftProgressQueries(fixture.database),
      nowUtc: now,
    ),
  );
}

Future<void> settleHost(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
  }
  expect(tester.takeException(), isNull);
}

Future<void> tapHost(WidgetTester tester, String key) async {
  debugPrint('BO action $key');
  final target = find.byKey(ValueKey(key));
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await settleHost(tester);
  await tester.tap(target);
  await settleHost(tester);
}

Future<void> captureHost(WidgetTester tester, String name) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('bo-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    final file = File(
      'docs/development/ux-delivery/evidence/S01-BO-runs/host-renders/$name.png',
    );
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes.buffer.asUint8List());
    image.dispose();
  });
  debugPrint('BO HOST SYNTHETIC captured $name');
}

void main() {
  setUpAll(() async {
    timezone_data.initializeTimeZones();
    await (FontLoader('NotoSansThai')
          ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'BO host canonical composition ${scale}x',
      (tester) async {
        final shadows = debugDisableShadows;
        debugDisableShadows = false;
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        SharedPreferences.setMockInitialValues({});
        final fixture = (await tester.runAsync(() async {
          final root = await Directory.systemTemp.createTemp('bo-host-');
          final fixture = await NativeBaselineFixture.open(
            root,
            'bm-bo-host',
            seed: true,
          );
          await fixture.seed();
          await fixture.changePreferenceAndCreateWord(changeDisplay: false);
          return fixture;
        }))!;
        final dependencies = composeHost(fixture);
        final semantics = tester.ensureSemantics();
        final previousNetwork = HttpOverrides.current;
        HttpOverrides.global = fixture.network;
        try {
          final before = await baselineAwait(tester, fixture.snapshot);
          final today = await baselineAwait(
            tester,
            dependencies.todayHub!.load,
          );
          expect(
            today.dependencyStates[TodayHubDependency.identity],
            TodayHubDependencyState.ready,
          );
          expect(today.resumableSession, isNull);
          final profile = await baselineAwait(
            tester,
            dependencies.progress!.loadPersonalLearningProfile,
          );
          expect(profile.isEmpty, isTrue);
          expect(
            dependencies.lessonModes!.resolve(LessonMode.matching),
            isNull,
          );
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('bo-capture'),
              child: MyApp(dependencies: dependencies, ownsDependencies: false),
            ),
          );
          await settleHost(tester);
          expect(
            dependencies.features.isVisible(Feature.dailyContinuity),
            isFalse,
          );
          expect(
            dependencies.hasComposedDependencyFor(Feature.dailyContinuity),
            isFalse,
          );
          expect(
            find.byKey(const ValueKey('today-unavailable-practice')),
            findsOneWidget,
          );
          await tapHost(tester, 'today-unavailable-practice');
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            1,
          );
          expect(find.byKey(const ValueKey('learn-starter')), findsOneWidget);
          await captureHost(tester, '02-learn-starter-${scale}x');
          await tapHost(tester, 'learn-show-all-modes');
          expect(
            find.byKey(const ValueKey('home/learn/quiz/matching')),
            findsNothing,
          );
          await tester.ensureVisible(
            find.byKey(const ValueKey('home/learn/quiz')),
          );
          await settleHost(tester);
          await captureHost(tester, '03-learn-catalog-${scale}x');
          await tapHost(tester, 'home/learn/quiz');
          await captureHost(tester, '04-mode-entry-${scale}x');
          expect(
            find.byKey(const ValueKey('session-configuration-sheet')),
            findsOneWidget,
          );
          // Traverse actual host focus stops without starting a lesson.
          var closeFocused = false;
          for (var i = 0; i < 12 && !closeFocused; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
              element,
            ) {
              if (element.widget.key ==
                  const ValueKey('session-config-close')) {
                closeFocused = true;
              }
              return true;
            });
          }
          expect(closeFocused, isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await settleHost(tester);
          expect(
            find.byKey(const ValueKey('session-configuration-sheet')),
            findsNothing,
          );
          await settleHost(tester);
          await tapHost(tester, 'home/profile');
          expect(find.text('ผู้เรียนในเครื่อง'), findsOneWidget);
          expect(
            find.text('ยังไม่มีหลักฐานการเรียนสำหรับโปรไฟล์นี้'),
            findsOneWidget,
          );
          expect(find.text('ไม่สามารถอ่านข้อมูลในเครื่องได้'), findsNothing);
          await captureHost(tester, '05-profile-loaded-${scale}x');
          await tapHost(tester, 'profile-learning-details');
          await tester.ensureVisible(find.text('รายละเอียดการเรียน'));
          await settleHost(tester);
          await captureHost(tester, '06-profile-details-${scale}x');
          await tapHost(tester, 'profile-learning-details');
          await tapHost(tester, 'profile-open-mastery');
          await captureHost(tester, '07-profile-overview-${scale}x');
          await tester.tap(find.byType(BackButton));
          await settleHost(tester);
          expect(find.text('ผู้เรียนในเครื่อง'), findsOneWidget);
          // Isolated success component; parent feature/composition gates remain closed.
          final actions = HostTodayActions();
          final componentLoader = FailOnceToday(dependencies.todayHub!);
          var practiceCalls = 0;
          await tester.pumpWidget(
            RepaintBoundary(
              key: const ValueKey('bo-capture'),
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: M3Theme.lightTheme,
                home: TodayHubScreen(
                  useCases: componentLoader,
                  actions: actions,
                  // Component-only enabled prerequisite, as existing Today unit
                  // tests. Does not change AppDependencies or runtime flags and
                  // does not assert routed composition/production availability.
                  features: const BuildFeatureRegistry({
                    Feature.dailyContinuity: FeatureState.enabled,
                    Feature.quiz: FeatureState.enabled,
                  }),
                  assessmentAvailable: false,
                  onOpenPractice: () => practiceCalls++,
                ),
              ),
            ),
          );
          await settleHost(tester);
          expect(find.text('ไม่สามารถโหลดรายการวันนี้ได้'), findsOneWidget);
          await captureHost(tester, '09-today-component-error-${scale}x');
          await tapHost(tester, 'today-hub-retry');
          expect(componentLoader.calls, 2);
          expect(find.byKey(const ValueKey('today-hub-view')), findsOneWidget);
          await captureHost(tester, '01-today-component-loaded-${scale}x');
          await tapHost(tester, 'today-hub-manual-practice');
          expect(practiceCalls, 1);
          await tapHost(tester, 'today-hub-open-review');
          expect(actions.reviews, 1);
          await tester.ensureVisible(
            find.byKey(const ValueKey('today-hub-open-history')),
          );
          await settleHost(tester);
          await captureHost(tester, '08-today-component-lower-${scale}x');
          await tapHost(tester, 'today-hub-open-history');
          expect(actions.histories, 1);
          expect(
            dependencies.features.isVisible(Feature.dailyContinuity),
            isFalse,
          );
          final after = await baselineAwait(tester, fixture.snapshot);
          expect(
            after,
            before,
            reason:
                'Navigation must not create learning/research or mutate synthetic vocabulary',
          );
          expect(fixture.network.calls, 0);
        } finally {
          HttpOverrides.global = previousNetwork;
          debugDisableShadows = shadows;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 1));
          semantics.dispose();
          (dependencies.features as RuntimeFeatureRegistry).dispose();
          dependencies.quest.dispose();
          await baselineAwait(tester, fixture.close);
        }
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
}
