/// Tests for DriftLearningProjectionRebuilder
///
/// Verifies rebuildWord() replays AnswerAttempts to reconstruct
/// SrsStates + XP PointsLedgerEntries, and is idempotent.
///
/// Run: flutter test test/features/learning/data/drift_learning_projection_rebuilder_test.dart
library;

import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';

AppDatabase _openMemory() => AppDatabase(NativeDatabase.memory());

Future<void> _seedOwnerAndWord(AppDatabase db) async {
  await db
      .into(db.localOwners)
      .insert(
        LocalOwnersCompanion.insert(id: 'owner-rebuild', createdAtUtcMs: 1),
      );
  // AnswerAttempts.session_id has FK → LearningSessions
  await db
      .into(db.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'session-rebuild',
          ownerId: 'owner-rebuild',
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: 1,
          appVersion: '0.0.0',
          buildId: 'test',
        ),
      );
  await db
      .into(db.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'cat-rebuild',
          ownerId: 'owner-rebuild',
          name: 'rebuild-test',
          normalizedName: 'rebuild-test',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await db
      .into(db.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word-rebuild',
          ownerId: 'owner-rebuild',
          categoryId: 'cat-rebuild',
          spelling: 'rebuild',
          normalizedSpelling: 'rebuild',
          meaning: 'test',
          normalizedMeaning: 'test',
          partOfSpeech: 'verb',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _insertAttempt(
  AppDatabase db, {
  required bool isCorrect,
  required int seqMs,
  required int attemptNumber,
  EvidenceContext? evidenceContext,
}) async {
  final occurredAtUtc = DateTime.utc(
    2026,
    1,
    1,
  ).add(Duration(milliseconds: seqMs));
  await db
      .into(db.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: 'attempt-$seqMs',
          ownerId: 'owner-rebuild',
          wordId: 'word-rebuild',
          sessionId: 'session-rebuild',
          promptMode: 'meaningChoice',
          isCorrect: isCorrect,
          attemptNumber: attemptNumber,
          occurredAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          evidenceClass: evidenceContext == null
              ? const Value.absent()
              : Value(evidenceContext.evidenceClass.name),
          evidenceContextJson: evidenceContext == null
              ? const Value.absent()
              : Value(jsonEncode(evidenceContext.toJson())),
        ),
      );
  final context = evidenceContext;
  if (context != null) {
    await DriftLearningEventStore(db).append(
      EventEnvelopeV2(
        eventId: 'learning-event:attempt-$seqMs',
        eventType: isCorrect ? 'QuizCompleted' : 'QuizAttempted',
        eventVersion: 2,
        occurredAtUtc: occurredAtUtc,
        recordedAtUtc: occurredAtUtc,
        actorIdentity: 'owner-rebuild',
        ownerIdentity: 'owner-rebuild',
        aggregateType: 'LearningSession',
        aggregateId: 'session-rebuild',
        idempotencyKey: 'learning-attempt:attempt-$seqMs:v2',
        consentContext: ConsentContext(
          researchConsentVersion: context.researchConsentVersion!,
          aiConsentGranted: false,
          voiceConsentGranted: false,
          socialConsentGranted: false,
        ),
        experimentContext: ExperimentContext(
          experimentId: context.experimentId!,
          variantId: context.cohort!,
          assignedAtUtc: DateTime.utc(2025, 12, 31),
        ),
        contentRevision: context.contentRevision,
        policyVersion: context.policyVersion,
        appVersion: '0.0.0',
        buildId: 'test',
        privacyClassification: PrivacyClassification.anonymized,
        payload: <String, dynamic>{
          'attemptId': 'attempt-$seqMs',
          'wordId': 'word-rebuild',
          'promptMode': 'meaningChoice',
          'correct': isCorrect,
          'score': isCorrect ? 100 : 0,
          'attemptNumber': attemptNumber,
          'evidenceContext': context.toJson(),
        },
      ),
    );
  }
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _openMemory();
    await _seedOwnerAndWord(db);
  });
  tearDown(() => db.close());

  group('DriftLearningProjectionRebuilder', () {
    test('default rollout is fixed Legacy', () {
      final rebuilder = DriftLearningProjectionRebuilder(db);

      expect(
        rebuilder.evidenceDecisions.rolloutModeProvider,
        isA<FixedEvidencePolicyRolloutModeProvider>().having(
          (provider) => provider.mode,
          'mode',
          EvidencePolicyRolloutMode.legacy,
        ),
      );
    });

    test('rebuildWord writes SrsState row from answer history', () async {
      await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);
      await _insertAttempt(db, isCorrect: false, seqMs: 1000, attemptNumber: 2);
      await _insertAttempt(db, isCorrect: true, seqMs: 2000, attemptNumber: 3);

      final rebuilder = DriftLearningProjectionRebuilder(db);
      final snapshot = await rebuilder.rebuildWord(
        ownerId: 'owner-rebuild',
        wordId: 'word-rebuild',
      );

      expect(snapshot?.intervalDays, greaterThanOrEqualTo(1));

      final srsRows = await (db.select(
        db.srsStates,
      )..where((row) => row.ownerId.equals('owner-rebuild'))).get();
      expect(srsRows.length, 1);
    });

    test('rebuildWord inserts XP entry for each correct answer', () async {
      await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);
      await _insertAttempt(db, isCorrect: true, seqMs: 1000, attemptNumber: 2);
      await _insertAttempt(db, isCorrect: false, seqMs: 2000, attemptNumber: 3);

      final rebuilder = DriftLearningProjectionRebuilder(db);
      await rebuilder.rebuildWord(
        ownerId: 'owner-rebuild',
        wordId: 'word-rebuild',
      );

      final entries = await (db.select(
        db.pointsLedgerEntries,
      )..where((row) => row.ownerId.equals('owner-rebuild'))).get();
      expect(entries.length, 2); // 2 correct answers → 2 XP entries
      expect(entries.every((e) => e.amount > 0), isTrue);
    });

    test(
      'rebuildWord excludes assessment from SRS and lifetime XP replay',
      () async {
        await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);
        await _insertAttempt(
          db,
          isCorrect: true,
          seqMs: 1000,
          attemptNumber: 2,
          evidenceContext: _assessmentEvidence(),
        );

        final rebuilder = DriftLearningProjectionRebuilder(
          db,
          rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
        );
        final snapshot = await rebuilder.rebuildWord(
          ownerId: 'owner-rebuild',
          wordId: 'word-rebuild',
        );

        expect(snapshot?.repetitions, 1);
        final entries = await (db.select(
          db.pointsLedgerEntries,
        )..where((row) => row.ownerId.equals('owner-rebuild'))).get();
        expect(entries.map((entry) => entry.sourceEventId), <String?>{
          'attempt-0',
        });
      },
    );

    test('denied evidence leaves mastery XP and achievements empty', () async {
      await _insertAttempt(
        db,
        isCorrect: true,
        seqMs: 0,
        attemptNumber: 1,
        evidenceContext: _assessmentEvidence(),
      );
      await _insertAttempt(
        db,
        isCorrect: true,
        seqMs: 1000,
        attemptNumber: 2,
        evidenceContext: _declaredEvidence(EvidenceClass.guidedPractice),
      );
      await _insertAttempt(
        db,
        isCorrect: true,
        seqMs: 2000,
        attemptNumber: 3,
        evidenceContext: _declaredEvidence(EvidenceClass.recreational),
      );

      final rebuilder = DriftLearningProjectionRebuilder(
        db,
        rolloutModeProvider: const ContextEvidencePolicyRolloutModeProvider(),
      );
      expect(
        await rebuilder.rebuildWord(
          ownerId: 'owner-rebuild',
          wordId: 'word-rebuild',
        ),
        isNull,
      );
      expect(await db.select(db.srsStates).get(), isEmpty);
      expect(await db.select(db.pointsLedgerEntries).get(), isEmpty);
      await rebuilder.rebuildAchievements('owner-rebuild');
      expect(await db.select(db.achievementUnlocks).get(), isEmpty);
    });

    test(
      'achievement rebuild preserves durable unlocks across definition changes',
      () async {
        await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);
        await db
            .into(db.achievementUnlocks)
            .insert(
              AchievementUnlocksCompanion.insert(
                id: 'achievement:owner-rebuild:first_answer:7',
                ownerId: 'owner-rebuild',
                achievementId: 'first_answer',
                definitionVersion: 7,
                sourceEventId: 'historical-source',
                unlockedAtUtcMs: 7,
              ),
            );
        await db
            .into(db.achievementUnlocks)
            .insert(
              AchievementUnlocksCompanion.insert(
                id: 'achievement:owner-rebuild:ten_correct:1',
                ownerId: 'owner-rebuild',
                achievementId: 'ten_correct',
                definitionVersion: 1,
                sourceEventId: 'historical-tenth',
                unlockedAtUtcMs: 8,
              ),
            );

        await DriftLearningProjectionRebuilder(
          db,
        ).rebuildAchievements('owner-rebuild');

        final rows = await (db.select(
          db.achievementUnlocks,
        )..orderBy([(row) => OrderingTerm.asc(row.achievementId)])).get();
        expect(rows.map((row) => row.achievementId), [
          'first_answer',
          'first_correct',
          'ten_correct',
        ]);
        expect(
          rows.singleWhere((row) => row.achievementId == 'first_answer'),
          isA<AchievementUnlock>()
              .having((row) => row.definitionVersion, 'definitionVersion', 7)
              .having(
                (row) => row.sourceEventId,
                'sourceEventId',
                'historical-source',
              ),
        );
        expect(
          rows.singleWhere((row) => row.achievementId == 'ten_correct'),
          isA<AchievementUnlock>().having(
            (row) => row.sourceEventId,
            'sourceEventId',
            'historical-tenth',
          ),
        );
      },
    );

    test(
      'achievement rebuild backfills outbox without rewriting legacy unlock',
      () async {
        await db
            .into(db.achievementUnlocks)
            .insert(
              AchievementUnlocksCompanion.insert(
                id: 'legacy-achievement-row',
                ownerId: 'owner-rebuild',
                achievementId: 'first_answer',
                definitionVersion: 7,
                sourceEventId: 'legacy-attempt',
                unlockedAtUtcMs: 7,
              ),
            );
        final before = (await db.select(db.achievementUnlocks).get()).single;

        await DriftLearningProjectionRebuilder(
          db,
        ).rebuildAchievements('owner-rebuild');

        expect((await db.select(db.achievementUnlocks).get()).single, before);
        final operation = (await db.select(db.outboxOperations).get()).single;
        expect(
          operation.operationId,
          'achievementUnlock:legacy-achievement-row:1',
        );
        expect(operation.entityId, 'legacy-achievement-row');
        expect(operation.createdAtUtcMs, 7);
      },
    );

    test('achievement rebuild rejects negative definition versions', () async {
      await db
          .into(db.achievementUnlocks)
          .insert(
            AchievementUnlocksCompanion.insert(
              id: 'invalid-negative-achievement-row',
              ownerId: 'owner-rebuild',
              achievementId: 'invalid_negative',
              definitionVersion: -1,
              sourceEventId: 'invalid-negative-source',
              unlockedAtUtcMs: 7,
            ),
          );

      await expectLater(
        DriftLearningProjectionRebuilder(
          db,
        ).rebuildAchievements('owner-rebuild'),
        throwsStateError,
      );
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    });

    test(
      'achievement rebuild is byte-stable and includes session milestones',
      () async {
        await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);
        final completedAt = DateTime.utc(2026, 1, 1, 0, 1);
        await (db.update(
          db.learningSessions,
        )..where((row) => row.id.equals('session-rebuild'))).write(
          LearningSessionsCompanion(
            state: const Value('completed'),
            endedAtUtcMs: Value(completedAt.millisecondsSinceEpoch),
          ),
        );
        final rebuilder = DriftLearningProjectionRebuilder(db);

        await rebuilder.rebuildAchievements('owner-rebuild');
        final first = (await db.select(db.achievementUnlocks).get())
            .map((row) => row.toJson())
            .toList(growable: false);
        await rebuilder.rebuildAchievements('owner-rebuild');
        final replay = (await db.select(db.achievementUnlocks).get())
            .map((row) => row.toJson())
            .toList(growable: false);

        expect(replay, first);
        expect(replay.map((row) => row['achievementId']).toSet(), {
          'first_answer',
          'first_correct',
          'first_session',
          'perfect_session',
        });
        expect(
          replay.singleWhere(
            (row) => row['achievementId'] == 'first_session',
          )['sourceEventId'],
          'session-rebuild',
        );
      },
    );

    test(
      'concurrent achievement rebuilds converge to one unlock per rule',
      () async {
        await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);
        final first = DriftLearningProjectionRebuilder(db);
        final second = DriftLearningProjectionRebuilder(db);

        await Future.wait([
          first.rebuildAchievements('owner-rebuild'),
          second.rebuildAchievements('owner-rebuild'),
        ]);

        final rows = await db.select(db.achievementUnlocks).get();
        expect(rows.map((row) => row.achievementId).toSet(), {
          'first_answer',
          'first_correct',
        });
        expect(rows, hasLength(2));
      },
    );

    test(
      'new achievement unlocks have stable source-bound outbox rows',
      () async {
        await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);

        await DriftLearningProjectionRebuilder(
          db,
        ).rebuildAchievements('owner-rebuild');

        final operations =
            await (db.select(db.outboxOperations)
                  ..where((row) => row.entityType.equals('achievementUnlock'))
                  ..orderBy([(row) => OrderingTerm.asc(row.operationId)]))
                .get();
        expect(operations, hasLength(2));
        expect(operations.map((row) => row.operationId), [
          'achievementUnlock:achievement:owner-rebuild:first_answer:1:1',
          'achievementUnlock:achievement:owner-rebuild:first_correct:1:1',
        ]);
        expect(operations.map((row) => row.entityId), [
          'achievement:owner-rebuild:first_answer:1',
          'achievement:owner-rebuild:first_correct:1',
        ]);
      },
    );

    test('conflicting achievement outbox rolls back every new unlock', () async {
      await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);
      await db
          .into(db.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId:
                  'achievementUnlock:achievement:owner-rebuild:first_answer:1:1',
              ownerId: 'owner-rebuild',
              entityType: 'achievementUnlock',
              entityId: 'forged-unlock',
              operationKind: 'upsert',
              createdAtUtcMs: 1,
            ),
          );

      await expectLater(
        DriftLearningProjectionRebuilder(
          db,
        ).rebuildAchievements('owner-rebuild'),
        throwsStateError,
      );

      expect(await db.select(db.achievementUnlocks).get(), isEmpty);
    });

    test('rebuildWord throws StateError when no attempts exist', () async {
      final rebuilder = DriftLearningProjectionRebuilder(db);
      await expectLater(
        () => rebuilder.rebuildWord(
          ownerId: 'owner-rebuild',
          wordId: 'word-rebuild',
        ),
        throwsStateError,
      );
    });

    test(
      'rebuildWord is idempotent — XP count stable across two runs',
      () async {
        await _insertAttempt(db, isCorrect: true, seqMs: 0, attemptNumber: 1);
        await _insertAttempt(
          db,
          isCorrect: true,
          seqMs: 1000,
          attemptNumber: 2,
        );

        final rebuilder = DriftLearningProjectionRebuilder(db);
        await rebuilder.rebuildWord(
          ownerId: 'owner-rebuild',
          wordId: 'word-rebuild',
        );
        // Second run — idempotency key must prevent duplicate XP entries
        await rebuilder.rebuildWord(
          ownerId: 'owner-rebuild',
          wordId: 'word-rebuild',
        );

        final entries = await (db.select(
          db.pointsLedgerEntries,
        )..where((row) => row.ownerId.equals('owner-rebuild'))).get();
        expect(entries.length, 2);
      },
    );
  });
}

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

EvidenceContext _declaredEvidence(EvidenceClass evidenceClass) =>
    EvidenceContext.forNewEvidence(
      evidenceClass: evidenceClass,
      skillId: 'declared-skill',
      hintLevel: evidenceClass == EvidenceClass.guidedPractice ? 1 : 0,
      contentRevision: 'declared-content-v1',
      rolloutMode: EvidencePolicyRolloutMode.enforced,
      protocolId: 'protocol-a',
      protocolVersion: 'protocol-v1',
      experimentId: 'experiment-a',
      experimentVersion: 1,
      assignmentId: 'assignment-a',
      cohort: 'treatment',
      researchConsentVersion: 1,
      engagementAllowed: true,
    );
