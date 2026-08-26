import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/recommendation/domain/recommendation_models.dart';
import 'package:vocab_learning_app/features/recommendation/domain/recommendation_policy.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';

void main() {
  const policy = FlashcardFirstRecommendationPolicy();
  final now = DateTime.utc(2026, 8, 26, 12);

  RecommendationEvidence evidence({
    String policyVersion = FlashcardFirstRecommendationPolicy.policyVersion,
    String ownerId = 'owner-1',
    String contentOwnerId = 'owner-1',
    String contentId = 'word-1',
    double? confidence = 0.5,
    bool isUnseen = false,
    bool isMastered = false,
    bool includeMasteryReference = true,
    String masteryReferenceId = 'srs:word-1',
    String masteryReferenceVersion = 'srs-v1',
    String? masteryReferenceOwnerId,
    String? masteryReferenceContentId,
    DateTime? observedAtUtc,
    DateTime? referenceCapturedAtUtc,
  }) => RecommendationEvidence(
    policyVersion: policyVersion,
    ownerId: ownerId,
    contentOwnerId: contentOwnerId,
    contentId: contentId,
    confidence: confidence,
    isUnseen: isUnseen,
    isMastered: isMastered,
    observedAtUtc: observedAtUtc ?? now.subtract(const Duration(days: 1)),
    evaluatedAtUtc: now,
    evidenceReferences: [
      RecommendationEvidenceReference(
        source: RecommendationEvidenceSource.progressReadModel,
        ownerId: ownerId,
        contentId: contentId,
        referenceId: 'progress:word-1',
        version: 'progress-v1',
        capturedAtUtc:
            referenceCapturedAtUtc ??
            observedAtUtc ??
            now.subtract(const Duration(days: 1)),
      ),
      if (isMastered && includeMasteryReference)
        RecommendationEvidenceReference(
          source: RecommendationEvidenceSource.srsReadModel,
          ownerId: masteryReferenceOwnerId ?? ownerId,
          contentId: masteryReferenceContentId ?? contentId,
          referenceId: masteryReferenceId,
          version: masteryReferenceVersion,
          capturedAtUtc:
              referenceCapturedAtUtc ??
              observedAtUtc ??
              now.subtract(const Duration(days: 1)),
        ),
    ],
  );

  group('FlashcardFirstRecommendationPolicy', () {
    test('recommends flashcard preparation for an unseen item', () {
      final decision = policy.recommend(
        evidence(confidence: 0, isUnseen: true),
      );

      expect(decision.action, RecommendationAction.flashcardPreparation);
      expect(decision.reasonCode, RecommendationReasonCode.unseenItem);
      expect(decision.isAdvisory, isTrue);
      expect(decision.allowedLearnerChoices, {
        RecommendationLearnerChoice.dismiss,
        RecommendationLearnerChoice.override,
      });
      expect(decision.evidenceReferences.single.referenceId, 'progress:word-1');
    });

    test('recommends flashcard preparation for a low-confidence item', () {
      final decision = policy.recommend(evidence(confidence: 0.69));

      expect(decision.action, RecommendationAction.flashcardPreparation);
      expect(decision.reasonCode, RecommendationReasonCode.lowConfidence);
    });

    test('does not mislabel a seen zero-confidence item as unseen', () {
      final decision = policy.recommend(evidence(confidence: 0));

      expect(decision.action, RecommendationAction.flashcardPreparation);
      expect(decision.reasonCode, RecommendationReasonCode.lowConfidence);
    });

    test('mastered item is never forced into flashcard preparation', () {
      final decision = policy.recommend(
        evidence(confidence: 0.1, isMastered: true),
      );

      expect(decision.action, RecommendationAction.noRecommendation);
      expect(decision.reasonCode, RecommendationReasonCode.masteredItem);
      expect(decision.isAdvisory, isTrue);
    });

    test('fails closed when a mastery claim has no SRS reference', () {
      final decision = policy.recommend(
        evidence(
          confidence: 0.1,
          isMastered: true,
          includeMasteryReference: false,
        ),
      );

      expect(decision.action, RecommendationAction.noRecommendation);
      expect(
        decision.reasonCode,
        RecommendationReasonCode.invalidMasteryEvidence,
      );
    });

    test(
      'fails closed when a mastery claim has a corrupt SRS state reference',
      () {
        final corruptId = policy.recommend(
          evidence(
            confidence: 0.1,
            isMastered: true,
            masteryReferenceId: 'srs:',
          ),
        );
        final corruptVersion = policy.recommend(
          evidence(
            confidence: 0.1,
            isMastered: true,
            masteryReferenceVersion: 'srs-v0',
          ),
        );

        expect(corruptId.action, RecommendationAction.noRecommendation);
        expect(
          corruptId.reasonCode,
          RecommendationReasonCode.invalidMasteryEvidence,
        );
        expect(corruptVersion.action, RecommendationAction.noRecommendation);
        expect(
          corruptVersion.reasonCode,
          RecommendationReasonCode.invalidMasteryEvidence,
        );
      },
    );

    test('fails closed for stale, future, or mismatched mastery evidence', () {
      final stale = policy.recommend(
        evidence(
          confidence: 0.1,
          isMastered: true,
          observedAtUtc: now.subtract(const Duration(days: 1)),
          referenceCapturedAtUtc: now.subtract(const Duration(days: 31)),
        ),
      );
      final future = policy.recommend(
        evidence(
          confidence: 0.1,
          isMastered: true,
          referenceCapturedAtUtc: now.add(const Duration(minutes: 1)),
        ),
      );
      final mismatched = policy.recommend(
        evidence(
          confidence: 0.1,
          isMastered: true,
          masteryReferenceContentId: 'word-2',
        ),
      );

      expect(stale.action, RecommendationAction.noRecommendation);
      expect(stale.reasonCode, RecommendationReasonCode.staleEvidence);
      expect(future.action, RecommendationAction.noRecommendation);
      expect(future.reasonCode, RecommendationReasonCode.invalidEvidenceTime);
      expect(mismatched.action, RecommendationAction.noRecommendation);
      expect(
        mismatched.reasonCode,
        RecommendationReasonCode.crossOwnerEvidence,
      );
    });

    test('learner dismissal and override are advisory-only', () {
      final original = policy.recommend(evidence(confidence: 0.2));

      final dismissed = original.withLearnerChoice(
        RecommendationLearnerChoice.dismiss,
      );
      final overridden = original.withLearnerChoice(
        RecommendationLearnerChoice.override,
      );

      expect(dismissed.learnerChoice, RecommendationLearnerChoice.dismiss);
      expect(overridden.learnerChoice, RecommendationLearnerChoice.override);
      expect(original.action, RecommendationAction.flashcardPreparation);
      expect(dismissed.action, RecommendationAction.flashcardPreparation);
      expect(overridden.action, RecommendationAction.flashcardPreparation);
    });

    test('fails closed for an unsupported policy version', () {
      final decision = policy.recommend(evidence(policyVersion: 'f14-v999'));

      expect(decision.action, RecommendationAction.noRecommendation);
      expect(
        decision.reasonCode,
        RecommendationReasonCode.unsupportedPolicyVersion,
      );
    });

    test('fails closed for missing or corrupt confidence', () {
      final missing = policy.recommend(evidence(confidence: null));
      final corrupt = policy.recommend(evidence(confidence: double.nan));

      expect(missing.action, RecommendationAction.noRecommendation);
      expect(missing.reasonCode, RecommendationReasonCode.missingConfidence);
      expect(corrupt.action, RecommendationAction.noRecommendation);
      expect(corrupt.reasonCode, RecommendationReasonCode.invalidConfidence);
    });

    test('fails closed for cross-owner or stale read evidence', () {
      final crossOwner = policy.recommend(evidence(contentOwnerId: 'owner-2'));
      final stale = policy.recommend(
        evidence(observedAtUtc: now.subtract(const Duration(days: 31))),
      );

      expect(crossOwner.action, RecommendationAction.noRecommendation);
      expect(
        crossOwner.reasonCode,
        RecommendationReasonCode.crossOwnerEvidence,
      );
      expect(stale.action, RecommendationAction.noRecommendation);
      expect(stale.reasonCode, RecommendationReasonCode.staleEvidence);
    });

    test('fails closed as invalid time for a future evidence reference', () {
      final decision = policy.recommend(
        evidence(referenceCapturedAtUtc: now.add(const Duration(minutes: 1))),
      );

      expect(decision.action, RecommendationAction.noRecommendation);
      expect(decision.reasonCode, RecommendationReasonCode.invalidEvidenceTime);
    });

    test('uses an inclusive deterministic freshness boundary', () {
      final decision = policy.recommend(
        evidence(observedAtUtc: now.subtract(const Duration(days: 30))),
      );

      expect(decision.action, RecommendationAction.flashcardPreparation);
      expect(decision.reasonCode, RecommendationReasonCode.lowConfidence);
    });

    test('does not recommend at the exact confidence threshold', () {
      final decision = policy.recommend(evidence(confidence: 0.7));

      expect(decision.action, RecommendationAction.noRecommendation);
      expect(
        decision.reasonCode,
        RecommendationReasonCode.confidenceSufficient,
      );
    });
  });

  group('DriftProgressQueries flashcard-first decisions', () {
    late AppDatabase database;
    late DriftProgressQueries progress;
    final now = DateTime.utc(2026, 8, 26, 12);

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      progress = DriftProgressQueries(database);
      await _seedOwnerAndWord(database, ownerId: 'owner-1', wordId: 'word-1');
    });

    tearDown(() => database.close());

    test(
      'uses canonical attempt and SRS observation times in its decision',
      () async {
        final attemptAt = now.subtract(const Duration(minutes: 10));
        final reviewedAt = now.subtract(const Duration(minutes: 5));
        await _recordIncorrectPracticeAttempt(
          database,
          ownerId: 'owner-1',
          wordId: 'word-1',
          occurredAtUtc: attemptAt,
        );
        await (database.update(database.srsStates)..where(
              (row) =>
                  row.ownerId.equals('owner-1') & row.wordId.equals('word-1'),
            ))
            .write(
              SrsStatesCompanion(
                repetitions: const Value(1),
                intervalDays: const Value(1),
                lastReviewAtUtcMs: Value(reviewedAt.millisecondsSinceEpoch),
                dueAtUtcMs: Value(now.millisecondsSinceEpoch),
                algorithmVersion: const Value(7),
              ),
            );

        final decisions = await progress.loadFlashcardFirstDecisions(
          ownerId: 'owner-1',
          nowUtc: now,
        );

        final decision = decisions.single;
        expect(decision.evidenceReferences, hasLength(2));
        expect(decision.evidenceReferences.first.capturedAtUtc, attemptAt);
        expect(decision.evidenceReferences.last.ownerId, 'owner-1');
        expect(decision.evidenceReferences.last.contentId, 'word-1');
        expect(decision.evidenceReferences.last.version, 'srs-v7');
        expect(decision.evidenceReferences.last.capturedAtUtc, reviewedAt);
      },
    );

    test(
      'fails closed for stale and future canonical database evidence',
      () async {
        await _recordIncorrectPracticeAttempt(
          database,
          ownerId: 'owner-1',
          wordId: 'word-1',
          occurredAtUtc: now.subtract(const Duration(days: 31)),
        );

        final stale = await progress.loadFlashcardFirstDecisions(
          ownerId: 'owner-1',
          nowUtc: now,
        );
        expect(stale.single.action, RecommendationAction.noRecommendation);
        expect(stale.single.reasonCode, RecommendationReasonCode.staleEvidence);

        await _seedOwnerAndWord(database, ownerId: 'owner-1', wordId: 'word-2');
        await _recordIncorrectPracticeAttempt(
          database,
          ownerId: 'owner-1',
          wordId: 'word-2',
          occurredAtUtc: now.add(const Duration(minutes: 1)),
        );

        final future = await progress.loadFlashcardFirstDecisions(
          ownerId: 'owner-1',
          nowUtc: now,
        );
        expect(
          future
              .firstWhere((decision) => decision.contentId == 'word-2')
              .action,
          RecommendationAction.noRecommendation,
        );
        expect(
          future
              .firstWhere((decision) => decision.contentId == 'word-2')
              .reasonCode,
          RecommendationReasonCode.invalidEvidenceTime,
        );
      },
    );

    test(
      'uses the owner-scoped SRS mastery state and excludes another owner',
      () async {
        final reviewedAt = now.subtract(const Duration(minutes: 1));
        await _recordIncorrectPracticeAttempt(
          database,
          ownerId: 'owner-1',
          wordId: 'word-1',
          occurredAtUtc: now.subtract(const Duration(minutes: 2)),
        );
        await (database.update(database.srsStates)..where(
              (row) =>
                  row.ownerId.equals('owner-1') & row.wordId.equals('word-1'),
            ))
            .write(
              SrsStatesCompanion(
                repetitions: const Value(4),
                intervalDays: const Value(14),
                lastReviewAtUtcMs: Value(reviewedAt.millisecondsSinceEpoch),
              ),
            );
        await _seedOwnerAndWord(database, ownerId: 'owner-2', wordId: 'word-2');
        await _recordIncorrectPracticeAttempt(
          database,
          ownerId: 'owner-2',
          wordId: 'word-2',
          occurredAtUtc: now.subtract(const Duration(minutes: 2)),
        );

        final decisions = await progress.loadFlashcardFirstDecisions(
          ownerId: 'owner-1',
          nowUtc: now,
        );

        expect(decisions, hasLength(1));
        expect(decisions.single.contentId, 'word-1');
        expect(decisions.single.action, RecommendationAction.noRecommendation);
        expect(
          decisions.single.reasonCode,
          RecommendationReasonCode.masteredItem,
        );
        expect(
          decisions.single.evidenceReferences.last.referenceId,
          isNot('srs-2'),
        );
      },
    );

    test(
      'keeps legacy progress recommendations and database snapshots unchanged',
      () async {
        final attemptAt = now.subtract(const Duration(minutes: 2));
        await _recordPracticeAttempt(
          database,
          ownerId: 'owner-1',
          wordId: 'word-1',
          occurredAtUtc: attemptAt,
          isCorrect: false,
        );
        for (var index = 0; index < 3; index++) {
          await _recordPracticeAttempt(
            database,
            ownerId: 'owner-1',
            wordId: 'word-1',
            occurredAtUtc: attemptAt.add(Duration(seconds: index + 1)),
            isCorrect: true,
          );
        }
        final assignments = DriftExperimentAssignmentRepository(database);
        await assignments.assignIfAbsent(
          ownerId: 'owner-1',
          experimentId: 'f14-read-only',
          experimentVersion: 1,
          cohort: 'control',
          protocolVersion: 'protocol-v1',
          assignedAtUtc: now.subtract(const Duration(days: 1)),
        );
        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: 'reward-1',
                ownerId: 'owner-1',
                idempotencyKey: 'reward-1',
                transactionType: 'coinGrant',
                amount: 10,
                catalogVersion: 1,
                occurredAtUtcMs: attemptAt.millisecondsSinceEpoch,
              ),
            );
        final before = await _ownerSnapshot(database, 'owner-1');

        final legacy = await progress.load(ownerId: 'owner-1', nowUtc: now);
        final decision = (await progress.loadFlashcardFirstDecisions(
          ownerId: 'owner-1',
          nowUtc: now,
        )).single;
        decision.withLearnerChoice(RecommendationLearnerChoice.dismiss);
        decision.withLearnerChoice(RecommendationLearnerChoice.override);
        final after = await _ownerSnapshot(database, 'owner-1');

        expect(legacy.algorithmVersion, 1);
        expect(legacy.recommendations, hasLength(1));
        expect(decision.action, RecommendationAction.noRecommendation);
        expect(
          decision.reasonCode,
          RecommendationReasonCode.confidenceSufficient,
        );
        expect(after, before);
      },
    );

    test(
      'rejects persisted noncanonical evidence before typed aggregation',
      () async {
        final occurredAt = now.subtract(const Duration(minutes: 1));
        await _recordIncorrectPracticeAttempt(
          database,
          ownerId: 'owner-1',
          wordId: 'word-1',
          occurredAtUtc: occurredAt,
        );
        final canonicalContext = jsonEncode(
          LearningEvidenceContract.frozenV13LegacyEvidenceContext().toJson(),
        );
        await database
            .into(database.answerAttempts)
            .insert(
              AnswerAttemptsCompanion.insert(
                id: 'attempt-corrupt',
                ownerId: 'owner-1',
                sessionId:
                    'session-word-1-${occurredAt.millisecondsSinceEpoch}',
                wordId: 'word-1',
                promptMode: 'meaningChoice',
                isCorrect: false,
                attemptNumber: 2,
                occurredAtUtcMs: occurredAt
                    .add(const Duration(seconds: 1))
                    .millisecondsSinceEpoch,
                evidenceClass: const Value('independentRecall'),
                evidenceContextJson: Value(' $canonicalContext'),
              ),
            );
        final before = await _ownerSnapshot(database, 'owner-1');

        await expectLater(
          progress.loadFlashcardFirstDecisions(ownerId: 'owner-1', nowUtc: now),
          throwsFormatException,
        );
        await expectLater(
          progress.load(ownerId: 'owner-1', nowUtc: now),
          throwsFormatException,
        );

        expect(await _ownerSnapshot(database, 'owner-1'), before);
      },
    );

    test(
      'rejects a migrated mastery row without a last SRS observation',
      () async {
        await _recordIncorrectPracticeAttempt(
          database,
          ownerId: 'owner-1',
          wordId: 'word-1',
          occurredAtUtc: now.subtract(const Duration(minutes: 2)),
        );
        await (database.update(database.srsStates)..where(
              (row) =>
                  row.ownerId.equals('owner-1') & row.wordId.equals('word-1'),
            ))
            .write(
              const SrsStatesCompanion(
                repetitions: Value(4),
                intervalDays: Value(14),
                lastReviewAtUtcMs: Value(null),
              ),
            );

        final decision = (await progress.loadFlashcardFirstDecisions(
          ownerId: 'owner-1',
          nowUtc: now,
        )).single;

        expect(decision.action, RecommendationAction.noRecommendation);
        expect(
          decision.reasonCode,
          RecommendationReasonCode.invalidMasteryEvidence,
        );
      },
    );
  });
}

