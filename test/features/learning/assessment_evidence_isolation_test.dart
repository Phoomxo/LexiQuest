import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_side_effect_reconciler.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  late AppDatabase database;
  LearningReconciliationScheduler? scheduler;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    scheduler = null;
    await _seed(database);
  });

  tearDown(() async {
    await scheduler?.dispose();
    await database.close();
  });

  test(
    'enforced assessment persists evidence without practice or engagement effects',
    () async {
      final evidence = _assessmentEvidence();
      const eventContextProvider = _GrantedAssessmentContextProvider();
      final resolved = await eventContextProvider.resolve(
        ownerId: _ownerId,
        evidenceContext: evidence,
        occurredAtUtc: _occurredAtUtc,
      );
      resolved.validateAgainst(
        evidenceContext: evidence,
        occurredAtUtc: _occurredAtUtc,
      );

      var questCalls = 0;
      var streakCalls = 0;
      var rewardCalls = 0;
      final reconciler = LearningSideEffectReconciler(
        database,
        questSink: (_) async {
          questCalls++;
          return const LearningProjectionResult.applied(
            payload: <String, dynamic>{'eligible': true},
          );
        },
        streakSink: (_) async {
          streakCalls++;
          return const LearningProjectionResult.applied();
        },
        rewardSink: (_, _) async {
          rewardCalls++;
          return const LearningProjectionResult.applied();
        },
      );
      final reconciliation = LearningReconciliationScheduler(reconciler);
      scheduler = reconciliation;
      final learning = LearningUseCases(
        owners: const _Owners(),
        repository: DriftLearningRepository(database),
        generateId: () => 'unused-generated-id',
        nowUtc: () => _occurredAtUtc,
        buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'task-7'),
        eventContextProvider: eventContextProvider,
        onSideEffectsPending: reconciliation.request,
      );
      final progress = DriftProgressQueries(database);
      final before = await progress.load(
        ownerId: _ownerId,
        nowUtc: _occurredAtUtc,
      );

      final result = await learning.recordEvidence(
        sourceEvidenceId: _evidenceId,
        occurredAtUtc: _occurredAtUtc,
        sessionId: _sessionId,
        wordId: _wordId,
        promptMode: 'assessmentResponse',
        isCorrect: true,
        responseTimeMs: 700,
        attemptNumber: 1,
        evidenceContext: evidence,
      );
      expect(result.inserted, isTrue);
      expect(result.srs, isNull);
      final summary = await learning.finishSession(_sessionId);
      expect(
        (summary.correctCount, summary.wrongCount, summary.score),
        (1, 0, 100),
      );
      await reconciliation.drain();

      expect(await _count(database, 'answer_attempts'), 1);
      expect(await _count(database, 'events_v2'), greaterThanOrEqualTo(1));
      expect(await _count(database, 'srs_states'), 0);
      expect(await _count(database, 'points_ledger_entries'), 0);
      expect(await _count(database, 'achievement_unlocks'), 0);
      expect(await _count(database, 'quest_objective_progress'), 0);
      expect(await _count(database, 'streak_states'), 0);
      expect(await _count(database, 'reward_transactions'), 0);
      expect((questCalls, streakCalls, rewardCalls), (0, 0, 0));

      final after = await progress.load(
        ownerId: _ownerId,
        nowUtc: _occurredAtUtc,
      );
      _expectPracticeSnapshotUnchanged(before, after);

      final skippedRows = await database
          .customSelect(
            "SELECT payload_json FROM events_v2 "
            "WHERE event_type = 'LearningProjectionSkipped' "
            "AND aggregate_id = 'learning-event:$_evidenceId'",
          )
          .get();
      final skipped = skippedRows
          .map(
            (row) =>
                (jsonDecode(row.read<String>('payload_json'))
                        as Map<String, dynamic>)['projection']
                    as String,
          )
          .toSet();
      expect(skipped, <String>{'quest', 'streak', 'reward'});

      final decisionRow =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.equals(
                  'learning-evidence-decisions:$_evidenceId:v1',
                ),
              ))
              .getSingle();
      expect(decisionRow.eventType, 'LearningEvidenceDecisionSet');
      final decisionPayload =
          jsonDecode(decisionRow.payloadJson) as Map<String, dynamic>;
      final decisions = (decisionPayload['decisions'] as List)
          .cast<Map<String, dynamic>>();
      expect(decisions, hasLength(LearningProjection.values.length));
      expect(
        decisions.map((entry) => entry['projection']).toSet(),
        LearningProjection.values.map((projection) => projection.name).toSet(),
      );
      for (final entry in decisions) {
        expect(entry.keys, <String>{
          'projection',
          'rolloutMode',
          'effectiveDecision',
          'candidateV1Decision',
          'policyVersion',
          'divergence',
        });
        expect(entry['rolloutMode'], EvidencePolicyRolloutMode.enforced.name);
        expect(entry['policyVersion'], EvidenceContext.currentPolicyVersion);
      }
    },
  );
}

