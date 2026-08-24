import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/config/research_runtime_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/assessment/application/assessment_use_cases.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_lifecycle_manifest.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/research/application/assigned_learning_event_context_provider.dart';
import 'package:vocab_learning_app/features/research/application/experiment_assignment_use_cases.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/review/domain/content_quality_report.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/sync/application/sync_trigger.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/time_tracking/application/learning_time_capture_rollout.dart';
import 'package:vocab_learning_app/features/time_tracking/application/focus_timer_rollout.dart';
import 'package:vocab_learning_app/features/time_tracking/presentation/focus_timer_widget.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/runtime/registries/consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';
import 'package:vocab_learning_app/runtime/runtime_feature_override_store.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

class _StubGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async {
    return const GuestSessionFailed(GuestSessionFailure.unknown);
  }
}

final class _SuccessfulGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'anonymous-bootstrap-user');
}

final class _ControllableBootstrapGuestSessionService
    implements GuestSessionService {
  final Completer<GuestSessionResult> _result = Completer<GuestSessionResult>();
  int startCalls = 0;

  @override
  Future<GuestSessionResult> start() {
    startCalls += 1;
    return _result.future;
  }

  void complete(GuestSessionResult result) => _result.complete(result);
}

AppConfig _validConfig() => AppConfig.fromValues(
  voiceApiUrl: 'https://voice.example.com',
  aiApiUrl: 'https://ai.example.com',
  isDebug: false,
);

AppDatabase _testDatabase() {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

Future<AppEntryStateStore> _createSignedOutEntryState() async =>
    _MemoryAppEntryStateStore();

Future<void> _insertFrozenLearningEvidence(
  AppDatabase database, {
  required String ownerId,
  required String attemptId,
  required String sessionId,
  required DateTime occurredAtUtc,
}) async {
  final categoryId = 'bootstrap-category:$ownerId';
  final wordId = 'bootstrap-word:$ownerId';
  final context = LearningEvidenceContract.frozenV13LegacyEvidenceContext();
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: categoryId,
          ownerId: ownerId,
          name: 'Bootstrap replay',
          normalizedName: 'bootstrap replay',
          createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          updatedAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: wordId,
          ownerId: ownerId,
          categoryId: categoryId,
          spelling: 'bootstrap',
          normalizedSpelling: 'bootstrap',
          meaning: 'bootstrap',
          normalizedMeaning: 'bootstrap',
          partOfSpeech: 'noun',
          createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          updatedAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: sessionId,
          ownerId: ownerId,
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          appVersion: '1.0.0',
          buildId: 'bootstrap-test',
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: attemptId,
          ownerId: ownerId,
          sessionId: sessionId,
          wordId: wordId,
          promptMode: 'meaningChoice',
          isCorrect: true,
          attemptNumber: 1,
          occurredAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          evidenceClass: Value(context.evidenceClass.name),
          evidenceContextJson: Value(jsonEncode(context.toJson())),
        ),
      );
  await database
      .into(database.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: 'learning-event:$attemptId',
          eventType: 'QuizCompleted',
          eventVersion: 1,
          occurredAtUtc: occurredAtUtc,
          recordedAtUtc: occurredAtUtc,
          actorIdentity: ownerId,
          ownerId: ownerId,
          aggregateType: 'LearningSession',
          aggregateId: sessionId,
          idempotencyKey: 'learning-attempt:$attemptId:v1',
          consentContextJson: '{}',
          appVersion: '1.0.0',
          buildId: 'bootstrap-test',
          privacyClassification: 'anonymized',
          payloadJson: jsonEncode(<String, dynamic>{'attemptId': attemptId}),
        ),
      );
}

Future<({String sessionId, String wordId})>
_insertBootstrapCurrentActivityTarget(
  AppDatabase database, {
  required String ownerId,
  required DateTime startedAtUtc,
}) async {
  final categoryId = 'bootstrap-live-category:$ownerId';
  final wordId = 'bootstrap-live-word:$ownerId';
  final sessionId = 'bootstrap-live-session:$ownerId';
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: categoryId,
          ownerId: ownerId,
          name: 'Bootstrap current activity',
          normalizedName: 'bootstrap current activity',
          createdAtUtcMs: startedAtUtc.millisecondsSinceEpoch,
          updatedAtUtcMs: startedAtUtc.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: wordId,
          ownerId: ownerId,
          categoryId: categoryId,
          spelling: 'persisted',
          normalizedSpelling: 'persisted',
          meaning: 'persisted research authority',
          normalizedMeaning: 'persisted research authority',
          partOfSpeech: 'adjective',
          createdAtUtcMs: startedAtUtc.millisecondsSinceEpoch,
          updatedAtUtcMs: startedAtUtc.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: sessionId,
          ownerId: ownerId,
          activityType: 'quiz',
          state: 'active',
          startedAtUtcMs: startedAtUtc.millisecondsSinceEpoch,
          appVersion: '1.0.0',
          buildId: 'bootstrap-test',
        ),
      );
  return (sessionId: sessionId, wordId: wordId);
}

const _bootstrapProtocolModeCatalog = ResearchProtocolModeCatalog(
  mappings: <ResearchProtocolModeMapping>[
    ResearchProtocolModeMapping(
      protocolId: 'bootstrap-protocol',
      protocolVersion: 'bootstrap-protocol-v1',
      experimentId: 'bootstrap-experiment',
      experimentVersion: 1,
      consentVersion: 7,
      mode: EvidencePolicyRolloutMode.shadow,
    ),
  ],
);

Future<void> _putBootstrapConsent(
  AppDatabase database, {
  required String ownerId,
  required int consentVersion,
  required DateTime decidedAtUtc,
}) {
  return database.customInsert(
    'INSERT INTO research_consents('
    'id, owner_id, consent_version, consent_state, decided_at_utc_ms'
    ') VALUES (?, ?, ?, ?, ?)',
    variables: [
      Variable<String>('bootstrap-consent:$ownerId:$consentVersion'),
      Variable<String>(ownerId),
      Variable<int>(consentVersion),
      const Variable<String>('accepted'),
      Variable<int>(decidedAtUtc.millisecondsSinceEpoch),
    ],
  );
}

Future<int> _bootstrapAssignmentCount(AppDatabase database) {
  return database
      .customSelect('SELECT COUNT(*) AS count FROM experiment_assignments')
      .map((row) => row.read<int>('count'))
      .getSingle();
}

Future<int> _bootstrapResearchOutboxCount(AppDatabase database) {
  return (database.select(database.outboxOperations)..where(
        (row) => row.entityType.equals(
          SyncCollection.experimentAssignments.entityType,
        ),
      ))
      .get()
      .then((rows) => rows.length);
}

EvidenceContext _bootstrapResearchEvidence(ExperimentAssignment assignment) {
  return EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: 'vocabulary-recall',
    hintLevel: 0,
    contentRevision: 'bootstrap-content-v1',
    rolloutMode: EvidencePolicyRolloutMode.enforced,
    protocolId: 'bootstrap-protocol',
    protocolVersion: assignment.protocolVersion,
    experimentId: assignment.experimentId,
    experimentVersion: assignment.experimentVersion,
    assignmentId: assignment.id,
    cohort: assignment.cohort,
    researchConsentVersion: 7,
    engagementAllowed: true,
  );
}

EvidenceContext _bootstrapMissingAssessmentEvidence() {
  return EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.assessment,
    skillId: 'assessment-vocabulary-recall',
    hintLevel: 0,
    contentRevision: 'bootstrap-assessment-v1',
    rolloutMode: EvidencePolicyRolloutMode.enforced,
    protocolId: 'bootstrap-protocol',
    protocolVersion: 'bootstrap-protocol-v1',
    experimentId: 'bootstrap-experiment',
    experimentVersion: 1,
    assignmentId: 'missing-bootstrap-assignment',
    cohort: 'intervention',
    researchConsentVersion: 7,
    instrumentId: 'instrument-1',
    instrumentVersion: '1',
    formId: 'form-a',
    formVersion: '1',
    assessmentItemId: 'item-1',
    assessmentResponseCode: 'correct',
    scoringRuleVersion: '1',
    engagementAllowed: false,
  );
}

