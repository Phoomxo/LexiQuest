/// Tests for DriftLearningProjectionRebuilder
///
/// Verifies rebuildWord() replays AnswerAttempts to reconstruct
/// SrsStates + XP PointsLedgerEntries, and is idempotent.
///
/// Run: flutter test test/features/learning/data/drift_learning_projection_rebuilder_test.dart
library;

import 'dart:convert';

import 'package:drift/drift.dart' show Value;
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

        final rebuilder = DriftLearningProjectionRebuilder(db);
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

    test('assessment-only rebuild leaves mastery and XP empty', () async {
      await _insertAttempt(
        db,
        isCorrect: true,
        seqMs: 0,
        attemptNumber: 1,
        evidenceContext: _assessmentEvidence(),
      );

      final rebuilder = DriftLearningProjectionRebuilder(db);
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
