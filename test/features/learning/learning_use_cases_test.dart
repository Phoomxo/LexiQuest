import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_side_effect_reconciler.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  late AppDatabase database;
  late LearningUseCases useCases;
  late DriftLocalOwnerRepository owners;
  late DateTime now;
  late int nextId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 7, 30, 9);
    nextId = 0;
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => now,
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: owner.id,
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in const [
      ('word-1', 'station', 'สถานี'),
      ('word-2', 'ticket', 'ตั๋ว'),
      ('word-3', 'platform', 'ชานชาลา'),
      ('word-4', 'journey', 'การเดินทาง'),
    ]) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.$1,
              ownerId: owner.id,
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
    useCases = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => '${++nextId}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1.2.3', buildId: 'test-build'),
      eventContextProvider: const BaselineLearningEventContextProvider(),
    );
  });

  tearDown(() => database.close());

  test(
    'starts quiz from local words with deterministic unique options',
    () async {
      final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 4);

      expect(quiz.id, 'session:1');
      expect(quiz.questions, hasLength(4));
      expect(quiz.questions.first.options.toSet(), hasLength(4));
      expect(
        quiz.questions.first.options,
        contains(quiz.questions.first.correctAnswer),
      );
      final stored = await database
          .select(database.learningSessions)
          .getSingle();
      expect(stored.appVersion, '1.2.3');
      expect(stored.buildId, 'test-build');
    },
  );

  test(
    'records answers and finishes a session from durable evidence',
    () async {
      final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 2);
      now = now.add(const Duration(seconds: 2));
      await useCases.recordAnswer(
        sessionId: quiz.id,
        wordId: quiz.questions.first.word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
      );
      now = now.add(const Duration(seconds: 1));
      final summary = await useCases.finishSession(quiz.id);

      expect(summary.correctCount, 1);
      expect(summary.wrongCount, 0);
      expect(summary.score, 100);
      final attempts = await database.select(database.answerAttempts).get();
      expect(attempts, hasLength(1));
      final evidence = EvidenceContext.fromJson(
        (jsonDecode(attempts.single.evidenceContextJson) as Map)
            .cast<String, Object?>(),
      );
      expect(
        attempts.single.evidenceClass,
        EvidenceClass.independentRecall.name,
      );
      expect(
        evidence.toJson(),
        EvidenceContext.legacyCompatibility(
          evidenceClass: EvidenceClass.independentRecall,
          skillId: 'legacy-current-activity',
          hintLevel: 0,
          contentRevision: 'legacy-unknown',
          engagementAllowed: true,
        ).toJson(),
      );
    },
  );

  test('recordEvidence reuses one source identity across retry', () async {
    final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 1);
    final occurredAtUtc = now.add(
      const Duration(seconds: 2, milliseconds: 123),
    );
    final evidenceContext = _legacyEvidence();

    final first = await useCases.recordEvidence(
      sourceEvidenceId: 'evidence-1',
      occurredAtUtc: occurredAtUtc,
      sessionId: quiz.id,
      wordId: quiz.questions.single.word.id,
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 2000,
      attemptNumber: 1,
      evidenceContext: evidenceContext,
    );
    final retry = await useCases.recordEvidence(
      sourceEvidenceId: 'evidence-1',
      occurredAtUtc: occurredAtUtc,
      sessionId: quiz.id,
      wordId: quiz.questions.single.word.id,
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 2000,
      attemptNumber: 1,
      evidenceContext: evidenceContext,
    );

    expect(first.inserted, isTrue);
    expect(retry.inserted, isFalse);
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    final learningEvents = (await database.select(database.eventsV2).get())
        .where((row) => row.eventId == 'learning-event:evidence-1')
        .toList(growable: false);
    expect(learningEvents, hasLength(1));
    expect(learningEvents.single.eventVersion, 2);
    expect(
      learningEvents.single.occurredAtUtc.toUtc(),
      now.add(const Duration(seconds: 2)),
    );
    expect(
      (await database.select(database.answerAttempts).getSingle())
          .occurredAtUtcMs,
      occurredAtUtc.millisecondsSinceEpoch,
    );
    expect(
      learningEvents.single.idempotencyKey,
      'learning-attempt:evidence-1:v2',
    );
    final attemptOutbox =
        (await database.select(database.outboxOperations).get())
            .where(
              (row) =>
                  row.entityType == 'attempt' && row.entityId == 'evidence-1',
            )
            .toList(growable: false);
    expect(attemptOutbox, hasLength(1));
    final reconciler = LearningSideEffectReconciler(
      database,
      questSink: (_) async => const LearningProjectionResult.applied(
        payload: {'eligible': true, 'rewardGrants': <Object>[]},
      ),
      streakSink: (_) async => const LearningProjectionResult.applied(),
      rewardSink: (_, _) async => const LearningProjectionResult.applied(),
    );
    await reconciler.reconcileOwner(learningEvents.single.ownerId);
    await reconciler.reconcileOwner(learningEvents.single.ownerId);
    final receiptIds = (await database.select(database.eventsV2).get())
        .where((row) => row.eventId.startsWith('learning-projection:'))
        .map((row) => row.eventId)
        .toList(growable: false);
    expect(receiptIds, hasLength(3));
    expect(receiptIds.toSet(), hasLength(receiptIds.length));

    await expectLater(
      useCases.recordEvidence(
        sourceEvidenceId: 'evidence-1',
        occurredAtUtc: occurredAtUtc,
        sessionId: quiz.id,
        wordId: quiz.questions.single.word.id,
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 2000,
        attemptNumber: 1,
        evidenceContext: evidenceContext,
      ),
      throwsStateError,
    );
    await expectLater(
      useCases.recordEvidence(
        sourceEvidenceId: 'evidence-1',
        occurredAtUtc: occurredAtUtc.add(const Duration(milliseconds: 1)),
        sessionId: quiz.id,
        wordId: quiz.questions.single.word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
        evidenceContext: evidenceContext,
      ),
      throwsStateError,
    );
    await expectLater(
      useCases.recordEvidence(
        sourceEvidenceId: 'evidence-1',
        occurredAtUtc: occurredAtUtc,
        sessionId: quiz.id,
        wordId: quiz.questions.single.word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
        evidenceContext: _legacyEvidence(skillId: 'changed-skill'),
      ),
      throwsStateError,
    );
  });

  test(
    'recordEvidence reuses exact-ms evidence after a file-backed reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-evidence-replay-',
      );
      final path = '${directory.path}${Platform.pathSeparator}learning.sqlite';
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final firstDatabase = AppDatabase(NativeDatabase(File(path)));
      AppDatabase? reopenedDatabase;
      var firstDatabaseClosed = false;
      final occurredAtUtc = DateTime.utc(2026, 8, 14, 9, 0, 2, 123);
      try {
        final firstOwners = DriftLocalOwnerRepository(
          firstDatabase,
          generateId: () => 'file-guest',
          nowUtc: () => now,
        );
        final owner = await firstOwners.getOrCreateActiveOwner();
        await _seedVocabulary(firstDatabase, owner.id);
        var fileId = 0;
        final firstUseCases = LearningUseCases(
          owners: firstOwners,
          repository: DriftLearningRepository(firstDatabase),
          generateId: () => 'file-${++fileId}',
          nowUtc: () => now,
          buildInfo: const AppBuildInfo(
            version: '1.2.3',
            buildId: 'test-build',
          ),
        );
        final quiz = await firstUseCases.startQuiz(
          categoryId: 'category-file',
          limit: 1,
        );
        await firstUseCases.recordEvidence(
          sourceEvidenceId: 'evidence-file-reopen',
          occurredAtUtc: occurredAtUtc,
          sessionId: quiz.id,
          wordId: quiz.questions.single.word.id,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 2000,
          attemptNumber: 1,
          evidenceContext: _legacyEvidence(),
        );
        await firstDatabase.close();
        firstDatabaseClosed = true;

        reopenedDatabase = AppDatabase(NativeDatabase(File(path)));
        final reopenedOwners = DriftLocalOwnerRepository(
          reopenedDatabase,
          generateId: () => 'unused-owner',
          nowUtc: () => now,
        );
        final throwingProvider = _ThrowingLearningEventContextProvider();
        final reopenedUseCases = LearningUseCases(
          owners: reopenedOwners,
          repository: DriftLearningRepository(reopenedDatabase),
          generateId: () => 'unused-id',
          nowUtc: () => now,
          buildInfo: const AppBuildInfo(
            version: '1.2.3',
            buildId: 'test-build',
          ),
          eventContextProvider: throwingProvider,
        );

        final replay = await reopenedUseCases.recordEvidence(
          sourceEvidenceId: 'evidence-file-reopen',
          occurredAtUtc: occurredAtUtc,
          sessionId: quiz.id,
          wordId: quiz.questions.single.word.id,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 2000,
          attemptNumber: 1,
          evidenceContext: _legacyEvidence(),
        );

        expect(replay.inserted, isFalse);
        expect(throwingProvider.calls, 0);
        final attempt = await reopenedDatabase
            .select(reopenedDatabase.answerAttempts)
            .getSingle();
        final event =
            await (reopenedDatabase.select(reopenedDatabase.eventsV2)..where(
                  (row) =>
                      row.eventId.equals('learning-event:evidence-file-reopen'),
                ))
                .getSingle();
        expect(attempt.occurredAtUtcMs, occurredAtUtc.millisecondsSinceEpoch);
        expect(event.occurredAtUtc.toUtc(), DateTime.utc(2026, 8, 14, 9, 0, 2));

        await expectLater(
          reopenedUseCases.recordEvidence(
            sourceEvidenceId: 'evidence-file-reopen',
            occurredAtUtc: occurredAtUtc.add(const Duration(milliseconds: 1)),
            sessionId: quiz.id,
            wordId: quiz.questions.single.word.id,
            promptMode: 'meaningChoice',
            isCorrect: true,
            responseTimeMs: 2000,
            attemptNumber: 1,
            evidenceContext: _legacyEvidence(),
          ),
          throwsStateError,
        );
        expect(throwingProvider.calls, 0);
      } finally {
        if (!firstDatabaseClosed) await firstDatabase.close();
        await reopenedDatabase?.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );

  test('committed retry bypasses a provider that throws or changes', () async {
    final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 1);
    final occurredAtUtc = now.add(
      const Duration(seconds: 2, milliseconds: 123),
    );
    final evidence = _declaredEvidence(EvidencePolicyRolloutMode.shadow);
    final validContext = _researchEventContext(
      evidence,
      assignedAtUtc: occurredAtUtc.subtract(const Duration(minutes: 1)),
    );
    final initialUseCases = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'unused',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1.2.3', buildId: 'test-build'),
      eventContextProvider: _FixedLearningEventContextProvider(validContext),
    );
    await initialUseCases.recordEvidence(
      sourceEvidenceId: 'evidence-provider-replay',
      occurredAtUtc: occurredAtUtc,
      sessionId: quiz.id,
      wordId: quiz.questions.single.word.id,
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 2000,
      attemptNumber: 1,
      evidenceContext: evidence,
    );

    final throwingProvider = _ThrowingLearningEventContextProvider();
    final throwingReplay = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'unused',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1.2.3', buildId: 'test-build'),
      eventContextProvider: throwingProvider,
    );
    expect(
      (await throwingReplay.recordEvidence(
        sourceEvidenceId: 'evidence-provider-replay',
        occurredAtUtc: occurredAtUtc,
        sessionId: quiz.id,
        wordId: quiz.questions.single.word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
        evidenceContext: evidence,
      )).inserted,
      isFalse,
    );
    expect(throwingProvider.calls, 0);

    final changedProvider = _CountingLearningEventContextProvider(
      _researchEventContext(
        evidence,
        assignedAtUtc: occurredAtUtc.subtract(const Duration(minutes: 1)),
        assignmentId: 'changed-assignment',
      ),
    );
    final scheduledOwners = <String>[];
    final changedReplay = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'unused',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1.2.3', buildId: 'test-build'),
      eventContextProvider: changedProvider,
      onSideEffectsPending: scheduledOwners.add,
    );
    expect(
      (await changedReplay.recordEvidence(
        sourceEvidenceId: 'evidence-provider-replay',
        occurredAtUtc: occurredAtUtc,
        sessionId: quiz.id,
        wordId: quiz.questions.single.word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
        evidenceContext: evidence,
      )).inserted,
      isFalse,
    );
    expect(changedProvider.calls, 0);
    expect(scheduledOwners, ['local:guest']);
    final replayedEvent =
        await (database.select(database.eventsV2)..where(
              (row) =>
                  row.eventId.equals('learning-event:evidence-provider-replay'),
            ))
            .getSingle();
    expect(replayedEvent.occurredAtUtc.toUtc().millisecond, 0);
    expect(
      (jsonDecode(replayedEvent.payloadJson)
          as Map<String, dynamic>)['evidenceContext'],
      evidence.toJson(),
    );
  });

  test('committed retry fails closed for a missing or corrupt event', () async {
    final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 1);
    final occurredAtUtc = now.add(
      const Duration(seconds: 2, milliseconds: 123),
    );

    Future<void> record(String id) => useCases.recordEvidence(
      sourceEvidenceId: id,
      occurredAtUtc: occurredAtUtc,
      sessionId: quiz.id,
      wordId: quiz.questions.single.word.id,
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 2000,
      attemptNumber: 1,
      evidenceContext: _legacyEvidence(),
    );

    await record('evidence-missing-event');
    await record('evidence-corrupt-event');
    await (database.delete(database.eventsV2)..where(
          (row) => row.eventId.equals('learning-event:evidence-missing-event'),
        ))
        .go();
    final missingProvider = _ThrowingLearningEventContextProvider();
    var missingCallbacks = 0;
    final missingReplay = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'unused',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1.2.3', buildId: 'test-build'),
      eventContextProvider: missingProvider,
      onSideEffectsPending: (_) => missingCallbacks++,
    );
    await expectLater(
      missingReplay.recordEvidence(
        sourceEvidenceId: 'evidence-missing-event',
        occurredAtUtc: occurredAtUtc,
        sessionId: quiz.id,
        wordId: quiz.questions.single.word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
        evidenceContext: _legacyEvidence(),
      ),
      throwsStateError,
    );
    expect(missingProvider.calls, 0);
    expect(missingCallbacks, 0);

    await database.customUpdate(
      'UPDATE events_v2 SET payload_json = ? WHERE event_id = ?',
      variables: const [
        Variable<String>('{}'),
        Variable<String>('learning-event:evidence-corrupt-event'),
      ],
      updates: {database.eventsV2},
    );
    final corruptProvider = _ThrowingLearningEventContextProvider();
    var corruptCallbacks = 0;
    final corruptReplay = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'unused',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1.2.3', buildId: 'test-build'),
      eventContextProvider: corruptProvider,
      onSideEffectsPending: (_) => corruptCallbacks++,
    );
    await expectLater(
      corruptReplay.recordEvidence(
        sourceEvidenceId: 'evidence-corrupt-event',
        occurredAtUtc: occurredAtUtc,
        sessionId: quiz.id,
        wordId: quiz.questions.single.word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
        evidenceContext: _legacyEvidence(),
      ),
      throwsStateError,
    );
    expect(corruptProvider.calls, 0);
    expect(corruptCallbacks, 0);
  });

  test('recordEvidence rejects an unstable caller-owned identity', () async {
    final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 1);
    for (final sourceEvidenceId in <String>[
      ' evidence-1',
      'evidence-1 ',
      '',
      'x' * 198,
    ]) {
      await expectLater(
        useCases.recordEvidence(
          sourceEvidenceId: sourceEvidenceId,
          occurredAtUtc: now,
          sessionId: quiz.id,
          wordId: quiz.questions.single.word.id,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 2000,
          attemptNumber: 1,
          evidenceContext: _legacyEvidence(),
        ),
        throwsArgumentError,
        reason: 'source identity must be canonical: "$sourceEvidenceId"',
      );
    }
    expect(await database.select(database.answerAttempts).get(), isEmpty);
  });

  test('source evidence identity reserves every derived ID budget', () async {
    final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 1);
    final accepted = List<String>.filled(197, '🧠').join();
    final rejected = '$accepted🧠';
    final evidence = _legacyEvidence();
    final provider = _CountingLearningEventContextProvider(
      LearningEventContext.noResearch(evidence),
    );
    final boundedUseCases = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => 'unused',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1.2.3', buildId: 'test-build'),
      eventContextProvider: provider,
    );

    expect(
      (await boundedUseCases.recordEvidence(
        sourceEvidenceId: accepted,
        occurredAtUtc: now,
        sessionId: quiz.id,
        wordId: quiz.questions.single.word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
        evidenceContext: evidence,
      )).inserted,
      isTrue,
    );
    expect(provider.calls, 1);

    await expectLater(
      boundedUseCases.recordEvidence(
        sourceEvidenceId: rejected,
        occurredAtUtc: now,
        sessionId: quiz.id,
        wordId: quiz.questions.single.word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
        evidenceContext: evidence,
      ),
      throwsArgumentError,
    );
    expect(provider.calls, 1, reason: '198 scalars fail before provider use');
    expect(await database.select(database.answerAttempts).get(), hasLength(1));

    final eventId = LearningEvidenceContract.learningEventId(accepted);
    final derivedIds = <String>[
      eventId,
      LearningEvidenceContract.learningAttemptIdempotencyKey(accepted),
      LearningEvidenceContract.answerAttemptOutboxOperationId(accepted),
      LearningEvidenceContract.learningProjectionReceiptId(
        projection: 'activeLearningEffort',
        sourceEventId: eventId,
        appliedVersion: 2,
      ),
    ];
    expect(accepted.runes.length, 197);
    expect(rejected.runes.length, 198);
    expect(
      derivedIds.map((id) => id.runes.length),
      everyElement(lessThanOrEqualTo(256)),
    );
    expect(derivedIds.last.runes.length, 256);
  });

  test('recordEvidence rejects a non-UTC occurrence time', () async {
    final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 1);

    await expectLater(
      useCases.recordEvidence(
        sourceEvidenceId: 'evidence-local-time',
        occurredAtUtc: DateTime(2026, 8, 14, 9),
        sessionId: quiz.id,
        wordId: quiz.questions.single.word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
        evidenceContext: _legacyEvidence(),
      ),
      throwsArgumentError,
    );
    expect(await database.select(database.answerAttempts).get(), isEmpty);
  });

  test(
    'baseline event context is no-research for Legacy and otherwise fails closed',
    () async {
      const provider = BaselineLearningEventContextProvider();
      for (final evidenceClass in EvidenceClass.values.where(
        (value) => value != EvidenceClass.assessment,
      )) {
        final evidence = EvidenceContext.legacyCompatibility(
          evidenceClass: evidenceClass,
          skillId: 'legacy-${evidenceClass.name}',
          hintLevel: 0,
          contentRevision: 'legacy-unknown',
          engagementAllowed: true,
        );

        final eventContext = await provider.resolve(
          ownerId: 'guest',
          evidenceContext: evidence,
          occurredAtUtc: now,
        );

        expect(eventContext.consentContext.researchConsentVersion, 0);
        expect(eventContext.experimentContext, isNull);
        expect(eventContext.protocolId, isNull);
        expect(eventContext.protocolVersion, isNull);
        expect(eventContext.experimentVersion, isNull);
        expect(eventContext.assignmentId, isNull);
        expect(
          eventContext.featureContractIdentity,
          FeatureContractIdentity(
            revision: evidence.featureContractRevision,
            semanticHash: evidence.featureContractHash,
          ),
        );
      }

      for (final evidence in <EvidenceContext>[
        _declaredEvidence(EvidencePolicyRolloutMode.shadow),
        _declaredEvidence(EvidencePolicyRolloutMode.enforced),
        _declaredEvidence(
          EvidencePolicyRolloutMode.legacy,
          evidenceClass: EvidenceClass.assessment,
        ),
      ]) {
        await expectLater(
          provider.resolve(
            ownerId: 'guest',
            evidenceContext: evidence,
            occurredAtUtc: now,
          ),
          throwsStateError,
          reason: '${evidence.rolloutMode.name}/${evidence.evidenceClass.name}',
        );
      }
    },
  );

  test('recordEvidence rejects every declared provider mismatch', () async {
    final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 1);
    final occurredAtUtc = now.add(const Duration(seconds: 2));
    final evidence = _declaredEvidence(EvidencePolicyRolloutMode.shadow);
    final assignedAtUtc = occurredAtUtc.subtract(const Duration(minutes: 1));
    final validIdentity = FeatureContractIdentity(
      revision: evidence.featureContractRevision,
      semanticHash: evidence.featureContractHash,
    );
    final mismatches = <String, LearningEventContext>{
      'schema version': _researchEventContext(
        evidence,
        assignedAtUtc: assignedAtUtc,
        schemaVersion: 2,
      ),
      'zero consent': _researchEventContext(
        evidence,
        assignedAtUtc: assignedAtUtc,
        researchConsentVersion: 0,
      ),
      'different consent': _researchEventContext(
        evidence,
        assignedAtUtc: assignedAtUtc,
        researchConsentVersion: 2,
      ),
      'missing experiment': LearningEventContext(
        consentContext: const ConsentContext(
          researchConsentVersion: 1,
          aiConsentGranted: false,
          voiceConsentGranted: false,
          socialConsentGranted: false,
        ),
        experimentContext: null,
        protocolId: evidence.protocolId,
        protocolVersion: evidence.protocolVersion,
        experimentVersion: evidence.experimentVersion,
        assignmentId: evidence.assignmentId,
        featureContractIdentity: validIdentity,
      ),
      'experiment id': _researchEventContext(
        evidence,
        assignedAtUtc: assignedAtUtc,
        experimentId: 'other-experiment',
      ),
      'experiment variant': _researchEventContext(
        evidence,
        assignedAtUtc: assignedAtUtc,
        variantId: 'other-cohort',
      ),
      'non-UTC assignment time': _researchEventContext(
        evidence,
        assignedAtUtc: DateTime(2026, 8, 14, 8, 59),
      ),
      'future assignment time': _researchEventContext(
        evidence,
        assignedAtUtc: occurredAtUtc.add(const Duration(milliseconds: 1)),
      ),
      'missing protocol id': LearningEventContext(
        consentContext: const ConsentContext(
          researchConsentVersion: 1,
          aiConsentGranted: false,
          voiceConsentGranted: false,
          socialConsentGranted: false,
        ),
        experimentContext: ExperimentContext(
          experimentId: evidence.experimentId!,
          variantId: evidence.cohort!,
          assignedAtUtc: assignedAtUtc,
        ),
        protocolId: null,
        protocolVersion: evidence.protocolVersion,
        experimentVersion: evidence.experimentVersion,
        assignmentId: evidence.assignmentId,
        featureContractIdentity: validIdentity,
      ),
      'protocol id': _researchEventContext(
        evidence,
        assignedAtUtc: assignedAtUtc,
        protocolId: 'other-protocol',
      ),
      'missing protocol version': LearningEventContext(
        consentContext: const ConsentContext(
          researchConsentVersion: 1,
          aiConsentGranted: false,
          voiceConsentGranted: false,
          socialConsentGranted: false,
        ),
        experimentContext: ExperimentContext(
          experimentId: evidence.experimentId!,
          variantId: evidence.cohort!,
          assignedAtUtc: assignedAtUtc,
        ),
        protocolId: evidence.protocolId,
        protocolVersion: null,
        experimentVersion: evidence.experimentVersion,
        assignmentId: evidence.assignmentId,
        featureContractIdentity: validIdentity,
      ),
      'protocol version': _researchEventContext(
        evidence,
        assignedAtUtc: assignedAtUtc,
        protocolVersion: 'other-protocol',
      ),
      'missing experiment version': LearningEventContext(
        consentContext: const ConsentContext(
          researchConsentVersion: 1,
          aiConsentGranted: false,
          voiceConsentGranted: false,
          socialConsentGranted: false,
        ),
        experimentContext: ExperimentContext(
          experimentId: evidence.experimentId!,
          variantId: evidence.cohort!,
          assignedAtUtc: assignedAtUtc,
        ),
        protocolId: evidence.protocolId,
        protocolVersion: evidence.protocolVersion,
        experimentVersion: null,
        assignmentId: evidence.assignmentId,
        featureContractIdentity: validIdentity,
      ),
      'experiment version': _researchEventContext(
        evidence,
        assignedAtUtc: assignedAtUtc,
        experimentVersion: 2,
      ),
      'missing assignment id': LearningEventContext(
        consentContext: const ConsentContext(
          researchConsentVersion: 1,
          aiConsentGranted: false,
          voiceConsentGranted: false,
          socialConsentGranted: false,
        ),
        experimentContext: ExperimentContext(
          experimentId: evidence.experimentId!,
          variantId: evidence.cohort!,
          assignedAtUtc: assignedAtUtc,
        ),
        protocolId: evidence.protocolId,
        protocolVersion: evidence.protocolVersion,
        experimentVersion: evidence.experimentVersion,
        assignmentId: null,
        featureContractIdentity: validIdentity,
      ),
      'assignment id': _researchEventContext(
        evidence,
        assignedAtUtc: assignedAtUtc,
        assignmentId: 'other-assignment',
      ),
      'contract revision': _researchEventContext(
        evidence,
        assignedAtUtc: assignedAtUtc,
        featureContractIdentity: FeatureContractIdentity(
          revision: 'other-revision',
          semanticHash: evidence.featureContractHash,
        ),
      ),
      'contract hash': _researchEventContext(
        evidence,
        assignedAtUtc: assignedAtUtc,
        featureContractIdentity: FeatureContractIdentity(
          revision: evidence.featureContractRevision,
          semanticHash: 'f' * 64,
        ),
      ),
    };

    var index = 0;
    for (final mismatch in mismatches.entries) {
      final mismatchedUseCases = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'unused',
        nowUtc: () => now,
        buildInfo: const AppBuildInfo(version: '1.2.3', buildId: 'test-build'),
        eventContextProvider: _FixedLearningEventContextProvider(
          mismatch.value,
        ),
      );
      await expectLater(
        mismatchedUseCases.recordEvidence(
          sourceEvidenceId: 'mismatch-${++index}',
          occurredAtUtc: occurredAtUtc,
          sessionId: quiz.id,
          wordId: quiz.questions.single.word.id,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 2000,
          attemptNumber: 1,
          evidenceContext: evidence,
        ),
        throwsStateError,
        reason: mismatch.key,
      );
    }
    expect(await database.select(database.answerAttempts).get(), isEmpty);
    expect(await database.select(database.eventsV2).get(), isEmpty);
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  });

  test('empty local vocabulary returns an explicit empty quiz', () async {
    final quiz = await useCases.startQuiz(categoryId: 'missing', limit: 10);

    expect(quiz.questions, isEmpty);
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  test(
    'weakness practice selects only requested local evidence words',
    () async {
      final session = await useCases.startWeaknessPractice(
        wordIds: const ['word-3', 'word-1', 'missing'],
      );

      expect(session.questions.map((question) => question.word.id).toSet(), {
        'word-1',
        'word-3',
      });
      final stored = await database
          .select(database.learningSessions)
          .getSingle();
      expect(stored.activityType, 'ghostDuel');
    },
  );

  test('reading use cases save and restore owner-scoped progress', () async {
    final empty = await useCases.loadReadingProgress(
      documentId: 'article-1',
      documentRevision: 1,
    );
    expect(empty, isNull);

    final saved = await useCases.saveReadingProgress(
      documentId: 'article-1',
      documentRevision: 1,
      position: 4,
      isCompleted: false,
    );
    final restored = await useCases.loadReadingProgress(
      documentId: 'article-1',
      documentRevision: 1,
    );

    expect(saved.lastPosition, 4);
    expect(restored, saved);
  });
}

Future<void> _seedVocabulary(AppDatabase database, String ownerId) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category-file',
          ownerId: ownerId,
          name: 'File-backed',
          normalizedName: 'file-backed',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word-file',
          ownerId: ownerId,
          categoryId: 'category-file',
          spelling: 'durable',
          normalizedSpelling: 'durable',
          meaning: 'persistent',
          normalizedMeaning: 'persistent',
          partOfSpeech: 'adjective',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

EvidenceContext _legacyEvidence({String skillId = 'legacy-current-activity'}) {
  return EvidenceContext.legacyCompatibility(
    evidenceClass: EvidenceClass.independentRecall,
    skillId: skillId,
    hintLevel: 0,
    contentRevision: 'legacy-unknown',
    engagementAllowed: true,
  );
}

EvidenceContext _declaredEvidence(
  EvidencePolicyRolloutMode rolloutMode, {
  EvidenceClass evidenceClass = EvidenceClass.independentRecall,
}) {
  return EvidenceContext.forNewEvidence(
    evidenceClass: evidenceClass,
    skillId: evidenceClass == EvidenceClass.assessment
        ? 'assessment-meaning'
        : 'meaning-recall',
    hintLevel: 0,
    contentRevision: 'content-r1',
    rolloutMode: rolloutMode,
    protocolId: 'protocol-1',
    protocolVersion: 'protocol-v1',
    experimentId: 'experiment-1',
    experimentVersion: 1,
    assignmentId: 'assignment-1',
    cohort: 'variant-a',
    researchConsentVersion: 1,
    instrumentId: evidenceClass == EvidenceClass.assessment
        ? 'instrument-1'
        : null,
    instrumentVersion: evidenceClass == EvidenceClass.assessment ? '1' : null,
    formId: evidenceClass == EvidenceClass.assessment ? 'form-1' : null,
    formVersion: evidenceClass == EvidenceClass.assessment ? '1' : null,
    assessmentItemId: evidenceClass == EvidenceClass.assessment
        ? 'item-1'
        : null,
    assessmentResponseCode: evidenceClass == EvidenceClass.assessment
        ? 'correct'
        : null,
    scoringRuleVersion: evidenceClass == EvidenceClass.assessment
        ? 'score-v1'
        : null,
    engagementAllowed: true,
  );
}

LearningEventContext _researchEventContext(
  EvidenceContext evidence, {
  required DateTime assignedAtUtc,
  int schemaVersion = LearningEventContext.currentSchemaVersion,
  int researchConsentVersion = 1,
  String? experimentId,
  String? variantId,
  String? protocolId,
  String? protocolVersion,
  int? experimentVersion,
  String? assignmentId,
  FeatureContractIdentity? featureContractIdentity,
}) {
  return LearningEventContext(
    schemaVersion: schemaVersion,
    consentContext: ConsentContext(
      researchConsentVersion: researchConsentVersion,
      aiConsentGranted: false,
      voiceConsentGranted: false,
      socialConsentGranted: false,
    ),
    experimentContext: ExperimentContext(
      experimentId: experimentId ?? evidence.experimentId!,
      variantId: variantId ?? evidence.cohort!,
      assignedAtUtc: assignedAtUtc,
    ),
    protocolId: protocolId ?? evidence.protocolId,
    protocolVersion: protocolVersion ?? evidence.protocolVersion,
    experimentVersion: experimentVersion ?? evidence.experimentVersion,
    assignmentId: assignmentId ?? evidence.assignmentId,
    featureContractIdentity:
        featureContractIdentity ??
        FeatureContractIdentity(
          revision: evidence.featureContractRevision,
          semanticHash: evidence.featureContractHash,
        ),
  );
}

final class _FixedLearningEventContextProvider
    implements LearningEventContextProvider {
  const _FixedLearningEventContextProvider(this.context);

  final LearningEventContext context;

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async => context;
}

final class _CountingLearningEventContextProvider
    implements LearningEventContextProvider {
  _CountingLearningEventContextProvider(this.context);

  final LearningEventContext context;
  int calls = 0;

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async {
    calls++;
    return context;
  }
}

final class _ThrowingLearningEventContextProvider
    implements LearningEventContextProvider {
  int calls = 0;

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) async {
    calls++;
    throw StateError('provider must not resolve committed evidence');
  }
}
