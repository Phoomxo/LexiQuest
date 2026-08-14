import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';

void main() {
  late AppDatabase database;
  late DriftLearningRepository learning;
  late DriftProgressQueries progress;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    learning = DriftLearningRepository(database);
    progress = DriftProgressQueries(database);
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-1',
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in const [
      ('word-1', 'station', 'สถานี'),
      ('word-2', 'ticket', 'ตั๋ว'),
    ]) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.$1,
              ownerId: 'owner-1',
              categoryId: 'category-1',
              spelling: word.$2,
              normalizedSpelling: word.$2,
              meaning: word.$3,
              normalizedMeaning: word.$3,
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
  });

  tearDown(() => database.close());

  test(
    'empty evidence returns sample size zero without invented scores',
    () async {
      final result = await progress.load(
        ownerId: 'owner-1',
        nowUtc: DateTime.utc(2026, 7, 30, 12),
      );

      expect(result.sampleSize, 0);
      expect(result.accuracy, isNull);
      expect(result.streakDays, 0);
      expect(result.weaknesses, isEmpty);
      expect(result.recommendations, isEmpty);
    },
  );

  test('mixed attempts derive accuracy points weakness and streak', () async {
    await learning.startSession(
      LearningSessionDraft(
        id: 'session-1',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: DateTime.utc(2026, 7, 29, 10),
        appVersion: 'test',
        buildId: 'test',
      ),
    );
    await learning.recordAnswer(
      RecordAnswerCommand.frozenV13LegacyIngress(
        id: 'attempt-1',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 500,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 29, 10),
        evidenceContext: _frozenV13LegacyEvidence(),
      ),
    );
    await learning.recordAnswer(
      RecordAnswerCommand.frozenV13LegacyIngress(
        id: 'attempt-2',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-2',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 400,
        attemptNumber: 2,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10),
        evidenceContext: _frozenV13LegacyEvidence(),
      ),
    );
    await learning.finishSession(
      ownerId: 'owner-1',
      sessionId: 'session-1',
      endedAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
    );

    final result = await progress.load(
      ownerId: 'owner-1',
      nowUtc: DateTime.utc(2026, 7, 30, 12),
    );

    expect(result.sampleSize, 2);
    expect(result.accuracy, 0.5);
    expect(result.totalXp, 1);
    expect(result.completedSessions, 1);
    expect(result.streakDays, 2);
    expect(result.weaknesses.single.wordId, 'word-1');
    expect(result.weaknesses.single.incorrectCount, 1);
    expect(result.recommendations.single.sampleSize, 1);
  });

  test('assessment evidence is absent from the practice read model', () async {
    final assessment = _assessmentEvidence();
    await database
        .into(database.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: 'session-assessment',
            ownerId: 'owner-1',
            activityType: 'assessment',
            state: 'completed',
            startedAtUtcMs: DateTime.utc(2026, 7, 30, 9).millisecondsSinceEpoch,
            endedAtUtcMs: Value(
              DateTime.utc(2026, 7, 30, 10).millisecondsSinceEpoch,
            ),
            correctCount: const Value(1),
            score: const Value(100),
            appVersion: 'test',
            buildId: 'test',
          ),
        );
    await database
        .into(database.answerAttempts)
        .insert(
          AnswerAttemptsCompanion.insert(
            id: 'attempt-assessment',
            ownerId: 'owner-1',
            sessionId: 'session-assessment',
            wordId: 'word-1',
            promptMode: 'assessmentResponse',
            isCorrect: true,
            responseTimeMs: const Value(300),
            attemptNumber: 1,
            occurredAtUtcMs: DateTime.utc(
              2026,
              7,
              30,
              9,
              30,
            ).millisecondsSinceEpoch,
            evidenceClass: Value(assessment.evidenceClass.name),
            evidenceContextJson: Value(jsonEncode(assessment.toJson())),
          ),
        );

    final result = await progress.load(
      ownerId: 'owner-1',
      nowUtc: DateTime.utc(2026, 7, 30, 12),
    );

    expect(result.sampleSize, 0);
    expect(result.correctCount, 0);
    expect(result.wrongCount, 0);
    expect(result.accuracy, isNull);
    expect(result.completedSessions, 0);
    expect(result.streakDays, 0);
    expect(result.skills.every((skill) => skill.sampleSize == 0), isTrue);
    expect(result.weaknesses, isEmpty);
    expect(result.recommendations, isEmpty);
    expect(result.averageResponseTimeMs, isNull);
    expect(result.latestEvidenceAtUtc, isNull);
  });
}

EvidenceContext _frozenV13LegacyEvidence() =>
    LearningEvidenceContract.frozenV13LegacyEvidenceContext();

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