void main() {
  group('AppBootstrap.initialize', () {
    test(
      'research configuration failure propagates before composition',
      () async {
        var databaseCalls = 0;
        var entryStateCalls = 0;
        final bootstrap = AppBootstrap(
          createDatabase: () {
            databaseCalls += 1;
            return _testDatabase();
          },
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          loadResearchRuntimeConfig: () =>
              throw const ResearchRuntimeConfigException(),
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: () async {
            entryStateCalls += 1;
            return _MemoryAppEntryStateStore();
          },
        );

        await expectLater(
          bootstrap.initialize(),
          throwsA(isA<ResearchRuntimeConfigException>()),
        );
        expect(databaseCalls, 0);
        expect(entryStateCalls, 0);
      },
    );

    test('delivery rollout cannot activate an unassigned owner', () async {
      for (final rollout in const <String>['shadow', 'enforced']) {
        var databaseCalls = 0;
        var entryStateCalls = 0;
        final bootstrap = AppBootstrap(
          createDatabase: () {
            databaseCalls += 1;
            return _testDatabase();
          },
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          loadResearchRuntimeConfig: () => ResearchRuntimeConfig.fromValues(
            evidenceRollout: rollout,
            answerAttemptWriteVersion: '2',
            firestoreRulesRevision: answerAttemptV2RulesRevision,
          ),
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: () async {
            entryStateCalls += 1;
            return _MemoryAppEntryStateStore();
          },
        );

        final dependencies = await bootstrap.initialize();
        final owner = await dependencies.localOwners!.getOrCreateActiveOwner();

        expect(databaseCalls, 1, reason: rollout);
        expect(entryStateCalls, 1, reason: rollout);
        expect(
          await dependencies.evidencePolicyRolloutModeProvider.resolve(
            ownerId: owner.id,
            evidenceContext: null,
          ),
          EvidencePolicyRolloutMode.legacy,
          reason: rollout,
        );
        expect(
          await dependencies.database!
              .customSelect(
                'SELECT COUNT(*) AS count FROM experiment_assignments',
              )
              .map((row) => row.read<int>('count'))
              .getSingle(),
          0,
          reason: rollout,
        );
      }
    });

    test(
      'valid delivery configuration stays separate from persisted policy',
      () async {
        final gateway = _BootstrapSyncGateway();
        final researchState = _BootstrapResearchStateProvider();
        final bootstrap = AppBootstrap(
          createDatabase: _testDatabase,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          loadResearchRuntimeConfig: () => ResearchRuntimeConfig.fromValues(
            evidenceRollout: 'shadow',
            answerAttemptWriteVersion: '2',
            firestoreRulesRevision: answerAttemptV2RulesRevision,
          ),
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          syncGatewayFactory: () => gateway,
          researchStateProvider: researchState,
        );

        final dependencies = await bootstrap.initialize();
        final store = dependencies.syncEngine!.store as DriftSyncStore;

        expect(
          store.payloadRollout.writeVersionFor(SyncCollection.attempts),
          2,
        );
        expect(
          store.projections.evidenceDecisions.rolloutModeProvider,
          same(dependencies.evidencePolicyRolloutModeProvider),
        );
        expect(
          dependencies.evidencePolicyRolloutModeProvider,
          isA<PersistedEvidencePolicyRolloutModeProvider>(),
        );
        final owner = await dependencies.localOwners!.getOrCreateActiveOwner();
        expect(
          await dependencies.evidencePolicyRolloutModeProvider.resolve(
            ownerId: owner.id,
            evidenceContext: null,
          ),
          EvidencePolicyRolloutMode.legacy,
        );
        expect(
          identical(dependencies.learning!.eventContextProvider, researchState),
          isTrue,
        );
        expect(
          identical(
            dependencies.currentActivityEvidence!.researchStateProvider,
            researchState,
          ),
          isTrue,
        );
      },
    );

    test('general constructor defaults policy and sync to Legacy/v1', () async {
      final gateway = _BootstrapSyncGateway();
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        syncGatewayFactory: () => gateway,
      );

      final dependencies = await bootstrap.initialize();
      final store = dependencies.syncEngine!.store as DriftSyncStore;

      expect(store.payloadRollout.writeVersionFor(SyncCollection.attempts), 1);
      expect(store.learningTimeSegmentSyncRollout.allowsClaims, isFalse);
      expect(store.learningGoalSyncRollout.allowsClaims, isFalse);
      expect(
        dependencies.syncEngine!.optionalPullCollections,
        isNot(contains(SyncCollection.learningTimeSegments)),
      );
      expect(
        dependencies.syncEngine!.optionalPullCollections,
        isNot(contains(SyncCollection.learningGoals)),
      );
      expect(
        store.projections.evidenceDecisions.rolloutModeProvider,
        same(dependencies.evidencePolicyRolloutModeProvider),
      );
      expect(
        dependencies.evidencePolicyRolloutModeProvider,
        isA<PersistedEvidencePolicyRolloutModeProvider>(),
      );
      final adapter = dependencies.currentActivityEvidence!;
      final repository =
          dependencies.learning!.repository as DriftLearningRepository;
      final rollout = adapter.rolloutModeProvider;
      expect(identical(repository.events.rolloutModeProvider, rollout), isTrue);
      expect(
        identical(
          repository.projections.evidenceDecisions.rolloutModeProvider,
          rollout,
        ),
        isTrue,
      );
      expect(
        identical(
          store.projections.evidenceDecisions.rolloutModeProvider,
          rollout,
        ),
        isTrue,
      );
      expect(
        identical(
          dependencies.learning!.eventContextProvider,
          adapter.researchStateProvider,
        ),
        isTrue,
      );
      expect(
        adapter.researchStateProvider,
        isA<BaselineCurrentActivityResearchStateProvider>(),
      );
      final lessonModes = dependencies.lessonModes!;
      expect(
        lessonModes.registrations.map((entry) => entry.mode).toSet(),
        LessonMode.values.toSet(),
      );
      expect(dependencies.createLessonController, isNotNull);
      expect(dependencies.learningGoals, isNotNull);
      final lessonController = dependencies.createLessonController!(
        lessonModes.find(LessonMode.meaningQuiz)!.adapter,
      );
      expect(lessonController, isA<UnifiedLessonController>());
      expect(lessonController.state.status, LessonSessionStatus.planned);
      lessonController.dispose();
    });

    test(
      'learning-time sync bootstrap is exact-revision gated and pull-aware',
      () async {
        for (final testCase
            in <({LearningTimeSegmentSyncRollout rollout, bool expected})>[
              (
                rollout: const LearningTimeSegmentSyncRollout.off(),
                expected: false,
              ),
              (
                rollout: const LearningTimeSegmentSyncRollout.v1(
                  deployedRulesRevision: 'not-deployed',
                ),
                expected: false,
              ),
              (
                rollout: const LearningTimeSegmentSyncRollout.v1(
                  deployedRulesRevision: learningTimeSegmentV1RulesRevision,
                ),
                expected: true,
              ),
            ]) {
          final dependencies = await AppBootstrap(
            createDatabase: _testDatabase,
            initializeFirebase: () async {},
            initializeSupabase: () async {},
            loadConfig: _validConfig,
            guestSessionService: _StubGuestSessionService(),
            createEntryStateStore: _createSignedOutEntryState,
            syncGatewayFactory: () => _BootstrapSyncGateway(testCase.rollout),
            learningTimeSegmentSyncRollout: testCase.rollout,
          ).initialize();
          final store = dependencies.syncEngine!.store as DriftSyncStore;
          final gateway =
              dependencies.syncEngine!.gateway
                  as LearningTimeSegmentSyncRolloutGateway;

          expect(
            store.learningTimeSegmentSyncRollout.allowsClaims,
            testCase.expected,
          );
          expect(
            dependencies.syncEngine!.optionalPullCollections.contains(
              SyncCollection.learningTimeSegments,
            ),
            testCase.expected,
          );
          expect(
            identical(gateway.learningTimeSegmentSyncRollout, testCase.rollout),
            isTrue,
          );
          await dependencies.dispose();
        }
      },
    );

    test('marks all components ready and retains the exact config', () async {
      final expectedConfig = _validConfig();
      final ai = _BootstrapAiTutorController();
      final voice = _BootstrapManagedVoiceProvider();
      var aiBuilds = 0;
      var voiceBuilds = 0;
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: () => expectedConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        buildAiTutor: (_) {
          aiBuilds += 1;
          return ManagedAiTutor(controller: ai, disposeController: ai.dispose);
        },
        buildVoice: (config) {
          voiceBuilds += 1;
          expect(identical(config, expectedConfig), isTrue);
          return voice;
        },
      );

      final dependencies = await bootstrap.initialize();
      final repeated = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.supabase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.voice, RuntimeAvailability.ready);
      expect(identical(dependencies.config, expectedConfig), isTrue);
      expect(dependencies.deviceModels, isNotNull);
      expect(dependencies.objectScanner, isNotNull);
      expect(dependencies.speechPractice, isNotNull);
      expect(identical(dependencies, repeated), isTrue);
      expect(identical(dependencies.aiTutor, ai), isTrue);
      expect(dependencies.voice, isNotNull);
      expect(aiBuilds, 1);
      expect(voiceBuilds, 1);
      expect(dependencies.localDataEraser, isNotNull);
      expect(dependencies.featureControls, isNotNull);
      expect(
        dependencies.learnerIntents,
        isNotNull,
        reason: 'bookmark actions require the production learner intent port',
      );
      expect(
        dependencies.bookmarkLearningItem,
        isNotNull,
        reason: 'bookmark UI requires the composed typed production action',
      );
      expect(
        dependencies.contentQualityReports,
        isNotNull,
        reason: 'report actions require an independent production repository',
      );
      expect(
        dependencies.reportContent,
        isNotNull,
        reason: 'report UI requires the composed typed production action',
      );
      await dependencies.reportContent!(
        identity: const ContentIdentity(
          type: ContentType.lexicalMetadata,
          id: 'word:bootstrap-report',
          revision: 1,
        ),
        reason: ContentReportReason.text,
      );
      expect(
        await dependencies.database!
            .select(dependencies.database!.contentQualityReports)
            .get(),
        hasLength(1),
      );
      expect(
        await (dependencies.database!.select(
          dependencies.database!.outboxOperations,
        )..where((row) => row.entityType.equals('contentQualityReport'))).get(),
        isEmpty,
        reason: 'report upload remains fail-closed by production default',
      );
      final ownerArchive = await dependencies.exports!.prepare(
        format: ExportFormat.ownerArchiveJson,
        selection: const ExportSelection(
          includeVocabulary: false,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
      final archiveEnvelope =
          jsonDecode(utf8.decode(ownerArchive.bytes)) as Map<String, dynamic>;
      expect(
        (archiveEnvelope['content'] as Map<String, dynamic>)['tables'],
        hasLength(ownerLifecycleManifest.length),
      );
    });

    test(
      'awaits and memoizes managed AI and voice disposal exactly once',
      () async {
        final aiDisposal = Completer<void>();
        final voiceDisposal = Completer<void>();
        final ai = _BootstrapAiTutorController(disposal: aiDisposal.future);
        final voice = _BootstrapManagedVoiceProvider(
          disposal: voiceDisposal.future,
        );
        final bootstrap = AppBootstrap(
          createDatabase: _testDatabase,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          buildAiTutor: (_) =>
              ManagedAiTutor(controller: ai, disposeController: ai.dispose),
          buildVoice: (_) => voice,
        );
        final dependencies = await bootstrap.initialize();

        var completed = false;
        final first = dependencies.dispose().whenComplete(
          () => completed = true,
        );
        final second = dependencies.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(completed, isFalse);
        expect(voice.disposeCalls, 1);
        expect(ai.disposeCalls, 0);

        voiceDisposal.complete();
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        expect(ai.disposeCalls, 1);

        aiDisposal.complete();
        await Future.wait(<Future<void>>[first, second]);

        expect(completed, isTrue);
        expect(voice.disposeCalls, 1);
        expect(ai.disposeCalls, 1);
      },
    );

    test('AI builder failure preserves voice and local learning', () async {
      final voice = _BootstrapManagedVoiceProvider();
      var aiBuilds = 0;
      var voiceBuilds = 0;
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        buildAiTutor: (_) {
          aiBuilds += 1;
          throw StateError('AI builder unavailable');
        },
        buildVoice: (_) {
          voiceBuilds += 1;
          return voice;
        },
      );

      final dependencies = await bootstrap.initialize();

      expect(aiBuilds, 1);
      expect(voiceBuilds, 1);
      expect(dependencies.aiTutor, isNull);
      expect(dependencies.voice, isNotNull);
      expect(dependencies.vocabulary, isNotNull);
      expect(dependencies.contentManifests, isNotNull);
      expect(dependencies.studyPlanning, isNotNull);
      expect(
        dependencies.hasComposedDependencyFor(Feature.studyPlanning),
        isTrue,
      );
      expect(dependencies.quest, isNotNull);
    });

    test('voice builder failure preserves AI and local learning', () async {
      final ai = _BootstrapAiTutorController();
      var aiBuilds = 0;
      var voiceBuilds = 0;
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        buildAiTutor: (_) {
          aiBuilds += 1;
          return ManagedAiTutor(controller: ai, disposeController: ai.dispose);
        },
        buildVoice: (_) {
          voiceBuilds += 1;
          throw StateError('voice builder unavailable');
        },
      );

      final dependencies = await bootstrap.initialize();

      expect(aiBuilds, 1);
      expect(voiceBuilds, 1);
      expect(identical(dependencies.aiTutor, ai), isTrue);
      expect(dependencies.voice, isNull);
      expect(dependencies.vocabulary, isNotNull);
      expect(dependencies.contentManifests, isNotNull);
      expect(dependencies.studyPlanning, isNotNull);
      expect(
        dependencies.hasComposedDependencyFor(Feature.studyPlanning),
        isTrue,
      );
      expect(dependencies.quest, isNotNull);
    });

    test(
      'cleanup errors do not prevent the remaining managed stack from draining',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        final ai = _BootstrapAiTutorController();
        final voice = _BootstrapManagedVoiceProvider(
          disposalError: StateError('voice cleanup failed'),
        );
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          buildAiTutor: (_) =>
              ManagedAiTutor(controller: ai, disposeController: ai.dispose),
          buildVoice: (_) => voice,
        );
        final dependencies = await bootstrap.initialize();

        final cleanupFailure = throwsA(
          isA<VoiceFailure>().having(
            (failure) => failure.category,
            'category',
            VoiceFailureCategory.cleanupIncomplete,
          ),
        );
        await expectLater(dependencies.dispose(), cleanupFailure);

        expect(voice.disposeCalls, 1);
        expect(ai.disposeCalls, 1);
        await expectLater(
          database.customSelect('SELECT 1').getSingle(),
          throwsA(anything),
        );
        await expectLater(dependencies.dispose(), cleanupFailure);
        expect(voice.disposeCalls, 1);
        expect(ai.disposeCalls, 1);
      },
    );

    test(
      'creates the active local owner before exposing dependencies',
      () async {
        final database = _testDatabase();
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
        );

        final dependencies = await bootstrap.initialize();
        final owners = await database.select(database.localOwners).get();

        expect(dependencies.localOwners, isNotNull);
        expect(owners, hasLength(1));
        expect(owners.single.isActive, isTrue);
      },
    );

    test(
      'production composes one persisted research authority after active owner',
      () async {
        final database = _testDatabase();
        final gateway = _BootstrapSyncGateway();
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          syncGatewayFactory: () => gateway,
          researchProtocolModeCatalog: _bootstrapProtocolModeCatalog,
        );

        final dependencies = await bootstrap.initialize();
        final repeatedDependencies = await bootstrap.initialize();
        final owner = await dependencies.localOwners!.getOrCreateActiveOwner();
        final store = dependencies.syncEngine!.store as DriftSyncStore;

        expect(identical(dependencies, repeatedDependencies), isTrue);
        expect(dependencies.experiments, isA<DriftExperimentRegistry>());
        expect(dependencies.experiments, isNot(isA<NoOpExperimentRegistry>()));
        expect(dependencies.consents, isA<DriftConsentRegistry>());
        expect(dependencies.consents, isNot(isA<NoOpConsentRegistry>()));
        expect(
          dependencies.experimentAssignments,
          isA<ExperimentAssignmentUseCases>(),
        );
        expect(
          dependencies.assignedLearningEventContext,
          isA<AssignedLearningEventContextProvider>(),
        );
        expect(
          dependencies.evidencePolicyRolloutModeProvider,
          isA<PersistedEvidencePolicyRolloutModeProvider>(),
        );
        expect(
          identical(
            dependencies.learning!.eventContextProvider,
            dependencies.assignedLearningEventContext,
          ),
          isTrue,
        );
        expect(
          identical(
            dependencies.currentActivityEvidence!.rolloutModeProvider,
            dependencies.evidencePolicyRolloutModeProvider,
          ),
          isTrue,
        );
        expect(store.researchSyncRollout.enabled, isFalse);
        expect(identical(store.consentRegistry, dependencies.consents), isTrue);
        expect(
          store.researchSyncRollout.allowsExperimentAssignmentClaims,
          isFalse,
        );

        expect(
          dependencies.features.isVisible(Feature.shadowRewardV2),
          isFalse,
        );
        await dependencies.featureControls!.emergencyOff(
          Feature.shadowRewardV2,
        );
        await dependencies.featureControls!.clear(Feature.shadowRewardV2);
        expect(await _bootstrapAssignmentCount(database), 0);
        final missingAssessment = _bootstrapMissingAssessmentEvidence();
        expect(dependencies.features.isVisible(Feature.quiz), isTrue);
        expect(
          await dependencies.evidencePolicyRolloutModeProvider.resolve(
            ownerId: owner.id,
            evidenceContext: missingAssessment,
          ),
          EvidencePolicyRolloutMode.legacy,
        );
        await expectLater(
          dependencies.assignedLearningEventContext.resolve(
            ownerId: owner.id,
            evidenceContext: missingAssessment,
            occurredAtUtc: DateTime.utc(2026, 8, 14, 8),
          ),
          throwsStateError,
        );
        expect(await _bootstrapAssignmentCount(database), 0);

        final decidedAt = DateTime.utc(2026, 8, 14, 8);
        final assignedAt = decidedAt.add(const Duration(minutes: 1));
        await _putBootstrapConsent(
          database,
          ownerId: owner.id,
          consentVersion: 7,
          decidedAtUtc: decidedAt,
        );
        final assignment = await dependencies.experimentAssignments
            .assignIfConsented(
              ownerId: owner.id,
              experimentId: 'bootstrap-experiment',
              experimentVersion: 1,
              cohort: 'intervention',
              protocolVersion: 'bootstrap-protocol-v1',
              consentVersion: 7,
              assignedAtUtc: assignedAt,
            );
        final replay = await dependencies.experimentAssignments
            .assignIfConsented(
              ownerId: owner.id,
              experimentId: 'bootstrap-experiment',
              experimentVersion: 1,
              cohort: 'intervention',
              protocolVersion: 'bootstrap-protocol-v1',
              consentVersion: 7,
              assignedAtUtc: assignedAt,
            );

        expect(assignment, isNotNull);
        final persistedAssignment = assignment!;
        expect(replay, assignment);
        expect(await _bootstrapAssignmentCount(database), 1);
        final outbox =
            await (database.select(database.outboxOperations)..where(
                  (row) => row.entityType.equals(
                    SyncCollection.experimentAssignments.entityType,
                  ),
                ))
                .get();
        expect(outbox, hasLength(1));
        expect(outbox.single.entityId, persistedAssignment.id);
        expect(outbox.single.payloadVersion, 1);
        expect(
          await dependencies.experiments.getAssignment(
            ownerId: owner.id,
            experimentId: 'bootstrap-experiment',
            experimentVersion: 1,
          ),
          assignment,
        );

        final evidence = _bootstrapResearchEvidence(persistedAssignment);
        expect(
          await dependencies.evidencePolicyRolloutModeProvider.resolve(
            ownerId: owner.id,
            evidenceContext: evidence,
          ),
          EvidencePolicyRolloutMode.shadow,
        );
        final eventContext = await dependencies.assignedLearningEventContext
            .resolve(
              ownerId: owner.id,
              evidenceContext: evidence,
              occurredAtUtc: assignedAt.add(const Duration(minutes: 1)),
            );
        expect(eventContext.assignmentId, persistedAssignment.id);

        await dependencies.featureControls!.emergencyOff(
          Feature.shadowRewardV2,
        );
        expect(
          dependencies.features.isEnabled(Feature.shadowRewardV2),
          isFalse,
        );
        expect(
          await dependencies.evidencePolicyRolloutModeProvider.resolve(
            ownerId: owner.id,
            evidenceContext: evidence,
          ),
          EvidencePolicyRolloutMode.shadow,
        );
        expect(await _bootstrapAssignmentCount(database), 1);
        expect(
          store.researchSyncRollout.allowsExperimentAssignmentClaims,
          isFalse,
        );
        expect(
          await (database.select(database.outboxOperations)..where(
                (row) => row.entityType.equals(
                  SyncCollection.experimentAssignments.entityType,
                ),
              ))
              .get(),
          hasLength(1),
        );
      },
    );

    test(
      'bootstrap reopen shares persisted research authority before evidence exists',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'lexiquest-bootstrap-research-',
        );
        final file = File(
          '${directory.path}${Platform.pathSeparator}app.sqlite',
        );
        final decidedAt = DateTime.utc(2026, 8, 14, 8);
        final assignedAt = decidedAt.add(const Duration(minutes: 1));
        ExperimentAssignment? assignment;
        AppDependencies? first;
        AppDependencies? second;

        Future<void> disposeAfterFailure(AppDependencies? dependencies) async {
          if (dependencies == null) return;
          try {
            await Future.wait(<Future<void>>[
              dependencies.dispose(),
              dependencies.dispose(),
            ]);
          } on Object {
            // Preserve the semantic RED failure while cleanup is best-effort.
          }
        }

        try {
          final firstBootstrap = AppBootstrap(
            createDatabase: () => AppDatabase(NativeDatabase(file)),
            initializeFirebase: () async {},
            initializeSupabase: () async {},
            loadConfig: _validConfig,
            guestSessionService: _StubGuestSessionService(),
            createEntryStateStore: _createSignedOutEntryState,
            researchProtocolModeCatalog: _bootstrapProtocolModeCatalog,
          );
          first = await firstBootstrap.initialize();
          final firstDependencies = first;
          final owner = await firstDependencies.localOwners!
              .getOrCreateActiveOwner();
          await _putBootstrapConsent(
            firstDependencies.database!,
            ownerId: owner.id,
            consentVersion: 7,
            decidedAtUtc: decidedAt,
          );
          assignment = await firstDependencies.experimentAssignments
              .assignIfConsented(
                ownerId: owner.id,
                experimentId: 'bootstrap-experiment',
                experimentVersion: 1,
                cohort: 'intervention',
                protocolVersion: 'bootstrap-protocol-v1',
                consentVersion: 7,
                assignedAtUtc: assignedAt,
              );
          expect(assignment, isNotNull);
          expect(
            await firstDependencies.evidencePolicyRolloutModeProvider.resolve(
              ownerId: owner.id,
              evidenceContext: _bootstrapResearchEvidence(assignment!),
            ),
            EvidencePolicyRolloutMode.shadow,
          );
          expect(
            await _bootstrapAssignmentCount(firstDependencies.database!),
            1,
          );
          expect(
            await _bootstrapResearchOutboxCount(firstDependencies.database!),
            1,
          );
          await Future.wait(<Future<void>>[
            firstDependencies.dispose(),
            firstDependencies.dispose(),
          ]);
          first = null;

          final secondBootstrap = AppBootstrap(
            createDatabase: () => AppDatabase(NativeDatabase(file)),
            initializeFirebase: () async {},
            initializeSupabase: () async {},
            loadConfig: _validConfig,
            guestSessionService: _StubGuestSessionService(),
            createEntryStateStore: _createSignedOutEntryState,
            researchProtocolModeCatalog: _bootstrapProtocolModeCatalog,
          );
          second = await secondBootstrap.initialize();
          final secondDependencies = second;
          final reopenedOwner = await secondDependencies.localOwners!
              .getOrCreateActiveOwner();
          final reopenedAssignment = await secondDependencies.experiments
              .getAssignment(
                ownerId: reopenedOwner.id,
                experimentId: 'bootstrap-experiment',
                experimentVersion: 1,
              );

          expect(reopenedAssignment, assignment);
          final restoredAssignment = reopenedAssignment!;
          await secondDependencies.featureControls!.emergencyOff(
            Feature.shadowRewardV2,
          );
          final target = await _insertBootstrapCurrentActivityTarget(
            secondDependencies.database!,
            ownerId: reopenedOwner.id,
            startedAtUtc: assignedAt.add(const Duration(minutes: 1)),
          );
          final pending = secondDependencies.currentActivityEvidence!.capture(
            input: CurrentActivityInput.meaningMultipleChoice,
            sessionId: target.sessionId,
            wordId: target.wordId,
            isCorrect: true,
            responseTimeMs: 750,
            attemptNumber: 1,
          );
          expect(pending.evidenceContext, isNull);

          await pending.record();

          final capturedContext = pending.evidenceContext!;
          expect(capturedContext.rolloutMode, EvidencePolicyRolloutMode.shadow);
          expect(capturedContext.protocolId, 'bootstrap-protocol');
          expect(capturedContext.protocolVersion, 'bootstrap-protocol-v1');
          expect(capturedContext.experimentId, 'bootstrap-experiment');
          expect(capturedContext.experimentVersion, 1);
          expect(capturedContext.assignmentId, restoredAssignment.id);
          expect(capturedContext.cohort, 'intervention');
          expect(capturedContext.researchConsentVersion, 7);
          expect(
            identical(
              secondDependencies.learning!.eventContextProvider,
              secondDependencies.currentActivityEvidence!.researchStateProvider,
            ),
            isTrue,
            reason:
                'learning events and current activity must share one persisted '
                'research-state authority',
          );
          final sharedEventContext = await secondDependencies
              .learning!
              .eventContextProvider
              .resolve(
                ownerId: reopenedOwner.id,
                evidenceContext: capturedContext,
                occurredAtUtc: pending.occurredAtUtc,
              );
          expect(sharedEventContext.assignmentId, restoredAssignment.id);
          expect(
            sharedEventContext.experimentContext?.variantId,
            capturedContext.cohort,
          );
          expect(
            await secondDependencies.evidencePolicyRolloutModeProvider.resolve(
              ownerId: reopenedOwner.id,
              evidenceContext: _bootstrapResearchEvidence(restoredAssignment),
            ),
            EvidencePolicyRolloutMode.shadow,
          );
          expect(
            await secondDependencies.experimentAssignments.assignIfConsented(
              ownerId: reopenedOwner.id,
              experimentId: 'bootstrap-experiment',
              experimentVersion: 1,
              cohort: 'intervention',
              protocolVersion: 'bootstrap-protocol-v1',
              consentVersion: 7,
              assignedAtUtc: assignedAt,
            ),
            assignment,
          );
          expect(
            await _bootstrapAssignmentCount(secondDependencies.database!),
            1,
          );
          expect(
            await _bootstrapResearchOutboxCount(secondDependencies.database!),
            1,
          );

          await secondDependencies.database!.customUpdate(
            'UPDATE research_consents SET withdrawn_at_utc_ms = ? '
            'WHERE owner_id = ? AND consent_version = ?',
            variables: <Variable<Object>>[
              Variable<int>(
                assignedAt
                    .add(const Duration(minutes: 2))
                    .millisecondsSinceEpoch,
              ),
              Variable<String>(reopenedOwner.id),
              const Variable<int>(7),
            ],
          );
          final withdrawn = secondDependencies.currentActivityEvidence!.capture(
            input: CurrentActivityInput.meaningMultipleChoice,
            sessionId: target.sessionId,
            wordId: target.wordId,
            isCorrect: true,
            responseTimeMs: 800,
            attemptNumber: 2,
          );
          await withdrawn.record();
          expect(
            withdrawn.evidenceContext!.rolloutMode,
            EvidencePolicyRolloutMode.legacy,
          );
          expect(
            await _bootstrapAssignmentCount(secondDependencies.database!),
            1,
          );
          expect(
            await _bootstrapResearchOutboxCount(secondDependencies.database!),
            1,
          );
          await Future.wait(<Future<void>>[
            secondDependencies.dispose(),
            secondDependencies.dispose(),
          ]);
          second = null;
        } finally {
          await disposeAfterFailure(second);
          await disposeAfterFailure(first);
          if (await directory.exists()) {
            await directory.delete(recursive: true);
          }
        }
      },
    );

    test(
      'seeds quest before replay and skips pre-assignment learning',
      () async {
        final database = _testDatabase();
        const ownerId = 'bootstrap-history-owner';
        final historicalAt = DateTime.utc(2000, 1, 1);
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: ownerId,
                createdAtUtcMs: historicalAt.millisecondsSinceEpoch,
              ),
            );
        await _insertFrozenLearningEvidence(
          database,
          ownerId: ownerId,
          attemptId: 'bootstrap-history',
          sessionId: 'session-history',
          occurredAtUtc: historicalAt,
        );
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
        );

        final dependencies = await bootstrap.initialize();
        await dependencies.learningReconciliation!.drain();

        final active = await dependencies.quest.getActiveInstances();
        expect(active, hasLength(1));
        expect(active.single.assignedAtUtc.isAfter(historicalAt), isTrue);
        expect(active.single.progress.single.currentCount, 0);
        final questResult =
            await (database.select(database.eventsV2)..where(
                  (row) =>
                      row.aggregateId.equals(
                        'learning-event:bootstrap-history',
                      ) &
                      row.aggregateType.equals('LearningProjection') &
                      row.eventType.equals('LearningProjectionSkipped') &
                      row.idempotencyKey.equals(
                        'learning-projection:quest:'
                        'learning-event:bootstrap-history:v2',
                      ),
                ))
                .getSingleOrNull();
        expect(questResult, isNotNull);
      },
    );

    test(
      'loads persisted emergency feature controls into navigation',
      () async {
        final database = _testDatabase();
        await RuntimeFeatureOverrideStore(database).setEmergencyOff(
          Feature.aiTutor,
          updatedAtUtc: DateTime.utc(2026, 8, 9, 12),
        );
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
        );

        final dependencies = await bootstrap.initialize();

        expect(
          dependencies.features.stateOf(Feature.aiTutor),
          FeatureState.emergencyOff,
        );
        expect(dependencies.features.isVisible(Feature.aiTutor), isFalse);
      },
    );

    test(
      'restored TTL controls schedule live expiry during bootstrap',
      () async {
        final database = _testDatabase();
        var now = DateTime.utc(2026, 8, 9, 12);
        final seedRegistry = RuntimeFeatureRegistry(
          const BuildFeatureRegistry.fieldDefaults(),
        );
        final seedControls = RuntimeFeatureControls(
          store: RuntimeFeatureOverrideStore(database),
          registry: seedRegistry,
          nowUtc: () => now,
          scheduleExpiry: (_, _) => () {},
        );
        await seedControls.emergencyOff(
          Feature.aiTutor,
          expiresAtUtc: now.add(const Duration(hours: 1)),
        );
        seedControls.dispose();
        seedRegistry.dispose();

        void Function()? expiryCallback;
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          runtimeFeatureNowUtc: () => now,
          scheduleRuntimeFeatureExpiry: (_, callback) {
            expiryCallback = callback;
            return () {};
          },
        );

        final dependencies = await bootstrap.initialize();
        expect(
          dependencies.features.stateOf(Feature.aiTutor),
          FeatureState.emergencyOff,
        );
        expect(expiryCallback, isNotNull);

        now = now.add(const Duration(hours: 1));
        expiryCallback!();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(
          dependencies.features.stateOf(Feature.aiTutor),
          FeatureState.limited,
        );
      },
    );

    test(
      'gated AI recovery purges only expired active-owner terminal usage',
      () async {
        final database = _testDatabase();
        final now = DateTime.utc(2026, 8, 11, 12);
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(id: 'owner-a', createdAtUtcMs: 1),
            );
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: 'owner-b',
                createdAtUtcMs: 2,
                isActive: const Value(false),
              ),
            );
        Future<void> seedUsage({
          required String eventId,
          required String ownerId,
          required DateTime occurredAt,
          required String outcome,
        }) => database
            .into(database.aiUsageEvents)
            .insert(
              AiUsageEventsCompanion.insert(
                eventId: eventId,
                ownerId: ownerId,
                occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
                providerId: 'gemini',
                model: 'typed-model',
                requestType: 'tutorReply',
                outcome: outcome,
                latencyMs: 1,
              ),
            );
        await seedUsage(
          eventId: 'expired-a',
          ownerId: 'owner-a',
          occurredAt: now.subtract(const Duration(days: 91)),
          outcome: 'success',
        );
        await seedUsage(
          eventId: 'recent-a',
          ownerId: 'owner-a',
          occurredAt: now.subtract(const Duration(days: 1)),
          outcome: 'failure',
        );
        await seedUsage(
          eventId: 'pending-a',
          ownerId: 'owner-a',
          occurredAt: now.subtract(const Duration(minutes: 1)),
          outcome: 'pending',
        );
        await seedUsage(
          eventId: 'expired-pending-a',
          ownerId: 'owner-a',
          occurredAt: now.subtract(const Duration(days: 91)),
          outcome: 'pending',
        );
        await seedUsage(
          eventId: 'expired-b',
          ownerId: 'owner-b',
          occurredAt: now.subtract(const Duration(days: 91)),
          outcome: 'success',
        );
        final ai = _BootstrapAiTutorController();
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          aiNowUtc: () => now,
          buildAiTutor: (context) async {
            await context.ownerCoordinator.run(AiCancellation(), (_) async {});
            return ManagedAiTutor(
              controller: ai,
              disposeController: ai.dispose,
            );
          },
        );

        await bootstrap.initialize();

        final rows = await database.select(database.aiUsageEvents).get();
        final byId = {for (final row in rows) row.eventId: row};
        expect(byId, isNot(contains('expired-a')));
        expect(byId['recent-a']?.outcome, 'failure');
        expect(byId['pending-a']?.outcome, 'pending');
        expect(byId, isNot(contains('expired-pending-a')));
        expect(byId['expired-b']?.outcome, 'success');
      },
    );

    test(
      'quest projection and reward reconciliation survive quest emergency-off',
      () async {
        final database = _testDatabase();
        await RuntimeFeatureOverrideStore(database).setEmergencyOff(
          Feature.questV2,
          updatedAtUtc: DateTime.utc(2026, 8, 11, 12),
        );
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
        );

        final dependencies = await bootstrap.initialize();
        await dependencies.learningReconciliation!.drain();
        final quest = dependencies.quest;
        final active = await quest.getActiveInstances();
        expect(
          dependencies.features.stateOf(Feature.questV2),
          FeatureState.emergencyOff,
        );
        expect(active, hasLength(1));

        final ownerId = active.single.ownerId;
        // events_v2 uses Drift's DateTime precision while quest assignment is
        // stored as explicit epoch milliseconds. Keep test evidence safely
        // beyond the assignment boundary instead of relying on subsecond
        // rounding in the in-memory SQLite adapter.
        final base = active.single.assignedAtUtc.add(
          const Duration(minutes: 1),
        );
        for (var index = 1; index <= 5; index++) {
          final occurredAt = LearningEvidenceContract.canonicalEventUtcSecond(
            base.add(Duration(seconds: index)),
          );
          await _insertFrozenLearningEvidence(
            database,
            ownerId: ownerId,
            attemptId: 'quest-off-$index',
            sessionId: 'session-quest-off',
            occurredAtUtc: occurredAt,
          );
        }

        dependencies.learningReconciliation!.request(ownerId);
        await dependencies.learningReconciliation!.drain();

        final firstQuestReceipt =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(
                    'learning-projection:quest:'
                    'learning-event:quest-off-1:v2',
                  ),
                ))
                .getSingleOrNull();
        expect(firstQuestReceipt, isNotNull);
        expect(firstQuestReceipt?.eventType, 'LearningProjectionApplied');
        final instances = await quest.getAllInstancesForCurrentOwner();
        expect(instances, hasLength(1));
        expect(instances.single.progress.single.currentCount, 5);
        expect(instances.single.state, QuestInstanceState.completed);
        final rewards =
            await (database.select(database.pointsLedgerEntries)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.entryType.equals('questCompletion'),
                ))
                .get();
        expect(rewards, hasLength(1));
        expect(rewards.single.amount, 50);
        final rewardReceipt =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(
                    'learning-projection:reward:'
                    'learning-event:quest-off-5:v2',
                  ),
                ))
                .getSingleOrNull();
        expect(rewardReceipt?.eventType, 'LearningProjectionApplied');
        final firstCoinsReceipt =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(
                    'learning-projection:coins:'
                    'learning-event:quest-off-1:v2',
                  ),
                ))
                .getSingleOrNull();
        expect(firstCoinsReceipt?.eventType, 'LearningProjectionApplied');
        final coinGrants =
            await (database.select(database.rewardTransactions)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.transactionType.equals('coinGrant'),
                ))
                .get();
        expect(coinGrants, hasLength(6));
        expect(
          coinGrants.fold<int>(
            0,
            (sum, transaction) => sum + transaction.amount,
          ),
          55,
          reason: 'five correct answers and one Quest completion grant Coins',
        );
      },
    );

    test('records Firebase failure and still returns', () async {
      final database = _testDatabase();
      final bootstrap = AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async => throw StateError('firebase-down'),
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
      );

      final dependencies = await bootstrap.initialize();

      expect(
        dependencies.runtimeStatus.firebase,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.runtimeStatus.localData, RuntimeAvailability.ready);
      expect(identical(dependencies.database, database), isTrue);
      expect(dependencies.vocabulary, isNotNull);
      expect(dependencies.runtimeStatus.supabase, RuntimeAvailability.ready);
      expect(
        dependencies.runtimeStatus.backends,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.runtimeStatus.voice, RuntimeAvailability.ready);
      expect(dependencies.config, isNotNull);
    });

    test('records Supabase failure and still returns', () async {
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async => throw StateError('supabase-down'),
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
      );

      final dependencies = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(
        dependencies.runtimeStatus.supabase,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
    });

    test('records config failure with null config', () async {
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: () => throw const AppConfigException('invalid config'),
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
      );

      final dependencies = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.supabase, RuntimeAvailability.ready);
      expect(
        dependencies.runtimeStatus.backends,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.config, isNull);
      expect(dependencies.aiTutor, isNotNull);
      expect(dependencies.voice, isNotNull);
      expect(dependencies.vocabulary, isNotNull);
    });

    test('represents multiple failures independently', () async {
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async => throw StateError('firebase-down'),
        initializeSupabase: () async => throw StateError('supabase-down'),
        loadConfig: () => throw const AppConfigException('invalid config'),
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
      );

      final dependencies = await bootstrap.initialize();

      expect(
        dependencies.runtimeStatus.firebase,
        RuntimeAvailability.unavailable,
      );
      expect(
        dependencies.runtimeStatus.supabase,
        RuntimeAvailability.unavailable,
      );
      expect(
        dependencies.runtimeStatus.backends,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.config, isNull);
    });

    test('never leaks exception credential sentinels', () async {
      const firebaseSentinel = 'FIREBASE-SECRET-7c9f3a';
      const supabaseSentinel = 'SUPABASE-SECRET-7c9f3a';
      const configSentinel = 'CONFIG-SECRET-7c9f3a';
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async => throw StateError(firebaseSentinel),
        initializeSupabase: () async => throw StateError(supabaseSentinel),
        loadConfig: () => throw const AppConfigException(configSentinel),
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
      );

      final dependencies = await bootstrap.initialize();
      final rendered = <String>[
        dependencies.toString(),
        dependencies.runtimeStatus.toString(),
        dependencies.runtimeStatus.firebase.name,
        dependencies.runtimeStatus.supabase.name,
        dependencies.runtimeStatus.backends.name,
        '${dependencies.config}',
        dependencies.guestSessionService.toString(),
      ];

      for (final value in rendered) {
        for (final sentinel in <String>[
          firebaseSentinel,
          supabaseSentinel,
          configSentinel,
        ]) {
          expect(value, isNot(contains(sentinel)));
        }
      }
    });

    test('retains exact injected GuestSessionService identity', () async {
      final guestSessionService = _StubGuestSessionService();
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: guestSessionService,
        createEntryStateStore: _createSignedOutEntryState,
      );

      final dependencies = await bootstrap.initialize();

      expect(
        identical(dependencies.guestSessionService, guestSessionService),
        isTrue,
      );
    });

    test(
      'production composition binds anonymous auth to local ownership',
      () async {
        final database = _testDatabase();
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _SuccessfulGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          bindGuestOwnership: true,
        );

        final dependencies = await bootstrap.initialize();
        final originalOwner = await (database.select(
          database.localOwners,
        )..where((row) => row.isActive.equals(true))).getSingle();
        final result = await dependencies.guestSessionService.start();
        LocalOwner? owner;
        for (var attempt = 0; attempt < 20; attempt++) {
          owner = await (database.select(
            database.localOwners,
          )..where((row) => row.isActive.equals(true))).getSingle();
          if (owner.firebaseUid == 'anonymous-bootstrap-user') {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        expect(result, isA<GuestSessionStarted>());
        expect(owner?.id, originalOwner.id);
        expect(owner?.firebaseUid, 'anonymous-bootstrap-user');
        expect(owner?.accountState, 'firebaseBound');
      },
    );

    test('composes local mutations into the shared sync trigger', () async {
      final gateway = _BootstrapSyncGateway();
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        syncGatewayFactory: () => gateway,
      );

      final dependencies = await bootstrap.initialize();
      await dependencies.vocabulary!.createCategory('Travel');
      await Future<void>.delayed(Duration.zero);

      expect(dependencies.syncTrigger, isNotNull);
      expect(gateway.policyFetches, 1);
    });

    test(
      'resolves launch route from the single persisted entry store',
      () async {
        final entryState = _MemoryAppEntryStateStore(AppEntryMode.guest);
        var factoryCalls = 0;
        final bootstrap = AppBootstrap(
          createDatabase: _testDatabase,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          bindGuestOwnership: true,
          createEntryStateStore: () async {
            factoryCalls += 1;
            return entryState;
          },
        );

        final dependencies = await bootstrap.initialize();

        expect(factoryCalls, 1);
        expect(dependencies.initialRoute, AppRoute.home);
        await entryState.clear();

        final guestResult = await dependencies.guestSessionService.start();

        expect(guestResult, isA<GuestSessionStarted>());
        expect(entryState.mode, AppEntryMode.guest);
      },
    );

    test('memoizes one dependency graph per bootstrap instance', () async {
      var databaseCalls = 0;
      var entryStateCalls = 0;
      final bootstrap = AppBootstrap(
        createDatabase: () {
          databaseCalls += 1;
          return _testDatabase();
        },
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: () async {
          entryStateCalls += 1;
          return _MemoryAppEntryStateStore();
        },
      );

      final first = await bootstrap.initialize();
      final second = await bootstrap.initialize();

      expect(identical(first, second), isTrue);
      expect(databaseCalls, 1);
      expect(entryStateCalls, 1);
    });

    test(
      'resolves one injected learning timezone for quest and streak',
      () async {
        var timezoneResolutionCalls = 0;
        final bootstrap = AppBootstrap(
          createDatabase: _testDatabase,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          learningTimezoneId: () {
            timezoneResolutionCalls += 1;
            return 'Asia/Bangkok';
          },
        );

        final dependencies = await bootstrap.initialize();

        expect(timezoneResolutionCalls, 1);
        expect(dependencies.quest.timezoneId, 'Asia/Bangkok');
        expect(dependencies.streak, isNotNull);
        expect(dependencies.streak!.timezoneId, 'Asia/Bangkok');
        expect(dependencies.streak!.timezoneId, dependencies.quest.timezoneId);
      },
    );

    test(
      'production lesson factory persists one trustworthy monotonic segment',
      () async {
        var monotonicMicros = 1000;
        final database = _testDatabase();
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          learningTimezoneId: () => 'Asia/Bangkok',
          learningTimeMonotonicMicros: () => monotonicMicros,
          learningTimeCaptureRollout:
              const LearningTimeCaptureRollout.internal(),
        );
        final dependencies = await bootstrap.initialize();
        final owner = await dependencies.localOwners!.getOrCreateActiveOwner();
        await database
            .into(database.learningSessions)
            .insert(
              LearningSessionsCompanion.insert(
                id: 'bootstrap-time-session',
                ownerId: owner.id,
                activityType: 'meaning-quiz',
                state: 'active',
                startedAtUtcMs: DateTime.utc(
                  2026,
                  8,
                  24,
                  9,
                ).millisecondsSinceEpoch,
                appVersion: 'test',
                buildId: 'bootstrap-time',
              ),
            );
        final adapter = dependencies.lessonModes!
            .find(LessonMode.meaningQuiz)!
            .adapter;
        final controller = dependencies.createLessonController!(adapter);

        expect(controller.activeLearningTime, isNotNull);
        expect(controller.focusTimer, isNull);
        await controller.start(
          LessonStartCommand(
            sessionId: 'bootstrap-time-session',
            mode: LessonMode.meaningQuiz,
            itemCount: 1,
            startedAtUtc: DateTime.utc(2026, 8, 24, 9),
          ),
        );
        monotonicMicros += const Duration(seconds: 7).inMicroseconds;
        await controller.pause(DateTime.utc(2026, 8, 24, 8, 59, 50));

        final segments = await database
            .select(database.learningTimeSegments)
            .get();
        final outbox = await (database.select(
          database.outboxOperations,
        )..where((row) => row.entityType.equals('learningTimeSegment'))).get();
        expect(segments, hasLength(1));
        expect(segments.single.ownerId, owner.id);
        expect(segments.single.activeDurationMs, 7000);
        expect(
          segments.single.startedAtUtcMs,
          greaterThan(segments.single.endedAtUtcMs),
        );
        expect(segments.single.timezoneId, 'Asia/Bangkok');
        expect(segments.single.timezoneOffsetMinutes, 420);
        expect(outbox, hasLength(1));
        expect(outbox.single.entityId, segments.single.id);
        controller.dispose();
      },
    );

    test('learning-time capture remains implemented-off by default', () async {
      final dependencies = await AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
      ).initialize();
      final adapter = dependencies.lessonModes!
          .find(LessonMode.meaningQuiz)!
          .adapter;
      final controller = dependencies.createLessonController!(adapter);

      expect(dependencies.learningTimeCaptureRollout.allowsCapture, isFalse);
      expect(dependencies.createActiveLearningTimeController, isNull);
      expect(controller.activeLearningTime, isNull);
      controller.dispose();
    });

    testWidgets(
      'real quiz route captures lifecycle effort and abandons on exit',
      (tester) async {
        var monotonicMicros = 0;
        final database = _testDatabase();
        final dependencies = await AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          learningTimeMonotonicMicros: () => monotonicMicros,
          learningTimeCaptureRollout:
              const LearningTimeCaptureRollout.internal(),
          focusTimerRollout: const FocusTimerRollout.internal(),
        ).initialize();
        final category = await dependencies.vocabulary!.createCategory(
          'Time capture',
        );
        await dependencies.vocabulary!.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'durable',
            meaning: 'lasting',
            partOfSpeech: 'adjective',
          ),
        );

        await tester.pumpWidget(
          AppDependenciesScope(
            dependencies: dependencies,
            child: const MaterialApp(home: ChooseModeScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey<String>('home/learn/quiz')));
        await tester.pumpAndSettle();
        expect(find.byType(QuizScreen), findsOneWidget);
        expect(find.byType(FocusTimerWidget), findsOneWidget);

        monotonicMicros += const Duration(seconds: 7).inMicroseconds;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        monotonicMicros += const Duration(seconds: 2).inMicroseconds;
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('ออก'));
        await tester.pumpAndSettle();

        final sessions = await database.select(database.learningSessions).get();
        final segments = await database
            .select(database.learningTimeSegments)
            .get();
        final timeOutbox = await (database.select(
          database.outboxOperations,
        )..where((row) => row.entityType.equals('learningTimeSegment'))).get();
        expect(sessions, hasLength(1));
        expect(sessions.single.state, 'abandoned');
        expect(segments, hasLength(2));
        expect(
          segments.fold<int>(0, (sum, row) => sum + row.activeDurationMs),
          9000,
        );
        expect(timeOutbox, hasLength(2));
        expect(await database.select(database.srsStates).get(), isEmpty);
        expect(
          await database.select(database.pointsLedgerEntries).get(),
          isEmpty,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
    );

    test(
      'default learning timezone is canonical and reconciles eligible streak',
      () async {
        final database = _testDatabase();
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
        );
        final dependencies = await bootstrap.initialize();
        expect(dependencies.quest.timezoneId, 'Asia/Bangkok');
        expect(dependencies.streak, isNotNull);
        expect(dependencies.streak!.timezoneId, 'Asia/Bangkok');
        expect(dependencies.streak!.timezoneId, dependencies.quest.timezoneId);
        final owner = await dependencies.localOwners!.getOrCreateActiveOwner();
        final target = await _insertBootstrapCurrentActivityTarget(
          database,
          ownerId: owner.id,
          startedAtUtc: DateTime.utc(2026, 8, 24, 8),
        );
        final pending = dependencies.currentActivityEvidence!.capture(
          input: CurrentActivityInput.meaningMultipleChoice,
          sessionId: target.sessionId,
          wordId: target.wordId,
          isCorrect: true,
          responseTimeMs: 500,
          attemptNumber: 1,
        );

        await pending.record();
        await dependencies.learningReconciliation!.drain();

        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );
        expect(
          await (database.select(database.eventsV2)..where(
                (row) =>
                    row.aggregateType.equals('LearningSession') &
                    row.aggregateId.equals(target.sessionId) &
                    row.idempotencyKey.equals(
                      'learning-attempt:${pending.sourceEvidenceId}:v2',
                    ),
              ))
              .get(),
          hasLength(1),
        );
        final streakState = await (database.select(
          database.streakStates,
        )..where((row) => row.ownerId.equals(owner.id))).getSingleOrNull();
        expect(streakState, isNotNull);
        expect(streakState!.currentStreakDays, 1);
      },
    );

    test('closes the database when later composition fails', () async {
      final database = AppDatabase(NativeDatabase.memory());
      final bootstrap = AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        syncGatewayFactory: () => throw StateError('gateway unavailable'),
      );

      await expectLater(bootstrap.initialize(), throwsStateError);
      await expectLater(
        database.customSelect('SELECT 1').getSingle(),
        throwsA(anything),
      );
    });

    test(
      'entry-store creation failure falls back to signed-out volatile guest state',
      () async {
        final bootstrap = AppBootstrap(
          createDatabase: _testDatabase,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          bindGuestOwnership: true,
          createEntryStateStore: () async {
            throw StateError('preferences unavailable');
          },
        );

        final dependencies = await bootstrap.initialize();
        final guest = await dependencies.guestSessionService.start();

        expect(dependencies.initialRoute, AppRoute.login);
        expect(guest, isA<GuestSessionStarted>());
      },
    );

    test('shares the bootstrap entry store with account transitions', () async {
      final entryState = _MemoryAppEntryStateStore(AppEntryMode.guest);
      final gateway = _BootstrapAccountGateway(
        currentSession: const AccountSession(
          uid: 'account-user',
          email: 'student@example.com',
          isAnonymous: false,
          emailVerified: true,
        ),
      );
      var factoryCalls = 0;
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        accountGatewayFactory: () => gateway,
        createEntryStateStore: () async {
          factoryCalls += 1;
          return entryState;
        },
      );

      final dependencies = await bootstrap.initialize();
      await dependencies.account!.signOutToLocalGuest();

      expect(factoryCalls, 1);
      expect(dependencies.initialRoute, AppRoute.home);
      expect(entryState.clearCalls, 1);
      expect(entryState.mode, AppEntryMode.signedOut);
    });

    test(
      'disposal cancels owner binding before closing the database',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        final delegate = _ControllableBootstrapGuestSessionService();
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: delegate,
          createEntryStateStore: _createSignedOutEntryState,
          bindGuestOwnership: true,
        );

        final dependencies = await bootstrap.initialize();
        await dependencies.guestSessionService.start();
        await dependencies.dispose().timeout(const Duration(milliseconds: 250));
        delegate.complete(
          const GuestSessionStarted(uid: 'late-bootstrap-provider'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(delegate.startCalls, 1);
        await expectLater(
          database.customSelect('SELECT 1').getSingle(),
          throwsA(anything),
        );
      },
    );

    test('disposal drains blocked sync before closing the database', () async {
      final database = AppDatabase(NativeDatabase.memory());
      final gateway = _BlockingBootstrapSyncGateway();
      final bootstrap = AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _SuccessfulGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        bindGuestOwnership: true,
        syncGatewayFactory: () => gateway,
      );

      final dependencies = await bootstrap.initialize();
      await dependencies.guestSessionService.start();
      await dependencies.syncTrigger!.request(SyncTriggerReason.manualRetry);
      await dependencies.vocabulary!.createCategory('Blocked sync');
      await gateway.pushEntered.future;

      var disposeCompleted = false;
      final disposing = dependencies.dispose().whenComplete(
        () => disposeCompleted = true,
      );
      await Future<void>.delayed(Duration.zero);
      final completedBeforeProvider = disposeCompleted;
      Object? databaseErrorBeforeProvider;
      QueryRow? databaseOpenBeforeProvider;
      try {
        databaseOpenBeforeProvider = await database
            .customSelect('SELECT 1')
            .getSingle();
      } catch (error) {
        databaseErrorBeforeProvider = error;
      }

      gateway.releasePush.complete();
      await disposing;

      expect(completedBeforeProvider, isFalse);
      expect(databaseErrorBeforeProvider, isNull);
      expect(databaseOpenBeforeProvider!.read<int>('1'), 1);
      await expectLater(
        database.customSelect('SELECT 1').getSingle(),
        throwsA(anything),
      );
      await expectLater(
        dependencies.syncTrigger!.request(SyncTriggerReason.manualRetry),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'production bootstrap keeps persisted v15 assessment runs dormant after restart',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'lexiquest-assessment-bootstrap-',
        );
        final file = File(
          '${directory.path}${Platform.pathSeparator}assessment.sqlite',
        );
        AppDependencies? dependencies;
        try {
          final seed = AppDatabase(NativeDatabase(file));
          await _seedDormantAssessmentRun(seed);
          await seed.close();

          final bootstrap = AppBootstrap(
            createDatabase: () => AppDatabase(NativeDatabase(file)),
            initializeFirebase: () async {},
            initializeSupabase: () async {},
            loadConfig: _validConfig,
            guestSessionService: _StubGuestSessionService(),
            createEntryStateStore: _createSignedOutEntryState,
          );
          dependencies = await bootstrap.initialize();

          expect(dependencies.assessment, isNull);
          expect(
            await dependencies.database!
                .customSelect(
                  'SELECT id, state FROM assessment_runs ORDER BY id',
                )
                .map((row) => row.data)
                .get(),
            [
              {'id': 'bootstrap-assessment-run', 'state': 'completed'},
            ],
          );
          expect(
            await dependencies.database!
                .customSelect('SELECT COUNT(*) AS count FROM assessment_runs')
                .map((row) => row.read<int>('count'))
                .getSingle(),
            1,
            reason: 'schema presence must not create another assessment run',
          );
          expect(
            await dependencies.database!
                .customSelect(
                  'SELECT COUNT(*) AS count FROM experiment_assignments',
                )
                .map((row) => row.read<int>('count'))
                .getSingle(),
            1,
            reason: 'bootstrap must not assign while assessment is off',
          );
          expect(
            AppRoute.values.map((route) => route.name),
            isNot(contains('assessment')),
          );
          expect(
            Feature.values.map((feature) => feature.name),
            contains('researchAssessment'),
          );
          expect(
            dependencies.features.stateOf(Feature.researchAssessment),
            FeatureState.hidden,
          );
          expect(
            dependencies.hasComposedDependencyFor(Feature.researchAssessment),
            isFalse,
          );

          final firstDispose = dependencies.dispose();
          final secondDispose = dependencies.dispose();
          expect(identical(firstDispose, secondDispose), isTrue);
          await firstDispose;
          dependencies = null;
        } finally {
          await dependencies?.dispose();
          if (await directory.exists()) await directory.delete(recursive: true);
        }
      },
    );

    test(
      'explicit assessment dependency injection preserves exact identity',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        final injected = _buildInjectedAssessment(database);
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          assessmentOverride: injected,
        );

        final dependencies = await bootstrap.initialize();

        expect(dependencies.assessment, same(injected));
        expect(
          dependencies.hasComposedDependencyFor(Feature.researchAssessment),
          isTrue,
        );
        expect(
          dependencies.features.stateOf(Feature.researchAssessment),
          FeatureState.hidden,
          reason: 'dependency composition must not auto-enable delivery',
        );
        expect(await bootstrap.initialize(), same(dependencies));
        await dependencies.dispose();
        await dependencies.dispose();
      },
    );

    test(
      'composes verified bundled lexical bytes into pinned vocabulary reads',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        final bytes = _verifiedLexicalArtifactBytes();
        await _seedPackagedLexicalArtifact(database, bytes);
        final requested = <ContentIdentity>[];
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          loadContentArtifactBytes: (identity) async {
            requested.add(identity);
            return identity == _lexicalIdentity ? bytes : null;
          },
        );
        AppDependencies? dependencies;
        try {
          dependencies = await bootstrap.initialize();
          final words = await dependencies.vocabulary!.readPinnedByIds(const [
            'word:station',
          ]);

          expect(requested, const [_lexicalIdentity]);
          expect(words.single.richMetadata!.ipa, '/ˈsteɪ.ʃən/');
          expect(words.single.richMetadata!.audio!.assetId, 'audio:station:en');
        } finally {
          await dependencies?.dispose();
        }
      },
    );
  });

  group('resolveAndroidAppCheckProvider', () {
    test('returns the debug provider when debugMode is true', () {
      final provider = resolveAndroidAppCheckProvider(debugMode: true);
      expect(provider, isA<AndroidDebugProvider>());
      expect(provider.type, 'debug');
    });

    test('returns the Play Integrity provider when debugMode is false', () {
      final provider = resolveAndroidAppCheckProvider(debugMode: false);
      expect(provider, isA<AndroidPlayIntegrityProvider>());
      expect(provider.type, 'playIntegrity');
    });

    test(
      'selects debug only for the exact debug flag, not a truthy default',
      () {
        // Regression guard: the production default is `!kReleaseMode`, so a
        // release build (kReleaseMode == true) must resolve to Play Integrity
        // and never fall back to the debug provider.
        expect(
          resolveAndroidAppCheckProvider(debugMode: false).runtimeType,
          AndroidPlayIntegrityProvider,
        );
      },
    );
  });
}

