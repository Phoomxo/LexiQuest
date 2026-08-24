import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/cefr_selection_screen.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  testWidgets(
    'CefrSelectionScreen renders tabs, search bar, and filters by query',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: CefrSelectionScreen()));
      await tester.pumpAndSettle();

      expect(find.text('คลังคำศัพท์ CEFR Multi-Matrix'), findsOneWidget);
      expect(find.text('เริ่มทบทวน SRS'), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField), 'achieve');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'achieve'), findsOneWidget);
    },
  );

  for (final mode in EvidencePolicyRolloutMode.values) {
    testWidgets(
      'CEFR SRS navigation is Legacy-only under ${mode.name} rollout',
      (tester) async {
        final harness = _CompatibilityHarness(mode);
        addTearDown(harness.close);
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: harness.dependencies,
            child: const MaterialApp(home: CefrSelectionScreen()),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('เริ่มทบทวน SRS'));
        await tester.pumpAndSettle();

        if (mode == EvidencePolicyRolloutMode.legacy) {
          expect(find.byType(SrsFlashcardsScreen), findsOneWidget);
          expect(find.byType(ProductionFeatureUnavailable), findsNothing);
          harness.features.emergencyOff(Feature.srs);
          await tester.pumpAndSettle();
          expect(find.byType(SrsFlashcardsScreen), findsNothing);
          expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
        } else {
          expect(find.byType(SrsFlashcardsScreen), findsNothing);
          expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
        }
        expect(
          await harness.database
              .select(harness.database.learningSessions)
              .get(),
          isEmpty,
        );
        expect(
          await harness.database.select(harness.database.answerAttempts).get(),
          isEmpty,
        );
      },
    );
  }
}

final class _CompatibilityHarness {
  _CompatibilityHarness(EvidencePolicyRolloutMode mode)
    : database = AppDatabase(NativeDatabase.memory()),
      features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      ) {
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'cefr-compatibility-owner',
      nowUtc: () => DateTime.utc(2026, 8, 25),
    );
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'cefr-compatibility-id',
      nowUtc: () => DateTime.utc(2026, 8, 25),
      buildInfo: const AppBuildInfo(
        version: 'test',
        buildId: 'f06-cefr-compatibility',
      ),
    );
    final research = InertResearchDependencies(database);
    dependencies = AppDependencies(
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
      evidencePolicyRolloutModeProvider: FixedEvidencePolicyRolloutModeProvider(
        mode,
      ),
      features: features,
      database: database,
      localOwners: owners,
      learning: learning,
    );
  }

  final AppDatabase database;
  final RuntimeFeatureRegistry features;
  late final AppDependencies dependencies;

  Future<void> close() async {
    features.dispose();
    await database.close();
  }
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}
