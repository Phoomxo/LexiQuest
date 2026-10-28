import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
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
  for (final samples in [0, 3]) {
    for (final dataOwner in ['owner', null]) {
      testWidgets('empty weakness context samples=$samples owner=$dataOwner', (
        tester,
      ) async {
        String? aiOwner = 'owner';
        final registry = MenuActionRegistry(currentOwner: () => aiOwner);
        final progress = ProgressSnapshot(
          ownerId: dataOwner,
          sampleSize: samples,
          correctCount: samples,
          wrongCount: 0,
          accuracy: samples == 0 ? null : 1,
          totalXp: 0,
          completedSessions: 0,
          streakDays: 0,
          dueReviewCount: 2,
          masteredWordCount: 0,
          achievementCount: 0,
          gameLevel: 1,
          skills: [],
          weaknesses: [],
          recommendations: [],
        );
        await tester.pumpWidget(
          MenuActionScope(
            registry: registry,
            child: MaterialApp(
              home: WeaknessClinicScreen(loader: () async => progress),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('จำนวนตัวอย่าง: $samples'), findsOneWidget);
        expect(registry.snapshot()['actions'], isEmpty);
        if (dataOwner == null) {
          expect(registry.snapshot()['context'], isEmpty);
        } else {
          final rows = registry.snapshot()['context'] as List;
          final summary = jsonDecode(rows.single['value'] as String);
          expect(summary['sampleSize'], samples);
          expect(summary['weaknessWordCount'], 0);
          expect(summary['dueReviewCount'], 2);
          expect(
            summary['state'],
            samples == 0 ? 'no-answer-evidence' : 'no-recorded-incorrect-words',
          );
          expect(summary['interpretation'], contains('not-proof-of-mastery'));
          aiOwner = null;
          expect(registry.snapshot()['context'], isEmpty);
          expect(
            find.textContaining('จำนวนตัวอย่าง: $samples'),
            findsOneWidget,
          );
          aiOwner = 'owner';
          expect(registry.snapshot()['context'], hasLength(1));
          aiOwner = 'other';
          expect(registry.snapshot()['context'], isEmpty);
          aiOwner = 'owner';
          expect(
            registry.snapshot()['context'],
            isEmpty,
            reason: 'An account switch retires the old registration',
          );
        }
      });
    }
  }
  testWidgets(
    'optional weakness evidence is owner-bound and distinguishes due',
    (tester) async {
      String? owner = 'weakness-owner';
      final registry = MenuActionRegistry(currentOwner: () => owner);
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(
            home: WeaknessClinicScreen(loader: () async => _snapshot),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final entries = registry.snapshot()['context'] as List;
      final data = entries
          .map((e) => jsonDecode(e['value'] as String) as Map<String, dynamic>)
          .toList();
      expect(data.any((e) => e['dueReviewCount'] == 1), true);
      final word = data.singleWhere((e) => e.containsKey('spelling'));
      expect(word['spelling'], 'ephemeral');
      expect(word['incorrectCount'], 2);
      expect(word['sampleSize'], 3);
      expect(word['interpretation'], 'incorrect-history-not-necessarily-due');
      expect(registry.snapshot()['actions'], isEmpty);
      owner = 'other';
      expect(registry.snapshot()['context'], isEmpty);
    },
  );

  testWidgets('displays weaknesses derived from attempt evidence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: WeaknessClinicScreen(loader: () async => _snapshot)),
    );
    await tester.pumpAndSettle();

    expect(find.text('คลินิกจุดอ่อน'), findsOneWidget);
    expect(find.text('1. ephemeral'), findsOneWidget);
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

      await tester.tap(find.text('ปรับตัวเลือก'));
      await tester.pumpAndSettle();
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
  ownerId: 'weakness-owner',
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