const _lexicalIdentity = ContentIdentity(
  type: ContentType.lexicalMetadata,
  id: 'word:station',
  revision: 1,
);

Uint8List _verifiedLexicalArtifactBytes() => Uint8List.fromList(
  utf8.encode(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'wordId': _lexicalIdentity.id,
      'contentRevision': _lexicalIdentity.revision,
      'ipa': '/ˈsteɪ.ʃən/',
      'examples': <String>['The station is near the market.'],
      'synonyms': <String>['terminal'],
      'antonyms': <String>[],
      'audio': <String, Object?>{
        'language': 'en',
        'assetId': 'audio:station:en',
      },
    }),
  ),
);

Future<void> _seedPackagedLexicalArtifact(
  AppDatabase database,
  Uint8List bytes,
) async {
  const createdAt = 1;
  final wordChecksum = ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: 'category:pack',
    spelling: 'station',
    normalizedSpelling: 'station',
    meaning: 'สถานี',
    normalizedMeaning: 'สถานี',
    partOfSpeech: 'noun',
    cefrLevel: 'A1',
    source: 'pack:v1',
    isGlobal: true,
  );
  await database.customInsert(
    "INSERT INTO local_owners(id, account_state, created_at_utc_ms, is_active) "
    "VALUES ('packaged-owner', 'localGuest', $createdAt, 0)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_categories "
    "(id, owner_id, name, normalized_name, created_at_utc_ms, "
    "updated_at_utc_ms) VALUES "
    "('category:pack', 'packaged-owner', 'Pack', 'pack', $createdAt, $createdAt)",
  );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: _lexicalIdentity.id,
          ownerId: 'packaged-owner',
          categoryId: 'category:pack',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          cefrLevel: const Value('A1'),
          source: const Value('pack:v1'),
          isGlobal: const Value(true),
          contentRevision: Value(_lexicalIdentity.revision),
          contentChecksumSha256: Value(wordChecksum),
          contentProvenance: Value(ContentProvenance.packaged.name),
          contentReviewState: Value(ContentReviewState.approved.name),
          contentPublicationState: Value(
            ContentPublicationState.published.name,
          ),
          createdAtUtcMs: createdAt,
          updatedAtUtcMs: createdAt,
        ),
      );
  await database
      .into(database.contentManifests)
      .insert(
        ContentManifestsCompanion.insert(
          id: 'manifest:lexical:station:r1',
          contentType: _lexicalIdentity.type.name,
          contentId: _lexicalIdentity.id,
          revision: _lexicalIdentity.revision,
          checksumSha256: sha256.convert(bytes).toString(),
          byteLength: bytes.length,
          provenance: ContentProvenance.packaged.name,
          sourceUri: 'asset://lexical-metadata/station/r1.json',
          reviewState: ContentReviewState.approved.name,
          publicationState: ContentPublicationState.published.name,
          createdAtUtcMs: createdAt,
          reviewedAtUtcMs: const Value(2),
          publishedAtUtcMs: const Value(3),
        ),
      );
}

