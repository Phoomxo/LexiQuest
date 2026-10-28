import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/application/assessment_use_cases.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/research/application/assigned_learning_event_context_provider.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';

void main() {
  test(
    'assessment response changes Outcome evidence only and preserves every learning authority byte-for-byte',
    () async {
      final harness = await _IsolationHarness.create();
      addTearDown(harness.close);
      await _seedCanonicalProjectionState(harness.database);
      final before = await _isolationSnapshot(harness.database);
      expect(before.values, everyElement(isNot('[]')));
      await harness.useCases.start(_startCommand());

      final result = await harness.useCases.recordResponse(
        runId: _runId,
        sourceEvidenceId: _evidenceId,
        itemId: _itemId,
        submittedResponse: 'choice-a',
        responseTimeMs: 725,
        occurredAtUtc: _responseAtUtc,
      );

      expect(result.inserted, isTrue);
      expect(result.isCorrect, isTrue);
      expect(await _isolationSnapshot(harness.database), before);
      final attempts = await harness.database
          .select(harness.database.answerAttempts)
          .get();
      expect(attempts, hasLength(1));
      final attempt = attempts.single;
      expect(attempt.id, _evidenceId);
      expect(attempt.isCorrect, isTrue);
      final context = EvidenceContext.fromJson(
        (jsonDecode(attempt.evidenceContextJson) as Map)
            .cast<String, Object?>(),
      );
      expect(context.evidenceClass, EvidenceClass.assessment);
      expect(context.rolloutMode, EvidencePolicyRolloutMode.enforced);
      expect(context.assignmentId, _assignmentId);
      expect(context.assessmentItemId, _itemId);
      expect(context.assessmentResponseCode, 'correct');
      expect(context.scoringRuleVersion, _scoringRuleVersion);
      expect(context.engagementAllowed, isFalse);
      final canonicalEvents =
          await (harness.database.select(harness.database.eventsV2)..where(
                (row) => row.eventId.equals('learning-event:$_evidenceId'),
              ))
              .get();
      expect(canonicalEvents, hasLength(1));
      expect(canonicalEvents.single.aggregateId, _sessionId);
      expect(canonicalEvents.single.ownerId, _ownerId);
      expect(
        canonicalEvents.single.idempotencyKey,
        'learning-attempt:$_evidenceId:v2',
      );
      expect(
        (await _tableNames(harness.database)).intersection(<String>{
          'assessment_attempts',
          'assessment_responses',
          'assessment_scores',
        }),
        isEmpty,
      );
      expect(await _count(harness.database, 'assessment_runs'), 1);
    },
  );

  test(
    'complete waits for the canonical AnswerAttempt Event transaction boundary',
    () async {
      final gate = _BlockingLearningRepository();
      final harness = await _IsolationHarness.create(repositoryGate: gate);
      addTearDown(harness.close);
      await harness.useCases.start(_startCommand());

      final response = harness.useCases.recordResponse(
        runId: _runId,
        sourceEvidenceId: 'assessment-evidence-blocked-complete',
        itemId: _itemId,
        submittedResponse: 'choice-a',
        responseTimeMs: 725,
        occurredAtUtc: _responseAtUtc,
      );
      await gate.entered.future;
      harness.now = _terminalAtUtc;
      var terminalFinished = false;
      final completion = harness.useCases.complete(_runId).then((value) {
        terminalFinished = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);

      expect(terminalFinished, isFalse);
      gate.release.complete();
      expect((await response).inserted, isTrue);
      expect((await completion).state, AssessmentRunState.completed);
      expect(await _count(harness.database, 'answer_attempts'), 1);
      expect(
        await (harness.database.select(harness.database.eventsV2)..where(
              (row) => row.eventId.equals(
                'learning-event:assessment-evidence-blocked-complete',
              ),
            ))
            .get(),
        hasLength(1),
      );
    },
  );

  test(
    'abandon waits for the same canonical evidence serialization boundary',
    () async {
      final gate = _BlockingLearningRepository();
      final harness = await _IsolationHarness.create(repositoryGate: gate);
      addTearDown(harness.close);
      await harness.useCases.start(_startCommand());

      final response = harness.useCases.recordResponse(
        runId: _runId,
        sourceEvidenceId: 'assessment-evidence-blocked-abandon',
        itemId: _itemId,
        submittedResponse: 'choice-b',
        responseTimeMs: 800,
        occurredAtUtc: _responseAtUtc,
      );
      await gate.entered.future;
      harness.now = _terminalAtUtc;
      var terminalFinished = false;
      final abandonment = harness.useCases.abandon(_runId).then((value) {
        terminalFinished = true;
        return value;
      });
      await Future<void>.delayed(Duration.zero);

      expect(terminalFinished, isFalse);
      gate.release.complete();
      expect((await response).isCorrect, isFalse);
      expect((await abandonment).state, AssessmentRunState.abandoned);
      expect(await _count(harness.database, 'answer_attempts'), 1);
      await expectLater(
        harness.useCases.recordResponse(
          runId: _runId,
          sourceEvidenceId: 'assessment-evidence-after-abandon',
          itemId: _itemId,
          submittedResponse: 'choice-a',
          responseTimeMs: 500,
          occurredAtUtc: _terminalAtUtc.add(const Duration(seconds: 1)),
        ),
        throwsA(isA<AssessmentRunConflict>()),
      );
    },
  );
}

final class _IsolationHarness {
  _IsolationHarness({
    required this.database,
    required this.useCases,
    required this._clock,
  });

  final AppDatabase database;
  final AssessmentUseCases useCases;
  final _MutableClock _clock;

  DateTime get now => _clock.value;
  set now(DateTime value) => _clock.value = value;

  static Future<_IsolationHarness> create({
    _BlockingLearningRepository? repositoryGate,
  }) async {
    final database = AppDatabase(NativeDatabase.memory());
    await _seedCore(database);
    final assignmentRepository = DriftExperimentAssignmentRepository(database);
    final experiments = DriftExperimentRegistry(assignmentRepository);
    final consents = DriftConsentRegistry(database);
    final protocolCatalog = ResearchProtocolModeCatalog(
      mappings: const [
        ResearchProtocolModeMapping(
          protocolId: _protocolId,
          experimentId: _experimentId,
          experimentVersion: 1,
          protocolVersion: _protocolVersion,
          consentVersion: 1,
          mode: EvidencePolicyRolloutMode.enforced,
        ),
      ],
    );
    final eventContexts = AssignedLearningEventContextProvider(
      experimentRegistry: experiments,
      consentRegistry: consents,
      protocolModeCatalog: protocolCatalog,
    );
    final rollout = PersistedEvidencePolicyRolloutModeProvider(
      experimentRegistry: experiments,
      consentRegistry: consents,
      protocolModeCatalog: protocolCatalog,
      currentActivityResearchStateProvider: eventContexts,
    );
    final owners = const _Owners();
    final driftLearning = DriftLearningRepository(
      database,
      rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
    );
    repositoryGate?.delegate = driftLearning;
    final learning = LearningUseCases(
      owners: owners,
      repository: repositoryGate ?? driftLearning,
      generateId: () => 'unused-assessment-id',
      nowUtc: () => _responseAtUtc,
      buildInfo: const AppBuildInfo(version: _appVersion, buildId: _buildId),
      eventContextProvider: eventContexts,
    );
    final clock = _MutableClock(_startedAtUtc);
    final harness = _IsolationHarness(
      database: database,
      clock: clock,
      useCases: AssessmentUseCases(
        owners: owners,
        repository: DriftAssessmentRepository(database),
        learning: learning,
        experimentRegistry: experiments,
        consentRegistry: consents,
        rolloutModeProvider: rollout,
        protocolModeCatalog: protocolCatalog,
        instrumentCatalog: AssessmentInstrumentCatalog(
          entries: [_instrumentDefinition()],
        ),
        contentManifests: const _ContentManifests(),
        buildInfo: const AppBuildInfo(version: _appVersion, buildId: _buildId),
        databaseSchemaVersion: AppDatabase.currentSchemaVersion,
        nowUtc: clock.call,
      ),
    );
    return harness;
  }

  Future<void> close() => database.close();
}

final class _MutableClock {
  _MutableClock(this.value);

  DateTime value;

  DateTime call() => value;
}

final class _BlockingLearningRepository
    implements LearningRepository, LearningEvidenceReplayRepository {
  late LearningRepository delegate;
  final Completer<void> entered = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    if (!entered.isCompleted) entered.complete();
    await release.future;
    return delegate.recordAnswer(command);
  }

  @override
  Future<CommittedAnswerReplay?> replayCommittedAnswer(
    RecordAnswerCandidate candidate,
  ) {
    final replay = delegate;
    return replay is LearningEvidenceReplayRepository
        ? (replay as LearningEvidenceReplayRepository).replayCommittedAnswer(
            candidate,
          )
        : Future<CommittedAnswerReplay?>.value(null);
  }

  @override
  Future<void> abandonActiveSessions({required String ownerId}) =>
      delegate.abandonActiveSessions(ownerId: ownerId);

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) => delegate.finishSession(
    ownerId: ownerId,
    sessionId: sessionId,
    endedAtUtc: endedAtUtc,
  );

  @override
  Future<LearningSessionSummary?> getActiveSession({required String ownerId}) =>
      delegate.getActiveSession(ownerId: ownerId);

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) => delegate.listDueWords(ownerId: ownerId, nowUtc: nowUtc, limit: limit);

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    limit: limit,
  );

  @override
  Future<List<LearningSessionSummary>> listSessionHistory({
    required String ownerId,
    required int limit,
  }) => delegate.listSessionHistory(ownerId: ownerId, limit: limit);

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) => delegate.readReadingProgress(
    ownerId: ownerId,
    documentId: documentId,
    documentRevision: documentRevision,
  );

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) => delegate.saveReadingProgress(command);

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);
}

