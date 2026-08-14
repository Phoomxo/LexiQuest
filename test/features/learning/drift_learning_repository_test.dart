import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

void main() {
  late AppDatabase database;
  late DriftLearningRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLearningRepository(database);
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

  test('quiz words come from active local vocabulary for the owner', () async {
    final words = await repository.listQuizWords(
      ownerId: 'owner-1',
      categoryId: 'category-1',
      limit: 10,
    );

    expect(words.map((word) => word.id), ['word-1', 'word-2']);
    expect(words.first.meaning, 'สถานี');
  });

  test('answer transaction is idempotent and updates SRS and points', () async {
    const session = LearningSessionDraft(
      id: 'session-1',
      ownerId: 'owner-1',
      activityType: 'quiz',
      startedAtUtc: null,
      appVersion: '1.0.0',
      buildId: 'test',
    );
    await repository.startSession(
      session.copyWith(startedAtUtc: DateTime.utc(2026, 7, 30, 10)),
    );
    final command = RecordAnswerCommand.frozenV13LegacyIngress(
      id: 'attempt-1',
      ownerId: 'owner-1',
      sessionId: 'session-1',
      wordId: 'word-1',
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 420,
      attemptNumber: 1,
      occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      evidenceContext: _legacyEvidence(),
    );

    final first = await repository.recordAnswer(command);
    final replay = await repository.recordAnswer(command);

    expect(first.inserted, isTrue);
    expect(replay.inserted, isFalse);
    expect(replay.srs, isA<SrsSnapshot>());
    expect(replay.srs!.intervalDays, 1);
    final attempts = await database.select(database.answerAttempts).get();
    expect(attempts, hasLength(1));
    final storedAttempt = attempts.single;
    expect(
      storedAttempt.evidenceClass,
      command.evidenceContext.evidenceClass.name,
    );
    expect(
      EvidenceContext.fromJson(
        (jsonDecode(storedAttempt.evidenceContextJson) as Map)
            .cast<String, Object?>(),
      ).toJson(),
      command.evidenceContext.toJson(),
    );
    expect(
      await database.select(database.pointsLedgerEntries).get(),
      hasLength(1),
    );
    final achievements = await database
        .select(database.achievementUnlocks)
        .get();
    expect(achievements.map((row) => row.achievementId).toSet(), {
      'first_answer',
      'first_correct',
    });
    final outbox = await database.select(database.outboxOperations).get();
    expect(outbox.map((row) => row.entityType), contains('attempt'));
    final storedSession = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals('session-1'))).getSingle();
    expect(storedSession.correctCount, 1);
    expect(storedSession.wrongCount, 0);
  });

  test('answer rejects an event not correlated to its evidence id', () async {
    await repository.startSession(
      LearningSessionDraft(
        id: 'session-event-correlation',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: DateTime.utc(2026, 7, 30, 10),
        appVersion: '1.0.0',
        buildId: 'test',
      ),
    );
    final base = RecordAnswerCommand.frozenV13LegacyIngress(
      id: 'attempt-event-correlation',
      ownerId: 'owner-1',
      sessionId: 'session-event-correlation',
      wordId: 'word-1',
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 420,
      attemptNumber: 1,
      occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      evidenceContext: _legacyEvidence(),
    );
    final canonicalEvidence = EvidenceContext.legacyCompatibility(
      evidenceClass: EvidenceClass.independentRecall,
      skillId: 'meaning-recall',
      hintLevel: 0,
      contentRevision: 'legacy-unknown',
      engagementAllowed: true,
    );
    final invalidJson = _eventForEvidence(base, canonicalEvidence).toJson()
      ..['eventId'] = 'learning-event:different-evidence';

    expect(
      () => repository.recordAnswer(
        RecordAnswerCommand(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: base.promptMode,
          isCorrect: base.isCorrect,
          responseTimeMs: base.responseTimeMs,
          attemptNumber: base.attemptNumber,
          occurredAtUtc: base.occurredAtUtc,
          evidenceContext: canonicalEvidence,
          event: EventEnvelopeV2.fromJson(invalidJson),
        ),
      ),
      throwsArgumentError,
    );
    expect(await database.select(database.answerAttempts).get(), isEmpty);
    expect(await database.select(database.eventsV2).get(), isEmpty);
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  });

  test('finishing session stores auditable score and counts', () async {
    await repository.startSession(
      LearningSessionDraft(
        id: 'session-1',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: DateTime.utc(2026, 7, 30, 10),
        appVersion: '1.0.0',
        buildId: 'test',
      ),
    );
    await repository.recordAnswer(
      RecordAnswerCommand.frozenV13LegacyIngress(
        id: 'attempt-1',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 800,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
        evidenceContext: _legacyEvidence(),
      ),
    );

    final result = await repository.finishSession(
      ownerId: 'owner-1',
      sessionId: 'session-1',
      endedAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
    );

    expect(result.state, 'completed');
    expect(result.correctCount, 0);
    expect(result.wrongCount, 1);
    expect(result.score, 0);
  });

  test(
    'out-of-order local attempts rebuild SRS in canonical event order',
    () async {
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-order',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 9),
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );
      final later = DateTime.utc(2026, 7, 30, 10);
      final earlier = DateTime.utc(2026, 7, 30, 9, 30);
      await repository.recordAnswer(
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: 'attempt-later',
          ownerId: 'owner-1',
          sessionId: 'session-order',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 200,
          attemptNumber: 2,
          occurredAtUtc: later,
          evidenceContext: _legacyEvidence(),
        ),
      );

      final result = await repository.recordAnswer(
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: 'attempt-earlier',
          ownerId: 'owner-1',
          sessionId: 'session-order',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: false,
          responseTimeMs: 300,
          attemptNumber: 1,
          occurredAtUtc: earlier,
          evidenceContext: _legacyEvidence(),
        ),
      );

      expect(result.srs, isA<SrsSnapshot>());
      expect(result.srs!.lastReviewAtUtc, later);
      expect(result.srs!.repetitions, 1);
      expect(result.srs!.lapses, 1);
      final firstAnswer = await (database.select(
        database.achievementUnlocks,
      )..where((row) => row.achievementId.equals('first_answer'))).getSingle();
      expect(firstAnswer.sourceEventId, 'attempt-earlier');
      expect(firstAnswer.unlockedAtUtcMs, earlier.millisecondsSinceEpoch);
    },
  );

  test('attempt replay compares provider provenance', () async {
    await repository.startSession(
      LearningSessionDraft(
        id: 'session-provenance',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: DateTime.utc(2026, 7, 30, 10),
        appVersion: '1.0.0',
        buildId: 'test',
      ),
    );
    final command = RecordAnswerCommand.frozenV13LegacyIngress(
      id: 'attempt-provenance',
      ownerId: 'owner-1',
      sessionId: 'session-provenance',
      wordId: 'word-1',
      promptMode: 'pronunciation',
      isCorrect: true,
      responseTimeMs: 400,
      attemptNumber: 1,
      occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      providerProvenance: 'device-stt',
      evidenceContext: _legacyEvidence(),
    );
    await repository.recordAnswer(command);

    await expectLater(
      repository.recordAnswer(
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: command.id,
          ownerId: command.ownerId,
          sessionId: command.sessionId,
          wordId: command.wordId,
          promptMode: command.promptMode,
          isCorrect: command.isCorrect,
          responseTimeMs: command.responseTimeMs,
          attemptNumber: command.attemptNumber,
          occurredAtUtc: command.occurredAtUtc,
          providerProvenance: 'cloud-stt',
          evidenceContext: command.evidenceContext,
        ),
      ),
      throwsStateError,
    );
  });

  test(
    'attempt replay rejects changes to every serialized evidence field',
    () async {
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-evidence-replay',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 10),
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );
      final command = RecordAnswerCommand.frozenV13LegacyIngress(
        id: 'attempt-evidence-replay',
        ownerId: 'owner-1',
        sessionId: 'session-evidence-replay',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 400,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
        evidenceContext: _legacyEvidence(),
      );
      await repository.recordAnswer(command);

      final canonical = command.evidenceContext.toJson();
      final mutations = <String, Object?>{
        'schemaVersion': 2,
        'evidenceClass': EvidenceClass.recognition.name,
        'skillId': 'changed-skill',
        'hintLevel': 1,
        'policyVersion': 'changed-policy',
        'contentRevision': 'changed-content',
        'featureContractRevision': 'changed-contract',
        'featureContractHash': '1' * 64,
        'classificationSource': EvidenceClassificationSource.declared.name,
        'rolloutMode': EvidencePolicyRolloutMode.shadow.name,
        'protocolId': 'protocol',
        'protocolVersion': 'protocol-version',
        'experimentId': 'experiment',
        'experimentVersion': 1,
        'assignmentId': 'assignment',
        'cohort': 'cohort',
        'researchConsentVersion': 1,
        'instrumentId': 'instrument',
        'instrumentVersion': 'instrument-version',
        'formId': 'form',
        'formVersion': 'form-version',
        'assessmentItemId': 'assessment-item',
        'assessmentResponseCode': 'correct',
        'scoringRuleVersion': 'scoring-rule',
        'engagementAllowed': false,
      };
      expect(mutations.keys.toSet(), canonical.keys.toSet());

      for (final mutation in mutations.entries) {
        final changed = Map<String, Object?>.from(canonical)
          ..[mutation.key] = mutation.value;
        await database.customUpdate(
          'UPDATE answer_attempts SET evidence_context_json = ? WHERE id = ?',
          variables: [
            Variable<String>(jsonEncode(changed)),
            const Variable<String>('attempt-evidence-replay'),
          ],
          updates: {database.answerAttempts},
        );

        await expectLater(
          repository.recordAnswer(command),
          throwsStateError,
          reason: 'changed ${mutation.key} must invalidate immutable replay',
        );

        await database.customUpdate(
          'UPDATE answer_attempts SET evidence_context_json = ? WHERE id = ?',
          variables: [
            Variable<String>(jsonEncode(canonical)),
            const Variable<String>('attempt-evidence-replay'),
          ],
          updates: {database.answerAttempts},
        );
      }

      await database.customUpdate(
        'UPDATE answer_attempts SET evidence_class = ? WHERE id = ?',
        variables: const [
          Variable<String>('recognition'),
          Variable<String>('attempt-evidence-replay'),
        ],
        updates: {database.answerAttempts},
      );
      await expectLater(repository.recordAnswer(command), throwsStateError);
    },
  );

  test(
    'invalid cloud-contract evidence is rejected before local commit',
    () async {
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-limits',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 10),
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );
      final base = RecordAnswerCommand.frozenV13LegacyIngress(
        id: 'attempt-limits',
        ownerId: 'owner-1',
        sessionId: 'session-limits',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 400,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
        evidenceContext: _legacyEvidence(),
      );

      for (final invalid in [
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: 'x' * 61,
          isCorrect: base.isCorrect,
          responseTimeMs: base.responseTimeMs,
          attemptNumber: base.attemptNumber,
          occurredAtUtc: base.occurredAtUtc,
          evidenceContext: base.evidenceContext,
        ),
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: base.promptMode,
          isCorrect: base.isCorrect,
          responseTimeMs: 2147483648,
          attemptNumber: base.attemptNumber,
          occurredAtUtc: base.occurredAtUtc,
          evidenceContext: base.evidenceContext,
        ),
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: base.promptMode,
          isCorrect: base.isCorrect,
          responseTimeMs: base.responseTimeMs,
          attemptNumber: 1000001,
          occurredAtUtc: base.occurredAtUtc,
          evidenceContext: base.evidenceContext,
        ),
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: base.promptMode,
          isCorrect: base.isCorrect,
          responseTimeMs: base.responseTimeMs,
          attemptNumber: base.attemptNumber,
          occurredAtUtc: base.occurredAtUtc,
          providerProvenance: 'p' * 121,
          evidenceContext: base.evidenceContext,
        ),
      ]) {
        expect(() => repository.recordAnswer(invalid), throwsArgumentError);
      }

      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'only the exact frozen-v13 factory admits eventless answer evidence',
    () async {
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-frozen-v13',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 10),
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );
      expect(
        () => RecordAnswerCommand.frozenV13LegacyIngress(
          id: 'declared-eventless',
          ownerId: 'owner-1',
          sessionId: 'session-frozen-v13',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 400,
          attemptNumber: 1,
          occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
          evidenceContext: EvidenceContext.forNewEvidence(
            evidenceClass: EvidenceClass.independentRecall,
            skillId: 'meaning-recall',
            hintLevel: 0,
            contentRevision: 'content-r1',
            rolloutMode: EvidencePolicyRolloutMode.legacy,
          ),
        ),
        throwsArgumentError,
      );

      final eventless = RecordAnswerCommand.frozenV13LegacyIngress(
        id: 'frozen-eventless',
        ownerId: 'owner-1',
        sessionId: 'session-frozen-v13',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 400,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1, 0, 123),
        evidenceContext:
            LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
      );
      expect((await repository.recordAnswer(eventless)).inserted, isTrue);
      expect((await repository.recordAnswer(eventless)).inserted, isFalse);
      final decisionEvents = await database.select(database.eventsV2).get();
      expect(decisionEvents, hasLength(1));
      expect(
        decisionEvents.single.eventId,
        'learning-evidence-decisions:frozen-eventless:v1',
      );
      expect(decisionEvents.single.eventType, 'LearningEvidenceDecisionSet');
      expect(
        decisionEvents.any(
          (event) => event.eventId == 'learning-event:frozen-eventless',
        ),
        isFalse,
      );
      expect(
        () => repository.replayCommittedAnswer(eventless.candidate),
        throwsArgumentError,
      );

      expect(
        () => RecordAnswerCommand(
          id: eventless.id,
          ownerId: eventless.ownerId,
          sessionId: eventless.sessionId,
          wordId: eventless.wordId,
          promptMode: eventless.promptMode,
          isCorrect: eventless.isCorrect,
          responseTimeMs: eventless.responseTimeMs,
          attemptNumber: eventless.attemptNumber,
          occurredAtUtc: eventless.occurredAtUtc,
          evidenceContext: eventless.evidenceContext,
          event: _eventFor(eventless),
        ),
        throwsArgumentError,
      );

      final canonicalEvidence = EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'canonical-legacy-recall',
        hintLevel: 0,
        contentRevision: 'legacy-unknown',
        engagementAllowed: true,
      );
      final canonicalSeed = RecordAnswerCommand.frozenV13LegacyIngress(
        id: 'frozen-canonical',
        ownerId: 'owner-1',
        sessionId: 'session-frozen-v13',
        wordId: 'word-2',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 450,
        attemptNumber: 2,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 2, 0, 123),
        evidenceContext:
            LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
      );
      final canonical = RecordAnswerCommand(
        id: canonicalSeed.id,
        ownerId: canonicalSeed.ownerId,
        sessionId: canonicalSeed.sessionId,
        wordId: canonicalSeed.wordId,
        promptMode: canonicalSeed.promptMode,
        isCorrect: canonicalSeed.isCorrect,
        responseTimeMs: canonicalSeed.responseTimeMs,
        attemptNumber: canonicalSeed.attemptNumber,
        occurredAtUtc: canonicalSeed.occurredAtUtc,
        evidenceContext: canonicalEvidence,
        event: _eventForEvidence(canonicalSeed, canonicalEvidence),
      );
      expect((await repository.recordAnswer(canonical)).inserted, isTrue);
      await expectLater(
        repository.recordAnswer(canonicalSeed),
        throwsStateError,
      );
    },
  );

  test('reading progress is monotonic and completion is idempotent', () async {
    final first = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-1',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 80,
        isCompleted: false,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10),
      ),
    );
    final rewound = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-2',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 30,
        isCompleted: false,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      ),
    );
    final completed = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-3',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 100,
        isCompleted: true,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
      ),
    );
    final replay = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-3',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 100,
        isCompleted: true,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
      ),
    );

    expect(first.lastPosition, 80);
    expect(rewound.lastPosition, 80);
    expect(completed.isCompleted, isTrue);
    expect(replay, completed);
    expect(await database.select(database.readingEvents).get(), hasLength(3));
    final readingOutbox = await (database.select(
      database.outboxOperations,
    )..where((row) => row.entityType.equals('readingEvent'))).get();
    expect(readingOutbox, hasLength(3));
  });

  test('answer result can represent evidence without an SRS projection', () {
    const result = AnswerRecordResult(inserted: true, srs: null);

    expect(result.inserted, isTrue);
    expect(result.srs, equals(null));
  });
}

EvidenceContext _legacyEvidence() =>
    LearningEvidenceContract.frozenV13LegacyEvidenceContext();

EventEnvelopeV2 _eventFor(RecordAnswerCommand command) {
  return _eventForEvidence(command, command.evidenceContext);
}

EventEnvelopeV2 _eventForEvidence(
  RecordAnswerCommand command,
  EvidenceContext evidenceContext,
) {
  const adapter = EventV1ToV2Adapter(appVersion: '1.0.0', buildId: 'test');
  return adapter.adaptFromCommand(
    sourceEvidenceId: command.id,
    ownerId: command.ownerId,
    sessionId: command.sessionId,
    wordId: command.wordId,
    promptMode: command.promptMode,
    isCorrect: command.isCorrect,
    attemptNumber: command.attemptNumber,
    occurredAtUtc: command.occurredAtUtc,
    evidenceContext: evidenceContext,
    learningEventContext: LearningEventContext.noResearch(evidenceContext),
  );
}
