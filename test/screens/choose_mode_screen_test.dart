import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/legacy_lesson_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  testWidgets(
    'shows only canonical production modes and does not navigate without an adapter',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChooseModeScreen(
            featureRegistry: BuildFeatureRegistry.allEnabled(),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey<String>('home/learn/associative-reading')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('home/learn/quiz')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('home/learn/srs')),
        findsOneWidget,
      );
      expect(find.byType(ListTile), findsNWidgets(3));

      await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
      await tester.pumpAndSettle();

      expect(find.byType(ChooseModeScreen), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(ChooseModeScreen))).canPop(),
        isFalse,
      );
    },
  );

  testWidgets(
    'resolved mode always enters through the fail-closed feature gate',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ChooseModeScreen(
            featureRegistry: const BuildFeatureRegistry.allEnabled(),
            lessonModes: buildLegacyLessonModeRegistry(),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
      await tester.pumpAndSettle();

      expect(find.byType(ProductionFeatureGate), findsOneWidget);
      final unavailable = tester.widget<ProductionFeatureUnavailable>(
        find.byType(ProductionFeatureUnavailable),
      );
      expect(
        unavailable.reason,
        ProductionFeatureUnavailableReason.missingDependency,
      );
    },
  );

  testWidgets(
    'every production mode creates one controller-backed shell on its stable route',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 8, 24, 12);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'choose-mode-owner',
        nowUtc: () => now,
      );
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'choose-mode-id',
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'f05-choose-mode-test',
        ),
      );
      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(database),
        generateId: () => 'choose-mode-vocabulary-id',
        nowUtc: () => now,
      );
      final modes = buildLegacyLessonModeRegistry();
      final research = InertResearchDependencies(database);
      var controllerBuilds = 0;
      final dependencies = AppDependencies(
        initialRoute: AppRoute.home,
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: _GuestSession(),
        quest: testQuestUseCases(),
        experiments: research.experiments,
        consents: research.consents,
        experimentAssignments: research.experimentAssignments,
        assignedLearningEventContext: research.assignedLearningEventContext,
        evidencePolicyRolloutModeProvider:
            research.evidencePolicyRolloutModeProvider,
        learning: learning,
        vocabulary: vocabulary,
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: learning,
        ),
        lessonModes: modes,
        createLessonController: (adapter) {
          controllerBuilds += 1;
          return UnifiedLessonController(learning: learning, adapter: adapter);
        },
        associativeLearning: InMemoryAssociativeLearningAdapter(),
      );
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: dependencies,
          child: const MaterialApp(home: ChooseModeScreen()),
        ),
      );

      const cases = <({String entryId, LessonMode mode, String routeName})>[
        (
          entryId: 'home/learn/associative-reading',
          mode: LessonMode.associativeReading,
          routeName: 'learning/associative-reading',
        ),
        (
          entryId: 'home/learn/quiz',
          mode: LessonMode.meaningQuiz,
          routeName: 'learning/quiz',
        ),
        (
          entryId: 'home/learn/srs',
          mode: LessonMode.flashcard,
          routeName: 'learning/srs',
        ),
      ];
      for (final (index, routeCase) in cases.indexed) {
        await tester.tap(find.byKey(ValueKey<String>(routeCase.entryId)));
        await tester.pumpAndSettle();

        expect(controllerBuilds, index + 1);
        expect(find.byType(UnifiedLessonShell), findsOneWidget);
        final shell = tester.widget<UnifiedLessonShell>(
          find.byType(UnifiedLessonShell),
        );
        expect(
          ModalRoute.of(
            tester.element(find.byType(UnifiedLessonShell)),
          )?.settings.name,
          routeCase.routeName,
        );
        final controller = shell.controller!;
        expect(controller.state.mode, routeCase.mode);
        if (routeCase.mode == LessonMode.meaningQuiz) {
          await controller.start(
            LessonStartCommand(
              mode: routeCase.mode,
              sessionId: 'session:production-route',
              startedAtUtc: now,
              itemCount: 1,
            ),
          );

          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          await tester.pump();
          expect(controller.state.status, LessonSessionStatus.paused);
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          expect(controller.state.status, LessonSessionStatus.active);
        }

        Navigator.of(tester.element(find.byType(UnifiedLessonShell))).pop();
        await tester.pumpAndSettle();
      }
    },
  );
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}
