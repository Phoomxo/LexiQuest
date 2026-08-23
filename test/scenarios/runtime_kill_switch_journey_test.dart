import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/runtime/runtime_feature_override_store.dart';
import 'package:vocab_learning_app/screens/ai_tutor_screen.dart';
import 'package:vocab_learning_app/screens/ai_tutor_settings_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  test(
    'file-backed permanent clear and TTL controls converge across restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-kill-switch-',
      );
      final file = File(
        '${directory.path}${Platform.pathSeparator}runtime.sqlite',
      );
      final clock = _UtcClock(DateTime.utc(2026, 8, 11, 12));
      final harnesses = <_RuntimeHarness>[];
      addTearDown(() async {
        for (final harness in harnesses.reversed) {
          await harness.close();
        }
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      final first = await _RuntimeHarness.open(file, clock);
      harnesses.add(first);
      await first.controls.emergencyOff(
        Feature.aiTutor,
        source: 'field-operator',
      );
      expect(
        first.registry.stateOf(Feature.aiTutor),
        FeatureState.emergencyOff,
      );
      await first.close();

      final restarted = await _RuntimeHarness.open(file, clock);
      harnesses.add(restarted);
      expect(
        restarted.registry.stateOf(Feature.aiTutor),
        FeatureState.emergencyOff,
      );
      await restarted.controls.clear(Feature.aiTutor);
      expect(restarted.registry.stateOf(Feature.aiTutor), FeatureState.limited);
      await restarted.close();

      final clearedRestart = await _RuntimeHarness.open(file, clock);
      harnesses.add(clearedRestart);
      expect(
        clearedRestart.registry.stateOf(Feature.aiTutor),
        FeatureState.limited,
        reason: 'clear must durably restore the immutable build default',
      );
      expect(await clearedRestart.store.load(nowUtc: clock.now), isEmpty);

      final expiresAt = clock.now.add(const Duration(hours: 1));
      await clearedRestart.controls.emergencyOff(
        Feature.aiTutor,
        source: 'field-operator',
        expiresAtUtc: expiresAt,
      );
      await clearedRestart.close();
      clock.now = clock.now.add(const Duration(minutes: 30));

      final ttlRestart = await _RuntimeHarness.open(file, clock);
      harnesses.add(ttlRestart);
      expect(
        ttlRestart.registry.stateOf(Feature.aiTutor),
        FeatureState.emergencyOff,
      );
      expect(ttlRestart.scheduler.entries, hasLength(1));
      expect(
        ttlRestart.scheduler.entries.single.delay,
        const Duration(minutes: 30),
      );

      clock.now = expiresAt;
      ttlRestart.scheduler.entries.single.callback();
      await _flushRuntimeCallbacks();

      expect(
        ttlRestart.registry.stateOf(Feature.aiTutor),
        FeatureState.limited,
      );
      expect(await ttlRestart.store.load(nowUtc: clock.now), isEmpty);
    },
  );

  testWidgets('emergency off replaces an already-mounted AI settings route', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
    );
    final controls = RuntimeFeatureControls(
      store: RuntimeFeatureOverrideStore(database),
      registry: registry,
      nowUtc: () => DateTime.utc(2026, 8, 11, 12),
    );
    final tutor = _RecordingAiTutorController();
    addTearDown(() async {
      controls.dispose();
      registry.dispose();
      await database.close();
    });
    await controls.initialize();
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database, registry, aiTutor: tutor),
        child: MaterialApp(
          home: ProductionFeatureGate(
            feature: Feature.aiTutor,
            registry: registry,
            builder: (_) =>
                AiTutorScreen(aiTutor: tutor, featureRegistry: registry),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('AI provider settings'));
    await tester.pumpAndSettle();
    expect(find.byType(AiTutorSettingsScreen), findsOneWidget);
    final callsBeforeKill = tutor.totalCalls;

    await tester.runAsync(
      () => controls.emergencyOff(Feature.aiTutor, source: 'field-operator'),
    );
    await tester.pump();

    expect(find.byType(AiTutorSettingsScreen), findsNothing);
    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    expect(find.byKey(const ValueKey('ai-save-key')), findsNothing);
    expect(tutor.totalCalls, callsBeforeKill);
  });

  testWidgets(
    'production entry live route direct route and restart all fail closed',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('lexiquest-kill-ui-'),
      ))!;
      final file = File(
        '${directory.path}${Platform.pathSeparator}runtime.sqlite',
      );
      final clock = _UtcClock(DateTime.utc(2026, 8, 11, 12));
      final harnesses = <_RuntimeHarness>[];
      addTearDown(() async {
        for (final harness in harnesses.reversed) {
          await harness.close();
        }
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      final first = (await tester.runAsync(
        () => _RuntimeHarness.open(file, clock),
      ))!;
      harnesses.add(first);
      await _pumpProductionShell(tester, first);
      await _openDrawer(tester);
      final entry = find.byKey(const ValueKey<String>('drawer/ai-tutor/chat'));
      await tester.scrollUntilVisible(
        entry,
        150,
        scrollable: find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(Scrollable),
        ),
      );
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(AiTutorScreen), findsOneWidget);

      await tester.runAsync(
        () => first.controls.emergencyOff(
          Feature.aiTutor,
          source: 'field-operator',
        ),
      );
      await tester.pump();
      expect(find.byType(AiTutorScreen), findsNothing);
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await _openDrawer(tester);
      expect(entry, findsNothing);
      await Navigator.of(
        tester.element(find.byType(MainNavigationScreen)),
      ).maybePop();
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(first.close);

      final restarted = (await tester.runAsync(
        () => _RuntimeHarness.open(file, clock),
      ))!;
      harnesses.add(restarted);
      await _pumpProductionShell(tester, restarted);
      await _openDrawer(tester);
      expect(entry, findsNothing);
      await Navigator.of(
        tester.element(find.byType(MainNavigationScreen)),
      ).maybePop();
      await tester.pumpAndSettle();

      var directBuilds = 0;
      Navigator.of(tester.element(find.byType(MainNavigationScreen)))
          .push<void>(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'ai-tutor/chat'),
              builder: (_) => ProductionFeatureGate(
                feature: Feature.aiTutor,
                registry: restarted.registry,
                builder: (_) {
                  directBuilds += 1;
                  return AiTutorScreen(featureRegistry: restarted.registry);
                },
              ),
            ),
          )
          .ignore();
      await tester.pumpAndSettle();
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(AiTutorScreen), findsNothing);
      expect(directBuilds, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.runAsync(() => restarted.controls.clear(Feature.aiTutor));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(restarted.close);

      final clearedRestart = (await tester.runAsync(
        () => _RuntimeHarness.open(file, clock),
      ))!;
      harnesses.add(clearedRestart);
      await _pumpProductionShell(tester, clearedRestart);
      await _openDrawer(tester);
      await tester.scrollUntilVisible(
        entry,
        150,
        scrollable: find.descendant(
          of: find.byType(Drawer),
          matching: find.byType(Scrollable),
        ),
      );
      expect(entry, findsOneWidget);
    },
  );
}