AssessmentUseCases _buildInjectedAssessment(AppDatabase database) {
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'injected-assessment-owner',
    nowUtc: () => DateTime.utc(2026, 8, 14),
  );
  final learning = LearningUseCases(
    owners: owners,
    repository: DriftLearningRepository(database),
    generateId: () => 'injected-assessment-evidence',
    nowUtc: () => DateTime.utc(2026, 8, 14),
    buildInfo: const AppBuildInfo(
      version: '1.0.0',
      buildId: 'task-12-bootstrap-test',
    ),
  );
  return AssessmentUseCases(
    owners: owners,
    repository: DriftAssessmentRepository(database),
    learning: learning,
    experimentRegistry: const NoOpExperimentRegistry(),
    consentRegistry: const NoOpConsentRegistry(),
    rolloutModeProvider: const FixedEvidencePolicyRolloutModeProvider.legacy(),
    protocolModeCatalog: const ResearchProtocolModeCatalog(
      mappings: <ResearchProtocolModeMapping>[],
    ),
    instrumentCatalog: AssessmentInstrumentCatalog(entries: const []),
    buildInfo: const AppBuildInfo(
      version: '1.0.0',
      buildId: 'task-12-bootstrap-test',
    ),
    databaseSchemaVersion: AppDatabase.currentSchemaVersion,
    nowUtc: () => DateTime.utc(2026, 8, 14),
  );
}

