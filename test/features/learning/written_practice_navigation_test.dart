import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:flutter/material.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/screens/personal_sets_screen.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../../support/inert_research_dependencies.dart';
import '../../support/test_quest_use_cases.dart';
import '../../support/r15_visual_capture.dart';
import 'dart:io';
import 'package:vocab_learning_app/features/learning/application/written_practice_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';

import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/identity/application/owner_generation.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_generation.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/personal_sets_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/application/personal_set_activities.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_personal_set_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/packaged_sense_crosswalk.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/personal_sets.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/sense_crosswalk_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/packaged_starter_catalog.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  setUpAll(loadR15Fonts);
  late AppDatabase db;
  late Directory directory;
  late PersonalSetsUseCases sets;
  late PersonalSetActivities activities;
  late LearningUseCases learning;
  late PersonalSetRevision original;
  var enabled = true;
  var missing = false;
  Future<void> Function()? duringAdmission;
  var serial = 0;
  final now = DateTime.utc(2026, 9, 20);
  Future<void> wire() async {
    Future<Uint8List?> load(ContentIdentity identity) async {
      if (missing) return null;
      if (identity == PackagedSenseCrosswalk.identity) {
        return File(PackagedSenseCrosswalk.assetPath).readAsBytesSync();
      }
      return File(
        'assets/content/lexical_metadata/${identity.id.substring(5)}/r${identity.revision}.json',
      ).readAsBytesSync();
    }

    final manifests = DriftContentManifestRepository(
      db,
      loadArtifactBytes: load,
    );
    await PackagedStarterCatalog.provision(db, manifests, load);
    await manifests.provisionPackagedArtifact(
      PackagedSenseCrosswalk.verify(
        (await load(PackagedSenseCrosswalk.identity))!,
      ),
    );
    final owners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'unused',
      nowUtc: () => now,
    );
    Future<String> activeOwner() async =>
        (await owners.getOrCreateActiveOwner()).id;
    sets = PersonalSetsUseCases(
      repository: DriftPersonalSetRepository(
        db,
        SenseCrosswalkRepository(manifests),
        nowUtc: () => now,
      ),
      ownerGeneration: OwnerGeneration(
        activeOwnerId: activeOwner,
        readDurableStamp: DriftOwnerGeneration(db).read,
      ),
      ownerOperations: OwnerOperationCoordinator(
        gate: DriftOwnerOperationGate(db),
        activeOwnerId: activeOwner,
        nowUtc: () => now,
      ),
    );

    learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(
        db,
        lexicalVocabulary: DriftVocabularyRepository(
          db,
          contentManifests: manifests,
        ),
      ),
      generateId: () => 'quiz-${serial++}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      beforeSessionStart: (_) async {
        await duringAdmission?.call();
      },
    );
    activities = PersonalSetActivities(
      sets: sets,
      learning: learning,
      isAvailable: () => enabled,
      contextAvailable: () => enabled,
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('personal-set-activity-');
    db = AppDatabase(NativeDatabase.memory());
    await db.customStatement(
      "INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES ('a', 1, 1)",
    );
    enabled = true;
    missing = false;
    duringAdmission = null;
    await wire();
    final owner = await sets.begin();
    final pin = SenseCrosswalkPin.fromJson({
      'corpusManifestHash': PackagedSenseCrosswalk.corpusManifestHash,
      'revision': 1,
      'artifactHash': PackagedSenseCrosswalk.artifactHash,
    });
    final crosswalk = await sets.candidates(owner, pin);
    original = PersonalSetRevision.create(
      setId: 'set',
      operationId: 'create',
      expectedPriorRevision: 0,
      createdAtUtcMs: now.millisecondsSinceEpoch,
      title: 'Objects',
      crosswalkPin: pin,
      members: crosswalk.entries.take(2).map((e) => e.ref).toList(),
    );
    await sets.save(owner, original);
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'personal set opens real writing and durable rubric at 320px text200',
    (tester) async {
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
      }

      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final inert = InertResearchDependencies(db);
      final dependencies = AppDependencies(
        initialRoute: AppRoute.home,
        runtimeStatus: const AppRuntimeStatus(
          localData: RuntimeAvailability.ready,
          firebase: RuntimeAvailability.unavailable,
          supabase: RuntimeAvailability.unavailable,
          backends: RuntimeAvailability.unavailable,
        ),
        config: null,
        guestSessionService: _Guest(),
        quest: testQuestUseCases(),
        features: const BuildFeatureRegistry({
          Feature.quiz: FeatureState.enabled,
          Feature.studyPlanning: FeatureState.enabled,
        }),
        experiments: inert.experiments,
        consents: inert.consents,
        experimentAssignments: inert.experimentAssignments,
        assignedLearningEventContext: inert.assignedLearningEventContext,
        evidencePolicyRolloutModeProvider:
            inert.evidencePolicyRolloutModeProvider,
        learning: learning,
        personalSets: sets,
        writtenPractice: WrittenPracticeUseCases(
          sets: sets,
          isAvailable: () => enabled,
        ),
        personalSetActivities: activities,
        studyPlanning: StudyPlanningUseCases(
          packs: DriftLearningPackRepository(
            db,
            contentManifests: sets.repository.crosswalks.manifests,
          ),
          progress: ProgressUseCases(
            owners: learning.owners,
            queries: DriftProgressQueries(db),
            nowUtc: () => now,
            learningTimezoneId: 'Asia/Bangkok',
          ),
        ),
        vocabulary: VocabularyUseCases(
          owners: learning.owners,
          vocabulary: DriftVocabularyRepository(
            db,
            contentManifests: sets.repository.crosswalks.manifests,
          ),
          generateId: () => 'unused',
          nowUtc: () => now,
        ),
        lessonModes: buildLessonModeRegistry(),
        createLessonController: (adapter) =>
            UnifiedLessonController(learning: learning, adapter: adapter),
        currentActivityEvidence: CurrentActivityEvidenceAdapter(
          learning: learning,
        ),
      );
      try {
        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: dependencies,
            child: MaterialApp(
              theme: M3Theme.lightTheme,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(2)),
                child: RepaintBoundary(
                  key: const ValueKey('synthetic-r15-surface'),
                  child: child!,
                ),
              ),
              home: const PersonalSetsScreen(),
            ),
          ),
        );
        await settle();
        await tester.tap(find.text('Objects'));
        await settle();
        final start = find.text('Use the word · เขียนประโยค');
        await tester.ensureVisible(start);
        await tester.tap(start);
        await settle();
        expect(find.text('Use the word'), findsOneWidget);
        final response = find.byKey(const Key('written-response'));
        await tester.ensureVisible(response);
        await tester.enterText(response, 'I read a book.');
        final submit = find.byKey(const Key('written-submit'));
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        await settle();
        final result = find.textContaining('Meaning 2/2');
        await tester.ensureVisible(result);
        await settle();
        expect(result, findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureR15Surface(tester, 'e33-writing-result-320-text200');
        await tester.pumpWidget(const SizedBox.shrink());
        await settle();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 1));
      }
    },
  );
}

class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'context-test');
}