Future<void> _seedCore(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners(id, account_state, created_at_utc_ms) '
    'VALUES (?, ?, ?)',
    variables: [
      const Variable<String>(_ownerId),
      const Variable<String>('localGuest'),
      Variable<int>(_consentAtUtc.millisecondsSinceEpoch),
    ],
  );
  await database.customInsert(
    'INSERT INTO research_consents('
    'id, owner_id, consent_version, consent_state, decided_at_utc_ms) '
    'VALUES (?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('consent-assessment'),
      const Variable<String>(_ownerId),
      const Variable<int>(1),
      const Variable<String>('accepted'),
      Variable<int>(_consentAtUtc.millisecondsSinceEpoch),
    ],
  );
  await database.customInsert(
    'INSERT INTO experiment_assignments('
    'id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?)',
    variables: [
      Variable<String>(_assignmentId),
      const Variable<String>(_ownerId),
      const Variable<String>(_experimentId),
      const Variable<int>(1),
      const Variable<String>(_cohort),
      const Variable<String>(_protocolVersion),
      Variable<int>(_assignedAtUtc.millisecondsSinceEpoch),
    ],
  );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: _categoryId,
          ownerId: _ownerId,
          name: 'Assessment',
          normalizedName: 'assessment',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: _wordId,
          ownerId: _ownerId,
          categoryId: _categoryId,
          spelling: 'evaluate',
          normalizedSpelling: 'evaluate',
          meaning: 'assess',
          normalizedMeaning: 'assess',
          partOfSpeech: 'verb',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await DriftLearningRepository(database).startSession(
    LearningSessionDraft(
      id: _sessionId,
      ownerId: _ownerId,
      activityType: 'assessment',
      startedAtUtc: _sessionAtUtc,
      appVersion: _appVersion,
      buildId: _buildId,
    ),
  );
}