Future<void> _seedDormantAssessmentRun(AppDatabase database) async {
  const ownerId = 'bootstrap-assessment-owner';
  const experimentId = 'bootstrap-assessment-study';
  final assignmentId =
      DriftExperimentAssignmentRepository.canonicalAssignmentId(
        ownerId: ownerId,
        experimentId: experimentId,
        experimentVersion: 1,
      );
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
    "VALUES ('$ownerId', NULL, 'localGuest', 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO research_consents '
    '(id, owner_id, consent_version, consent_state, decided_at_utc_ms, '
    'withdrawn_at_utc_ms) VALUES '
    "('bootstrap-assessment-consent', '$ownerId', 1, 'withdrawn', 2, 3)",
  );
  await database.customInsert(
    'INSERT INTO experiment_assignments '
    '(id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms) VALUES (?, ?, ?, 1, ?, ?, 2)',
    variables: [
      Variable<String>(assignmentId),
      const Variable<String>(ownerId),
      const Variable<String>(experimentId),
      const Variable<String>('enforced-a'),
      const Variable<String>('assessment-protocol-v1'),
    ],
  );
  await database.customInsert(
    'INSERT INTO learning_sessions '
    '(id, owner_id, activity_type, state, started_at_utc_ms, ended_at_utc_ms, '
    'app_version, build_id) VALUES '
    "('bootstrap-assessment-session', '$ownerId', 'assessment', "
    "'completed', 4, 6, '1.0.0', 'task-12-bootstrap-test')",
  );
  await database.customInsert(
    'INSERT INTO assessment_runs '
    '(id, owner_id, learning_session_id, study_cycle_id, phase, state, '
    'protocol_id, protocol_version, experiment_id, experiment_version, '
    'assignment_id, cohort, consent_version, consent_decided_at_utc_ms, '
    'instrument_id, instrument_version, form_id, form_version, '
    'instrument_checksum_sha256, form_checksum_sha256, app_version, build_id, '
    'database_schema_version, content_revision, evidence_policy_version, '
    'feature_contract_revision, feature_contract_hash, started_at_utc_ms, '
    'completed_at_utc_ms, abandoned_at_utc_ms) VALUES '
    "('bootstrap-assessment-run', '$ownerId', 'bootstrap-assessment-session', "
    "'bootstrap-cycle', 'pre', 'completed', 'assessment-protocol', "
    "'assessment-protocol-v1', '$experimentId', 1, ?, 'enforced-a', 1, 2, "
    "'vocabulary-outcome', '1.0.0', 'form-a', '1.0.0', ?, ?, '1.0.0', "
    "'task-12-bootstrap-test', 15, 'assessment-content-r1', "
    "'learning-evidence-v1', '8-44-r1', ?, 4, 6, NULL)",
    variables: [
      Variable<String>(assignmentId),
      const Variable<String>(
        '1111111111111111111111111111111111111111111111111111111111111111',
      ),
      const Variable<String>(
        '2222222222222222222222222222222222222222222222222222222222222222',
      ),
      const Variable<String>(
        '3333333333333333333333333333333333333333333333333333333333333333',
      ),
    ],
  );
}

