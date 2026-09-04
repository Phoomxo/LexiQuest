import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_motivation_projection_reader.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';

void main() {
  late AppDatabase database;
  late DriftAdventureMotivationProjectionReader reader;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    reader = DriftAdventureMotivationProjectionReader(database);
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'owner-adventure-projection',
            createdAtUtcMs: 1,
          ),
        );
    await database
        .into(database.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: 'session-adventure-projection',
            ownerId: 'owner-adventure-projection',
            activityType: 'quiz',
            state: 'active',
            startedAtUtcMs: 1,
            appVersion: '1.0.0',
            buildId: 'test-build',
          ),
        );
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-adventure-projection',
            ownerId: 'owner-adventure-projection',
            name: 'Test',
            normalizedName: 'test',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-adventure-projection',
            ownerId: 'owner-adventure-projection',
            categoryId: 'category-adventure-projection',
            spelling: 'test',
            normalizedSpelling: 'test',
            meaning: 'test',
            normalizedMeaning: 'test',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  });

  tearDown(() => database.close());

  test(
    'REC-007 committed learning stays pending until canonical receipts exist',
    () async {
      await _addEvidence(database, id: 'evidence-pending');
      final before = await _authorityCounts(database);

      final snapshot = await reader.readForEvidence('evidence-pending');

      expect(snapshot.sourceEvidenceId, 'evidence-pending');
      expect(
        snapshot.questOutcome.state,
        AdventureProjectionReceiptState.pending,
      );
      expect(
        snapshot.streakOutcome.state,
        AdventureProjectionReceiptState.pending,
      );
      expect(
        snapshot.rewardOutcome.state,
        AdventureProjectionReceiptState.pending,
      );
      expect(snapshot.achievementOutcomes, isEmpty);
      expect(snapshot.pendingProjection, isTrue);
      expect(await _authorityCounts(database), before);
    },
  );

  test(
    'REC-008 reads exact Quest Streak Achievement and Reward receipt identities',
    () async {
      final source = await _addEvidence(database, id: 'evidence-committed');
      final store = DriftLearningEventStore(database);
      await store.markProjectionOutcome(
        source: source,
        projection: 'quest',
        appliedVersion: DriftLearningEventStore.appliedProjectionVersion,
        outcome: LearningProjectionOutcome.applied,
        result: const <String, dynamic>{
          'eligible': true,
          'rewardGrants': <Object>[],
        },
      );
      await store.markProjectionOutcome(
        source: source,
        projection: 'streak',
        appliedVersion: DriftLearningEventStore.appliedProjectionVersion,
        outcome: LearningProjectionOutcome.applied,
        result: const StreakPolicyReceipt(
          ownerId: 'owner-adventure-projection',
          learningDay: '2026-09-04',
          policyVersion: StreakPolicy.version,
          currentStreakDays: 2,
          longestStreakDays: 3,
          freezeCount: 1,
        ).toJson(),
      );
      await store.markProjectionOutcome(
        source: source,
        projection: 'reward',
        appliedVersion: DriftLearningEventStore.appliedProjectionVersion,
        outcome: LearningProjectionOutcome.applied,
      );
      await database
          .into(database.achievementUnlocks)
          .insert(
            AchievementUnlocksCompanion.insert(
              id: 'achievement:owner-adventure-projection:first_correct:1',
              ownerId: 'owner-adventure-projection',
              achievementId: 'first_correct',
              definitionVersion: 1,
              sourceEventId: 'evidence-committed',
              unlockedAtUtcMs: DateTime.utc(
                2026,
                9,
                4,
                10,
              ).millisecondsSinceEpoch,
            ),
          );
      await database
          .into(database.achievementUnlocks)
          .insert(
            AchievementUnlocksCompanion.insert(
              id: 'achievement:owner-adventure-projection:first_session:1',
              ownerId: 'owner-adventure-projection',
              achievementId: 'first_session',
              definitionVersion: 1,
              sourceEventId: 'session-adventure-projection',
              unlockedAtUtcMs: DateTime.utc(
                2026,
                9,
                4,
                11,
              ).millisecondsSinceEpoch,
            ),
          );
      final before = await _authorityCounts(database);

      final snapshot = await reader.readForEvidence('evidence-committed');

      expect(snapshot.pendingProjection, isFalse);
      expect(snapshot.questOutcome.toJson(), <String, Object?>{
        'state': 'committed',
        'receiptId':
            'learning-projection:quest:'
            'learning-event:evidence-committed:v2',
        'displayCode': null,
      });
      expect(snapshot.streakOutcome.toJson(), <String, Object?>{
        'state': 'committed',
        'receiptId':
            'learning-projection:streak:'
            'learning-event:evidence-committed:v2',
        'displayCode': null,
      });
      expect(snapshot.rewardOutcome.toJson(), <String, Object?>{
        'state': 'committed',
        'receiptId':
            'learning-projection:reward:'
            'learning-event:evidence-committed:v2',
        'displayCode': null,
      });
      expect(
        snapshot.achievementOutcomes.map((outcome) => outcome.toJson()),
        <Map<String, Object?>>[
          <String, Object?>{
            'state': 'committed',
            'receiptId':
                'achievement:owner-adventure-projection:first_correct:1',
            'displayCode': 'first_correct',
          },
        ],
        reason: 'session-sourced unlocks are not evidence-sourced receipts',
      );
      expect(await _authorityCounts(database), before);
    },
  );

  test('assessment evidence is excluded without waiting or writing', () async {
    await _addEvidence(
      database,
      id: 'evidence-assessment',
      context: _assessmentContext(),
    );
    final before = await _authorityCounts(database);

    final snapshot = await reader.readForEvidence('evidence-assessment');

    expect(snapshot.pendingProjection, isFalse);
    expect(
      <AdventureProjectionReceiptState>{
        snapshot.questOutcome.state,
        snapshot.streakOutcome.state,
        snapshot.rewardOutcome.state,
      },
      <AdventureProjectionReceiptState>{
        AdventureProjectionReceiptState.notEligible,
      },
    );
    expect(snapshot.achievementOutcomes, isEmpty);
    expect(await _authorityCounts(database), before);
  });

  test(
    'REC-009 replay returns the same receipts and creates no duplicate',
    () async {
      final source = await _addEvidence(database, id: 'evidence-replay');
      final store = DriftLearningEventStore(database);
      for (final projection in <String>['quest', 'streak', 'reward']) {
        await store.markProjectionOutcome(
          source: source,
          projection: projection,
          appliedVersion: DriftLearningEventStore.appliedProjectionVersion,
          outcome: LearningProjectionOutcome.notApplicable,
          result: projection == 'quest'
              ? const <String, dynamic>{
                  'eligible': false,
                  'rewardGrants': <Object>[],
                }
              : const <String, dynamic>{'reasonCode': 'notEarned'},
        );
      }
      final before = await _authorityCounts(database);

      final first = await reader.readForEvidence('evidence-replay');
      final replay = await reader.readForEvidence('evidence-replay');

      expect(replay.toJson(), first.toJson());
      expect(replay.pendingProjection, isFalse);
      expect(
        replay.rewardOutcome.state,
        AdventureProjectionReceiptState.notEligible,
      );
      expect(await _authorityCounts(database), before);
    },
  );

  test(
    'REC-010 map and story reads are no-ops over canonical authority',
    () async {
      final before = await _authorityCounts(database);

      final map = await reader.readForEvidence('map-open');
      final story = await reader.readForEvidence('story-open');

      for (final snapshot in <AdventureMotivationSnapshot>[map, story]) {
        expect(snapshot.pendingProjection, isFalse);
        expect(
          snapshot.questOutcome.state,
          AdventureProjectionReceiptState.notEligible,
        );
        expect(
          snapshot.streakOutcome.state,
          AdventureProjectionReceiptState.notEligible,
        );
        expect(
          snapshot.rewardOutcome.state,
          AdventureProjectionReceiptState.notEligible,
        );
        expect(snapshot.achievementOutcomes, isEmpty);
      }
      expect(await _authorityCounts(database), before);
    },
  );
}