Future<void> _seedCanonicalProjectionState(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO srs_states('
    'id, owner_id, word_id, stability, difficulty, interval_days, repetitions, '
    'lapses, last_review_at_utc_ms, due_at_utc_ms, algorithm_version) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('srs-assessment'),
      const Variable<String>(_ownerId),
      const Variable<String>(_wordId),
      const Variable<double>(2),
      const Variable<double>(3),
      const Variable<int>(4),
      const Variable<int>(2),
      const Variable<int>(0),
      Variable<int>(_sessionAtUtc.millisecondsSinceEpoch),
      Variable<int>(_terminalAtUtc.millisecondsSinceEpoch),
      const Variable<int>(1),
    ],
  );
  await database.customInsert(
    'INSERT INTO points_ledger_entries('
    'id, owner_id, idempotency_key, entry_type, amount, occurred_at_utc_ms) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('points-existing'),
      const Variable<String>(_ownerId),
      const Variable<String>('points-existing-key'),
      const Variable<String>('questCompletion'),
      const Variable<int>(20),
      Variable<int>(_sessionAtUtc.millisecondsSinceEpoch),
    ],
  );
  await database.customInsert(
    'INSERT INTO reward_transactions('
    'id, owner_id, idempotency_key, transaction_type, amount, item_id, '
    'catalog_version, source_event_id, occurred_at_utc_ms) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('reward-purchase-existing'),
      const Variable<String>(_ownerId),
      const Variable<String>('purchase-existing-key'),
      const Variable<String>('purchase'),
      const Variable<int>(-10),
      const Variable<String>('theme_ocean'),
      const Variable<int>(1),
      const Variable<String>('source-purchase-existing'),
      Variable<int>(_sessionAtUtc.millisecondsSinceEpoch),
    ],
  );
  await database.customInsert(
    'INSERT INTO reward_transactions('
    'id, owner_id, idempotency_key, transaction_type, amount, item_id, '
    'catalog_version, source_event_id, occurred_at_utc_ms) '
    'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('reward-equip-existing'),
      const Variable<String>(_ownerId),
      const Variable<String>('equip-existing-key'),
      const Variable<String>('equip'),
      const Variable<int>(0),
      const Variable<String>('theme_ocean'),
      const Variable<int>(1),
      const Variable<String>('source-equip-existing'),
      Variable<int>(_sessionAtUtc.millisecondsSinceEpoch + 1),
    ],
  );
  await database.customInsert(
    'INSERT INTO owned_reward_items('
    'id, owner_id, item_id, catalog_version, acquired_by_transaction_id, '
    'acquired_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('owned-existing'),
      const Variable<String>(_ownerId),
      const Variable<String>('theme_ocean'),
      const Variable<int>(1),
      const Variable<String>('reward-purchase-existing'),
      Variable<int>(_sessionAtUtc.millisecondsSinceEpoch),
    ],
  );
  await database.customInsert(
    'INSERT INTO equipped_reward_items('
    'id, owner_id, slot, item_id, equipped_at_utc_ms) VALUES (?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('equipped-existing'),
      const Variable<String>(_ownerId),
      const Variable<String>('theme'),
      const Variable<String>('theme_ocean'),
      Variable<int>(_sessionAtUtc.millisecondsSinceEpoch + 1),
    ],
  );
  await database.customInsert(
    'INSERT INTO achievement_unlocks('
    'id, owner_id, achievement_id, definition_version, source_event_id, '
    'unlocked_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('achievement-existing'),
      const Variable<String>(_ownerId),
      const Variable<String>('existing-achievement'),
      const Variable<int>(1),
      const Variable<String>('source-achievement-existing'),
      Variable<int>(_sessionAtUtc.millisecondsSinceEpoch),
    ],
  );
  await database.customInsert(
    'INSERT INTO quest_definitions('
    'quest_id, catalog_version, title, description, type, objectives_json, '
    'reward_json, tags_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    variables: const [
      Variable<String>('quest-existing'),
      Variable<int>(1),
      Variable<String>('Existing quest'),
      Variable<String>('Must remain byte-equal'),
      Variable<String>('milestone'),
      Variable<String>('[]'),
      Variable<String>('{"xp":0}'),
      Variable<String>('[]'),
    ],
  );
  await database.customInsert(
    'INSERT INTO quest_instances('
    'instance_id, quest_id, owner_id, catalog_version, assigned_at_utc_ms, state) '
    'VALUES (?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('quest-instance-existing'),
      const Variable<String>('quest-existing'),
      const Variable<String>(_ownerId),
      const Variable<int>(1),
      Variable<int>(_sessionAtUtc.millisecondsSinceEpoch),
      const Variable<String>('active'),
    ],
  );
  await database.customInsert(
    'INSERT INTO quest_objective_progress('
    'id, instance_id, objective_id, current_count, target_count, '
    'source_event_ids_json) VALUES (?, ?, ?, ?, ?, ?)',
    variables: const [
      Variable<String>('quest-objective-existing'),
      Variable<String>('quest-instance-existing'),
      Variable<String>('objective-existing'),
      Variable<int>(1),
      Variable<int>(3),
      Variable<String>('["source-existing"]'),
    ],
  );
  await database.customInsert(
    'INSERT INTO streak_states('
    'owner_id, current_streak_days, longest_streak_days, freeze_count, '
    'last_learned_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>(_ownerId),
      const Variable<int>(3),
      const Variable<int>(5),
      const Variable<int>(1),
      Variable<int>(_sessionAtUtc.millisecondsSinceEpoch),
      Variable<int>(_sessionAtUtc.millisecondsSinceEpoch),
    ],
  );
  await database.customInsert(
    'INSERT INTO learning_day_log('
    'id, owner_id, learning_day, first_session_at_utc_ms) VALUES (?, ?, ?, ?)',
    variables: [
      const Variable<String>('day-existing'),
      const Variable<String>(_ownerId),
      const Variable<String>('2026-08-14'),
      Variable<int>(_sessionAtUtc.millisecondsSinceEpoch),
    ],
  );
}