final class _BootstrapAiTutorController implements AiTutorController {
  _BootstrapAiTutorController({Future<void>? disposal})
    : _disposal = disposal ?? Future<void>.value();

  final Future<void> _disposal;
  int disposeCalls = 0;

  @override
  Future<void> dispose() {
    disposeCalls += 1;
    return _disposal;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _BootstrapManagedVoiceProvider implements ManagedVoiceProvider {
  _BootstrapManagedVoiceProvider({Future<void>? disposal, this.disposalError})
    : _disposal = disposal ?? Future<void>.value();

  final Future<void> _disposal;
  final Object? disposalError;
  int disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _disposal;
    final error = disposalError;
    if (error != null) throw error;
  }

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    return VoicePlaybackResult(
      requestedEngine: request.assignedEngine ?? VoiceEngine.nativeTts,
      actualEngine: request.assignedEngine ?? VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}

final class _MemoryAppEntryStateStore implements AppEntryStateStore {
  _MemoryAppEntryStateStore([this.mode = AppEntryMode.signedOut]);

  AppEntryMode mode;
  int clearCalls = 0;
  int markGuestCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls += 1;
    mode = AppEntryMode.signedOut;
  }

  @override
  Future<void> markGuest() async {
    markGuestCalls += 1;
    mode = AppEntryMode.guest;
  }

  @override
  Future<AppEntryMode> read() async => mode;
}

final class _BootstrapAccountGateway implements AccountGateway {
  _BootstrapAccountGateway({this.currentSession});