Future<void> _seedOwnerAndWord(
  AppDatabase database, {
  required String ownerId,
  required String wordId,
}) async {
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(id: ownerId, createdAtUtcMs: 1),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category-$ownerId',
          ownerId: ownerId,
          name: 'Travel',
          normalizedName: 'travel',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: wordId,
          ownerId: ownerId,
          categoryId: 'category-$ownerId',
          spelling: wordId,
          normalizedSpelling: wordId,
          meaning: 'meaning-$wordId',
          normalizedMeaning: 'meaning-$wordId',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _recordIncorrectPracticeAttempt(
  AppDatabase database, {
  required String ownerId,
  required String wordId,
  required DateTime occurredAtUtc,
}) => _recordPracticeAttempt(
  database,
  ownerId: ownerId,
  wordId: wordId,
  occurredAtUtc: occurredAtUtc,
  isCorrect: false,
);

Future<void> _recordPracticeAttempt(
  AppDatabase database, {
  required String ownerId,
  required String wordId,
  required DateTime occurredAtUtc,
  required bool isCorrect,
}) async {
  final learning = DriftLearningRepository(database);
  final sessionId = 'session-$wordId-${occurredAtUtc.millisecondsSinceEpoch}';
  await learning.startSession(
    LearningSessionDraft(
      id: sessionId,
      ownerId: ownerId,
      activityType: 'quiz',
      startedAtUtc: occurredAtUtc,
      appVersion: 'test',
      buildId: 'test',
    ),
  );
  await learning.recordAnswer(
    RecordAnswerCommand.frozenV13LegacyIngress(
      id: 'attempt-$wordId-${occurredAtUtc.millisecondsSinceEpoch}',
      ownerId: ownerId,
      sessionId: sessionId,
      wordId: wordId,
      promptMode: 'meaningChoice',
      isCorrect: isCorrect,
      responseTimeMs: 100,
      attemptNumber: 1,
      occurredAtUtc: occurredAtUtc,
      evidenceContext:
          LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
    ),
  );
}

Future<Map<String, List<Map<String, Object?>>>> _ownerSnapshot(
  AppDatabase database,
  String ownerId,
) async {
  const tables = <String>[
    'answer_attempts',
    'srs_states',
    'points_ledger_entries',
    'reward_transactions',
    'experiment_assignments',
  ];
  final result = <String, List<Map<String, Object?>>>{};
  for (final table in tables) {
    final rows = await database
        .customSelect(
          'SELECT * FROM $table WHERE owner_id = ? ORDER BY id',
          variables: [Variable<String>(ownerId)],
        )
        .get();
    result[table] = rows
        .map((row) => Map<String, Object?>.unmodifiable(row.data))
        .toList(growable: false);
  }
  return result;
}
