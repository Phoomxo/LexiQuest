import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  testWidgets('S01-AB live emergency-off recovery returns to parent without enabling', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final registry = RuntimeFeatureRegistry(const BuildFeatureRegistry({Feature.questV2: FeatureState.enabled}));
    addTearDown(registry.dispose);
    final navigator = GlobalKey<NavigatorState>();
    var builds = 0;
    await tester.pumpWidget(AppDependenciesScope(
      dependencies: _dependencies(db, registry),
      child: MaterialApp(navigatorKey: navigator, home: const Scaffold(body: Text('safe parent'))),
    ));
    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => ProductionFeatureGate(
      feature: Feature.questV2, registry: registry, builder: (_) {
        builds++;
        return const Scaffold(body: Text('live quest'));
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('live quest'), findsOneWidget);
    final before = builds;
    registry.emergencyOff(Feature.questV2);
    await tester.pumpAndSettle();
    expect(find.text('ยังเปิดหน้านี้ไม่ได้'), findsOneWidget);
    expect(find.text('live quest'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'กลับหน้าก่อนหน้า'));
    await tester.pumpAndSettle();
    expect(find.text('safe parent'), findsOneWidget);
    expect(registry.stateOf(Feature.questV2), FeatureState.emergencyOff);
    expect(builds, before);
    expect(navigator.currentState!.canPop(), isFalse);
  });

  for (final pushed in [false, true]) {
    testWidgets('S01-AB Thai unavailable recovery root=$pushed at 360px 200%', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final navigator = GlobalKey<NavigatorState>();
      const gate = ProductionFeatureGate(
        feature: Feature.vocabulary,
        registry: BuildFeatureRegistry({Feature.vocabulary: FeatureState.disabled}),
        builder: _unexpectedContent,
      );
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: pushed ? const Scaffold(body: Text('parent destination')) : gate,
      ));
      if (pushed) {
        navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => gate));
        await tester.pumpAndSettle();
      }
      expect(find.text('ยังเปิดหน้านี้ไม่ได้'), findsOneWidget);
      expect(find.textContaining('ข้อมูลการเรียนที่บันทึกไว้ยังอยู่'), findsOneWidget);
      expect(find.text('ลองอีกครั้ง'), findsNothing);
      final back = find.widgetWithText(FilledButton, 'กลับหน้าก่อนหน้า');
      if (pushed) {
        await tester.ensureVisible(back);
        await tester.pumpAndSettle();
        expect(tester.getSemantics(back), matchesSemantics(
          label: 'กลับหน้าก่อนหน้า', isButton: true, hasEnabledState: true,
          isEnabled: true, hasTapAction: true, hasFocusAction: true, isFocusable: true,
        ));
        expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
        await tester.tap(back);
        await tester.pumpAndSettle();
        expect(find.text('parent destination'), findsOneWidget);
      } else {
        expect(back, findsNothing);
        expect(find.textContaining('เลือกหน้าอื่นจากเมนูที่มีอยู่'), findsOneWidget);
      }
      expect(navigator.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('disabled features never construct the lazy enabled subtree', (
    tester,
  ) async {
    var builds = 0;
    const registry = BuildFeatureRegistry({
      Feature.vocabulary: FeatureState.disabled,
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ProductionFeatureGate(
          feature: Feature.vocabulary,
          registry: registry,
          builder: (_) {
            builds += 1;
            return const Text('enabled content');
          },
        ),
      ),
    );

    expect(builds, 0);
    expect(find.text('enabled content'), findsNothing);
    final unavailable = tester.widget<ProductionFeatureUnavailable>(
      find.byType(ProductionFeatureUnavailable),
    );
    expect(unavailable.feature, Feature.vocabulary);
    expect(
      unavailable.reason,
      ProductionFeatureUnavailableReason.unavailableState,
    );
    expect(unavailable.state, FeatureState.disabled);
  });

  testWidgets('missing dependency scope fails closed without building', (
    tester,
  ) async {
    var builds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ProductionFeatureGate(
          feature: Feature.quiz,
          builder: (_) {
            builds += 1;
            return const Text('quiz content');
          },
        ),
      ),
    );

    expect(builds, 0);
    final unavailable = tester.widget<ProductionFeatureUnavailable>(
      find.byType(ProductionFeatureUnavailable),
    );
    expect(
      unavailable.reason,
      ProductionFeatureUnavailableReason.missingRegistry,
    );
    expect(unavailable.state, isNull);
  });

  testWidgets('enabled content switches live to unavailable on emergency-off', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry({Feature.questV2: FeatureState.enabled}),
    );
    addTearDown(registry.dispose);
    var builds = 0;

    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database, registry),
        child: MaterialApp(
          home: ProductionFeatureGate(
            feature: Feature.questV2,
            registry: registry,
            builder: (_) {
              builds += 1;
              return const Text('quest content');
            },
          ),
        ),
      ),
    );

    expect(find.text('quest content'), findsOneWidget);
    expect(builds, 1);

    registry.emergencyOff(Feature.questV2);
    await tester.pump();

    expect(find.text('quest content'), findsNothing);
    final unavailable = tester.widget<ProductionFeatureUnavailable>(
      find.byType(ProductionFeatureUnavailable),
    );
    expect(unavailable.state, FeatureState.emergencyOff);
    expect(builds, 1, reason: 'disabled rebuild must stay lazy');
  });

  testWidgets('enabled Adventure stays lazy without composed dependencies', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    const registry = BuildFeatureRegistry({
      Feature.adventureMotivation: FeatureState.enabled,
    });
    var builds = 0;

    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database, registry),
        child: MaterialApp(
          home: ProductionFeatureGate(
            feature: Feature.adventureMotivation,
            registry: registry,
            builder: (_) {
              builds += 1;
              return const Text('Adventure presentation');
            },
          ),
        ),
      ),
    );

    expect(builds, 0);
    expect(find.text('Adventure presentation'), findsNothing);
    expect(
      tester
          .widget<ProductionFeatureUnavailable>(
            find.byType(ProductionFeatureUnavailable),
          )
          .reason,
      ProductionFeatureUnavailableReason.missingDependency,
    );
  });
}

AppDependencies _dependencies(AppDatabase database, FeatureRegistry features) {
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
  );
}

final class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'production-feature-gate');
}

Widget _unexpectedContent(BuildContext context) => const Text('must stay unavailable');