  @override
  AccountSession? currentSession;

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) async => currentSession = AccountSession(
    uid: 'account-user',
    email: email,
    isAnonymous: false,
    emailVerified: false,
  );

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => register(email: email, password: password);

  @override
  Future<void> signOut() async {
    currentSession = null;
  }

  @override
  Future<void> applyEmailVerificationCode(String code) async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {}

  @override
  Future<AccountSession> reload() async => currentSession!;

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> sendVerification() async {}
}

final class _BootstrapResearchStateProvider
    implements CurrentActivityResearchStateProvider {
  @override
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  }) async => CurrentActivityResearchSnapshot(
    engagementAllowed: true,
    consentContext: const ConsentContext(
      researchConsentVersion: 1,
      aiConsentGranted: false,
      voiceConsentGranted: false,
      socialConsentGranted: false,
    ),
    experimentContext: ExperimentContext(
      experimentId: 'bootstrap-experiment',
      variantId: 'shadow',
      assignedAtUtc: occurredAtUtc.subtract(const Duration(minutes: 1)),
    ),
    protocolId: 'bootstrap-protocol',
    protocolVersion: '1.0.0',
    experimentVersion: 1,
    assignmentId: 'bootstrap-assignment',
  );

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async => LearningEventContext(
    consentContext: const ConsentContext(
      researchConsentVersion: 1,
      aiConsentGranted: false,
      voiceConsentGranted: false,
      socialConsentGranted: false,
    ),
    experimentContext: ExperimentContext(
      experimentId: evidenceContext.experimentId!,
      variantId: evidenceContext.cohort!,
      assignedAtUtc: occurredAtUtc.subtract(const Duration(minutes: 1)),
    ),
    protocolId: evidenceContext.protocolId,
    protocolVersion: evidenceContext.protocolVersion,
    experimentVersion: evidenceContext.experimentVersion,
    assignmentId: evidenceContext.assignmentId,
    featureContractIdentity: FeatureContractIdentity(
      revision: evidenceContext.featureContractRevision,
      semanticHash: evidenceContext.featureContractHash,
    ),
  );
}