Future<Map<String, String>> _isolationSnapshot(AppDatabase database) async {
  const tables = <String, String>{
    'masterySrs': 'srs_states',
    'lifetimeXp': 'points_ledger_entries',
    'achievements': 'achievement_unlocks',
    'rewardTransactions': 'reward_transactions',
    'ownedRewards': 'owned_reward_items',
    'equippedRewards': 'equipped_reward_items',
    'questDefinitions': 'quest_definitions',
    'questInstances': 'quest_instances',
    'questProgress': 'quest_objective_progress',
    'streak': 'streak_states',
    'learningDays': 'learning_day_log',
  };
  final snapshot = <String, String>{};
  for (final entry in tables.entries) {
    final rows = await database
        .customSelect('SELECT * FROM ${entry.value}')
        .get();
    final encoded = rows.map((row) => row.data).toList(growable: false)
      ..sort((left, right) => jsonEncode(left).compareTo(jsonEncode(right)));
    snapshot[entry.key] = jsonEncode(encoded);
  }
  return Map<String, String>.unmodifiable(snapshot);
}

AssessmentStartCommand _startCommand() => const AssessmentStartCommand(
  runId: _runId,
  learningSessionId: _sessionId,
  studyCycleId: _studyCycleId,
  phase: AssessmentPhase.pre,
  instrumentId: _instrumentId,
  instrumentVersion: _instrumentVersion,
  formId: _formId,
  formVersion: _formVersion,
);

