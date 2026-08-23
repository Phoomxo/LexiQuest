import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/application/assessment_use_cases.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/research/application/assigned_learning_event_context_provider.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';

void main() {
  test('Ready returns separate pre and post Outcome summaries only', () async {
    final harness = await _ComparisonHarness.create();
    addTearDown(harness.close);
    await harness.createCompletedPair();

    final result = await harness.useCases.compare(_studyCycleId);

    expect(result, isA<AssessmentComparisonReady>());
    final ready = result as AssessmentComparisonReady;
    expect(
      ready.preOutcome,
      isA<AssessmentOutcomeSummary>()
          .having((value) => value.sampleSize, 'sample size', 1)
          .having((value) => value.correctCount, 'correct count', 1)
          .having((value) => value.incorrectCount, 'incorrect count', 0)
          .having((value) => value.accuracy, 'accuracy', 1.0),
    );
    expect(
      ready.postOutcome,
      isA<AssessmentOutcomeSummary>()
          .having((value) => value.sampleSize, 'sample size', 1)
          .having((value) => value.correctCount, 'correct count', 0)
          .having((value) => value.incorrectCount, 'incorrect count', 1)
          .having((value) => value.accuracy, 'accuracy', 0.0),
    );
    expect(ready.comparison.correctCountDelta, -1);
    expect(ready.comparison.accuracyDelta, -1.0);
    expect(await _forbiddenScoreTables(harness.database), isEmpty);
  });

  test(
    'catalog word prompt and completed-run interval are canonical evidence',
    () async {
      final corruptions =
          <
            ({
              String name,
              String column,
              Object Function(AssessmentRun run) value,
            })
          >[
            (
              name: 'word_id differs from the catalog item',
              column: 'word_id',
              value: (_) => _otherWordId,
            ),
            (
              name: 'prompt_mode differs from the catalog item',
              column: 'prompt_mode',
              value: (_) => 'meaningChoice',
            ),
            (
              name: 'occurrence is before the run starts',
              column: 'occurred_at_utc_ms',
              value: (run) => run.startedAtUtc
                  .subtract(const Duration(milliseconds: 1))
                  .millisecondsSinceEpoch,
            ),
            (
              name: 'occurrence is after the exact terminal timestamp',
              column: 'occurred_at_utc_ms',
              value: (run) => run.completedAtUtc!
                  .add(const Duration(milliseconds: 1))
                  .millisecondsSinceEpoch,
            ),
          ];

      for (final corruption in corruptions) {
        final harness = await _ComparisonHarness.create();
        try {
          await harness.createCompletedPair();
          await _seedAlternateComparisonWord(harness.database);
          final preRun = await DriftAssessmentRepository(
            harness.database,
          ).getRun(_preRunId);
          final value = corruption.value(preRun);
          await harness.database.customUpdate(
            'UPDATE answer_attempts SET ${corruption.column} = ? WHERE id = ?',
            variables: [
              if (value is int)
                Variable<int>(value)
              else
                Variable<String>(value as String),
              const Variable<String>('evidence-pre-ready'),
            ],
          );

          final result = await harness.useCases.compare(_studyCycleId);
          expect(
            result,
            isA<AssessmentComparisonIncompatibleMetadata>(),
            reason: corruption.name,
          );
          expect(
            result,
            isNot(isA<AssessmentComparisonReady>()),
            reason: corruption.name,
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test('exact assessment occurrence boundaries remain compatible', () async {
    final harness = await _ComparisonHarness.create();
    addTearDown(harness.close);
    await harness.createCompletedPair();
    final repository = DriftAssessmentRepository(harness.database);
    final preRun = await repository.getRun(_preRunId);
    final postRun = await repository.getRun(_postRunId);

    await harness.database.customUpdate(
      'UPDATE answer_attempts SET occurred_at_utc_ms = ? WHERE id = ?',
      variables: [
        Variable<int>(preRun.startedAtUtc.millisecondsSinceEpoch),
        const Variable<String>('evidence-pre-ready'),
      ],
    );
    await harness.database.customUpdate(
      'UPDATE answer_attempts SET occurred_at_utc_ms = ? WHERE id = ?',
      variables: [
        Variable<int>(postRun.completedAtUtc!.millisecondsSinceEpoch),
        const Variable<String>('evidence-post-ready'),
      ],
    );

    expect(
      await harness.useCases.compare(_studyCycleId),
      isA<AssessmentComparisonReady>(),
    );
  });

  test('MissingPair covers absent and nonterminal pre or post runs', () async {
    final missing = await _ComparisonHarness.create();
    addTearDown(missing.close);
    await missing.startAndComplete(
      runId: _preRunId,
      sessionId: _preSessionId,
      phase: AssessmentPhase.pre,
      sourceEvidenceId: 'evidence-pre-only',
      submittedResponse: 'choice-a',
    );
    expect(
      await missing.useCases.compare(_studyCycleId),
      isA<AssessmentComparisonMissingPair>(),
    );

    final activePost = await _ComparisonHarness.create();
    addTearDown(activePost.close);
    await activePost.startAndComplete(
      runId: _preRunId,
      sessionId: _preSessionId,
      phase: AssessmentPhase.pre,
      sourceEvidenceId: 'evidence-pre-completed',
      submittedResponse: 'choice-a',
    );
    activePost.now = _postStartedAtUtc;
    await activePost.useCases.start(
      _command(
        runId: _postRunId,
        sessionId: _postSessionId,
        phase: AssessmentPhase.post,
      ),
    );
    expect(
      await activePost.useCases.compare(_studyCycleId),
      isA<AssessmentComparisonMissingPair>(),
    );
  });

  test(
    'every immutable run metadata mismatch is IncompatibleMetadata',
    () async {
      final mismatches = <String, Object>{
        'protocol_id': 'other-protocol',
        'protocol_version': 'protocol-2.0.0',
        'experiment_id': 'other-experiment',
        'experiment_version': 2,
        'instrument_id': 'other-instrument',
        'instrument_version': 'instrument-v2',
        'form_id': 'other-form',
        'form_version': 'form-v2',
        'instrument_checksum_sha256': _otherSha256,
        'form_checksum_sha256': _otherSha256,
        'content_revision': 'assessment-content-v2',
        'evidence_policy_version': 'learning-evidence-v2',
        'feature_contract_revision': 'contract-other',
        'feature_contract_hash': _otherSha256,
      };

      for (final mismatch in mismatches.entries) {
        final harness = await _ComparisonHarness.create();
        try {
          await harness.createCompletedPair();
          await harness.database.customUpdate(
            'UPDATE assessment_runs SET ${mismatch.key} = ? WHERE id = ?',
            variables: [
              if (mismatch.value is int)
                Variable<int>(mismatch.value as int)
              else
                Variable<String>(mismatch.value as String),
              const Variable<String>(_postRunId),
            ],
          );

          expect(
            await harness.useCases.compare(_studyCycleId),
            isA<AssessmentComparisonIncompatibleMetadata>(),
            reason: mismatch.key,
          );
        } finally {
          await harness.close();
        }
      }
    },
  );

  test(
    'different or unsupported canonical attempt scoring identity is incompatible',
    () async {
      final differentScoring = await _ComparisonHarness.create();
      addTearDown(differentScoring.close);
      await differentScoring.startAndComplete(
        runId: _preRunId,
        sessionId: _preSessionId,
        phase: AssessmentPhase.pre,
        sourceEvidenceId: 'evidence-pre-score-v1',
        submittedResponse: 'choice-a',
        itemId: _itemV1,
      );
      await differentScoring.startAndComplete(
        runId: _postRunId,
        sessionId: _postSessionId,
        phase: AssessmentPhase.post,
        sourceEvidenceId: 'evidence-post-score-v2',
        submittedResponse: 'choice-a',
        itemId: _itemV2,
      );
      expect(
        await differentScoring.useCases.compare(_studyCycleId),
        isA<AssessmentComparisonIncompatibleMetadata>(),
      );

      final unsupported = await _ComparisonHarness.create();
      addTearDown(unsupported.close);
      await unsupported.createCompletedPair();
      final legacy = EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'legacy-current-activity',
        hintLevel: 0,
        contentRevision: 'legacy-unknown',
        engagementAllowed: true,
      );
      await unsupported.database.customUpdate(
        'UPDATE answer_attempts SET evidence_class = ?, evidence_context_json = ? '
        'WHERE id = ?',
        variables: [
          Variable<String>(EvidenceClass.independentRecall.name),
          Variable<String>(jsonEncode(legacy.toJson())),
          const Variable<String>('evidence-post-ready'),
        ],
      );
      expect(
        await unsupported.useCases.compare(_studyCycleId),
        isA<AssessmentComparisonIncompatibleMetadata>(),
      );
    },
  );

  test(
    'comparison is owner scoped even when another owner uses the same cycle id',
    () async {
      final harness = await _ComparisonHarness.create();
      addTearDown(harness.close);
      await harness.createCompletedPair();
      await _seedForeignCompletedPair(harness.database);

      final result = await harness.useCases.compare(_studyCycleId);

      expect(result, isA<AssessmentComparisonReady>());
      final ready = result as AssessmentComparisonReady;
      expect(ready.preOutcome.correctCount, 1);
      expect(ready.postOutcome.correctCount, 0);
    },
  );
}

final class _ComparisonHarness {
  _ComparisonHarness({
    required this.database,
    required this.useCases,
    required this._clock,
  });

  final AppDatabase database;
  final AssessmentUseCases useCases;
  final _MutableClock _clock;

  DateTime get now => _clock.value;
  set now(DateTime value) => _clock.value = value;

  static Future<_ComparisonHarness> create() async {
    final database = AppDatabase(NativeDatabase.memory());
    await _seedCore(database);
    final experiments = DriftExperimentRegistry(
      DriftExperimentAssignmentRepository(database),
    );
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
    const owners = _Owners();
    final learning = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(
        database,
        rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
      ),
      generateId: () => 'unused-comparison-id',
      nowUtc: () => _preResponseAtUtc,
      buildInfo: const AppBuildInfo(version: _appVersion, buildId: _buildId),
      eventContextProvider: eventContexts,
    );
    final clock = _MutableClock(_preStartedAtUtc);
    return _ComparisonHarness(
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
        buildInfo: const AppBuildInfo(version: _appVersion, buildId: _buildId),
        databaseSchemaVersion: AppDatabase.currentSchemaVersion,
        nowUtc: clock.call,
      ),
    );
  }

  Future<void> startAndComplete({
    required String runId,
    required String sessionId,
    required AssessmentPhase phase,
    required String sourceEvidenceId,
    required Object submittedResponse,
    String itemId = _itemV1,
  }) async {
    now = phase == AssessmentPhase.pre ? _preStartedAtUtc : _postStartedAtUtc;
    await useCases.start(
      _command(runId: runId, sessionId: sessionId, phase: phase),
    );
    final responseAt = phase == AssessmentPhase.pre
        ? _preResponseAtUtc
        : _postResponseAtUtc;
    await useCases.recordResponse(
      runId: runId,
      sourceEvidenceId: sourceEvidenceId,
      itemId: itemId,
      submittedResponse: submittedResponse,
      responseTimeMs: 600,
      occurredAtUtc: responseAt,
    );
    now = responseAt.add(const Duration(minutes: 1));
    await useCases.complete(runId);
  }

  Future<void> createCompletedPair() async {
    await startAndComplete(
      runId: _preRunId,
      sessionId: _preSessionId,
      phase: AssessmentPhase.pre,
      sourceEvidenceId: 'evidence-pre-ready',
      submittedResponse: 'choice-a',
    );
    await startAndComplete(
      runId: _postRunId,
      sessionId: _postSessionId,
      phase: AssessmentPhase.post,
      sourceEvidenceId: 'evidence-post-ready',
      submittedResponse: 'choice-b',
    );
  }

  Future<void> close() => database.close();
}

final class _MutableClock {
  _MutableClock(this.value);
  DateTime value;
  DateTime call() => value;
}

AssessmentStartCommand _command({
  required String runId,
  required String sessionId,
  required AssessmentPhase phase,
}) => AssessmentStartCommand(
  runId: runId,
  learningSessionId: sessionId,
  studyCycleId: _studyCycleId,
  phase: phase,
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
          itemId: _itemV1,
          wordId: _wordId,
          promptMode: 'assessmentResponse',
          scoringRuleVersion: 'score-v1',
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
        AssessmentItemDefinition(
          itemId: _itemV2,
          wordId: _wordId,
          promptMode: 'assessmentResponse',
          scoringRuleVersion: 'score-v2',
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

Future<void> _seedCore(AppDatabase database) async {
  for (final owner in const [_ownerId, _foreignOwnerId]) {
    await database.customInsert(
      'INSERT INTO local_owners(id, account_state, created_at_utc_ms) '
      'VALUES (?, ?, ?)',
      variables: [
        Variable<String>(owner),
        const Variable<String>('localGuest'),
        Variable<int>(_consentAtUtc.millisecondsSinceEpoch),
      ],
    );
  }
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
      Variable<String>(_assignmentId(_ownerId)),
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
          spelling: 'compare',
          normalizedSpelling: 'compare',
          meaning: 'contrast',
          normalizedMeaning: 'contrast',
          partOfSpeech: 'verb',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  final learning = DriftLearningRepository(database);
  await learning.startSession(
    LearningSessionDraft(
      id: _preSessionId,
      ownerId: _ownerId,
      activityType: 'assessment',
      startedAtUtc: _preSessionAtUtc,
      appVersion: _appVersion,
      buildId: _buildId,
    ),
  );
  await learning.startSession(
    LearningSessionDraft(
      id: _postSessionId,
      ownerId: _ownerId,
      activityType: 'assessment',
      startedAtUtc: _postSessionAtUtc,
      appVersion: _appVersion,
      buildId: _buildId,
    ),
  );
}

Future<void> _seedAlternateComparisonWord(AppDatabase database) => database
    .into(database.vocabularyWords)
    .insert(
      VocabularyWordsCompanion.insert(
        id: _otherWordId,
        ownerId: _ownerId,
        categoryId: _categoryId,
        spelling: 'mismatch',
        normalizedSpelling: 'mismatch',
        meaning: 'ไม่ตรงกัน',
        normalizedMeaning: 'ไม่ตรงกัน',
        partOfSpeech: 'verb',
        createdAtUtcMs: 2,
        updatedAtUtcMs: 2,
      ),
    );

Future<void> _seedForeignCompletedPair(AppDatabase database) async {
  // Foreign rows intentionally share the study-cycle string. The application
  // must select only the active owner's pair.
  await database.customInsert(
    'INSERT INTO research_consents('
    'id, owner_id, consent_version, consent_state, decided_at_utc_ms) '
    'VALUES (?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('consent-assessment-foreign'),
      const Variable<String>(_foreignOwnerId),
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
      Variable<String>(_assignmentId(_foreignOwnerId)),
      const Variable<String>(_foreignOwnerId),
      const Variable<String>(_experimentId),
      const Variable<int>(1),
      const Variable<String>(_cohort),
      const Variable<String>(_protocolVersion),
      Variable<int>(_assignedAtUtc.millisecondsSinceEpoch),
    ],
  );
  for (final phase in AssessmentPhase.values) {
    final suffix = phase.name;
    final sessionId = 'foreign-session-$suffix';
    await DriftLearningRepository(database).startSession(
      LearningSessionDraft(
        id: sessionId,
        ownerId: _foreignOwnerId,
        activityType: 'assessment',
        startedAtUtc: _preSessionAtUtc,
        appVersion: _appVersion,
        buildId: _buildId,
      ),
    );
    final run = AssessmentRun(
      id: 'foreign-run-$suffix',
      ownerId: _foreignOwnerId,
      learningSessionId: sessionId,
      studyCycleId: _studyCycleId,
      phase: phase,
      state: AssessmentRunState.active,
      protocolId: _protocolId,
      protocolVersion: _protocolVersion,
      experimentId: _experimentId,
      experimentVersion: 1,
      assignmentId: _assignmentId(_foreignOwnerId),
      cohort: _cohort,
      consentVersion: 1,
      consentDecidedAtUtc: _consentAtUtc,
      instrumentId: _instrumentId,
      instrumentVersion: _instrumentVersion,
      formId: _formId,
      formVersion: _formVersion,
      instrumentChecksumSha256: sha256.convert(_instrumentBytes).toString(),
      formChecksumSha256: sha256.convert(_formBytes).toString(),
      appVersion: _appVersion,
      buildId: _buildId,
      databaseSchemaVersion: AppDatabase.currentSchemaVersion,
      contentRevision: _contentRevision,
      evidencePolicyVersion: EvidenceContext.currentPolicyVersion,
      featureContractRevision: '2026-08-14-alltcas-8-44-v1',
      featureContractHash: _otherSha256,
      startedAtUtc: _preStartedAtUtc,
      completedAtUtc: null,
      abandonedAtUtc: null,
    );
    final repository = DriftAssessmentRepository(database);
    await repository.start(run);
    await repository.complete(runId: run.id, completedAtUtc: _preResponseAtUtc);
  }
}

Future<Set<String>> _forbiddenScoreTables(AppDatabase database) => database
    .customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ("
      "'assessment_scores','assessment_score_ledger','assessment_responses')",
    )
    .map((row) => row.read<String>('name'))
    .get()
    .then((rows) => rows.toSet());

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

String _assignmentId(String ownerId) =>
    DriftExperimentAssignmentRepository.canonicalAssignmentId(
      ownerId: ownerId,
      experimentId: _experimentId,
      experimentVersion: 1,
    );

const _ownerId = 'owner-assessment';
const _foreignOwnerId = 'owner-foreign';
const _categoryId = 'category-assessment';
const _wordId = 'word-assessment';
const _otherWordId = 'word-assessment-other';
const _preSessionId = 'session-assessment-pre';
const _postSessionId = 'session-assessment-post';
const _preRunId = 'assessment-run-pre';
const _postRunId = 'assessment-run-post';
const _studyCycleId = 'study-cycle-2026';
const _protocolId = 'assessment-protocol';
const _protocolVersion = 'protocol-1.0.0';
const _experimentId = 'assessment-experiment';
const _cohort = 'enforced';
const _instrumentId = 'instrument-core';
const _instrumentVersion = 'instrument-v1';
const _formId = 'form-a';
const _formVersion = 'form-v1';
const _itemV1 = 'item-score-v1';
const _itemV2 = 'item-score-v2';
const _contentRevision = 'assessment-content-v1';
const _appVersion = '1.0.0';
const _buildId = 'task-12-comparison';
const _instrumentBytes = <int>[1, 2, 3];
const _formBytes = <int>[4, 5, 6];
const _otherSha256 =
    'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';
final _consentAtUtc = DateTime.utc(2026, 8, 1, 8);
final _assignedAtUtc = DateTime.utc(2026, 8, 2, 8);
final _preSessionAtUtc = DateTime.utc(2026, 8, 14, 9, 59);
final _preStartedAtUtc = DateTime.utc(2026, 8, 14, 10);
final _preResponseAtUtc = DateTime.utc(2026, 8, 14, 10, 5);
final _postSessionAtUtc = DateTime.utc(2026, 8, 21, 9, 59);
final _postStartedAtUtc = DateTime.utc(2026, 8, 21, 10);
final _postResponseAtUtc = DateTime.utc(2026, 8, 21, 10, 5);