final class _BootstrapSyncGateway
    implements SyncGateway, LearningTimeSegmentSyncRolloutGateway {
  _BootstrapSyncGateway([
    this.learningTimeSegmentSyncRollout =
        const LearningTimeSegmentSyncRollout.off(),
  ]);

  @override
  final LearningTimeSegmentSyncRollout learningTimeSegmentSyncRollout;

  int policyFetches = 0;

  @override
  Future<CloudSyncPolicy> fetchPolicy() async {
    policyFetches += 1;
    final now = DateTime.now().toUtc();
    return CloudSyncPolicy(
      enabled: true,
      source: CloudSyncPolicySource.remote,
      fetchedAtUtc: now,
      expiresAtUtc: now.add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async => PullPage(changes: const [], nextCursor: after, hasMore: false);

  @override
  Future<PushResult> push(PushMutation mutation) {
    throw UnimplementedError();
  }
}

final class _BlockingBootstrapSyncGateway implements SyncGateway {
  final Completer<void> pushEntered = Completer<void>();
  final Completer<void> releasePush = Completer<void>();

  @override
  Future<CloudSyncPolicy> fetchPolicy() async {
    final now = DateTime.now().toUtc();
    return CloudSyncPolicy(
      enabled: true,
      source: CloudSyncPolicySource.remote,
      fetchedAtUtc: now,
      expiresAtUtc: now.add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async => PullPage(
    changes: const <SyncEntity>[],
    nextCursor: after,
    hasMore: false,
  );

  @override
  Future<PushResult> push(PushMutation mutation) async {
    if (!pushEntered.isCompleted) pushEntered.complete();
    await releasePush.future;
    return PushAcknowledged(
      operationId: mutation.operationId,
      resultingRevision: mutation.localRevision,
      acknowledgedAtUtc: DateTime.now().toUtc(),
    );
  }
}