const _ownerId = 'owner-assessment';
const _sessionId = 'session-assessment';
const _wordId = 'word-assessment';
const _evidenceId = 'assessment-evidence-1';
final _occurredAtUtc = DateTime.utc(2026, 8, 14, 10, 0, 0, 123);

EvidenceContext _assessmentEvidence() => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.assessment,
  skillId: 'assessment-skill',
  hintLevel: 0,
  contentRevision: 'assessment-content-v1',
  rolloutMode: EvidencePolicyRolloutMode.enforced,
  protocolId: 'protocol-a',
  protocolVersion: 'protocol-v1',
  experimentId: 'experiment-a',
  experimentVersion: 1,
  assignmentId: 'assignment-a',
  cohort: 'assessment',
  researchConsentVersion: 1,
  instrumentId: 'instrument-a',
  instrumentVersion: 'instrument-v1',
  formId: 'form-a',
  formVersion: 'form-v1',
  assessmentItemId: 'item-a',
  assessmentResponseCode: 'correct',
  scoringRuleVersion: 'score-v1',
  engagementAllowed: false,
);

final class _GrantedAssessmentContextProvider
    implements LearningEventContextProvider {
  const _GrantedAssessmentContextProvider();

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async {
    expect(ownerId, _ownerId);
    return LearningEventContext(
      consentContext: const ConsentContext(
        researchConsentVersion: 1,
        aiConsentGranted: false,
        voiceConsentGranted: false,
        socialConsentGranted: false,
      ),
      experimentContext: ExperimentContext(
        experimentId: 'experiment-a',
        variantId: 'assessment',
        assignedAtUtc: DateTime.utc(2026, 8, 1),
      ),
      protocolId: 'protocol-a',
      protocolVersion: 'protocol-v1',
      experimentVersion: 1,
      assignmentId: 'assignment-a',
      featureContractIdentity: FeatureContractIdentity(
        revision: evidenceContext.featureContractRevision,
        semanticHash: evidenceContext.featureContractHash,
      ),
    );
  }
}

final class _Owners implements LocalOwnerRepository {
  const _Owners();

  static final owner = LocalOwner(
    id: _ownerId,
    createdAtUtc: DateTime.utc(2026, 8, 1),
  );

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => owner;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) async => owner;
}

Future<void> _seed(AppDatabase database) async {
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: _ownerId,
          createdAtUtcMs: DateTime.utc(2026, 8, 1).millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category-assessment',
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
          categoryId: 'category-assessment',
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
      startedAtUtc: DateTime.utc(2026, 8, 14, 9, 59),
      appVersion: '1.0.0',
      buildId: 'task-7',
    ),
  );
}

Future<int> _count(AppDatabase database, String table) async {
  final row = await database
      .customSelect('SELECT COUNT(*) AS n FROM $table')
      .getSingle();
  return row.read<int>('n');
}

void _expectPracticeSnapshotUnchanged(
  ProgressSnapshot before,
  ProgressSnapshot after,
) {
  expect(after.sampleSize, before.sampleSize);
  expect(after.correctCount, before.correctCount);
  expect(after.wrongCount, before.wrongCount);
  expect(after.accuracy, before.accuracy);
  expect(after.totalXp, before.totalXp);
  expect(after.completedSessions, before.completedSessions);
  expect(after.streakDays, before.streakDays);
  expect(after.dueReviewCount, before.dueReviewCount);
  expect(after.masteredWordCount, before.masteredWordCount);
  expect(after.achievementCount, before.achievementCount);
  expect(after.gameLevel, before.gameLevel);
  expect(
    after.skills.map((item) => (item.key, item.sampleSize, item.accuracy)),
    before.skills.map((item) => (item.key, item.sampleSize, item.accuracy)),
  );
  expect(after.weaknesses, isEmpty);
  expect(after.recommendations, isEmpty);
  expect(after.achievements, isEmpty);
  expect(after.averageResponseTimeMs, before.averageResponseTimeMs);
  expect(after.latestEvidenceAtUtc, before.latestEvidenceAtUtc);
}
