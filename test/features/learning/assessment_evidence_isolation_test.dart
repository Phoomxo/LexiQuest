import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_side_effect_reconciler.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
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
      const rolloutModeProvider = ContextEvidencePolicyRolloutModeProvider();
      final reconciler = LearningSideEffectReconciler(
        database,
        rolloutModeProvider: rolloutModeProvider,
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
        repository: DriftLearningRepository(
          database,
          rolloutModeProvider: rolloutModeProvider,
        ),
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

  test(
    'enforced assessment preserves non-empty projection bytes without mutation',
    () async {
      final repository = DriftLearningRepository(
        database,
        rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
      );
      // This fixture represents durable reward state written before f32 made
      // the avatar cutover authoritative. Seed it before the first live
      // learning projection establishes that boundary.
      await _seedRewardState(database);
      await repository.startSession(
        LearningSessionDraft(
          id: _practiceSessionId,
          ownerId: _ownerId,
          activityType: 'quiz',
          startedAtUtc: _practiceAtUtc.subtract(const Duration(minutes: 1)),
          appVersion: '1.0.0',
          buildId: 'task-7',
        ),
      );
      final practice = LearningUseCases(
        owners: const _Owners(),
        repository: repository,
        generateId: () => 'unused-practice-id',
        nowUtc: () => _practiceAtUtc,
        buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'task-7'),
      );
      await practice.recordEvidence(
        sourceEvidenceId: _practiceEvidenceId,
        occurredAtUtc: _practiceAtUtc,
        sessionId: _practiceSessionId,
        wordId: _wordId,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 400,
        attemptNumber: 1,
        evidenceContext: _practiceEvidence(),
      );
      await practice.finishSession(_practiceSessionId);

      final before = await _projectionBytes(database);
      expect(before.values, everyElement(isNot('[]')));
      await _forbidProjectionMutation(database);

      final assessment = LearningUseCases(
        owners: const _Owners(),
        repository: repository,
        generateId: () => 'unused-assessment-id',
        nowUtc: () => _occurredAtUtc,
        buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'task-7'),
        eventContextProvider: const _GrantedAssessmentContextProvider(),
      );
      final result = await assessment.recordEvidence(
        sourceEvidenceId: _evidenceId,
        occurredAtUtc: _occurredAtUtc,
        sessionId: _sessionId,
        wordId: _wordId,
        promptMode: 'assessmentResponse',
        isCorrect: true,
        responseTimeMs: 700,
        attemptNumber: 1,
        evidenceContext: _assessmentEvidence(),
      );

      expect(result.inserted, isTrue);
      expect(result.srs, isNull);
      expect(await _projectionBytes(database), before);
      expect(await _count(database, 'answer_attempts'), 2);
      expect(
        await (database.select(database.learningSessions)
              ..where((row) => row.id.equals(_sessionId)))
            .getSingle()
            .then((row) => (row.correctCount, row.wrongCount)),
        (1, 0),
      );
    },
  );
}

const _ownerId = 'owner-assessment';
const _sessionId = 'session-assessment';
const _wordId = 'word-assessment';
const _evidenceId = 'assessment-evidence-1';
const _practiceSessionId = 'session-practice';
const _practiceEvidenceId = 'practice-evidence-1';
final _occurredAtUtc = DateTime.utc(2026, 8, 14, 10, 0, 0, 123);
final _practiceAtUtc = DateTime.utc(2026, 8, 14, 9, 30, 0, 123);

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

EvidenceContext _practiceEvidence() => EvidenceContext.legacyCompatibility(
  evidenceClass: EvidenceClass.independentRecall,
  skillId: 'legacy-current-activity',
  hintLevel: 0,
  contentRevision: 'legacy-unknown',
  engagementAllowed: true,
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

Future<void> _seedRewardState(AppDatabase database) async {
  const coinGrantId = 'reward-coin-grant-practice';
  const purchaseId = 'reward-purchase-practice';
  const equipId = 'reward-equip-practice';
  await database
      .into(database.rewardTransactions)
      .insert(
        RewardTransactionsCompanion.insert(
          id: coinGrantId,
          ownerId: _ownerId,
          idempotencyKey: 'coin-grant-practice',
          transactionType: 'coinGrant',
          amount: 100,
          catalogVersion: 0,
          sourceEventId: const Value('reward-source-practice'),
          occurredAtUtcMs: _practiceAtUtc.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.rewardTransactions)
      .insert(
        RewardTransactionsCompanion.insert(
          id: purchaseId,
          ownerId: _ownerId,
          idempotencyKey: 'purchase-practice',
          transactionType: 'purchase',
          amount: -80,
          itemId: const Value('theme_ocean'),
          catalogVersion: RewardCatalog.legacyVersion,
          occurredAtUtcMs: _practiceAtUtc.millisecondsSinceEpoch + 1,
        ),
      );
  await database
      .into(database.rewardTransactions)
      .insert(
        RewardTransactionsCompanion.insert(
          id: equipId,
          ownerId: _ownerId,
          idempotencyKey: 'equip-practice',
          transactionType: 'equip',
          amount: 0,
          itemId: const Value('theme_ocean'),
          catalogVersion: RewardCatalog.legacyVersion,
          occurredAtUtcMs: _practiceAtUtc.millisecondsSinceEpoch + 2,
        ),
      );
  await DriftRewardProjectionRebuilder(database).rebuild(_ownerId);
}

Future<Map<String, String>> _projectionBytes(AppDatabase database) async {
  final srs = await database.select(database.srsStates).get();
  final points = await database.select(database.pointsLedgerEntries).get();
  final achievements = await database.select(database.achievementUnlocks).get();
  final transactions = await database.select(database.rewardTransactions).get();
  final owned = await database.select(database.ownedRewardItems).get();
  final equipped = await database.select(database.equippedRewardItems).get();
  return <String, String>{
    'srs': jsonEncode(srs.map((row) => row.toJson()).toList()),
    'points': jsonEncode(points.map((row) => row.toJson()).toList()),
    'achievements': jsonEncode(
      achievements.map((row) => row.toJson()).toList(),
    ),
    'rewardTransactions': jsonEncode(
      transactions.map((row) => row.toJson()).toList(),
    ),
    'ownedRewardItems': jsonEncode(owned.map((row) => row.toJson()).toList()),
    'equippedRewardItems': jsonEncode(
      equipped.map((row) => row.toJson()).toList(),
    ),
  };
}

Future<void> _forbidProjectionMutation(AppDatabase database) async {
  const tables = <String>[
    'srs_states',
    'points_ledger_entries',
    'achievement_unlocks',
    'reward_transactions',
    'owned_reward_items',
    'equipped_reward_items',
  ];
  for (final table in tables) {
    for (final operation in const <String>['INSERT', 'UPDATE', 'DELETE']) {
      final suffix = operation.toLowerCase();
      await database.customStatement(
        'CREATE TEMP TRIGGER guard_${table}_$suffix '
        'BEFORE $operation ON $table BEGIN '
        "SELECT RAISE(ABORT, 'assessment mutated $table'); END",
      );
    }
  }
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