Future<EventEnvelopeV2> _addEvidence(
  AppDatabase database, {
  required String id,
  EvidenceContext? context,
}) async {
  final evidenceContext =
      context ??
      EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'meaning',
        hintLevel: 0,
        contentRevision: 'content-v1',
        engagementAllowed: true,
      );
  final occurredAt = DateTime.utc(2026, 9, 4, 10);
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: id,
          ownerId: 'owner-adventure-projection',
          sessionId: 'session-adventure-projection',
          wordId: 'word-adventure-projection',
          promptMode: evidenceContext.evidenceClass == EvidenceClass.assessment
              ? 'assessmentResponse'
              : 'meaningChoice',
          isCorrect: true,
          attemptNumber: 1,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          evidenceClass: Value(evidenceContext.evidenceClass.name),
          evidenceContextJson: Value(jsonEncode(evidenceContext.toJson())),
        ),
      );
  final event = EventEnvelopeV2(
    eventId: LearningEvidenceContract.learningEventId(id),
    eventType: 'QuizCompleted',
    eventVersion: 2,
    occurredAtUtc: occurredAt,
    recordedAtUtc: occurredAt,
    actorIdentity: 'owner-adventure-projection',
    ownerIdentity: 'owner-adventure-projection',
    aggregateType: 'LearningSession',
    aggregateId: 'session-adventure-projection',
    idempotencyKey: LearningEvidenceContract.learningAttemptIdempotencyKey(id),
    consentContext: evidenceContext.evidenceClass == EvidenceClass.assessment
        ? const ConsentContext(
            researchConsentVersion: 1,
            aiConsentGranted: false,
            voiceConsentGranted: false,
            socialConsentGranted: false,
          )
        : const ConsentContext.none(),
    experimentContext: evidenceContext.evidenceClass == EvidenceClass.assessment
        ? ExperimentContext(
            experimentId: 'experiment-a',
            variantId: 'assessment',
            assignedAtUtc: DateTime.utc(2026, 9, 1),
          )
        : null,
    contentRevision: evidenceContext.contentRevision,
    policyVersion: evidenceContext.policyVersion,
    appVersion: '1.0.0',
    buildId: 'test-build',
    privacyClassification: PrivacyClassification.anonymized,
    payload: <String, Object?>{
      'attemptId': id,
      'wordId': 'word-adventure-projection',
      'promptMode': evidenceContext.evidenceClass == EvidenceClass.assessment
          ? 'assessmentResponse'
          : 'meaningChoice',
      'correct': true,
      'score': 100,
      'attemptNumber': 1,
      'evidenceContext': evidenceContext.toJson(),
    },
  );
  await DriftLearningEventStore(database).append(event);
  return event;
}

EvidenceContext _assessmentContext() => EvidenceContext.forNewEvidence(
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

Future<Map<String, int>> _authorityCounts(
  AppDatabase database,
) async => <String, int>{
  'events': (await database.select(database.eventsV2).get()).length,
  'quests': (await database.select(database.questInstances).get()).length,
  'streaks': (await database.select(database.streakStates).get()).length,
  'achievements':
      (await database.select(database.achievementUnlocks).get()).length,
  'rewards': (await database.select(database.rewardTransactions).get()).length,
  'points': (await database.select(database.pointsLedgerEntries).get()).length,
};