AssessmentInstrumentDefinition _instrumentDefinition() =>
    AssessmentInstrumentDefinition(
      instrumentId: _instrumentId,
      instrumentVersion: _instrumentVersion,
      formId: _formId,
      formVersion: _formVersion,
      formContentRevision: 1,
      sourceState: AssessmentCatalogSourceState.approved,
      reviewState: AssessmentCatalogReviewState.approved,
      protocolId: _protocolId,
      experimentId: _experimentId,
      experimentVersion: 1,
      contentRevision: _contentRevision,
      instrumentBytes: _instrumentBytes,
      formBytes: _formBytes,
      instrumentChecksumSha256: sha256.convert(_instrumentBytes).toString(),
      formChecksumSha256: sha256.convert(_formBytes).toString(),
      items: const [
        AssessmentItemDefinition(
          itemId: _itemId,
          prompt: 'Choose the best meaning.',
          wordId: _wordId,
          promptMode: 'assessmentResponse',
          scoringRuleVersion: _scoringRuleVersion,
          responses: {
            'choice-a': AssessmentControlledResponse(
              responseCode: 'correct',
              isCorrect: true,
            ),
            'choice-b': AssessmentControlledResponse(
              responseCode: 'incorrect',
              isCorrect: false,
            ),
          },
        ),
      ],
    );

