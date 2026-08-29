import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_avatar_progression_eligibility.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

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

  test('default repository and rebuilder rollout is fixed Legacy', () {
    expect(
      repository.events.rolloutModeProvider,
      isA<FixedEvidencePolicyRolloutModeProvider>().having(
        (provider) => provider.mode,
        'mode',
        EvidencePolicyRolloutMode.legacy,
      ),
    );
    expect(
      repository.projections.evidenceDecisions.rolloutModeProvider,
      isA<FixedEvidencePolicyRolloutModeProvider>().having(
        (provider) => provider.mode,
        'mode',
        EvidencePolicyRolloutMode.legacy,
      ),
    );
  });

  test(
    'current-schema null checksum rows receive a canonical read identity',
    () async {
      final words = await repository.listQuizWords(
        ownerId: 'owner-1',
        categoryId: 'category-1',
        limit: 10,
      );

      expect(words.map((word) => word.id), ['word-1', 'word-2']);
      expect(words.first.meaning, 'สถานี');
      expect(
        words.first.contentChecksumSha256,
        ContentQualityPolicy.vocabularyChecksumSha256(
          categoryId: 'category-1',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          cefrLevel: null,
          source: 'manual',
          isGlobal: false,
        ),
      );
      expect(
        (await database.select(database.vocabularyWords).get()).every(
          (word) => word.contentChecksumSha256 == null,
        ),
        isTrue,
        reason: 'compatibility identity is deterministic and read-only',
      );
    },
  );

  test(
    'valid-shaped wrong core checksum fails before learning mutation',
    () async {
      await (database.update(
        database.vocabularyWords,
      )..where((word) => word.id.equals('word-1'))).write(
        VocabularyWordsCompanion(contentChecksumSha256: Value('a' * 64)),
      );

      await expectLater(
        repository.listQuizWords(
          ownerId: 'owner-1',
          categoryId: 'category-1',
          limit: 10,
        ),
        throwsA(
          isA<ContentQualityFailure>().having(
            (failure) => failure.code,
            'code',
            ContentQualityFailureCode.checksumMismatch,
          ),
        ),
      );
      expect(await database.select(database.learningSessions).get(), isEmpty);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(await database.select(database.eventsV2).get(), isEmpty);
    },
  );

  test('typed recall records from a null legacy checksum identity', () async {
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'unexpected-owner',
      nowUtc: () => DateTime.utc(2026, 8, 28, 9),
    );
    var generatedId = 0;
    final learning = LearningUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'legacy-typed-${++generatedId}',
      nowUtc: () => DateTime.utc(2026, 8, 28, 9, generatedId),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'legacy-typed'),
    );
    final session = await learning.startQuiz(
      categoryId: 'category-1',
      limit: 1,
    );
    final prompt = const TypedRecallModeAdapter().pinQuizPrompt(
      session.questions.single.word,
    );
    final captured = const TypedRecallModeAdapter().capture(
      evidence: CurrentActivityEvidenceAdapter(learning: learning),
      ownerId: session.ownerId,
      sessionId: session.id,
      prompt: prompt,
      response: 'station',
      responseTimeMs: 100,
      attemptNumber: 1,
      support: const TypedRecallSupport.unassisted(),
    );

    expect((await captured.pending.record()).isCorrect, isTrue);
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    expect(
      (await database.select(database.vocabularyWords).get()).every(
        (word) => word.contentChecksumSha256 == null,
      ),
      isTrue,
    );
  });

  test(
    'typed recall rejects wrong checksum before creating its session',
    () async {
      await (database.update(
        database.vocabularyWords,
      )..where((word) => word.id.equals('word-1'))).write(
        VocabularyWordsCompanion(contentChecksumSha256: Value('b' * 64)),
      );
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'unexpected-owner',
        nowUtc: () => DateTime.utc(2026, 8, 28, 10),
      );
      final learning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'wrong-typed',
        nowUtc: () => DateTime.utc(2026, 8, 28, 10),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'wrong-typed'),
      );

      await expectLater(
        learning.startQuiz(categoryId: 'category-1', limit: 1),
        throwsA(
          isA<ContentQualityFailure>().having(
            (failure) => failure.code,
            'code',
            ContentQualityFailureCode.checksumMismatch,
          ),
        ),
      );
      expect(await database.select(database.learningSessions).get(), isEmpty);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(await database.select(database.eventsV2).get(), isEmpty);
    },
  );

  test(
    'verified lexical variants reach typed evidence and stale artifacts fail closed',
    () async {
      const wordId = 'word-2';
      final coreChecksum = ContentQualityPolicy.vocabularyChecksumSha256(
        categoryId: 'category-1',
        spelling: 'ticket',
        normalizedSpelling: 'ticket',
        meaning: 'ตั๋ว',
        normalizedMeaning: 'ตั๋ว',
        partOfSpeech: 'noun',
        cefrLevel: null,
        source: 'pack:v1',
        isGlobal: true,
      );
      await (database.update(
        database.vocabularyWords,
      )..where((row) => row.id.equals(wordId))).write(
        VocabularyWordsCompanion(
          source: const Value('pack:v1'),
          isGlobal: const Value(true),
          contentRevision: const Value(1),
          contentChecksumSha256: Value(coreChecksum),
          contentProvenance: const Value('packaged'),
          contentReviewState: const Value('approved'),
          contentPublicationState: const Value('published'),
        ),
      );
      final artifact = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': 3,
            'wordId': wordId,
            'contentRevision': 1,
            'englishDefinition': 'A pass used for a journey.',
            'ipa': null,
            'examples': <String>[],
            'synonyms': <String>[],
            'antonyms': <String>[],
            'acceptedSpellingVariants': <String>['rail ticket'],
            'audio': null,
          }),
        ),
      );
      final artifacts = <String, Uint8List>{wordId: artifact};
      Future<void> writeManifest({
        required String manifestId,
        required String contentId,
        required Uint8List bytes,
      }) async {
        await database
            .into(database.contentManifests)
            .insert(
              ContentManifestsCompanion.insert(
                id: manifestId,
                contentType: ContentType.lexicalMetadata.name,
                contentId: contentId,
                revision: 1,
                checksumSha256: sha256.convert(bytes).toString(),
                byteLength: bytes.length,
                provenance: ContentProvenance.packaged.name,
                sourceUri: 'asset://lexical-metadata/$contentId/r1.json',
                reviewState: ContentReviewState.approved.name,
                publicationState: ContentPublicationState.published.name,
                createdAtUtcMs: 1,
                reviewedAtUtcMs: const Value(2),
                publishedAtUtcMs: const Value(3),
              ),
            );
      }

      await writeManifest(
        manifestId: 'manifest:word-2:r1',
        contentId: wordId,
        bytes: artifact,
      );
      final vocabulary = DriftVocabularyRepository(
        database,
        contentManifests: DriftContentManifestRepository(
          database,
          loadArtifactBytes: (identity) async => artifacts[identity.id],
        ),
      );
      final lexicalLearningRepository = DriftLearningRepository(
        database,
        lexicalVocabulary: vocabulary,
      );
      final words = await lexicalLearningRepository.listQuizWords(
        ownerId: 'owner-1',
        categoryId: 'category-1',
        limit: 10,
      );
      final ticket = words.singleWhere((word) => word.id == wordId);
      final artifactChecksum = sha256.convert(artifact).toString();
      expect(ticket.acceptedSpellingVariants, const <String>['rail ticket']);
      expect(ticket.acceptedSpellingVariantsRevision, 1);
      expect(ticket.acceptedSpellingVariantsChecksumSha256, artifactChecksum);

      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'unexpected-owner',
        nowUtc: () => DateTime.utc(2026, 8, 26, 13),
      );
      var id = 0;
      final learning = LearningUseCases(
        owners: owners,
        repository: lexicalLearningRepository,
        generateId: () => 'verified-variant-${++id}',
        nowUtc: () => DateTime.utc(2026, 8, 26, 13, 0, id),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'f11-real-variant',
        ),
      );
      final session = await learning.startQuiz(
        categoryId: 'category-1',
        limit: 2,
      );
      final adapter = const TypedRecallModeAdapter();
      final prompt = adapter.pinQuizPrompt(
        session.questions
            .singleWhere((question) => question.word.id == wordId)
            .word,
      );
      final accepted = adapter.capture(
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        sessionId: session.id,
        prompt: prompt,
        response: 'RAIL TICKET',
        responseTimeMs: 240,
        attemptNumber: 1,
        support: const TypedRecallSupport.unassisted(),
      );
      expect((await accepted.pending.record()).isCorrect, isTrue);
      expect(
        adapter
            .evaluate(
              prompt: prompt,
              response: 'unknown ticket',
              support: const TypedRecallSupport.unassisted(),
            )
            .isCorrect,
        isFalse,
      );
      final stored =
          (await database.select(database.answerAttempts).get()).single;
      final storedContext = EvidenceContext.fromJson(
        (jsonDecode(stored.evidenceContextJson) as Map).cast<String, Object?>(),
      );
      expect(
        storedContext.contentRevision,
        'lexical-typed-recall:$wordId@1:'
        '${typedRecallAnswerSetChecksumSha256(coreChecksumSha256: coreChecksum, acceptedVariantsRevision: 1, acceptedVariantsChecksumSha256: artifactChecksum)}',
      );

      artifacts.remove(wordId);
      final offlineWords = await lexicalLearningRepository.listQuizWords(
        ownerId: 'owner-1',
        categoryId: 'category-1',
        limit: 10,
      );
      expect(
        offlineWords
            .singleWhere((word) => word.id == wordId)
            .acceptedSpellingVariants,
        isEmpty,
      );
      artifacts[wordId] = Uint8List.fromList(<int>[...artifact, 0x20]);
      final tamperedWords = await lexicalLearningRepository.listQuizWords(
        ownerId: 'owner-1',
        categoryId: 'category-1',
        limit: 10,
      );
      expect(
        tamperedWords
            .singleWhere((word) => word.id == wordId)
            .acceptedSpellingVariants,
        isEmpty,
      );
      artifacts[wordId] = artifact;

      const staleWordId = 'word-stale';
      final staleCoreChecksum = ContentQualityPolicy.vocabularyChecksumSha256(
        categoryId: 'category-1',
        spelling: 'pass',
        normalizedSpelling: 'pass',
        meaning: 'บัตรผ่าน',
        normalizedMeaning: 'บัตรผ่าน',
        partOfSpeech: 'noun',
        cefrLevel: null,
        source: 'pack:v1',
        isGlobal: true,
      );
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: staleWordId,
              ownerId: 'owner-1',
              categoryId: 'category-1',
              spelling: 'pass',
              normalizedSpelling: 'pass',
              meaning: 'บัตรผ่าน',
              normalizedMeaning: 'บัตรผ่าน',
              partOfSpeech: 'noun',
              source: const Value('pack:v1'),
              isGlobal: const Value(true),
              contentRevision: const Value(1),
              contentChecksumSha256: Value(staleCoreChecksum),
              contentProvenance: const Value('packaged'),
              contentReviewState: const Value('approved'),
              contentPublicationState: const Value('published'),
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      final staleArtifact = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schemaVersion': 3,
            'wordId': staleWordId,
            'contentRevision': 2,
            'englishDefinition': 'A pass used for a journey.',
            'ipa': null,
            'examples': <String>[],
            'synonyms': <String>[],
            'antonyms': <String>[],
            'acceptedSpellingVariants': <String>['stale rail ticket'],
            'audio': null,
          }),
        ),
      );
      artifacts[staleWordId] = staleArtifact;
      await writeManifest(
        manifestId: 'manifest:word-stale:r1',
        contentId: staleWordId,
        bytes: staleArtifact,
      );
      final staleWords = await lexicalLearningRepository.listQuizWords(
        ownerId: 'owner-1',
        categoryId: 'category-1',
        limit: 10,
      );
      expect(
        staleWords
            .singleWhere((word) => word.id == staleWordId)
            .acceptedSpellingVariants,
        isEmpty,
      );
    },
  );

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
    expect(first.isCorrect, isTrue);
    expect(replay.isCorrect, isTrue);
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

  test(
    'avatar cutover quarantine cannot roll back canonical learning evidence',
    () async {
      await DriftAvatarProgressionEligibility(
        database,
      ).establishCutover('owner-1');
      await database
          .into(database.rewardTransactions)
          .insert(
            RewardTransactionsCompanion.insert(
              id: 'late-avatar-row',
              ownerId: 'owner-1',
              idempotencyKey: 'late-avatar-row',
              transactionType: 'purchase',
              amount: -80,
              itemId: const Value('theme_ocean'),
              catalogVersion: RewardCatalog.catalogV1Version,
              occurredAtUtcMs: 2,
            ),
          );
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-avatar-quarantine',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 10),
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );

      final result = await repository.recordAnswer(
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: 'attempt-avatar-quarantine',
          ownerId: 'owner-1',
          sessionId: 'session-avatar-quarantine',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 420,
          attemptNumber: 1,
          occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
          evidenceContext: _legacyEvidence(),
        ),
      );

      expect(result.inserted, isTrue);
      expect(
        await (database.select(database.answerAttempts)
              ..where((row) => row.id.equals('attempt-avatar-quarantine')))
            .getSingleOrNull(),
        isA<AnswerAttempt>(),
      );
      expect(
        await (database.select(database.pointsLedgerEntries)..where(
              (row) => row.sourceEventId.equals('attempt-avatar-quarantine'),
            ))
            .getSingleOrNull(),
        isA<PointsLedgerEntry>(),
      );
    },
  );

  test(
    'eligible answer grandfathers legacy definition zero unlock and outbox',
    () async {
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-legacy-zero-answer',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 10),
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );
      await database
          .into(database.achievementUnlocks)
          .insert(
            AchievementUnlocksCompanion.insert(
              id: 'legacy-zero-answer-unlock',
              ownerId: 'owner-1',
              achievementId: 'legacy_zero_answer',
              definitionVersion: 0,
              sourceEventId: 'legacy-zero-answer-source',
              unlockedAtUtcMs: 7,
            ),
          );

      final result = await repository.recordAnswer(
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: 'attempt-legacy-zero',
          ownerId: 'owner-1',
          sessionId: 'session-legacy-zero-answer',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 300,
          attemptNumber: 1,
          occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
          evidenceContext: _legacyEvidence(),
        ),
      );

      expect(result.inserted, isTrue);
      final legacy =
          await (database.select(database.achievementUnlocks)
                ..where((row) => row.id.equals('legacy-zero-answer-unlock')))
              .getSingle();
      expect(legacy.definitionVersion, 0);
      expect(legacy.sourceEventId, 'legacy-zero-answer-source');
      final outbox = await (database.select(
        database.outboxOperations,
      )..where((row) => row.entityId.equals(legacy.id))).getSingle();
      expect(outbox.operationId, 'achievementUnlock:${legacy.id}:1');
      expect(outbox.createdAtUtcMs, legacy.unlockedAtUtcMs);
      final newlyEmitted = await (database.select(
        database.achievementUnlocks,
      )..where((row) => row.id.isNotValue(legacy.id))).get();
      expect(newlyEmitted, isNotEmpty);
      expect(
        newlyEmitted.every((unlock) => unlock.definitionVersion > 0),
        isTrue,
      );
    },
  );

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
    'session completion grandfathers legacy definition zero unlock',
    () async {
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-legacy-zero-finish',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 10),
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );
      await database
          .into(database.achievementUnlocks)
          .insert(
            AchievementUnlocksCompanion.insert(
              id: 'legacy-zero-finish-unlock',
              ownerId: 'owner-1',
              achievementId: 'first_session',
              definitionVersion: 0,
              sourceEventId: 'legacy-zero-finish-source',
              unlockedAtUtcMs: 8,
            ),
          );

      final result = await repository.finishSession(
        ownerId: 'owner-1',
        sessionId: 'session-legacy-zero-finish',
        endedAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
      );

      expect(result.state, 'completed');
      final unlocks = await database.select(database.achievementUnlocks).get();
      expect(unlocks, hasLength(1));
      expect(unlocks.single.definitionVersion, 0);
      expect(unlocks.single.sourceEventId, 'legacy-zero-finish-source');
      final outbox = await database.select(database.outboxOperations).get();
      expect(
        outbox.where(
          (operation) => operation.entityType == 'achievementUnlock',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'live and rebuild achievement paths preserve one durable unlock identity',
    () async {
      final startedAt = DateTime.utc(2026, 7, 30, 10);
      final endedAt = DateTime.utc(2026, 7, 30, 10, 2);
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-achievement-policy',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: startedAt,
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );
      await repository.recordAnswer(
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: 'attempt-achievement-policy',
          ownerId: 'owner-1',
          sessionId: 'session-achievement-policy',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 300,
          attemptNumber: 1,
          occurredAtUtc: startedAt.add(const Duration(minutes: 1)),
          evidenceContext: _legacyEvidence(),
        ),
      );
      await database
          .into(database.achievementUnlocks)
          .insert(
            AchievementUnlocksCompanion.insert(
              id: 'historical-first-session',
              ownerId: 'owner-1',
              achievementId: 'first_session',
              definitionVersion: 7,
              sourceEventId: 'historical-session',
              unlockedAtUtcMs: 7,
            ),
          );

      await repository.finishSession(
        ownerId: 'owner-1',
        sessionId: 'session-achievement-policy',
        endedAtUtc: endedAt,
      );
      final live = (await database.select(database.achievementUnlocks).get())
          .map((row) => row.toJson())
          .toList(growable: false);
      await repository.projections.rebuildAchievements('owner-1');
      final rebuilt = (await database.select(database.achievementUnlocks).get())
          .map((row) => row.toJson())
          .toList(growable: false);

      expect(rebuilt, live);
      expect(
        rebuilt.where((row) => row['achievementId'] == 'first_session'),
        hasLength(1),
      );
      expect(
        rebuilt.singleWhere(
          (row) => row['achievementId'] == 'first_session',
        )['definitionVersion'],
        7,
      );
      expect(
        rebuilt.where((row) => row['achievementId'] == 'perfect_session'),
        hasLength(1),
      );
    },
  );

  test(
    'session-scoped abandon preserves a recoverable peer and exact terminal time',
    () async {
      final startedAt = DateTime.utc(2026, 7, 30, 10);
      for (final sessionId in <String>[
        'session-abandon-a',
        'session-active-b',
      ]) {
        await repository.startSession(
          LearningSessionDraft(
            id: sessionId,
            ownerId: 'owner-1',
            activityType: 'quiz',
            startedAtUtc: startedAt,
            appVersion: '1.0.0',
            buildId: 'test',
          ),
        );
      }
      final abandonedAt = DateTime.utc(2026, 7, 30, 10, 2);

      final first = await repository.abandonSession(
        ownerId: 'owner-1',
        sessionId: 'session-abandon-a',
        abandonedAtUtc: abandonedAt,
      );
      final replay = await repository.abandonSession(
        ownerId: 'owner-1',
        sessionId: 'session-abandon-a',
        abandonedAtUtc: abandonedAt,
      );

      expect(first.state, 'abandoned');
      expect(first.endedAtUtc, abandonedAt);
      expect(replay.state, first.state);
      expect(replay.endedAtUtc, first.endedAtUtc);
      final sessions = {
        for (final row
            in await database.select(database.learningSessions).get())
          row.id: row,
      };
      expect(sessions['session-abandon-a']!.state, 'abandoned');
      expect(
        sessions['session-abandon-a']!.endedAtUtcMs,
        abandonedAt.millisecondsSinceEpoch,
      );
      expect(sessions['session-active-b']!.state, 'active');
      expect(sessions['session-active-b']!.endedAtUtcMs, equals(null));
      await expectLater(
        repository.abandonSession(
          ownerId: 'owner-1',
          sessionId: 'session-abandon-a',
          abandonedAtUtc: abandonedAt.add(const Duration(seconds: 1)),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'session-scoped abandon rejects invalid identity and non-active state',
    () async {
      final startedAt = DateTime.utc(2026, 7, 30, 10);
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-abandon-validation',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: startedAt,
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );

      await expectLater(
        repository.abandonSession(
          ownerId: 'wrong-owner',
          sessionId: 'session-abandon-validation',
          abandonedAtUtc: startedAt.add(const Duration(minutes: 1)),
        ),
        throwsStateError,
      );
      expect(
        () => repository.abandonSession(
          ownerId: 'owner-1',
          sessionId: 'session-abandon-validation',
          abandonedAtUtc: DateTime(2026, 7, 30, 10, 1),
        ),
        throwsArgumentError,
      );
      await repository.finishSession(
        ownerId: 'owner-1',
        sessionId: 'session-abandon-validation',
        endedAtUtc: startedAt.add(const Duration(minutes: 2)),
      );
      await expectLater(
        repository.abandonSession(
          ownerId: 'owner-1',
          sessionId: 'session-abandon-validation',
          abandonedAtUtc: startedAt.add(const Duration(minutes: 3)),
        ),
        throwsStateError,
      );
    },
  );

  test(
    'out-of-order attempts rebuild SRS without rewriting unlock evidence',
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
      expect(firstAnswer.sourceEventId, 'attempt-later');
      expect(firstAnswer.unlockedAtUtcMs, later.millisecondsSinceEpoch);
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
    const result = AnswerRecordResult(
      inserted: true,
      isCorrect: true,
      srs: null,
    );

    expect(result.inserted, isTrue);
    expect(result.isCorrect, isTrue);
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
