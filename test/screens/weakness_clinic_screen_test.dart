import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_session_configuration_store.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/presentation/session_configuration_sheet.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  testWidgets('displays weaknesses derived from attempt evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: WeaknessClinicScreen(loader: () async => _snapshot)),
    );
    await tester.pumpAndSettle();

    expect(find.text('คลินิกจุดอ่อน'), findsOneWidget);
    expect(find.text('ephemeral'), findsOneWidget);
    expect(find.textContaining('ตอบผิด 2/3 ครั้ง'), findsOneWidget);
    expect(find.text('ทบทวนคำที่ถึงกำหนด (1)'), findsOneWidget);
  });

  testWidgets('new account shows sample size zero instead of sample words', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WeaknessClinicScreen(loader: () async => _emptySnapshot),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('จำนวนตัวอย่าง: 0'), findsOneWidget);
    expect(find.text('ephemeral'), findsNothing);
  });

  testWidgets('SRS launch fails closed when no feature authority exists', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: WeaknessClinicScreen(loader: () async => _snapshot)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    expect(find.byType(SrsFlashcardsScreen), findsNothing);
  });

  testWidgets(
    'f16 reachable Weakness Clinic SRS validates configuration before host',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'weakness-f16-owner',
        nowUtc: () => DateTime.utc(2026, 8, 26),
      );
      final learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'weakness-f16-session',
        nowUtc: () => DateTime.utc(2026, 8, 26),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f16-test'),
      );
      final research = InertResearchDependencies(database);
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      final controllers = <UnifiedLessonController>[];
      final dependencies = AppDependencies(
        initialRoute: AppRoute.home,
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: const _WeaknessGuestSession(),
        quest: testQuestUseCases(),
        features: features,
        experiments: research.experiments,
        consents: research.consents,
        experimentAssignments: research.experimentAssignments,
        assignedLearningEventContext: research.assignedLearningEventContext,
        evidencePolicyRolloutModeProvider:
            research.evidencePolicyRolloutModeProvider,
        localOwners: owners,
        learning: learning,
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: learning,
        ),
        lessonModes: buildLessonModeRegistry(),
        sessionConfigurationProtocols: const _WeaknessProtocols(),
        sessionConfigurations: DriftSessionConfigurationStore(database),
        createLessonController: (adapter) {
          final controller = UnifiedLessonController(
            learning: learning,
            adapter: adapter,
          );
          controllers.add(controller);
          return controller;
        },
      );
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: dependencies,
          child: MaterialApp(
            home: WeaknessClinicScreen(loader: () async => _snapshot),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(find.byType(SessionConfigurationSheet), findsOneWidget);
      expect(find.byType(SrsFlashcardsScreen), findsNothing);
      expect(controllers, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey('session-item-count')),
        '3',
      );
      final start = find.byKey(const ValueKey('session-config-start'));
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();

      final screen = tester.widget<SrsFlashcardsScreen>(
        find.byType(SrsFlashcardsScreen),
      );
      expect(screen.sessionConfiguration?.itemCount, 3);
      expect(controllers.single.sessionConfiguration?.itemCount, 3);
    },
  );
}

final class _WeaknessGuestSession implements GuestSessionService {
  const _WeaknessGuestSession();

  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'weakness-f16');
}

final class _WeaknessProtocols implements SessionConfigurationProtocolProvider {
  const _WeaknessProtocols();

  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(
    String ownerId,
  ) async => const SessionConfigurationProtocolLimits.standard();
}

const _snapshot = ProgressSnapshot(
  sampleSize: 3,
  correctCount: 1,
  wrongCount: 2,
  accuracy: 1 / 3,
  totalXp: 1,
  completedSessions: 1,
  streakDays: 1,
  dueReviewCount: 1,
  masteredWordCount: 0,
  achievementCount: 1,
  gameLevel: 1,
  skills: [],
  weaknesses: [
    WeaknessEvidence(
      wordId: 'word-1',
      spelling: 'ephemeral',
      meaning: 'ชั่วคราว',
      sampleSize: 3,
      incorrectCount: 2,
      errorRate: 2 / 3,
      dueAtUtc: null,
    ),
  ],
  recommendations: [],
);

const _emptySnapshot = ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);