final class _ContentManifests implements ContentManifestRepository {
  const _ContentManifests();

  @override
  Future<VerifiedContentManifest> requireVerified(
    ContentIdentity identity,
  ) async => VerifiedContentManifest(
    manifest: ContentManifest(
      storageId: 'manifest-form-a-r1',
      identity: identity,
      checksumSha256: sha256.convert(_formBytes).toString(),
      byteLength: _formBytes.length,
      provenance: ContentProvenance.packaged,
      sourceUri: 'asset://assessment/form-a',
      reviewState: ContentReviewState.approved,
      publicationState: ContentPublicationState.published,
      createdAtUtc: _consentAtUtc,
      reviewedAtUtc: _consentAtUtc,
      publishedAtUtc: _consentAtUtc,
    ),
    bytes: Uint8List.fromList(_formBytes),
  );
}

final class _Owners implements LocalOwnerRepository {
  const _Owners();

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(id: _ownerId, createdAtUtc: _consentAtUtc);

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async => identity.LocalOwner(
    id: _ownerId,
    firebaseUid: firebaseUid,
    createdAtUtc: _consentAtUtc,
  );
}

Future<int> _count(AppDatabase database, String table) => database
    .customSelect('SELECT COUNT(*) AS count FROM $table')
    .map((row) => row.read<int>('count'))
    .getSingle();

Future<Set<String>> _tableNames(AppDatabase database) => database
    .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
    .map((row) => row.read<String>('name'))
    .get()
    .then((rows) => rows.toSet());

const _ownerId = 'owner-assessment';
const _categoryId = 'category-assessment';
const _wordId = 'word-assessment';
const _sessionId = 'session-assessment';
const _runId = 'assessment-run-pre';
const _studyCycleId = 'study-cycle-2026';
const _protocolId = 'assessment-protocol';
const _protocolVersion = 'protocol-1.0.0';
const _experimentId = 'assessment-experiment';
const _cohort = 'enforced';
final _assignmentId = DriftExperimentAssignmentRepository.canonicalAssignmentId(
  ownerId: _ownerId,
  experimentId: _experimentId,
  experimentVersion: 1,
);
const _instrumentId = 'instrument-core';
const _instrumentVersion = 'instrument-v1';
const _formId = 'form-a';
const _formVersion = 'form-v1';
const _itemId = 'item-meaning-1';
const _scoringRuleVersion = 'score-v1';
const _contentRevision = 'assessment-content-v1';
const _evidenceId = 'assessment-evidence-isolation';
const _appVersion = '1.0.0';
const _buildId = 'task-12-isolation';
const _instrumentBytes = <int>[1, 3, 5, 7];
final _formBytes = AssessmentInstrumentDefinition.canonicalFormBytes(
  instrumentId: _instrumentId,
  instrumentVersion: _instrumentVersion,
  formId: _formId,
  formVersion: _formVersion,
  formContentRevision: 1,
  items: const [
    AssessmentItemDefinition(
      itemId: _itemId,
      prompt: 'Choose the best meaning.',
      wordId: _wordId,
      promptMode: 'assessmentResponse',
      scoringRuleVersion: _scoringRuleVersion,
      responses: {
        'choice-a': AssessmentControlledResponse(
          responseCode: 'correct',
          isCorrect: true,
        ),
        'choice-b': AssessmentControlledResponse(
          responseCode: 'incorrect',
          isCorrect: false,
        ),
      },
    ),
  ],
);
final _consentAtUtc = DateTime.utc(2026, 8, 1, 8);
final _assignedAtUtc = DateTime.utc(2026, 8, 2, 8);
final _sessionAtUtc = DateTime.utc(2026, 8, 14, 9, 59);
final _startedAtUtc = DateTime.utc(2026, 8, 14, 10);
final _responseAtUtc = DateTime.utc(2026, 8, 14, 10, 5);
final _terminalAtUtc = DateTime.utc(2026, 8, 14, 10, 30);