Future<void> _pumpProductionShell(
  WidgetTester tester,
  _RuntimeHarness harness,
) async {
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: _dependencies(harness.database, harness.registry),
      child: MaterialApp(
        home: MainNavigationScreen(featureRegistry: harness.registry),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppDependencies _dependencies(
  AppDatabase database,
  FeatureRegistry features, {
  AiTutorController? aiTutor,
}) {
  final research = InertResearchDependencies(database);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    guestSessionService: _GuestSessionService(),
    quest: testQuestUseCases(),
    features: features,
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    aiTutor: aiTutor ?? _RecordingAiTutorController(),
  );
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('legacy-drawer-button')));
  await tester.pumpAndSettle();
}

Future<void> _flushRuntimeCallbacks() async {
  for (var turn = 0; turn < 10; turn += 1) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class _UtcClock {
  _UtcClock(this.now);

  DateTime now;
}

final class _RuntimeHarness {
  _RuntimeHarness._({
    required this.database,
    required this.registry,
    required this.store,
    required this.controls,
    required this.scheduler,
  });

  final AppDatabase database;
  final RuntimeFeatureRegistry registry;
  final RuntimeFeatureOverrideStore store;
  final RuntimeFeatureControls controls;
  final _ManualExpiryScheduler scheduler;
  bool _closed = false;

  static Future<_RuntimeHarness> open(File file, _UtcClock clock) async {
    final database = AppDatabase(NativeDatabase(file));
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
    );
    final store = RuntimeFeatureOverrideStore(database);
    final scheduler = _ManualExpiryScheduler();
    final controls = RuntimeFeatureControls(
      store: store,
      registry: registry,
      nowUtc: () => clock.now,
      scheduleExpiry: scheduler.schedule,
    );
    await controls.initialize();
    return _RuntimeHarness._(
      database: database,
      registry: registry,
      store: store,
      controls: controls,
      scheduler: scheduler,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    controls.dispose();
    registry.dispose();
    await database.close();
  }
}

final class _ManualExpiryScheduler {
  final List<_ScheduledExpiry> entries = [];

  RuntimeFeatureTimerCancellation schedule(
    Duration delay,
    void Function() callback,
  ) {
    final entry = _ScheduledExpiry(delay, callback);
    entries.add(entry);
    return entry.cancel;
  }
}

final class _ScheduledExpiry {
  _ScheduledExpiry(this.delay, this.callback);

  final Duration delay;
  final void Function() callback;
  bool cancelled = false;

  void cancel() => cancelled = true;
}

final class _RecordingAiTutorController implements AiTutorController {
  int totalCalls = 0;

  @override
  Future<void> clearUsage() async => totalCalls += 1;

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    required AiProviderId providerId,
    required String model,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) async => totalCalls += 1;

  @override
  Future<void> configureActiveModel({
    required String model,
    required bool shareLearningSummary,
    AiCancellation? cancellation,
  }) async => totalCalls += 1;

  @override
  Future<void> dispose() async => totalCalls += 1;

  @override
  Future<List<AiModel>> listModels({
    required AiProviderId providerId,
    required String key,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) async {
    totalCalls += 1;
    return const [];
  }

  @override
  Future<List<AiModel>> listModelsForActiveCredential({
    AiCancellation? cancellation,
  }) async {
    totalCalls += 1;
    return const [];
  }

  @override
  Future<AiTutorSettingsStatus> loadSettings() async {
    totalCalls += 1;
    return const AiTutorSettingsStatus(
      hasKey: false,
      providerConsent: false,
      shareLearningSummary: false,
      providerId: AiProviderId.gemini,
      model: null,
    );
  }

  @override
  Future<List<AiUsageSummary>> loadUsage() async {
    totalCalls += 1;
    return const [];
  }

  @override
  Future<void> removeKey() async => totalCalls += 1;

  @override
  Future<AiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    AiCancellation? cancellation,
  }) {
    totalCalls += 1;
    throw UnimplementedError();
  }

  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async => totalCalls += 1;
}

final class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'runtime-kill-switch');
}
