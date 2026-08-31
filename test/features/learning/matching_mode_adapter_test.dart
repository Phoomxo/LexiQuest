import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/contrastive_feedback_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/matching_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/learning/domain/answer_feedback.dart';
import 'package:vocab_learning_app/features/learning/domain/contrastive_explanation.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/domain/hint_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_event_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lexical_prompt_artifact_identity.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart'
    as vocabulary_domain;
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  const adapter = MatchingModeAdapter();

  test('pins a deterministic ambiguity-safe pair set for restart', () {
    final session = _session(<QuizWord>[
      _word('one', 'Station', 'train stop'),
      _word('one-copy', '  STATION ', 'railway platform'),
      _word('shared-a', 'airport', 'shared meaning'),
      _word('shared-b', 'market', ' SHARED   MEANING '),
      _word('hotel', 'hotel', 'place to stay'),
      _word('museum', 'museum', 'place with exhibits'),
      _word('bank', 'bank', 'financial institution'),
      _word('park', 'park', 'public green space'),
    ]);

    final first = adapter.pinPairs(session);
    final restarted = const MatchingModeAdapter().pinPairs(session);

    expect(first.pairs.map((pair) => pair.word.id).toSet(), <String>{
      'word:hotel',
      'word:museum',
      'word:bank',
      'word:park',
    });
    expect(
      first.wordOrder.map((pair) => pair.word.id),
      restarted.wordOrder.map((pair) => pair.word.id),
    );
    expect(
      first.meaningOrder.map((pair) => pair.word.id),
      restarted.meaningOrder.map((pair) => pair.word.id),
    );
    expect(
      first.wordOrder.map((pair) => normalizeVocabularyText(pair.wordLabel)),
      hasLength(first.pairs.length),
    );
    expect(
      first.meaningOrder
          .map((pair) => normalizeVocabularyText(pair.meaningLabel))
          .toSet(),
      hasLength(first.pairs.length),
    );
  });

  test('excludes every occurrence of a conflicting duplicate word id', () {
    final pairSet = adapter.pinPairs(
      _session(<QuizWord>[
        _word('conflict', 'bank', 'financial institution'),
        _word('conflict', 'banking', 'the banking industry'),
        _word('safe', 'park', 'public green space'),
        _word('safe-two', 'museum', 'place with exhibits'),
      ]),
    );

    expect(pairSet.pairs.map((pair) => pair.word.id).toSet(), <String>{
      'word:safe',
      'word:safe-two',
    });
  });

  test('rejects a one-pair board with no discriminating choice', () {
    final pairSet = adapter.pinPairs(
      _session(<QuizWord>[_word('only', 'bank', 'financial institution')]),
    );

    expect(pairSet.isEmpty, isTrue);
  });

  test('base matching is recognition and every support state is guided', () {
    final unassisted = adapter.classifyResponse(
      hint: const HintUsageSnapshot.known(0),
      supportUsed: false,
    );
    final hinted = adapter.classifyResponse(
      hint: const HintUsageSnapshot.known(1),
      supportUsed: false,
    );
    final supported = adapter.classifyResponse(
      hint: const HintUsageSnapshot.unavailable(),
      supportUsed: true,
    );
    final unknown = adapter.classifyResponse(
      hint: const HintUsageSnapshot.unknown(),
      supportUsed: false,
    );

    expect(unassisted.evidenceClass, EvidenceClass.recognition);
    for (final assisted in <HintEvidenceClassification>[
      hinted,
      supported,
      unknown,
    ]) {
      expect(assisted.evidenceClass, EvidenceClass.guidedPractice);
      expect(assisted.hintLevel, greaterThan(0));
      expect(assisted.evidenceClass, isNot(EvidenceClass.independentRecall));
    }
  });

  test('typed boundary rejects forged recall and non-matching prompts', () {
    final response = LessonResponse(
      sourceEvidenceId: 'attempt:matching-boundary',
      occurredAtUtc: DateTime.utc(2026, 8, 25, 9),
      sessionId: 'session:matching-boundary',
      wordId: 'word:matching-boundary',
      promptMode: 'matchingPair',
      isCorrect: true,
      responseTimeMs: 100,
      attemptNumber: 1,
      feedbackContext: const AnswerFeedbackContext(
        canonicalCorrectAnswer: 'meaning',
      ),
    );
    EvidenceContext context(EvidenceClass evidenceClass, int hintLevel) =>
        EvidenceContext.legacyCompatibility(
          evidenceClass: evidenceClass,
          skillId: 'matching-recognition',
          hintLevel: hintLevel,
          contentRevision: 'built-in-v1',
          engagementAllowed: true,
        );
    final recognition = context(EvidenceClass.recognition, 0);
    final guided = context(EvidenceClass.guidedPractice, 1);
    final forgedRecall = context(EvidenceClass.independentRecall, 0);

    expect(
      adapter.classify(response, LessonSupport(evidenceContext: recognition)),
      same(recognition),
    );
    expect(
      adapter.classify(response, LessonSupport(evidenceContext: guided)),
      same(guided),
    );
    expect(
      () => adapter.classify(
        response,
        LessonSupport(evidenceContext: forgedRecall),
      ),
      throwsStateError,
    );
    expect(
      () => adapter.classify(
        LessonResponse(
          sourceEvidenceId: response.sourceEvidenceId,
          occurredAtUtc: response.occurredAtUtc,
          sessionId: response.sessionId,
          wordId: response.wordId,
          promptMode: 'meaningChoice',
          isCorrect: response.isCorrect,
          responseTimeMs: response.responseTimeMs,
          attemptNumber: response.attemptNumber,
          feedbackContext: response.feedbackContext,
        ),
        LessonSupport(evidenceContext: recognition),
      ),
      throwsStateError,
    );
  });

  group('durable matching evidence', () {
    late AppDatabase database;
    late DriftLocalOwnerRepository owners;
    late LearningUseCases learning;
    var generatedId = 0;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'matching-owner',
        nowUtc: () => DateTime.utc(2026, 8, 25, 9),
      );
      final owner = await owners.getOrCreateActiveOwner();
      await database.customStatement(
        'INSERT INTO vocabulary_categories '
        '(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) '
        "VALUES ('category:travel', ?, 'Travel', 'travel', 1, 1)",
        <Object?>[owner.id],
      );
      for (final entry in const <(String, String, String)>[
        ('word:airport', 'airport', 'place for flights'),
        ('word:station', 'station', 'place for trains'),
        ('word:market', 'market', 'place to buy goods'),
      ]) {
        final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
          categoryId: 'category:travel',
          spelling: entry.$2,
          normalizedSpelling: entry.$2,
          meaning: entry.$3,
          normalizedMeaning: entry.$3,
          partOfSpeech: 'noun',
          cefrLevel: null,
          source: 'manual',
          isGlobal: false,
        );
        await database.customStatement(
          'INSERT INTO vocabulary_words '
          '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
          'normalized_meaning, part_of_speech, content_checksum_sha256, '
          'created_at_utc_ms, updated_at_utc_ms) '
          "VALUES (?, ?, 'category:travel', ?, ?, ?, ?, 'noun', ?, 1, 1)",
          <Object?>[
            entry.$1,
            owner.id,
            entry.$2,
            entry.$2,
            entry.$3,
            entry.$3,
            checksum,
          ],
        );
      }
      learning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'matching-${++generatedId}',
        nowUtc: () => DateTime.utc(2026, 8, 25, 10, 0, generatedId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
      );
    });

    tearDown(() => database.close());

    test(
      'missing canonical matching identity fails before durable mutation',
      () async {
        final session = await learning.startQuiz(categoryId: 'category:travel');
        final missingIdentitySession = QuizSession(
          id: session.id,
          ownerId: session.ownerId,
          startedAtUtc: session.startedAtUtc,
          questions: <QuizQuestion>[
            for (final question in session.questions)
              QuizQuestion(
                word: QuizWord(
                  id: question.word.id,
                  categoryId: question.word.categoryId,
                  spelling: question.word.spelling,
                  meaning: question.word.meaning,
                  partOfSpeech: question.word.partOfSpeech,
                  contentRevision: question.word.contentRevision,
                  contentChecksumSha256: null,
                ),
                options: question.options,
              ),
          ],
        );
        final review = adapter.createReview(
          session: missingIdentitySession,
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);
        final pair = review.pairSet.pairs.first;

        await review.selectWord(pair.word.id, responseTimeMs: 100);
        expect(
          () => review.selectMeaning(pair.word.id, responseTimeMs: 100),
          throwsStateError,
        );

        expect(review.nextAttemptNumber, 1);
        expect(await database.select(database.answerAttempts).get(), isEmpty);
        expect(
          await (database.select(database.eventsV2)..where(
                (row) => row.eventType.isNotValue('StreakPolicyCutover'),
              ))
              .get(),
          isEmpty,
        );
      },
    );

    test(
      'legacy null rows complete a real pair and restart from canonical identity',
      () async {
        await database
            .update(database.vocabularyWords)
            .write(
              const VocabularyWordsCompanion(
                contentChecksumSha256: Value(null),
              ),
            );
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        final prepared = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final first = adapter.createReview(
          session: prepared.session,
          learning: learning,
          evidence: evidence,
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final pair = first.pairSet.pairs.first;
        expect(pair.word.contentChecksumSha256, isNotNull);
        await first.selectWord(pair.word.id, responseTimeMs: 100);
        await first.selectMeaning(pair.word.id, responseTimeMs: 200);
        first.dispose();

        final restarted = await adapter.prepareSession(
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          categoryId: 'category:travel',
        );
        final review = adapter.createReview(
          session: restarted.session,
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          recovery: restarted,
        );
        addTearDown(review.dispose);

        expect(restarted.session.id, prepared.session.id);
        expect(review.matchedWordIds, contains(pair.word.id));
        expect(
          await database.select(database.learningSessions).get(),
          hasLength(1),
        );
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );
        expect(
          (await database.select(database.vocabularyWords).get()).every(
            (word) => word.contentChecksumSha256 == null,
          ),
          isTrue,
          reason: 'legacy compatibility is a read identity, not a write',
        );
      },
    );

    test(
      'wrong stored checksum rejects before matching session or checkpoint',
      () async {
        await (database.update(
          database.vocabularyWords,
        )..where((word) => word.id.equals('word:airport'))).write(
          VocabularyWordsCompanion(contentChecksumSha256: Value('f' * 64)),
        );

        await expectLater(
          adapter.prepareSession(
            learning: learning,
            evidence: CurrentActivityEvidenceAdapter(learning: learning),
            categoryId: 'category:travel',
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
        expect(
          await (database.select(database.eventsV2)..where(
                (row) => row.eventType.isNotValue('StreakPolicyCutover'),
              ))
              .get(),
          isEmpty,
        );
      },
    );

    test(
      'duplicate taps are idempotent and default policy isolates projections',
      () async {
        final session = await learning.startQuiz(categoryId: 'category:travel');
        final review = adapter.createReview(
          session: session,
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);
        final pair = review.pairSet.pairs.first;
        final before = await _projectionSnapshot(database);

        await review.selectWord(pair.word.id, responseTimeMs: 500);
        await review.selectWord(pair.word.id, responseTimeMs: 501);
        final first = review.selectMeaning(pair.word.id, responseTimeMs: 502);
        final duplicate = review.selectMeaning(
          pair.word.id,
          responseTimeMs: 9999,
        );
        await Future.wait(<Future<AnswerRecordResult?>>[first, duplicate]);

        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts, hasLength(1));
        expect(attempts.single.promptMode, 'matchingPair');
        expect(attempts.single.responseTimeMs, 502);
        final context = _context(attempts.single.evidenceContextJson);
        expect(context.evidenceClass, EvidenceClass.recognition);
        expect(context.skillId, 'matching-recognition');
        expect(context.policyVersion, EvidenceContext.currentPolicyVersion);
        expect(
          context.classificationSource,
          EvidenceClassificationSource.declared,
        );
        expect(context.rolloutMode, EvidencePolicyRolloutMode.legacy);
        expect(context.engagementAllowed, isFalse);
        expect(review.matchedWordIds, <String>{pair.word.id});
        expect(await _projectionSnapshot(database), before);
      },
    );

    test(
      'support produces guided evidence and no mastery or reward state',
      () async {
        final session = await learning.startQuiz(categoryId: 'category:travel');
        final review = adapter.createReview(
          session: session,
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          hintUsage: () => const HintUsageSnapshot.unavailable(),
        );
        addTearDown(review.dispose);
        final pair = review.pairSet.pairs.first;
        review.markSupportUsed();
        await review.selectWord(pair.word.id, responseTimeMs: 100);
        await review.selectMeaning(pair.word.id, responseTimeMs: 200);

        final attempt =
            (await database.select(database.answerAttempts).get()).single;
        final context = _context(attempt.evidenceContextJson);
        expect(context.evidenceClass, EvidenceClass.guidedPractice);
        expect(context.hintLevel, 1);
        expect(await database.select(database.srsStates).get(), isEmpty);
        expect(
          await database.select(database.pointsLedgerEntries).get(),
          isEmpty,
        );
        expect(
          await database.select(database.rewardTransactions).get(),
          isEmpty,
        );
      },
    );

    test(
      'adapter scores mismatched pairs without trusting the screen',
      () async {
        final session = await learning.startQuiz(categoryId: 'category:travel');
        final review = adapter.createReview(
          session: session,
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);
        final word = review.pairSet.pairs.first;
        final wrongMeaning = review.pairSet.pairs.firstWhere(
          (pair) => pair.word.id != word.word.id,
        );

        await review.selectWord(word.word.id, responseTimeMs: 100);
        await review.selectMeaning(wrongMeaning.word.id, responseTimeMs: 200);

        final attempt =
            (await database.select(database.answerAttempts).get()).single;
        expect(attempt.isCorrect, isFalse);
        expect(review.matchedWordIds, isEmpty);
        expect(review.feedback!.isCorrect, isFalse);
        expect(review.feedback!.canonicalCorrectAnswer, word.meaningLabel);
      },
    );

    test(
      'lost acknowledgement retries the exact frozen match occurrence',
      () async {
        final repository = _LostAckLearningRepository(
          DriftLearningRepository(database),
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'retry-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 11, 0, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final session = await retryLearning.startQuiz(
          categoryId: 'category:travel',
        );
        final review = adapter.createReview(
          session: session,
          learning: retryLearning,
          evidence: CurrentActivityEvidenceAdapter(learning: retryLearning),
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);
        final pair = review.pairSet.pairs.first;
        await review.selectWord(pair.word.id, responseTimeMs: 111);

        await expectLater(
          review.selectMeaning(pair.word.id, responseTimeMs: 1234),
          throwsStateError,
        );
        expect(review.phase, MatchingReviewPhase.evidenceRetryRequired);
        await review.retryEvidence();

        expect(repository.commands, hasLength(2));
        final original = repository.commands.first;
        final retry = repository.commands.last;
        expect(retry.id, original.id);
        expect(retry.occurredAtUtc, original.occurredAtUtc);
        expect(retry.wordId, original.wordId);
        expect(retry.promptMode, original.promptMode);
        expect(retry.isCorrect, original.isCorrect);
        expect(retry.responseTimeMs, original.responseTimeMs);
        expect(retry.attemptNumber, original.attemptNumber);
        expect(
          retry.evidenceContext.toJson(),
          original.evidenceContext.toJson(),
        );
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );
      },
    );

    test(
      'production restart reconstructs the pinned board and canonical attempts',
      () async {
        await _setCanonicalCoreIdentities(database, revision: 7);
        final prepared = await adapter.prepareSession(
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          categoryId: 'category:travel',
        );
        final first = adapter.createReview(
          session: prepared.session,
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final originalIds = first.pairSet.pairs
            .map((pair) => pair.word.id)
            .toList(growable: false);
        final pair = first.pairSet.pairs.first;
        await first.selectWord(pair.word.id, responseTimeMs: 100);
        await first.selectMeaning(pair.word.id, responseTimeMs: 200);
        first.dispose();

        await (database.update(
          database.vocabularyWords,
        )..where((row) => row.id.equals(pair.word.id))).write(
          VocabularyWordsCompanion(
            meaning: const Value('changed after the session was pinned'),
            normalizedMeaning: const Value(
              'changed after the session was pinned',
            ),
            contentRevision: const Value(8),
            contentChecksumSha256: Value('b' * 64),
            isDeleted: const Value(true),
          ),
        );

        final restarted = await adapter.prepareSession(
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          categoryId: 'category:travel',
        );
        final review = adapter.createReview(
          session: restarted.session,
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          recovery: restarted,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);

        expect(restarted.session.id, prepared.session.id);
        expect(
          review.pairSet.pairs.map((candidate) => candidate.word.id),
          originalIds,
        );
        expect(review.matchedWordIds, <String>{pair.word.id});
        expect(review.nextAttemptNumber, 2);
        final attempt =
            (await database.select(database.answerAttempts).get()).single;
        final context = _context(attempt.evidenceContextJson);
        expect(
          context.contentRevision,
          _matchingRevision(7, pair.word.contentChecksumSha256!),
        );
      },
    );

    test(
      'validated pinned evidence can answer after live word deletion',
      () async {
        await _setCanonicalCoreIdentities(database, revision: 9);
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        final prepared = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final pair = adapter.pinPairs(prepared.session).pairs.first;
        await (database.update(database.vocabularyWords)
              ..where((row) => row.id.equals(pair.word.id)))
            .write(const VocabularyWordsCompanion(isDeleted: Value(true)));
        final recovered = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final review = adapter.createReview(
          session: recovered.session,
          learning: learning,
          evidence: evidence,
          recovery: recovered,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);

        await review.selectWord(pair.word.id, responseTimeMs: 100);
        await review.selectMeaning(pair.word.id, responseTimeMs: 200);

        final attempt =
            (await database.select(database.answerAttempts).get()).single;
        expect(attempt.wordId, pair.word.id);
        expect(
          _context(attempt.evidenceContextJson).contentRevision,
          _matchingRevision(9, pair.word.contentChecksumSha256!),
        );
      },
    );

    test(
      'deleted word requires the exact latest persisted pending occurrence',
      () async {
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
          recordFailure: _RecordFailure.beforeWrite,
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'deleted-auth-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 10, 30, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final evidence = CurrentActivityEvidenceAdapter(
          learning: retryLearning,
        );
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final review = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence,
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);
        final pair = review.pairSet.pairs.first;
        await (database.update(database.vocabularyWords)
              ..where((row) => row.id.equals(pair.word.id)))
            .write(const VocabularyWordsCompanion(isDeleted: Value(true)));
        await review.selectWord(pair.word.id, responseTimeMs: 100);
        await expectLater(
          review.selectMeaning(pair.word.id, responseTimeMs: 200),
          throwsStateError,
        );
        final command = repository.commands.single;
        final rows =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventType.equals('LearningActivityCheckpoint'),
                ))
                .get();
        rows.sort((left, right) {
          final leftRevision =
              (jsonDecode(left.payloadJson) as Map<String, dynamic>)['revision']
                  as int;
          final rightRevision =
              (jsonDecode(right.payloadJson)
                      as Map<String, dynamic>)['revision']
                  as int;
          return leftRevision.compareTo(rightRevision);
        });
        final latest = rows.last;
        final originalPayload = latest.payloadJson;

        Future<void> expectRejected(
          void Function(Map<String, dynamic> state) mutate,
        ) async {
          final payload = jsonDecode(originalPayload) as Map<String, dynamic>;
          final state = payload['state'] as Map<String, dynamic>;
          mutate(state);
          await (database.update(
            database.eventsV2,
          )..where((row) => row.eventId.equals(latest.eventId))).write(
            EventsV2Companion(payloadJson: Value(jsonEncode(payload))),
          );
          await expectLater(
            repository.delegate.recordAnswer(command),
            throwsStateError,
          );
        }

        await expectRejected((state) => state['pendingEvidence'] = null);
        await expectRejected((state) {
          (state['pendingEvidence']
                  as Map<String, dynamic>)['sourceEvidenceId'] =
              'attempt:forged';
        });
        await expectRejected((state) {
          (state['pendingEvidence']
              as Map<String, dynamic>)['occurredAtUtc'] = command.occurredAtUtc
              .add(const Duration(seconds: 1))
              .toIso8601String();
        });
        await expectRejected((state) {
          (state['pendingEvidence'] as Map<String, dynamic>)['attemptNumber'] =
              command.attemptNumber + 1;
        });
        await expectRejected((state) {
          final pending = state['pendingEvidence'] as Map<String, dynamic>;
          pending['selectedMeaningWordId'] = review.pairSet.pairs
              .firstWhere((candidate) => candidate.word.id != pair.word.id)
              .word
              .id;
        });
        await expectRejected((state) {
          (state['pendingEvidence'] as Map<String, dynamic>)['isCorrect'] =
              false;
        });
        await expectRejected((state) {
          final pending = state['pendingEvidence'] as Map<String, dynamic>;
          final context = pending['evidenceContext'] as Map<String, dynamic>;
          context['contentRevision'] = 'forged-revision';
        });

        await (database.update(database.eventsV2)
              ..where((row) => row.eventId.equals(latest.eventId)))
            .write(EventsV2Companion(payloadJson: Value(originalPayload)));
        await repository.delegate.recordAnswer(command);
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );
      },
    );

    test('deleted word rejects a future matching checkpoint schema', () async {
      final repository = _RestartRecoveryRepository(
        DriftLearningRepository(database),
        recordFailure: _RecordFailure.beforeWrite,
      );
      final retryLearning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'deleted-future-${++generatedId}',
        nowUtc: () => DateTime.utc(2026, 8, 25, 10, 31, generatedId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
      );
      final evidence = CurrentActivityEvidenceAdapter(learning: retryLearning);
      final prepared = await adapter.prepareSession(
        learning: retryLearning,
        evidence: evidence,
        categoryId: 'category:travel',
      );
      final review = adapter.createReview(
        session: prepared.session,
        learning: retryLearning,
        evidence: evidence,
        recovery: prepared,
        hintUsage: () => const HintUsageSnapshot.known(0),
      );
      addTearDown(review.dispose);
      final pair = review.pairSet.pairs.first;
      await (database.update(database.vocabularyWords)
            ..where((row) => row.id.equals(pair.word.id)))
          .write(const VocabularyWordsCompanion(isDeleted: Value(true)));
      await review.selectWord(pair.word.id, responseTimeMs: 100);
      await expectLater(
        review.selectMeaning(pair.word.id, responseTimeMs: 200),
        throwsStateError,
      );
      final command = repository.commands.single;
      final rows =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventType.equals('LearningActivityCheckpoint'),
              ))
              .get();
      rows.sort((left, right) {
        final leftRevision =
            (jsonDecode(left.payloadJson) as Map<String, dynamic>)['revision']
                as int;
        final rightRevision =
            (jsonDecode(right.payloadJson) as Map<String, dynamic>)['revision']
                as int;
        return leftRevision.compareTo(rightRevision);
      });
      final latest = rows.last;
      final payload = jsonDecode(latest.payloadJson) as Map<String, dynamic>;
      final state = payload['state'] as Map<String, dynamic>;
      expect(state['schemaVersion'], 5);
      state['schemaVersion'] = 6;
      await (database.update(database.eventsV2)
            ..where((row) => row.eventId.equals(latest.eventId)))
          .write(EventsV2Companion(payloadJson: Value(jsonEncode(payload))));

      await expectLater(
        repository.delegate.recordAnswer(command),
        throwsStateError,
      );
      expect(await database.select(database.answerAttempts).get(), isEmpty);
    });

    test('guest owner upgrade resumes and closes the active board', () async {
      final guest = await owners.getOrCreateActiveOwner();
      var upgradeId = 0;
      final evidence = CurrentActivityEvidenceAdapter(learning: learning);
      final prepared = await adapter.prepareSession(
        learning: learning,
        evidence: evidence,
        categoryId: 'category:travel',
      );
      await database.customInsert(
        'INSERT INTO local_owners '
        '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
        "VALUES ('account-owner', 'firebase-account', 'firebaseBound', 2, 0)",
      );
      await DriftOwnerUpgradeRepository(
        database,
        nowUtc: () => DateTime.utc(2026, 8, 25, 11),
        generateConflictId: () => 'matching-upgrade-conflict-${++upgradeId}',
        generateOwnerId: () => 'matching-upgrade-new-owner',
        generateOwnerOperationToken: () => 'matching-upgrade-operation',
        deleteOwnerSecrets: (_) async {},
      ).upgrade(activeOwnerId: guest.id, firebaseUid: 'firebase-account');

      final recovered = await adapter.prepareSession(
        learning: learning,
        evidence: evidence,
        categoryId: 'category:travel',
      );
      expect(recovered.session.id, prepared.session.id);
      final review = adapter.createReview(
        session: recovered.session,
        learning: learning,
        evidence: evidence,
        recovery: recovered,
      );
      addTearDown(review.dispose);
      final summary = await review.timeout();

      expect(summary.ownerId, 'account-owner');
      expect(summary.state, 'completed');
      final checkpoints =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventType.equals('LearningActivityCheckpoint'),
              ))
              .get();
      expect(checkpoints, hasLength(3));
      expect(
        checkpoints.every((row) => row.ownerId == 'account-owner'),
        isTrue,
      );
      expect(checkpoints.first.actorIdentity, guest.id);
      expect(checkpoints.last.actorIdentity, 'account-owner');
    });

    Future<void> expectWordCollisionFencesMatching({
      required bool recordPriorAttempt,
    }) async {
      final guest = await owners.getOrCreateActiveOwner();
      final repository = _RestartRecoveryRepository(
        DriftLearningRepository(database),
        recordFailure: recordPriorAttempt
            ? _RecordFailure.none
            : _RecordFailure.beforeWrite,
      );
      final scenarioLearning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'collision-matching-${++generatedId}',
        nowUtc: () => DateTime.utc(2026, 8, 25, 10, 45, generatedId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
      );
      final evidence = CurrentActivityEvidenceAdapter(
        learning: scenarioLearning,
      );
      final prepared = await adapter.prepareSession(
        learning: scenarioLearning,
        evidence: evidence,
        categoryId: 'category:travel',
      );
      final review = adapter.createReview(
        session: prepared.session,
        learning: scenarioLearning,
        evidence: evidence,
        recovery: prepared,
        hintUsage: () => const HintUsageSnapshot.known(0),
      );
      final collidedPair = review.pairSet.pairs.first;
      await review.selectWord(collidedPair.word.id, responseTimeMs: 100);
      if (recordPriorAttempt) {
        await review.selectMeaning(collidedPair.word.id, responseTimeMs: 200);
      } else {
        await expectLater(
          review.selectMeaning(collidedPair.word.id, responseTimeMs: 200),
          throwsStateError,
        );
      }
      review.dispose();
      String? originalSourcePayload;
      if (recordPriorAttempt) {
        final attempt =
            (await database.select(database.answerAttempts).get()).single;
        originalSourcePayload =
            (await (database.select(database.eventsV2)..where(
                      (row) => row.eventId.equals(
                        LearningEvidenceContract.learningEventId(attempt.id),
                      ),
                    ))
                    .getSingle())
                .payloadJson;
      }

      await database.customInsert(
        'INSERT INTO local_owners '
        '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
        "VALUES ('collision-account', 'firebase-collision', "
        "'firebaseBound', 2, 0)",
      );
      await database.customInsert(
        'INSERT INTO vocabulary_categories '
        '(id, owner_id, name, normalized_name, created_at_utc_ms, '
        'updated_at_utc_ms) VALUES '
        "('category:account-travel', 'collision-account', 'Travel', "
        "'travel', 2, 2)",
      );
      await database.customStatement(
        'INSERT INTO vocabulary_words '
        '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
        'normalized_meaning, part_of_speech, created_at_utc_ms, '
        'updated_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 2, 2)',
        <Object?>[
          'word:account-collision',
          'collision-account',
          'category:account-travel',
          collidedPair.word.spelling,
          collidedPair.word.normalizedSpelling!,
          collidedPair.word.meaning,
          collidedPair.word.normalizedMeaning!,
          collidedPair.word.partOfSpeech,
        ],
      );
      var upgradeId = 0;
      await DriftOwnerUpgradeRepository(
        database,
        nowUtc: () => DateTime.utc(2026, 8, 25, 11, 15),
        generateConflictId: () => 'collision-conflict-${++upgradeId}',
        generateOwnerId: () => 'collision-new-owner',
        generateOwnerOperationToken: () => 'collision-operation',
        deleteOwnerSecrets: (_) async {},
      ).upgrade(activeOwnerId: guest.id, firebaseUid: 'firebase-collision');

      final oldSession = await (database.select(
        database.learningSessions,
      )..where((row) => row.id.equals(prepared.session.id))).getSingle();
      expect(oldSession.ownerId, 'collision-account');
      expect(oldSession.state, 'abandoned');
      expect(
        oldSession.endedAtUtcMs,
        DateTime.utc(2026, 8, 25, 11, 15).millisecondsSinceEpoch,
      );
      final historicalAttempts = await database
          .select(database.answerAttempts)
          .get();
      if (recordPriorAttempt) {
        expect(historicalAttempts, hasLength(1));
        expect(historicalAttempts.single.wordId, collidedPair.word.id);
        final sourceEvent =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(
                    LearningEvidenceContract.learningEventId(
                      historicalAttempts.single.id,
                    ),
                  ),
                ))
                .getSingle();
        expect(
          (jsonDecode(sourceEvent.payloadJson)
              as Map<String, dynamic>)['wordId'],
          collidedPair.word.id,
        );
        expect(sourceEvent.payloadJson, originalSourcePayload);
        expect(sourceEvent.actorIdentity, guest.id);
        expect(sourceEvent.ownerId, 'collision-account');
        final historicalWord = await (database.select(
          database.vocabularyWords,
        )..where((row) => row.id.equals(collidedPair.word.id))).getSingle();
        expect(historicalWord.ownerId, 'collision-account');
        expect(historicalWord.isDeleted, isTrue);
        final tombstoneOutbox = await database
            .customSelect(
              'SELECT operation_kind, state FROM outbox_operations '
              'WHERE owner_id = ? AND entity_type = ? AND entity_id = ?',
              variables: <Variable<Object>>[
                const Variable<String>('collision-account'),
                const Variable<String>('word'),
                Variable<String>(collidedPair.word.id),
              ],
            )
            .getSingle();
        expect(tombstoneOutbox.read<String>('operation_kind'), 'delete');
        expect(tombstoneOutbox.read<String>('state'), 'pending');
      } else {
        expect(historicalAttempts, isEmpty);
      }
      final replacement = await adapter.prepareSession(
        learning: scenarioLearning,
        evidence: evidence,
        categoryId: 'category:account-travel',
      );
      expect(replacement.session.id, isNot(prepared.session.id));
      expect(
        replacement.session.questions.map((question) => question.word.id),
        isNot(contains(collidedPair.word.id)),
      );
    }

    test(
      'owner upgrade fences a first-response Matching word collision',
      () => expectWordCollisionFencesMatching(recordPriorAttempt: false),
    );

    test(
      'owner upgrade fences a Matching word collision after a prior attempt',
      () => expectWordCollisionFencesMatching(recordPriorAttempt: true),
    );

    test(
      'collision alias folds recall mastery without projecting Matching',
      () async {
        final guest = await owners.getOrCreateActiveOwner();
        final guestEvidence = CurrentActivityEvidenceAdapter(
          learning: learning,
        );
        final recallSession = await learning.startQuiz(
          categoryId: 'category:travel',
        );
        await guestEvidence
            .capture(
              input: CurrentActivityInput.typedRecall,
              sessionId: recallSession.id,
              wordId: 'word:airport',
              isCorrect: true,
              responseTimeMs: 100,
              attemptNumber: 1,
            )
            .record();

        final matchingPrepared = await adapter.prepareSession(
          learning: learning,
          evidence: guestEvidence,
          categoryId: 'category:travel',
        );
        final matching = adapter.createReview(
          session: matchingPrepared.session,
          learning: learning,
          evidence: guestEvidence,
          recovery: matchingPrepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final matchingPair = matching.pairSet.pairs.singleWhere(
          (pair) => pair.word.id == 'word:airport',
        );
        await matching.selectWord(matchingPair.word.id, responseTimeMs: 110);
        await matching.selectMeaning(matchingPair.word.id, responseTimeMs: 120);
        matching.dispose();

        await database.customInsert(
          'INSERT INTO local_owners '
          '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
          "VALUES ('alias-account', 'firebase-alias', 'firebaseBound', 2, 0)",
        );
        await database.customInsert(
          'INSERT INTO vocabulary_categories '
          '(id, owner_id, name, normalized_name, created_at_utc_ms, '
          'updated_at_utc_ms) VALUES '
          "('category:alias-travel', 'alias-account', 'Travel', 'travel', 2, 2)",
        );
        await database.customInsert(
          'INSERT INTO vocabulary_words '
          '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
          'normalized_meaning, part_of_speech, created_at_utc_ms, '
          'updated_at_utc_ms) VALUES '
          "('word:alias-airport', 'alias-account', 'category:alias-travel', "
          "'airport', 'airport', 'place for flights', 'place for flights', "
          "'noun', 2, 2)",
        );
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals(guest.id)))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals('alias-account')))
            .write(const LocalOwnersCompanion(isActive: Value(true)));
        var accountId = 0;
        final accountLearning = LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(database),
          generateId: () => 'alias-account-${++accountId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 10, 30, accountId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final accountSession = await accountLearning.startQuiz(
          categoryId: 'category:alias-travel',
        );
        await CurrentActivityEvidenceAdapter(learning: accountLearning)
            .capture(
              input: CurrentActivityInput.typedRecall,
              sessionId: accountSession.id,
              wordId: 'word:alias-airport',
              isCorrect: true,
              responseTimeMs: 130,
              attemptNumber: 1,
            )
            .record();
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals('alias-account')))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals(guest.id)))
            .write(const LocalOwnersCompanion(isActive: Value(true)));

        final eventPayloadsBefore = <String, String>{
          for (final row in await (database.select(
            database.eventsV2,
          )..where((row) => row.eventType.equals('QuizAttempted'))).get())
            row.eventId: row.payloadJson,
        };
        var conflictId = 0;
        await DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => DateTime.utc(2026, 8, 25, 11),
          generateConflictId: () => 'alias-conflict-${++conflictId}',
          generateOwnerId: () => 'alias-new-owner',
          generateOwnerOperationToken: () => 'alias-operation',
          deleteOwnerSecrets: (_) async {},
        ).upgrade(activeOwnerId: guest.id, firebaseUid: 'firebase-alias');

        final srsRows = await (database.select(
          database.srsStates,
        )..where((row) => row.ownerId.equals('alias-account'))).get();
        expect(srsRows, hasLength(1));
        expect(srsRows.single.wordId, 'word:alias-airport');
        expect(srsRows.single.repetitions, 2);
        expect(srsRows.any((row) => row.wordId == 'word:airport'), isFalse);
        final historicalWord = await (database.select(
          database.vocabularyWords,
        )..where((row) => row.id.equals('word:airport'))).getSingle();
        expect(historicalWord.ownerId, 'alias-account');
        expect(historicalWord.isDeleted, isTrue);
        final matchingAttempt = (await (database.select(
          database.answerAttempts,
        )..where((row) => row.promptMode.equals('matchingPair'))).get()).single;
        expect(
          _context(matchingAttempt.evidenceContextJson).evidenceClass,
          EvidenceClass.recognition,
        );
        final eventPayloadsAfter = <String, String>{
          for (final row in await (database.select(
            database.eventsV2,
          )..where((row) => row.eventType.equals('QuizAttempted'))).get())
            row.eventId: row.payloadJson,
        };
        expect(eventPayloadsAfter, eventPayloadsBefore);

        final rebuilder = DriftLearningProjectionRebuilder(database);
        await rebuilder.rebuildWord(
          ownerId: 'alias-account',
          wordId: 'word:airport',
        );
        await rebuilder.rebuildWord(
          ownerId: 'alias-account',
          wordId: 'word:alias-airport',
        );
        final rebuilt = await (database.select(
          database.srsStates,
        )..where((row) => row.ownerId.equals('alias-account'))).get();
        expect(rebuilt, hasLength(1));
        expect(rebuilt.single.wordId, 'word:alias-airport');
        expect(rebuilt.single.repetitions, 2);

        await database.customInsert(
          'INSERT INTO local_owners '
          '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
          "VALUES ('alias-final-account', 'firebase-alias-final', "
          "'firebaseBound', 3, 0)",
        );
        await database.customInsert(
          'INSERT INTO vocabulary_categories '
          '(id, owner_id, name, normalized_name, created_at_utc_ms, '
          'updated_at_utc_ms) VALUES '
          "('category:alias-final', 'alias-final-account', 'Travel', "
          "'travel', 3, 3)",
        );
        await database.customInsert(
          'INSERT INTO vocabulary_words '
          '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
          'normalized_meaning, part_of_speech, created_at_utc_ms, '
          'updated_at_utc_ms) VALUES '
          "('word:alias-final', 'alias-final-account', "
          "'category:alias-final', 'airport', 'airport', "
          "'place for flights', 'place for flights', 'noun', 3, 3)",
        );
        await DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => DateTime.utc(2026, 8, 25, 12),
          generateConflictId: () => 'alias-chain-${++conflictId}',
          generateOwnerId: () => 'alias-chain-owner',
          generateOwnerOperationToken: () => 'alias-chain-operation',
          deleteOwnerSecrets: (_) async {},
        ).upgrade(
          activeOwnerId: 'alias-account',
          firebaseUid: 'firebase-alias-final',
        );
        final chained = await (database.select(
          database.srsStates,
        )..where((row) => row.ownerId.equals('alias-final-account'))).get();
        expect(chained, hasLength(1));
        expect(chained.single.wordId, 'word:alias-final');
        expect(chained.single.repetitions, 2);
        expect(
          chained.any(
            (row) =>
                row.wordId == 'word:airport' ||
                row.wordId == 'word:alias-airport',
          ),
          isFalse,
        );
        final chainedPayloads = <String, String>{
          for (final row in await (database.select(
            database.eventsV2,
          )..where((row) => row.eventType.equals('QuizAttempted'))).get())
            row.eventId: row.payloadJson,
        };
        expect(chainedPayloads, eventPayloadsBefore);
      },
    );

    test(
      'incoming alias evidence survives an intermediate collision without a direct attempt',
      () async {
        final guest = await owners.getOrCreateActiveOwner();
        final guestSession = await learning.startQuiz(
          categoryId: 'category:travel',
        );
        await CurrentActivityEvidenceAdapter(learning: learning)
            .capture(
              input: CurrentActivityInput.typedRecall,
              sessionId: guestSession.id,
              wordId: 'word:airport',
              isCorrect: true,
              responseTimeMs: 100,
              attemptNumber: 1,
            )
            .record();
        final historicalAttempt =
            (await database.select(database.answerAttempts).get()).single;
        final historicalEvent =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(
                    LearningEvidenceContract.learningEventId(
                      historicalAttempt.id,
                    ),
                  ),
                ))
                .getSingle();

        await database.customInsert(
          'INSERT INTO local_owners '
          '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
          "VALUES ('alias-middle-account', 'firebase-alias-middle', "
          "'firebaseBound', 2, 0)",
        );
        await database.customInsert(
          'INSERT INTO vocabulary_categories '
          '(id, owner_id, name, normalized_name, created_at_utc_ms, '
          'updated_at_utc_ms) VALUES '
          "('category:alias-middle', 'alias-middle-account', 'Travel', "
          "'travel', 2, 2)",
        );
        await database.customInsert(
          'INSERT INTO vocabulary_words '
          '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
          'normalized_meaning, part_of_speech, created_at_utc_ms, '
          'updated_at_utc_ms) VALUES '
          "('word:alias-middle', 'alias-middle-account', "
          "'category:alias-middle', 'airport', 'airport', "
          "'place for flights', 'place for flights', 'noun', 2, 2)",
        );
        var conflictId = 0;
        await DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => DateTime.utc(2026, 8, 25, 10),
          generateConflictId: () => 'alias-middle-${++conflictId}',
          generateOwnerId: () => 'alias-middle-new-owner',
          generateOwnerOperationToken: () => 'alias-middle-operation',
          deleteOwnerSecrets: (_) async {},
        ).upgrade(
          activeOwnerId: guest.id,
          firebaseUid: 'firebase-alias-middle',
        );
        expect(
          (await database.select(database.answerAttempts).get()).single.wordId,
          'word:airport',
        );
        expect(
          (await database.select(database.srsStates).get()).single.wordId,
          'word:alias-middle',
        );

        await database.customInsert(
          'INSERT INTO local_owners '
          '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
          "VALUES ('alias-final-only-account', 'firebase-alias-final-only', "
          "'firebaseBound', 3, 0)",
        );
        await database.customInsert(
          'INSERT INTO vocabulary_categories '
          '(id, owner_id, name, normalized_name, created_at_utc_ms, '
          'updated_at_utc_ms) VALUES '
          "('category:alias-final-only', 'alias-final-only-account', 'Travel', "
          "'travel', 3, 3)",
        );
        await database.customInsert(
          'INSERT INTO vocabulary_words '
          '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
          'normalized_meaning, part_of_speech, created_at_utc_ms, '
          'updated_at_utc_ms) VALUES '
          "('word:alias-final-only', 'alias-final-only-account', "
          "'category:alias-final-only', 'airport', 'airport', "
          "'place for flights', 'place for flights', 'noun', 3, 3)",
        );
        await DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => DateTime.utc(2026, 8, 25, 11),
          generateConflictId: () => 'alias-final-only-${++conflictId}',
          generateOwnerId: () => 'alias-final-only-new-owner',
          generateOwnerOperationToken: () => 'alias-final-only-operation',
          deleteOwnerSecrets: (_) async {},
        ).upgrade(
          activeOwnerId: 'alias-middle-account',
          firebaseUid: 'firebase-alias-final-only',
        );

        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts, hasLength(1));
        expect(attempts.single.ownerId, 'alias-final-only-account');
        expect(attempts.single.wordId, 'word:airport');
        final source = await (database.select(
          database.vocabularyWords,
        )..where((row) => row.id.equals('word:airport'))).getSingle();
        final middle = await (database.select(
          database.vocabularyWords,
        )..where((row) => row.id.equals('word:alias-middle'))).getSingle();
        expect(source.ownerId, 'alias-final-only-account');
        expect(source.isDeleted, isTrue);
        expect(middle.ownerId, 'alias-final-only-account');
        expect(middle.isDeleted, isTrue);
        final aliases = await database
            .customSelect(
              'SELECT entity_id, local_snapshot_json FROM sync_conflicts '
              'WHERE owner_id = ? AND entity_type = ? '
              "AND local_snapshot_json LIKE '%projectionAlias%'",
              variables: const <Variable<Object>>[
                Variable<String>('alias-final-only-account'),
                Variable<String>('word'),
              ],
            )
            .get();
        expect(aliases, hasLength(2));
        expect(
          aliases.map((row) {
            final local =
                jsonDecode(row.read<String>('local_snapshot_json'))
                    as Map<String, dynamic>;
            return (
              local['id'],
              local['projectionAliasTargetWordId'],
              row.read<String>('entity_id'),
            );
          }).toSet(),
          <(Object?, Object?, String)>{
            ('word:airport', 'word:alias-middle', 'word:alias-final-only'),
            (
              'word:alias-middle',
              'word:alias-final-only',
              'word:alias-final-only',
            ),
          },
        );
        final preservedEvent =
            await (database.select(database.eventsV2)
                  ..where((row) => row.eventId.equals(historicalEvent.eventId)))
                .getSingle();
        expect(preservedEvent.payloadJson, historicalEvent.payloadJson);

        final rebuilder = DriftLearningProjectionRebuilder(database);
        await rebuilder.rebuildWord(
          ownerId: 'alias-final-only-account',
          wordId: 'word:airport',
        );
        await rebuilder.rebuildWord(
          ownerId: 'alias-final-only-account',
          wordId: 'word:alias-middle',
        );
        await rebuilder.rebuildWord(
          ownerId: 'alias-final-only-account',
          wordId: 'word:alias-final-only',
        );
        final folded =
            await (database.select(database.srsStates)..where(
                  (row) => row.ownerId.equals('alias-final-only-account'),
                ))
                .get();
        expect(folded, hasLength(1));
        expect(folded.single.wordId, 'word:alias-final-only');
        expect(folded.single.repetitions, 1);
      },
    );

    Future<void> expectUnrelatedRecallSurvivesAliasTargetMutation({
      required bool deleteTarget,
    }) async {
      final guest = await owners.getOrCreateActiveOwner();
      final guestSession = await learning.startQuiz(
        categoryId: 'category:travel',
      );
      await CurrentActivityEvidenceAdapter(learning: learning)
          .capture(
            input: CurrentActivityInput.typedRecall,
            sessionId: guestSession.id,
            wordId: 'word:airport',
            isCorrect: true,
            responseTimeMs: 100,
            attemptNumber: 1,
          )
          .record();
      final guestAttempt =
          (await database.select(database.answerAttempts).get()).single;
      final historicalEvent =
          await (database.select(database.eventsV2)..where(
                (row) => row.eventId.equals(
                  LearningEvidenceContract.learningEventId(guestAttempt.id),
                ),
              ))
              .getSingle();

      await database.customInsert(
        'INSERT INTO local_owners '
        '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
        "VALUES ('alias-mutation-account', 'firebase-alias-mutation', "
        "'firebaseBound', 2, 0)",
      );
      await database.customInsert(
        'INSERT INTO vocabulary_categories '
        '(id, owner_id, name, normalized_name, created_at_utc_ms, '
        'updated_at_utc_ms) VALUES '
        "('category:alias-mutation', 'alias-mutation-account', 'Travel', "
        "'travel', 2, 2)",
      );
      await database.customInsert(
        'INSERT INTO vocabulary_words '
        '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
        'normalized_meaning, part_of_speech, created_at_utc_ms, '
        'updated_at_utc_ms) VALUES '
        "('word:alias-mutation-airport', 'alias-mutation-account', "
        "'category:alias-mutation', 'airport', 'airport', "
        "'place for flights', 'place for flights', 'noun', 2, 2)",
      );
      var upgradeId = 0;
      await DriftOwnerUpgradeRepository(
        database,
        nowUtc: () => DateTime.utc(2026, 8, 25, 13),
        generateConflictId: () => 'alias-mutation-${++upgradeId}',
        generateOwnerId: () => 'alias-mutation-new-owner',
        generateOwnerOperationToken: () => 'alias-mutation-operation',
        deleteOwnerSecrets: (_) async {},
      ).upgrade(
        activeOwnerId: guest.id,
        firebaseUid: 'firebase-alias-mutation',
      );

      final vocabulary = VocabularyUseCases(
        owners: owners,
        vocabulary: DriftVocabularyRepository(database),
        generateId: () => 'unused-alias-mutation-id',
        nowUtc: () => DateTime.utc(2026, 8, 25, 13, 30),
      );
      if (deleteTarget) {
        await vocabulary.deleteWord('word:alias-mutation-airport');
      } else {
        await vocabulary.updateWord(
          const UpdateWordCommand(
            id: 'word:alias-mutation-airport',
            categoryId: 'category:alias-mutation',
            spelling: 'airport terminal',
            meaning: 'a place where flights arrive and depart',
            partOfSpeech: 'noun',
          ),
        );
      }

      var accountId = 0;
      final accountLearning = LearningUseCases(
        owners: owners,
        repository: DriftLearningRepository(database),
        generateId: () => 'alias-mutation-account-${++accountId}',
        nowUtc: () => DateTime.utc(2026, 8, 25, 14, 0, accountId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
      );
      final unrelatedSession = await accountLearning.startQuiz(
        categoryId: 'category:alias-mutation',
      );
      final unrelatedResult =
          await CurrentActivityEvidenceAdapter(learning: accountLearning)
              .capture(
                input: CurrentActivityInput.typedRecall,
                sessionId: unrelatedSession.id,
                wordId: 'word:station',
                isCorrect: true,
                responseTimeMs: 140,
                attemptNumber: 1,
              )
              .record();
      expect(unrelatedResult.inserted, isTrue);

      final rebuilder = DriftLearningProjectionRebuilder(database);
      await rebuilder.rebuildWord(
        ownerId: 'alias-mutation-account',
        wordId: 'word:station',
      );
      final unrelatedAttempt = await (database.select(
        database.answerAttempts,
      )..where((row) => row.wordId.equals('word:station'))).getSingle();
      final unrelatedSrs = await (database.select(
        database.srsStates,
      )..where((row) => row.wordId.equals('word:station'))).getSingle();
      expect(unrelatedAttempt.ownerId, 'alias-mutation-account');
      expect(unrelatedSrs.ownerId, 'alias-mutation-account');

      final preservedEvent =
          await (database.select(database.eventsV2)
                ..where((row) => row.eventId.equals(historicalEvent.eventId)))
              .getSingle();
      expect(preservedEvent.payloadJson, historicalEvent.payloadJson);

      if (deleteTarget) {
        final projectionBeforeFence = await _projectionSnapshot(database);
        await expectLater(
          () => rebuilder.rebuildWord(
            ownerId: 'alias-mutation-account',
            wordId: 'word:airport',
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'word projection alias canonical target is deleted',
            ),
          ),
        );
        expect(await _projectionSnapshot(database), projectionBeforeFence);
      } else {
        await rebuilder.rebuildWord(
          ownerId: 'alias-mutation-account',
          wordId: 'word:airport',
        );
        final folded = await (database.select(
          database.srsStates,
        )..where((row) => row.ownerId.equals('alias-mutation-account'))).get();
        expect(
          folded.where((row) => row.wordId == 'word:alias-mutation-airport'),
          hasLength(1),
        );
        expect(folded.any((row) => row.wordId == 'word:airport'), isFalse);
      }
    }

    test(
      'edited alias target keeps folding and unrelated recall durable',
      () =>
          expectUnrelatedRecallSurvivesAliasTargetMutation(deleteTarget: false),
    );

    test(
      'deleted alias target fences only its historical projection',
      () =>
          expectUnrelatedRecallSurvivesAliasTargetMutation(deleteTarget: true),
    );

    test(
      'pre-write guest pending retry uses current account actor after upgrade',
      () async {
        final guest = await owners.getOrCreateActiveOwner();
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
          recordFailure: _RecordFailure.beforeWrite,
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'guest-pending-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 11, 30, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        CurrentActivityEvidenceAdapter evidence() =>
            CurrentActivityEvidenceAdapter(learning: retryLearning);
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        final first = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final pair = first.pairSet.pairs.first;
        await first.selectWord(pair.word.id, responseTimeMs: 100);
        await expectLater(
          first.selectMeaning(pair.word.id, responseTimeMs: 200),
          throwsStateError,
        );
        first.dispose();
        await database.customInsert(
          'INSERT INTO local_owners '
          '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
          "VALUES ('pending-account', 'firebase-pending', 'firebaseBound', 4, 0)",
        );
        var upgradeId = 0;
        await DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => DateTime.utc(2026, 8, 25, 11, 31),
          generateConflictId: () => 'pending-conflict-${++upgradeId}',
          generateOwnerId: () => 'pending-new-owner',
          generateOwnerOperationToken: () => 'pending-operation',
          deleteOwnerSecrets: (_) async {},
        ).upgrade(activeOwnerId: guest.id, firebaseUid: 'firebase-pending');

        repository.recordFailure = _RecordFailure.none;
        final recovered = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        final checkpointRows =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventType.equals('LearningActivityCheckpoint'),
                ))
                .get();
        checkpointRows.sort((left, right) {
          final leftRevision =
              (jsonDecode(left.payloadJson) as Map<String, dynamic>)['revision']
                  as int;
          final rightRevision =
              (jsonDecode(right.payloadJson)
                      as Map<String, dynamic>)['revision']
                  as int;
          return leftRevision.compareTo(rightRevision);
        });
        final pending =
            ((jsonDecode(checkpointRows.last.payloadJson)
                        as Map<String, dynamic>)['state']
                    as Map<String, dynamic>)['pendingEvidence']
                as Map<String, dynamic>;
        expect(pending['schemaVersion'], 4);
        expect(pending['actorIdentity'], guest.id);
        expect(pending['providerProvenance'], 'pinned-lexical-matching');
        expect(pending['contrastiveFeedback'], isNull);
        final restarted = adapter.createReview(
          session: recovered.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: recovered,
        );
        addTearDown(restarted.dispose);
        await restarted.retryEvidence();
        final retried = repository.commands.last;
        expect(retried.ownerId, 'pending-account');
        expect(retried.event!.ownerIdentity, 'pending-account');
        expect(retried.event!.actorIdentity, 'pending-account');
        final attempt =
            (await database.select(database.answerAttempts).get()).single;
        expect(attempt.ownerId, 'pending-account');
        final event =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(
                    LearningEvidenceContract.learningEventId(attempt.id),
                  ),
                ))
                .getSingle();
        expect(event.ownerId, 'pending-account');
        expect(event.actorIdentity, 'pending-account');
        await restarted.timeout();
      },
    );

    test(
      'post-write guest pending recovery preserves historical actor on exact replay',
      () async {
        final guest = await owners.getOrCreateActiveOwner();
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
          recordFailure: _RecordFailure.afterWrite,
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'guest-lost-ack-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 11, 35, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        CurrentActivityEvidenceAdapter evidence() =>
            CurrentActivityEvidenceAdapter(learning: retryLearning);
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        final first = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final pair = first.pairSet.pairs.first;
        await first.selectWord(pair.word.id, responseTimeMs: 100);
        await expectLater(
          first.selectMeaning(pair.word.id, responseTimeMs: 200),
          throwsStateError,
        );
        first.dispose();
        final attemptBeforeUpgrade =
            (await database.select(database.answerAttempts).get()).single;
        final eventBeforeUpgrade =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(
                    LearningEvidenceContract.learningEventId(
                      attemptBeforeUpgrade.id,
                    ),
                  ),
                ))
                .getSingle();
        expect(eventBeforeUpgrade.actorIdentity, guest.id);

        await database.customInsert(
          'INSERT INTO local_owners '
          '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
          "VALUES ('lost-ack-account', 'firebase-lost-ack', "
          "'firebaseBound', 5, 0)",
        );
        var upgradeId = 0;
        await DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => DateTime.utc(2026, 8, 25, 11, 36),
          generateConflictId: () => 'lost-ack-conflict-${++upgradeId}',
          generateOwnerId: () => 'lost-ack-new-owner',
          generateOwnerOperationToken: () => 'lost-ack-operation',
          deleteOwnerSecrets: (_) async {},
        ).upgrade(activeOwnerId: guest.id, firebaseUid: 'firebase-lost-ack');

        final recovered = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        expect(recovered.pendingEvidence, isNull);
        expect(recovered.matchedWordIds, contains(pair.word.id));
        expect(repository.commands, hasLength(1));
        final attemptAfterUpgrade =
            (await database.select(database.answerAttempts).get()).single;
        expect(attemptAfterUpgrade.id, attemptBeforeUpgrade.id);
        expect(attemptAfterUpgrade.ownerId, 'lost-ack-account');
        final eventAfterUpgrade =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(eventBeforeUpgrade.eventId),
                ))
                .getSingle();
        expect(eventAfterUpgrade.ownerId, 'lost-ack-account');
        expect(eventAfterUpgrade.actorIdentity, guest.id);
        expect(eventAfterUpgrade.payloadJson, eventBeforeUpgrade.payloadJson);
      },
    );

    test(
      'restart recovers exact pending evidence and lost acknowledgement identity',
      () async {
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
          recordFailure: _RecordFailure.beforeWrite,
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'durable-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 12, 30, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final evidence = CurrentActivityEvidenceAdapter(
          learning: retryLearning,
        );
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final originalPairIds = prepared.session.questions
            .map((question) => question.word.id)
            .toList(growable: false);
        final first = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence,
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final pair = first.pairSet.pairs.first;
        await first.selectWord(pair.word.id, responseTimeMs: 300);
        await expectLater(
          first.selectMeaning(pair.word.id, responseTimeMs: 400),
          throwsStateError,
        );
        final sourceEvidenceId = repository.commands.single.id;
        final occurredAtUtc = repository.commands.single.occurredAtUtc;
        first.dispose();
        expect(await database.select(database.answerAttempts).get(), isEmpty);

        repository.recordFailure = _RecordFailure.none;
        final pending = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final restarted = adapter.createReview(
          session: pending.session,
          learning: retryLearning,
          evidence: evidence,
          recovery: pending,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        expect(restarted.phase, MatchingReviewPhase.evidenceRetryRequired);
        expect(pending.pendingEvidence!.sourceEvidenceId, sourceEvidenceId);
        expect(pending.pendingEvidence!.occurredAtUtc, occurredAtUtc);
        expect(
          pending.session.questions.map((question) => question.word.id),
          originalPairIds,
        );
        await restarted.retryEvidence();
        restarted.dispose();

        final attempt =
            (await database.select(database.answerAttempts).get()).single;
        expect(attempt.id, sourceEvidenceId);
        expect(attempt.occurredAtUtcMs, occurredAtUtc.millisecondsSinceEpoch);

        repository.recordFailure = _RecordFailure.afterWrite;
        final afterPending = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final after = adapter.createReview(
          session: afterPending.session,
          learning: retryLearning,
          evidence: evidence,
          recovery: afterPending,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final secondPair = after.pairSet.pairs.firstWhere(
          (candidate) => candidate.word.id != pair.word.id,
        );
        await after.selectWord(secondPair.word.id, responseTimeMs: 500);
        await expectLater(
          after.selectMeaning(secondPair.word.id, responseTimeMs: 600),
          throwsStateError,
        );
        final lostAckId = repository.commands.last.id;
        after.dispose();

        final reconciled = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        expect(reconciled.pendingEvidence, isNull);
        expect(reconciled.matchedWordIds, contains(secondPair.word.id));
        expect(
          (await database.select(database.answerAttempts).get()).where(
            (attempt) => attempt.id == lostAckId,
          ),
          hasLength(1),
        );
      },
    );

    test(
      'f18 restart reconstructs the exact reviewed matching explanation',
      () async {
        await _setCanonicalCoreIdentities(database, revision: 4);
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
          recordFailure: _RecordFailure.beforeWrite,
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'f18-restart-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 26, 14, 0, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f18-test'),
        );
        CurrentActivityEvidenceAdapter evidence() =>
            CurrentActivityEvidenceAdapter(learning: retryLearning);
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        final lexical = _matchingLexicalArtifacts(prepared.session);
        final first = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: prepared,
          lexicalWords: lexical.words,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final correct = first.pairSet.pairs.first;
        final selectedDistractor = first.pairSet.pairs.firstWhere(
          (pair) => pair.word.id != correct.word.id,
        );
        await first.selectWord(correct.word.id, responseTimeMs: 100);
        await expectLater(
          first.selectMeaning(selectedDistractor.word.id, responseTimeMs: 200),
          throwsStateError,
        );
        first.dispose();
        expect(await database.select(database.answerAttempts).get(), isEmpty);

        final recovered = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        final restarted = adapter.createReview(
          session: recovered.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: recovered,
          lexicalWords: lexical.words,
        );
        addTearDown(restarted.dispose);
        final result = await restarted.retryEvidence();

        expect(result!.committedContrastiveAttempt, isNotNull);
        expect(
          result.committedContrastiveAttempt!.correctOptionId,
          correct.word.id,
        );
        expect(
          result.committedContrastiveAttempt!.selectedDistractorId,
          selectedDistractor.word.id,
        );
        final explanation = await ContrastiveFeedbackUseCases(
          manifests: _MatchingManifestRepository(lexical.artifacts),
        ).resolveAfterCommit(committedFeedback: restarted.feedback!);
        expect(explanation, isNotNull);
        expect(explanation!.manifestIdentity.id, correct.word.id);
        expect(explanation.selectedDistractorId, selectedDistractor.word.id);
      },
    );

    test(
      'f18 restart rejects legacy and mutated frozen context before writes',
      () async {
        await _setCanonicalCoreIdentities(database, revision: 4);
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
          recordFailure: _RecordFailure.beforeWrite,
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'f18-corrupt-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 26, 14, 30, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f18-test'),
        );
        CurrentActivityEvidenceAdapter evidence() =>
            CurrentActivityEvidenceAdapter(learning: retryLearning);
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        final lexical = _matchingLexicalArtifacts(prepared.session);
        final first = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: prepared,
          lexicalWords: lexical.words,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final correct = first.pairSet.pairs.first;
        final selectedDistractor = first.pairSet.pairs.firstWhere(
          (pair) => pair.word.id != correct.word.id,
        );
        await first.selectWord(correct.word.id, responseTimeMs: 100);
        await expectLater(
          first.selectMeaning(selectedDistractor.word.id, responseTimeMs: 200),
          throwsStateError,
        );
        first.dispose();

        final rows =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventType.equals('LearningActivityCheckpoint'),
                ))
                .get();
        rows.sort((left, right) {
          final leftRevision =
              (jsonDecode(left.payloadJson) as Map<String, dynamic>)['revision']
                  as int;
          final rightRevision =
              (jsonDecode(right.payloadJson)
                      as Map<String, dynamic>)['revision']
                  as int;
          return leftRevision.compareTo(rightRevision);
        });
        final latest = rows.last;
        final original = jsonDecode(latest.payloadJson) as Map<String, dynamic>;
        final originalPending =
            (original['state'] as Map<String, dynamic>)['pendingEvidence']
                as Map<String, dynamic>;
        expect(originalPending['schemaVersion'], 4);
        expect(originalPending['contrastiveFeedback'], isA<Map>());

        Map<String, dynamic> copyPayload() =>
            jsonDecode(jsonEncode(original)) as Map<String, dynamic>;
        final mutations = <String, void Function(Map<String, dynamic>)>{
          'legacy f18 without context': (pending) {
            pending['schemaVersion'] = 3;
            pending.remove('contrastiveFeedback');
          },
          'provider provenance hash': (pending) {
            pending['providerProvenance'] = 'f18:v1:${'0' * 64}';
          },
          'manifest word identity': (pending) {
            (pending['contrastiveFeedback']
                    as Map<String, dynamic>)['contentId'] =
                selectedDistractor.word.id;
          },
          'manifest revision': (pending) {
            (pending['contrastiveFeedback']
                    as Map<String, dynamic>)['contentRevision'] =
                5;
          },
          'manifest checksum': (pending) {
            (pending['contrastiveFeedback']
                    as Map<String, dynamic>)['manifestChecksumSha256'] =
                'c' * 64;
          },
          'evidence revision': (pending) {
            (pending['contrastiveFeedback']
                    as Map<String, dynamic>)['evidenceContentRevision'] =
                'lexical-matching:v4:${'c' * 64}';
          },
          'correct option identity': (pending) {
            (pending['contrastiveFeedback']
                as Map<String, dynamic>)['correctOptionId'] = first
                .pairSet
                .pairs
                .firstWhere(
                  (pair) =>
                      pair.word.id != correct.word.id &&
                      pair.word.id != selectedDistractor.word.id,
                )
                .word
                .id;
          },
          'selected distractor identity': (pending) {
            (pending['contrastiveFeedback']
                as Map<String, dynamic>)['selectedDistractorId'] = first
                .pairSet
                .pairs
                .firstWhere(
                  (pair) =>
                      pair.word.id != correct.word.id &&
                      pair.word.id != selectedDistractor.word.id,
                )
                .word
                .id;
          },
        };
        for (final mutation in mutations.entries) {
          final payload = copyPayload();
          final pending =
              (payload['state'] as Map<String, dynamic>)['pendingEvidence']
                  as Map<String, dynamic>;
          mutation.value(pending);
          if (mutation.key != 'legacy f18 without context' &&
              mutation.key != 'provider provenance hash') {
            try {
              final frozen = FrozenContrastiveFeedbackContext.fromJson(
                (pending['contrastiveFeedback'] as Map<String, dynamic>)
                    .cast<String, Object?>(),
              );
              pending['providerProvenance'] =
                  contrastiveFeedbackAttemptProvenance(frozen);
            } on FormatException {
              // Invalid context shapes must fail before provenance matters.
            }
          }
          await (database.update(
            database.eventsV2,
          )..where((row) => row.eventId.equals(latest.eventId))).write(
            EventsV2Companion(payloadJson: Value(jsonEncode(payload))),
          );
          final commandsBefore = repository.commands.length;
          await expectLater(
            () async {
              final recovered = await adapter.prepareSession(
                learning: retryLearning,
                evidence: evidence(),
                categoryId: 'category:travel',
              );
              final review = adapter.createReview(
                session: recovered.session,
                learning: retryLearning,
                evidence: evidence(),
                recovery: recovered,
                lexicalWords: lexical.words,
              );
              review.dispose();
            }(),
            throwsStateError,
            reason: mutation.key,
          );
          expect(repository.commands, hasLength(commandsBefore));
          expect(
            await database.select(database.answerAttempts).get(),
            isEmpty,
            reason: mutation.key,
          );
        }
      },
    );

    test(
      'checkpoint append failure retries the same selection in process',
      () async {
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
        );
        var evidenceId = 0;
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'checkpoint-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 13, 0, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final evidence = CurrentActivityEvidenceAdapter(
          learning: retryLearning,
          generateId: () => 'checkpoint-evidence-${++evidenceId}',
        );
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        repository.checkpointFailure = _CheckpointFailure.beforeWrite;
        final review = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence,
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);
        final pair = review.pairSet.pairs.first;
        await review.selectWord(pair.word.id, responseTimeMs: 100);
        await expectLater(
          review.selectMeaning(pair.word.id, responseTimeMs: 200),
          throwsStateError,
        );

        expect(review.phase, MatchingReviewPhase.evidenceRetryRequired);
        expect(review.selectedWordId, pair.word.id);
        expect(review.selectedMeaningWordId, pair.word.id);
        await review.retryEvidence();

        final attempt =
            (await database.select(database.answerAttempts).get()).single;
        expect(attempt.id, 'attempt:checkpoint-evidence-1');
        expect(attempt.attemptNumber, 1);
        expect(evidenceId, 1);
      },
    );

    test(
      'lost checkpoint acknowledgement reconstructs the same pending match',
      () async {
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
        );
        var evidenceId = 0;
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'checkpoint-restart-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 13, 15, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        CurrentActivityEvidenceAdapter evidence() =>
            CurrentActivityEvidenceAdapter(
              learning: retryLearning,
              generateId: () => 'checkpoint-restart-evidence-${++evidenceId}',
            );
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        repository.checkpointFailure = _CheckpointFailure.afterWrite;
        final first = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final pair = first.pairSet.pairs.first;
        await first.selectWord(pair.word.id, responseTimeMs: 100);
        await expectLater(
          first.selectMeaning(pair.word.id, responseTimeMs: 200),
          throwsStateError,
        );
        first.dispose();
        expect(repository.commands, isEmpty);

        final recovered = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        final restarted = adapter.createReview(
          session: recovered.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: recovered,
        );
        addTearDown(restarted.dispose);
        expect(restarted.phase, MatchingReviewPhase.evidenceRetryRequired);
        await restarted.retryEvidence();

        final attempt =
            (await database.select(database.answerAttempts).get()).single;
        expect(attempt.id, 'attempt:checkpoint-restart-evidence-1');
        expect(attempt.wordId, pair.word.id);
        expect(attempt.attemptNumber, 1);
        expect(evidenceId, 1);
      },
    );

    for (final failure in <_CheckpointFailure>[
      _CheckpointFailure.beforeWrite,
      _CheckpointFailure.afterWrite,
    ]) {
      test(
        'clear pending ${failure.name} retains exact retry before next answer and close',
        () async {
          final repository = _RestartRecoveryRepository(
            DriftLearningRepository(database),
          );
          final retryLearning = LearningUseCases(
            owners: owners,
            repository: repository,
            generateId: () => 'clear-${failure.name}-${++generatedId}',
            nowUtc: () => DateTime.utc(2026, 8, 25, 13, 25, generatedId),
            buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
          );
          final evidence = CurrentActivityEvidenceAdapter(
            learning: retryLearning,
          );
          final prepared = await adapter.prepareSession(
            learning: retryLearning,
            evidence: evidence,
            categoryId: 'category:travel',
          );
          repository
            ..checkpointFailure = failure
            ..checkpointFailureRevision = 3;
          final review = adapter.createReview(
            session: prepared.session,
            learning: retryLearning,
            evidence: evidence,
            recovery: prepared,
            hintUsage: () => const HintUsageSnapshot.known(0),
          );
          addTearDown(review.dispose);
          final firstPair = review.pairSet.pairs.first;
          await review.selectWord(firstPair.word.id, responseTimeMs: 100);
          await expectLater(
            review.selectMeaning(firstPair.word.id, responseTimeMs: 200),
            throwsStateError,
          );
          expect(review.phase, MatchingReviewPhase.evidenceRetryRequired);
          expect(
            await database.select(database.answerAttempts).get(),
            hasLength(1),
          );

          await review.retryEvidence();
          final nextPair = review.pairSet.pairs.firstWhere(
            (candidate) => candidate.word.id != firstPair.word.id,
          );
          await review.selectWord(nextPair.word.id, responseTimeMs: 300);
          await review.selectMeaning(nextPair.word.id, responseTimeMs: 400);
          final summary = await review.timeout();

          expect(summary.state, 'completed');
          expect(
            await database.select(database.answerAttempts).get(),
            hasLength(2),
          );
        },
      );
    }

    test(
      'restart drains a committed pending occurrence after clear pre-write failure',
      () async {
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'clear-restart-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 13, 28, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        CurrentActivityEvidenceAdapter evidence() =>
            CurrentActivityEvidenceAdapter(learning: retryLearning);
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        repository
          ..checkpointFailure = _CheckpointFailure.beforeWrite
          ..checkpointFailureRevision = 3;
        final first = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final pair = first.pairSet.pairs.first;
        await first.selectWord(pair.word.id, responseTimeMs: 100);
        await expectLater(
          first.selectMeaning(pair.word.id, responseTimeMs: 200),
          throwsStateError,
        );
        first.dispose();

        final restartedPrepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        final checkpointRows =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventType.equals('LearningActivityCheckpoint'),
                ))
                .get();
        checkpointRows.sort((left, right) {
          final leftRevision =
              (jsonDecode(left.payloadJson) as Map<String, dynamic>)['revision']
                  as int;
          final rightRevision =
              (jsonDecode(right.payloadJson)
                      as Map<String, dynamic>)['revision']
                  as int;
          return leftRevision.compareTo(rightRevision);
        });
        final latestState =
            (jsonDecode(checkpointRows.last.payloadJson)
                    as Map<String, dynamic>)['state']
                as Map<String, dynamic>;
        expect(latestState['pendingEvidence'], isNull);
        final restarted = adapter.createReview(
          session: restartedPrepared.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: restartedPrepared,
        );
        addTearDown(restarted.dispose);
        final next = restarted.pairSet.pairs.firstWhere(
          (candidate) => candidate.word.id != pair.word.id,
        );
        await restarted.selectWord(next.word.id, responseTimeMs: 300);
        await restarted.selectMeaning(next.word.id, responseTimeMs: 400);
        expect((await restarted.timeout()).state, 'completed');
      },
    );

    test(
      'pending recovery rejects an inner-only independent recall mutation before restore',
      () async {
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
          recordFailure: _RecordFailure.beforeWrite,
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'inner-class-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 13, 28, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        CurrentActivityEvidenceAdapter evidence() =>
            CurrentActivityEvidenceAdapter(learning: retryLearning);
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        final first = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final pair = first.pairSet.pairs.first;
        await first.selectWord(pair.word.id, responseTimeMs: 100);
        await expectLater(
          first.selectMeaning(pair.word.id, responseTimeMs: 200),
          throwsStateError,
        );
        first.dispose();
        expect(await database.select(database.answerAttempts).get(), isEmpty);
        expect(await database.select(database.srsStates).get(), isEmpty);

        final rows =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventType.equals('LearningActivityCheckpoint'),
                ))
                .get();
        rows.sort((left, right) {
          final leftRevision =
              (jsonDecode(left.payloadJson) as Map<String, dynamic>)['revision']
                  as int;
          final rightRevision =
              (jsonDecode(right.payloadJson)
                      as Map<String, dynamic>)['revision']
                  as int;
          return leftRevision.compareTo(rightRevision);
        });
        final latest = rows.last;
        final payload = jsonDecode(latest.payloadJson) as Map<String, dynamic>;
        final pending =
            (payload['state'] as Map<String, dynamic>)['pendingEvidence']
                as Map<String, dynamic>;
        expect(pending['evidenceClass'], EvidenceClass.recognition.name);
        final frozenEvidence =
            pending['evidenceContext'] as Map<String, dynamic>;
        frozenEvidence['evidenceClass'] = EvidenceClass.independentRecall.name;
        await (database.update(database.eventsV2)
              ..where((row) => row.eventId.equals(latest.eventId)))
            .write(EventsV2Companion(payloadJson: Value(jsonEncode(payload))));

        final recordCallsBeforeRecovery = repository.commands.length;
        await expectLater(
          adapter.prepareSession(
            learning: retryLearning,
            evidence: evidence(),
            categoryId: 'category:travel',
          ),
          throwsStateError,
        );
        expect(repository.commands, hasLength(recordCallsBeforeRecovery));
        expect(await database.select(database.answerAttempts).get(), isEmpty);
        expect(await database.select(database.srsStates).get(), isEmpty);
      },
    );

    test(
      'committed pending recovery rejects actor provider and class collisions',
      () async {
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'pending-collision-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 13, 29, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        CurrentActivityEvidenceAdapter evidence() =>
            CurrentActivityEvidenceAdapter(learning: retryLearning);
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        repository
          ..checkpointFailure = _CheckpointFailure.beforeWrite
          ..checkpointFailureRevision = 3;
        final first = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence(),
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        final pair = first.pairSet.pairs.first;
        await first.selectWord(pair.word.id, responseTimeMs: 100);
        await expectLater(
          first.selectMeaning(pair.word.id, responseTimeMs: 200),
          throwsStateError,
        );
        first.dispose();

        RecordAnswerCandidate replaceAttempt(
          RecordAnswerCandidate attempt, {
          required String actorIdentity,
          required String providerProvenance,
          EvidenceContext? evidenceContext,
        }) => RecordAnswerCandidate(
          id: attempt.id,
          ownerId: attempt.ownerId,
          sessionId: attempt.sessionId,
          wordId: attempt.wordId,
          promptMode: attempt.promptMode,
          isCorrect: attempt.isCorrect,
          responseTimeMs: attempt.responseTimeMs,
          attemptNumber: attempt.attemptNumber,
          occurredAtUtc: attempt.occurredAtUtc,
          evidenceContext: evidenceContext ?? attempt.evidenceContext,
          providerProvenance: providerProvenance,
          actorIdentity: actorIdentity,
          eventContext: attempt.eventContext,
        );

        Future<void> expectCollision(
          RecordAnswerCandidate Function(RecordAnswerCandidate attempt) corrupt,
        ) async {
          repository.recoveryTransform = (recovery) => LearningActivityRecovery(
            session: recovery.session,
            checkpoint: recovery.checkpoint,
            attempts: recovery.attempts.map(corrupt).toList(growable: false),
          );
          await expectLater(
            adapter.prepareSession(
              learning: retryLearning,
              evidence: evidence(),
              categoryId: 'category:travel',
            ),
            throwsStateError,
          );
        }

        await expectCollision(
          (attempt) => replaceAttempt(
            attempt,
            actorIdentity: 'actor:collision',
            providerProvenance: attempt.providerProvenance!,
          ),
        );
        await expectCollision(
          (attempt) => replaceAttempt(
            attempt,
            actorIdentity: attempt.actorIdentity!,
            providerProvenance: 'provider:collision',
          ),
        );

        final rows =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventType.equals('LearningActivityCheckpoint'),
                ))
                .get();
        rows.sort((left, right) {
          final leftRevision =
              (jsonDecode(left.payloadJson) as Map<String, dynamic>)['revision']
                  as int;
          final rightRevision =
              (jsonDecode(right.payloadJson)
                      as Map<String, dynamic>)['revision']
                  as int;
          return leftRevision.compareTo(rightRevision);
        });
        final latest = rows.last;
        final originalPayload = latest.payloadJson;
        final contextCollisionPayload =
            jsonDecode(originalPayload) as Map<String, dynamic>;
        final contextCollisionPending =
            (contextCollisionPayload['state']
                    as Map<String, dynamic>)['pendingEvidence']
                as Map<String, dynamic>;
        final contextCollision =
            contextCollisionPending['eventContext'] as Map<String, dynamic>;
        (contextCollision['consentContext']
                as Map<String, dynamic>)['aiConsentGranted'] =
            true;
        await (database.update(
          database.eventsV2,
        )..where((row) => row.eventId.equals(latest.eventId))).write(
          EventsV2Companion(
            payloadJson: Value(jsonEncode(contextCollisionPayload)),
          ),
        );
        await expectCollision((attempt) => attempt);
        await (database.update(database.eventsV2)
              ..where((row) => row.eventId.equals(latest.eventId)))
            .write(EventsV2Companion(payloadJson: Value(originalPayload)));

        final payload = jsonDecode(latest.payloadJson) as Map<String, dynamic>;
        final pending =
            (payload['state'] as Map<String, dynamic>)['pendingEvidence']
                as Map<String, dynamic>;
        final frozenEvidence =
            pending['evidenceContext'] as Map<String, dynamic>;
        pending['evidenceClass'] = EvidenceClass.guidedPractice.name;
        pending['hintLevel'] = 0;
        frozenEvidence['evidenceClass'] = EvidenceClass.guidedPractice.name;
        frozenEvidence['hintLevel'] = 0;
        final invalidClassification = EvidenceContext.fromJson(
          Map<String, Object?>.from(frozenEvidence),
        );
        await (database.update(database.eventsV2)
              ..where((row) => row.eventId.equals(latest.eventId)))
            .write(EventsV2Companion(payloadJson: Value(jsonEncode(payload))));
        await expectCollision(
          (attempt) => replaceAttempt(
            attempt,
            actorIdentity: attempt.actorIdentity!,
            providerProvenance: attempt.providerProvenance!,
            evidenceContext: invalidClassification,
          ),
        );
      },
    );

    test('restart retries the frozen policy and research contexts', () async {
      final repository = _RestartRecoveryRepository(
        DriftLearningRepository(database),
        recordFailure: _RecordFailure.beforeWrite,
      );
      final retryLearning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'context-${++generatedId}',
        nowUtc: () => DateTime.utc(2026, 8, 25, 13, 30, generatedId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
      );
      final rollout = _MutableRolloutProvider();
      final research = _MutableResearchProvider();
      CurrentActivityEvidenceAdapter evidence() =>
          CurrentActivityEvidenceAdapter(
            learning: retryLearning,
            rolloutModeProvider: rollout,
            researchStateProvider: research,
          );
      final prepared = await adapter.prepareSession(
        learning: retryLearning,
        evidence: evidence(),
        categoryId: 'category:travel',
      );
      final first = adapter.createReview(
        session: prepared.session,
        learning: retryLearning,
        evidence: evidence(),
        recovery: prepared,
        hintUsage: () => const HintUsageSnapshot.known(0),
      );
      final pair = first.pairSet.pairs.first;
      await first.selectWord(pair.word.id, responseTimeMs: 100);
      await expectLater(
        first.selectMeaning(pair.word.id, responseTimeMs: 200),
        throwsStateError,
      );
      first.dispose();
      expect(rollout.calls, 1);
      expect(research.calls, 1);
      final original = repository.commands.single;

      rollout.mode = EvidencePolicyRolloutMode.enforced;
      research.fail = true;
      final recovered = await adapter.prepareSession(
        learning: retryLearning,
        evidence: evidence(),
        categoryId: 'category:travel',
      );
      final restarted = adapter.createReview(
        session: recovered.session,
        learning: retryLearning,
        evidence: evidence(),
        recovery: recovered,
      );
      addTearDown(restarted.dispose);
      await restarted.retryEvidence();

      expect(rollout.calls, 1);
      expect(research.calls, 1);
      final retried = repository.commands.last;
      expect(
        retried.evidenceContext.toJson(),
        original.evidenceContext.toJson(),
      );
      expect(retried.event?.toJson(), original.event?.toJson());
    });

    test(
      'orphan is fenced and restored close is owned before emergency retry',
      () async {
        final owner = await owners.getOrCreateActiveOwner();
        final repository = DriftLearningRepository(database);
        await repository.startSession(
          LearningSessionDraft(
            id: 'session:orphan-matching',
            ownerId: owner.id,
            activityType: MatchingModeAdapter.activityType,
            startedAtUtc: DateTime.utc(2026, 8, 25, 12),
            appVersion: 'test',
            buildId: 'f10-test',
          ),
        );
        final restartRepository = _RestartRecoveryRepository(
          repository,
          finishFailuresRemaining: 1,
        );
        final restartLearning = LearningUseCases(
          owners: owners,
          repository: restartRepository,
          generateId: () => 'close-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 14, 0, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final evidence = CurrentActivityEvidenceAdapter(
          learning: restartLearning,
        );
        final prepared = await adapter.prepareSession(
          learning: restartLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        expect(prepared.session.id, isNot('session:orphan-matching'));
        final orphan =
            await (database.select(database.learningSessions)
                  ..where((row) => row.id.equals('session:orphan-matching')))
                .getSingle();
        expect(orphan.state, 'abandoned');
        final first = adapter.createReview(
          session: prepared.session,
          learning: restartLearning,
          evidence: evidence,
          recovery: prepared,
        );
        await expectLater(first.timeout(), throwsStateError);
        final closeAtUtc = restartRepository.closes.single.endedAtUtc;
        first.dispose();

        final recovered = await adapter.prepareSession(
          learning: restartLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        PendingLearningSessionClose? retirementClose;
        Future<void> Function()? retirementPreparation;
        final restarted = adapter.createReview(
          session: recovered.session,
          learning: restartLearning,
          evidence: evidence,
          recovery: recovered,
          ownClose: (close, ensureDurable) {
            retirementClose = close;
            retirementPreparation = ensureDurable;
          },
        );
        addTearDown(restarted.dispose);
        expect(restarted.phase, MatchingReviewPhase.completionRetryRequired);
        expect(retirementClose, same(recovered.pendingClose));
        expect(retirementPreparation, isNotNull);

        await retirementPreparation!();
        final owned = retirementClose!;
        final emergencySummary = await (owned.requiresRetry
            ? owned.retry()
            : owned.finish());

        expect(emergencySummary.id, recovered.session.id);
        expect(emergencySummary.state, 'completed');
        expect(restartRepository.closes, hasLength(2));
        expect(restartRepository.closes.last.endedAtUtc, closeAtUtc);
      },
    );

    test(
      'reconstructed active board closes only its original owner after switch',
      () async {
        final originalOwner = await owners.getOrCreateActiveOwner();
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
        );
        final recoveryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'owner-recovery-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 14, 30, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final evidence = CurrentActivityEvidenceAdapter(
          learning: recoveryLearning,
        );
        final prepared = await adapter.prepareSession(
          learning: recoveryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final recovered = await adapter.prepareSession(
          learning: recoveryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        expect(recovered.session.id, prepared.session.id);

        await database.transaction(() async {
          await (database.update(database.localOwners)
                ..where((row) => row.id.equals(originalOwner.id)))
              .write(const LocalOwnersCompanion(isActive: Value(false)));
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'matching-next-owner',
                  createdAtUtcMs: DateTime.utc(
                    2026,
                    8,
                    25,
                    14,
                    31,
                  ).millisecondsSinceEpoch,
                ),
              );
        });

        final review = adapter.createReview(
          session: recovered.session,
          learning: recoveryLearning,
          evidence: evidence,
          recovery: recovered,
        );
        addTearDown(review.dispose);
        final summary = await review.timeout();

        expect(summary.ownerId, originalOwner.id);
        expect(repository.closes, hasLength(1));
        expect(repository.closes.single.ownerId, originalOwner.id);
        final originalSession = await (database.select(
          database.learningSessions,
        )..where((row) => row.id.equals(prepared.session.id))).getSingle();
        expect(originalSession.state, 'completed');
        expect(
          await (database.select(
            database.learningSessions,
          )..where((row) => row.ownerId.equals('matching-next-owner'))).get(),
          isEmpty,
        );
      },
    );

    test(
      'restored pending close retry remains pinned across an owner switch',
      () async {
        final originalOwner = await owners.getOrCreateActiveOwner();
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
          finishFailuresRemaining: 1,
        );
        final recoveryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'owner-close-recovery-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 14, 45, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final evidence = CurrentActivityEvidenceAdapter(
          learning: recoveryLearning,
        );
        final prepared = await adapter.prepareSession(
          learning: recoveryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final first = adapter.createReview(
          session: prepared.session,
          learning: recoveryLearning,
          evidence: evidence,
          recovery: prepared,
        );
        await expectLater(first.timeout(), throwsStateError);
        first.dispose();

        final recovered = await adapter.prepareSession(
          learning: recoveryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        expect(recovered.pendingClose, isNotNull);
        await database.transaction(() async {
          await (database.update(database.localOwners)
                ..where((row) => row.id.equals(originalOwner.id)))
              .write(const LocalOwnersCompanion(isActive: Value(false)));
          await database
              .into(database.localOwners)
              .insert(
                LocalOwnersCompanion.insert(
                  id: 'matching-retry-next-owner',
                  createdAtUtcMs: DateTime.utc(
                    2026,
                    8,
                    25,
                    14,
                    46,
                  ).millisecondsSinceEpoch,
                ),
              );
        });

        final restarted = adapter.createReview(
          session: recovered.session,
          learning: recoveryLearning,
          evidence: evidence,
          recovery: recovered,
        );
        addTearDown(restarted.dispose);
        final summary = await restarted.retryCompletion();

        expect(summary.ownerId, originalOwner.id);
        expect(repository.closes, hasLength(2));
        expect(
          repository.closes.map((close) => close.ownerId),
          everyElement(originalOwner.id),
        );
        final originalSession = await (database.select(
          database.learningSessions,
        )..where((row) => row.id.equals(prepared.session.id))).getSingle();
        expect(originalSession.state, 'completed');
        expect(
          await (database.select(database.learningSessions)..where(
                (row) => row.ownerId.equals('matching-retry-next-owner'),
              ))
              .get(),
          isEmpty,
        );
      },
    );

    test(
      'checkpoint-less recovery abandons its pinned owner across a load race',
      () async {
        final originalOwner = await owners.getOrCreateActiveOwner();
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
        );
        await repository.delegate.startSession(
          LearningSessionDraft(
            id: 'matching-checkpointless-owner-race',
            ownerId: originalOwner.id,
            activityType: MatchingModeAdapter.activityType,
            startedAtUtc: DateTime.utc(2026, 8, 25, 14, 50),
            appVersion: 'test',
            buildId: 'f10-test',
          ),
        );
        repository.afterRecoveryLoad = (recovery) async {
          expect(recovery?.session.id, 'matching-checkpointless-owner-race');
          await database.transaction(() async {
            await (database.update(database.localOwners)
                  ..where((row) => row.id.equals(originalOwner.id)))
                .write(const LocalOwnersCompanion(isActive: Value(false)));
            await database
                .into(database.localOwners)
                .insert(
                  LocalOwnersCompanion.insert(
                    id: 'matching-checkpointless-next-owner',
                    createdAtUtcMs: DateTime.utc(
                      2026,
                      8,
                      25,
                      14,
                      51,
                    ).millisecondsSinceEpoch,
                  ),
                );
            await database
                .into(database.learningSessions)
                .insert(
                  LearningSessionsCompanion.insert(
                    id: 'matching-checkpointless-next-active',
                    ownerId: 'matching-checkpointless-next-owner',
                    activityType: 'quiz',
                    state: 'active',
                    startedAtUtcMs: DateTime.utc(
                      2026,
                      8,
                      25,
                      14,
                      51,
                    ).millisecondsSinceEpoch,
                    appVersion: 'test',
                    buildId: 'next-owner',
                  ),
                );
          });
        };
        final recoveryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'checkpointless-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 14, 52, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );

        final prepared = await adapter.prepareSession(
          learning: recoveryLearning,
          evidence: CurrentActivityEvidenceAdapter(learning: recoveryLearning),
          categoryId: 'category:travel',
        );

        expect(prepared.session.isEmpty, isTrue);
        final sessions = await database.select(database.learningSessions).get();
        expect(
          sessions
              .singleWhere(
                (row) => row.id == 'matching-checkpointless-owner-race',
              )
              .state,
          'abandoned',
        );
        expect(
          sessions
              .singleWhere(
                (row) => row.id == 'matching-checkpointless-next-active',
              )
              .state,
          'active',
        );
      },
    );

    test(
      'fresh checkpointed session reload remains scoped across owner switch',
      () async {
        final originalOwner = await owners.getOrCreateActiveOwner();
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
        );
        repository.afterCheckpointedStart = () async {
          await database.transaction(() async {
            await (database.update(database.localOwners)
                  ..where((row) => row.id.equals(originalOwner.id)))
                .write(const LocalOwnersCompanion(isActive: Value(false)));
            await database
                .into(database.localOwners)
                .insert(
                  LocalOwnersCompanion.insert(
                    id: 'matching-reload-next-owner',
                    createdAtUtcMs: DateTime.utc(
                      2026,
                      8,
                      25,
                      14,
                      56,
                    ).millisecondsSinceEpoch,
                  ),
                );
            await database
                .into(database.learningSessions)
                .insert(
                  LearningSessionsCompanion.insert(
                    id: 'matching-reload-next-active',
                    ownerId: 'matching-reload-next-owner',
                    activityType: 'quiz',
                    state: 'active',
                    startedAtUtcMs: DateTime.utc(
                      2026,
                      8,
                      25,
                      14,
                      56,
                    ).millisecondsSinceEpoch,
                    appVersion: 'test',
                    buildId: 'next-owner',
                  ),
                );
          });
        };
        final recoveryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'reload-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 14, 55, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final evidence = CurrentActivityEvidenceAdapter(
          learning: recoveryLearning,
        );

        final prepared = await adapter.prepareSession(
          learning: recoveryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        expect(prepared.session.ownerId, originalOwner.id);
        final review = adapter.createReview(
          session: prepared.session,
          learning: recoveryLearning,
          evidence: evidence,
          recovery: prepared,
        );
        addTearDown(review.dispose);
        final summary = await review.timeout();

        expect(summary.ownerId, originalOwner.id);
        final sessions = await database.select(database.learningSessions).get();
        expect(
          sessions.singleWhere((row) => row.id == prepared.session.id).state,
          'completed',
        );
        expect(
          sessions
              .singleWhere((row) => row.id == 'matching-reload-next-active')
              .state,
          'active',
        );
      },
    );

    test(
      'process restart reconciles a post-commit close acknowledgement loss',
      () async {
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
          finishFailure: _FinishFailure.afterWrite,
        );
        final restartLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'close-ack-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 15, 0, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final evidence = CurrentActivityEvidenceAdapter(
          learning: restartLearning,
        );
        final prepared = await adapter.prepareSession(
          learning: restartLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final first = adapter.createReview(
          session: prepared.session,
          learning: restartLearning,
          evidence: evidence,
          recovery: prepared,
        );
        await expectLater(first.timeout(), throwsStateError);
        first.dispose();
        final committed =
            (await database.select(database.learningSessions).get()).single;
        expect(committed.state, 'completed');
        final exactCloseAt = DateTime.fromMillisecondsSinceEpoch(
          committed.endedAtUtcMs!,
          isUtc: true,
        );
        await expectLater(
          repository.delegate.finishSession(
            ownerId: committed.ownerId,
            sessionId: committed.id,
            endedAtUtc: exactCloseAt.add(const Duration(seconds: 1)),
          ),
          throwsStateError,
        );

        final reconstructedLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'must-not-open-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 16, 0, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        repository
          ..checkpointFailure = _CheckpointFailure.afterWrite
          ..checkpointFailureRevision = 3;
        final reconstructed = await adapter.prepareSession(
          learning: reconstructedLearning,
          evidence: CurrentActivityEvidenceAdapter(
            learning: reconstructedLearning,
          ),
          categoryId: 'category:travel',
        );
        final recoveredSummary = await reconstructed.reconcileCompleted(
          completeSession: (close) => close.finish(),
        );

        expect(reconstructed.session.id, prepared.session.id);
        expect(recoveredSummary.endedAtUtc, exactCloseAt);
        expect(
          await database.select(database.learningSessions).get(),
          hasLength(1),
        );
        expect(repository.closes, hasLength(2));
        final acknowledged =
            (await (database.select(database.eventsV2)..where(
                      (row) =>
                          row.eventType.equals('LearningActivityCheckpoint'),
                    ))
                    .get())
                .map(
                  (row) => jsonDecode(row.payloadJson) as Map<String, dynamic>,
                )
                .where((payload) => payload['terminalAcknowledged'] == true)
                .toList(growable: false);
        expect(acknowledged, hasLength(1));

        final afterCrash = await adapter.prepareSession(
          learning: reconstructedLearning,
          evidence: CurrentActivityEvidenceAdapter(
            learning: reconstructedLearning,
          ),
          categoryId: 'category:travel',
        );
        expect(afterCrash.session.id, prepared.session.id);
        expect(afterCrash.completedSummary?.endedAtUtc, exactCloseAt);
        await afterCrash.reconcileCompleted(
          completeSession: (close) => close.finish(),
        );
        await afterCrash.markSummaryPresented(afterCrash.completedSummary!);

        final subsequent = await adapter.prepareSession(
          learning: reconstructedLearning,
          evidence: CurrentActivityEvidenceAdapter(
            learning: reconstructedLearning,
          ),
          categoryId: 'category:travel',
        );
        expect(subsequent.session.id, isNot(prepared.session.id));
        expect(subsequent.completedSummary, isNull);
        expect(
          await database.select(database.learningSessions).get(),
          hasLength(2),
        );
      },
    );

    test(
      'live summary receipt prevents replay and terminal writes stay in budget',
      () async {
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        final prepared = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final review = adapter.createReview(
          session: prepared.session,
          learning: learning,
          evidence: evidence,
          recovery: prepared,
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);
        final wordId = review.pairSet.pairs.first.word.id;
        final wrongMeaningId = review.pairSet.pairs
            .firstWhere((pair) => pair.word.id != wordId)
            .word
            .id;

        for (
          var attempt = 1;
          attempt <= MatchingModeAdapter.maximumAttempts;
          attempt += 1
        ) {
          await review.selectWord(wordId, responseTimeMs: attempt * 10);
          await review.selectMeaning(
            wrongMeaningId,
            responseTimeMs: attempt * 10 + 1,
          );
        }

        expect(review.timeoutRequested, isTrue);
        expect(
          () => review.selectWord(wordId, responseTimeMs: 999),
          throwsStateError,
        );
        final summary = await review.timeout();
        await prepared.markSummaryPresented(summary);

        final checkpoints =
            await (database.select(database.eventsV2)
                  ..where(
                    (row) => row.eventType.equals('LearningActivityCheckpoint'),
                  )
                  ..where((row) => row.aggregateId.equals(prepared.session.id)))
                .get();
        expect(checkpoints, hasLength(MatchingModeAdapter.maximumCheckpoints));
        expect(
          checkpoints
              .map(
                (row) =>
                    (jsonDecode(row.payloadJson)
                            as Map<String, dynamic>)['revision']
                        as int,
              )
              .reduce((left, right) => left > right ? left : right),
          MatchingModeAdapter.maximumCheckpoints,
        );
        final attempts = await (database.select(
          database.answerAttempts,
        )..where((row) => row.sessionId.equals(prepared.session.id))).get();
        expect(attempts, hasLength(MatchingModeAdapter.maximumAttempts));

        final repository = DriftLearningRepository(database);
        final owner = await owners.getOrCreateActiveOwner();
        await expectLater(
          repository.appendActivityCheckpoint(
            ownerId: owner.id,
            checkpoint: LearningActivityCheckpoint(
              sessionId: prepared.session.id,
              activityType: MatchingModeAdapter.activityType,
              revision: MatchingModeAdapter.maximumCheckpoints + 1,
              occurredAtUtc: DateTime.utc(2026, 8, 25, 19),
              state: const <String, Object?>{'overBudget': true},
              terminalAtUtc: summary.endedAtUtc,
              terminalAcknowledged: true,
            ),
          ),
          throwsRangeError,
        );

        final next = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        expect(next.session.id, isNot(prepared.session.id));
        expect(next.completedSummary, isNull);
      },
    );

    test('restart recovery and duplicate timeout are bounded', () async {
      final prepared = await adapter.prepareSession(
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        categoryId: 'category:travel',
      );
      final session = prepared.session;
      final first = adapter.createReview(
        session: session,
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        recovery: prepared,
        hintUsage: () => const HintUsageSnapshot.known(0),
      );
      final pair = first.pairSet.pairs.first;
      await first.selectWord(pair.word.id, responseTimeMs: 100);
      await first.selectMeaning(pair.word.id, responseTimeMs: 200);
      first.dispose();

      final recovered = await adapter.prepareSession(
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        categoryId: 'category:travel',
      );
      final restarted = adapter.createReview(
        session: recovered.session,
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        recovery: recovered,
        hintUsage: () => const HintUsageSnapshot.known(0),
      );
      addTearDown(restarted.dispose);
      expect(restarted.matchedWordIds, <String>{pair.word.id});
      expect(restarted.remainingPairCount, restarted.pairSet.pairs.length - 1);

      final firstTimeout = restarted.timeout();
      final duplicateTimeout = restarted.timeout();
      expect(duplicateTimeout, same(firstTimeout));
      final summary = await firstTimeout;
      expect(summary.state, 'completed');
      expect(restarted.phase, MatchingReviewPhase.completed);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      final sessions = await database.select(database.learningSessions).get();
      expect(sessions.single.state, 'completed');
    });

    test(
      'late timeout admission cannot mutate matching after retirement',
      () async {
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        final prepared = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        var recoveryAccepting = false;
        final review = adapter.createReview(
          session: prepared.session,
          learning: learning,
          evidence: evidence,
          recovery: prepared,
          runRecoveryOperation: <T>(operation) {
            if (!recoveryAccepting) {
              return Future<T>.error(StateError('retired'));
            }
            return operation();
          },
        );
        addTearDown(review.dispose);

        await expectLater(review.timeout(), throwsStateError);
        expect(review.timeoutRequested, isFalse);
        expect(review.phase, MatchingReviewPhase.awaitingSelection);

        recoveryAccepting = true;
        final summary = await review.timeout();
        expect(summary.state, 'completed');
      },
    );

    test(
      'repeated reconstruction cannot extend the absolute timeout',
      () async {
        var clock = DateTime.utc(2026, 8, 25, 17);
        final timedLearning = LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(database),
          generateId: () => 'timed-${++generatedId}',
          nowUtc: () => clock,
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        CurrentActivityEvidenceAdapter evidence() =>
            CurrentActivityEvidenceAdapter(learning: timedLearning);
        final first = await adapter.prepareSession(
          learning: timedLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
          timeLimit: const Duration(minutes: 2),
        );
        final deadline = DateTime.utc(2026, 8, 25, 17, 2);
        expect(first.timeoutDeadlineUtc, deadline);

        clock = DateTime.utc(2026, 8, 25, 17, 1);
        final second = await adapter.prepareSession(
          learning: timedLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
          timeLimit: const Duration(minutes: 20),
        );
        expect(second.timeoutDeadlineUtc, deadline);
        expect(second.remainingTime(clock), const Duration(minutes: 1));
        expect(
          () => second.remainingTime(
            first.session.startedAtUtc!.subtract(const Duration(seconds: 1)),
          ),
          throwsStateError,
        );

        clock = DateTime.utc(2026, 8, 25, 17, 3);
        final third = await adapter.prepareSession(
          learning: timedLearning,
          evidence: evidence(),
          categoryId: 'category:travel',
        );
        expect(third.timeoutDeadlineUtc, deadline);
        expect(third.remainingTime(clock), Duration.zero);
        expect(
          await database.select(database.learningSessions).get(),
          hasLength(1),
        );
      },
    );

    test(
      'untimed alternative persists no wall-clock deadline across idle restart',
      () async {
        var clock = DateTime.utc(2026, 8, 25, 17);
        final untimedLearning = LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(database),
          generateId: () => 'untimed-${++generatedId}',
          nowUtc: () => clock,
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f16-test'),
        );
        final evidence = CurrentActivityEvidenceAdapter(
          learning: untimedLearning,
        );
        final first = await adapter.prepareSession(
          learning: untimedLearning,
          evidence: evidence,
          categoryId: 'category:travel',
          timeLimit: null,
        );

        expect(first.hasWallClockTimeout, isFalse);
        expect(first.timeoutAnchorUtc, isNull);
        expect(first.timeoutDeadlineUtc, isNull);
        expect(first.remainingTime(clock), isNull);

        clock = clock.add(const Duration(days: 30));
        final restarted = await adapter.prepareSession(
          learning: untimedLearning,
          evidence: evidence,
          categoryId: 'category:travel',
          timeLimit: null,
        );
        expect(restarted.session.id, first.session.id);
        expect(restarted.hasWallClockTimeout, isFalse);
        expect(restarted.remainingTime(clock), isNull);

        final checkpointRows =
            await (database.select(database.eventsV2)..where(
                  (event) =>
                      event.eventType.equals('LearningActivityCheckpoint'),
                ))
                .get();
        final latest = checkpointRows.last;
        final payload = jsonDecode(latest.payloadJson) as Map<String, dynamic>;
        final state = payload['state'] as Map<String, dynamic>;
        expect(state['timingKind'], 'activeEffort');
        expect(state['timeoutAnchorUtc'], isNull);
        expect(state['timeoutDurationMs'], isNull);
        expect(state['timeoutDeadlineUtc'], isNull);
      },
    );

    test(
      'checkpoint v1 bootstrap derives the original bounded deadline',
      () async {
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        final prepared = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
          timeLimit: const Duration(minutes: 2),
        );
        final row =
            (await (database.select(database.eventsV2)..where(
                      (event) =>
                          event.eventType.equals('LearningActivityCheckpoint'),
                    ))
                    .get())
                .single;
        final payload = (jsonDecode(row.payloadJson) as Map<String, dynamic>);
        final state = (payload['state'] as Map<String, dynamic>);
        state
          ..['schemaVersion'] = 1
          ..remove('timeoutDeadlineUtc')
          ..remove('timeoutAnchorUtc')
          ..remove('timeoutDurationMs')
          ..remove('timingKind')
          ..remove('summaryPresented');
        payload
          ..['schemaVersion'] = 1
          ..remove('terminalAtUtc')
          ..remove('terminalAcknowledged');
        await (database.update(
          database.eventsV2,
        )..where((event) => event.eventId.equals(row.eventId))).write(
          EventsV2Companion(
            eventVersion: const Value(1),
            payloadJson: Value(jsonEncode(payload)),
          ),
        );

        final recovered = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
          timeLimit: const Duration(minutes: 20),
        );
        expect(recovered.session.id, prepared.session.id);
        expect(
          recovered.timeoutDeadlineUtc,
          prepared.session.startedAtUtc!.add(const Duration(minutes: 2)),
        );
        final afterUpgrade = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
          timeLimit: const Duration(minutes: 20),
        );
        expect(afterUpgrade.timeoutDeadlineUtc, recovered.timeoutDeadlineUtc);
      },
    );

    test(
      'timezone-less timeout payload fails closed before conversion',
      () async {
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final row =
            (await (database.select(database.eventsV2)..where(
                      (event) =>
                          event.eventType.equals('LearningActivityCheckpoint'),
                    ))
                    .get())
                .single;
        final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
        final state = payload['state'] as Map<String, dynamic>;
        final deadline = DateTime.parse(state['timeoutDeadlineUtc'] as String);
        state['timeoutDeadlineUtc'] =
            '${deadline.add(const Duration(hours: 7)).toIso8601String().replaceFirst('Z', '')}+07:00';
        await (database.update(database.eventsV2)
              ..where((event) => event.eventId.equals(row.eventId)))
            .write(EventsV2Companion(payloadJson: Value(jsonEncode(payload))));

        await expectLater(
          adapter.prepareSession(
            learning: learning,
            evidence: evidence,
            categoryId: 'category:travel',
          ),
          throwsStateError,
        );
      },
    );

    test(
      'pending occurrence requires canonical UTC encoding on recovery',
      () async {
        final repository = _RestartRecoveryRepository(
          DriftLearningRepository(database),
          recordFailure: _RecordFailure.beforeWrite,
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'pending-utc-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 17, 30, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final evidence = CurrentActivityEvidenceAdapter(
          learning: retryLearning,
        );
        final prepared = await adapter.prepareSession(
          learning: retryLearning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final review = adapter.createReview(
          session: prepared.session,
          learning: retryLearning,
          evidence: evidence,
          recovery: prepared,
        );
        final pair = review.pairSet.pairs.first;
        await review.selectWord(pair.word.id, responseTimeMs: 100);
        await expectLater(
          review.selectMeaning(pair.word.id, responseTimeMs: 200),
          throwsStateError,
        );
        review.dispose();

        final rows =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventType.equals('LearningActivityCheckpoint'),
                ))
                .get();
        final row = rows.singleWhere((candidate) {
          final payload =
              jsonDecode(candidate.payloadJson) as Map<String, dynamic>;
          return payload['revision'] == 2;
        });
        final payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
        final state = payload['state'] as Map<String, dynamic>;
        final pending = state['pendingEvidence'] as Map<String, dynamic>;
        final occurredAt = DateTime.parse(pending['occurredAtUtc'] as String);
        pending['occurredAtUtc'] =
            '${occurredAt.add(const Duration(hours: 7)).toIso8601String().replaceFirst('Z', '')}+07:00';
        await (database.update(database.eventsV2)
              ..where((candidate) => candidate.eventId.equals(row.eventId)))
            .write(EventsV2Companion(payloadJson: Value(jsonEncode(payload))));

        await expectLater(
          adapter.prepareSession(
            learning: retryLearning,
            evidence: evidence,
            categoryId: 'category:travel',
          ),
          throwsStateError,
        );
      },
    );

    test(
      'generic checkpoints fail closed for owner, bounds, and collisions',
      () async {
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        final prepared = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final owner = await owners.getOrCreateActiveOwner();
        final repository = DriftLearningRepository(database);
        final recovery = await repository.loadLatestActivityRecovery(
          ownerId: owner.id,
          activityType: MatchingModeAdapter.activityType,
        );
        final checkpoint = recovery!.checkpoint!;
        expect(
          await repository.loadLatestActivityRecovery(
            ownerId: 'different-owner',
            activityType: MatchingModeAdapter.activityType,
          ),
          isNull,
        );
        await expectLater(
          repository.appendActivityCheckpoint(
            ownerId: 'different-owner',
            checkpoint: LearningActivityCheckpoint(
              sessionId: prepared.session.id,
              activityType: MatchingModeAdapter.activityType,
              revision: checkpoint.revision + 1,
              occurredAtUtc: DateTime.utc(2026, 8, 25, 18),
              state: const <String, Object?>{'owner': 'forged'},
            ),
          ),
          throwsStateError,
        );
        expect(
          () => repository.appendActivityCheckpoint(
            ownerId: owner.id,
            checkpoint: LearningActivityCheckpoint(
              sessionId: prepared.session.id,
              activityType: MatchingModeAdapter.activityType,
              revision: checkpoint.revision + 1,
              occurredAtUtc: DateTime.utc(2026, 8, 25, 18),
              state: <String, Object?>{'oversized': 'x' * 65537},
            ),
          ),
          throwsArgumentError,
        );
        expect(
          () => repository.appendActivityCheckpoint(
            ownerId: owner.id,
            checkpoint: LearningActivityCheckpoint(
              sessionId: prepared.session.id,
              activityType: MatchingModeAdapter.activityType,
              revision: checkpoint.revision + 1,
              occurredAtUtc: DateTime.utc(2026, 8, 25, 18),
              state: <String, Object?>{'oversizedUtf8': 'ก' * 30000},
            ),
          ),
          throwsArgumentError,
        );
        final accepted = LearningActivityCheckpoint(
          sessionId: prepared.session.id,
          activityType: MatchingModeAdapter.activityType,
          revision: checkpoint.revision + 1,
          occurredAtUtc: DateTime.utc(2026, 8, 25, 18),
          state: const <String, Object?>{'identity': 'accepted'},
        );
        await repository.appendActivityCheckpoint(
          ownerId: owner.id,
          checkpoint: accepted,
        );
        await expectLater(
          repository.appendActivityCheckpoint(
            ownerId: owner.id,
            checkpoint: LearningActivityCheckpoint(
              sessionId: accepted.sessionId,
              activityType: accepted.activityType,
              revision: accepted.revision,
              occurredAtUtc: accepted.occurredAtUtc,
              state: const <String, Object?>{'identity': 'collision'},
            ),
          ),
          throwsStateError,
        );

        final collisionStartedAt = DateTime.utc(2026, 8, 25, 18, 30);
        await repository.startSession(
          LearningSessionDraft(
            id: 'session:checkpoint-bootstrap-collision',
            ownerId: owner.id,
            activityType: MatchingModeAdapter.activityType,
            startedAtUtc: collisionStartedAt,
            appVersion: 'test',
            buildId: 'f10-test',
          ),
        );
        await expectLater(
          repository.startSessionWithCheckpoint(
            session: LearningSessionDraft(
              id: 'session:checkpoint-bootstrap-collision',
              ownerId: owner.id,
              activityType: MatchingModeAdapter.activityType,
              startedAtUtc: collisionStartedAt.add(const Duration(seconds: 1)),
              appVersion: 'different',
              buildId: 'different',
            ),
            checkpoint: LearningActivityCheckpoint(
              sessionId: 'session:checkpoint-bootstrap-collision',
              activityType: MatchingModeAdapter.activityType,
              revision: 1,
              occurredAtUtc: collisionStartedAt.add(const Duration(seconds: 1)),
              state: const <String, Object?>{'identity': 'collision'},
            ),
          ),
          throwsStateError,
        );
      },
    );

    test(
      'checkpoint collision validates every envelope column and freezes state',
      () async {
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        final prepared = await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        final owner = await owners.getOrCreateActiveOwner();
        final repository = DriftLearningRepository(database);
        final recovery = (await repository.loadLatestActivityRecovery(
          ownerId: owner.id,
          activityType: MatchingModeAdapter.activityType,
        ))!;
        final checkpoint = recovery.checkpoint!;
        await database.customInsert(
          'INSERT INTO local_owners '
          '(id, account_state, created_at_utc_ms, is_active) '
          "VALUES ('wrong-owner', 'guest', 3, 0)",
        );
        final checkpointRow =
            (await (database.select(database.eventsV2)
                      ..where(
                        (event) =>
                            event.aggregateId.equals(prepared.session.id),
                      )
                      ..where(
                        (event) => event.eventType.equals(
                          'LearningActivityCheckpoint',
                        ),
                      ))
                    .get())
                .single;
        final corruptions = <EventsV2Companion>[
          const EventsV2Companion(ownerId: Value('wrong-owner')),
          const EventsV2Companion(eventType: Value('WrongCheckpoint')),
          const EventsV2Companion(aggregateType: Value('WrongAggregate')),
          const EventsV2Companion(aggregateId: Value('wrong-session')),
          const EventsV2Companion(actorIdentity: Value('wrong-actor')),
          const EventsV2Companion(buildId: Value('wrong-build')),
        ];
        for (final corruption in corruptions) {
          await (database.update(database.eventsV2)
                ..where((event) => event.eventId.equals(checkpointRow.eventId)))
              .write(corruption);
          await expectLater(
            repository.appendActivityCheckpoint(
              ownerId: owner.id,
              checkpoint: checkpoint,
            ),
            throwsStateError,
          );
          await (database.update(database.eventsV2)
                ..where((event) => event.eventId.equals(checkpointRow.eventId)))
              .write(
                EventsV2Companion(
                  eventType: Value(checkpointRow.eventType),
                  actorIdentity: Value(checkpointRow.actorIdentity),
                  ownerId: Value(checkpointRow.ownerId),
                  aggregateType: Value(checkpointRow.aggregateType),
                  aggregateId: Value(checkpointRow.aggregateId),
                  buildId: Value(checkpointRow.buildId),
                ),
              );
        }

        final nested = <String, Object?>{'value': 'original'};
        final append = repository.appendActivityCheckpoint(
          ownerId: owner.id,
          checkpoint: LearningActivityCheckpoint(
            sessionId: prepared.session.id,
            activityType: MatchingModeAdapter.activityType,
            revision: checkpoint.revision + 1,
            occurredAtUtc: DateTime.utc(2026, 8, 25, 18, 45),
            state: <String, Object?>{'nested': nested},
          ),
        );
        nested['value'] = 'mutated-after-call';
        await append;
        final restored = (await repository.loadLatestActivityRecovery(
          ownerId: owner.id,
          activityType: MatchingModeAdapter.activityType,
        ))!;
        final restoredNested =
            restored.checkpoint!.state['nested']! as Map<String, Object?>;
        expect(restoredNested['value'], 'original');
        expect(
          () => restoredNested['value'] = 'mutable',
          throwsUnsupportedError,
        );
      },
    );

    test('checkpoint recovery revalidates revision and UTF-8 bounds', () async {
      final evidence = CurrentActivityEvidenceAdapter(learning: learning);
      await adapter.prepareSession(
        learning: learning,
        evidence: evidence,
        categoryId: 'category:travel',
      );
      final row =
          (await (database.select(database.eventsV2)..where(
                    (event) =>
                        event.eventType.equals('LearningActivityCheckpoint'),
                  ))
                  .get())
              .single;
      final originalPayload = row.payloadJson;

      Future<void> expectRecoveryRejects(
        void Function(Map<String, dynamic> payload) corrupt,
      ) async {
        final payload = jsonDecode(originalPayload) as Map<String, dynamic>;
        corrupt(payload);
        await (database.update(database.eventsV2)
              ..where((event) => event.eventId.equals(row.eventId)))
            .write(EventsV2Companion(payloadJson: Value(jsonEncode(payload))));
        await expectLater(
          adapter.prepareSession(
            learning: learning,
            evidence: evidence,
            categoryId: 'category:travel',
          ),
          throwsStateError,
        );
        await (database.update(database.eventsV2)
              ..where((event) => event.eventId.equals(row.eventId)))
            .write(EventsV2Companion(payloadJson: Value(originalPayload)));
      }

      await expectRecoveryRejects((payload) => payload['revision'] = 0);
      await expectRecoveryRejects(
        (payload) =>
            payload['state'] = <String, Object?>{'oversizedUtf8': 'ก' * 30000},
      );
    });

    test('checkpoint recovery rejects max plus one matching rows', () async {
      await adapter.prepareSession(
        learning: learning,
        evidence: CurrentActivityEvidenceAdapter(learning: learning),
        categoryId: 'category:travel',
      );
      final checkpointRow =
          (await (database.select(database.eventsV2)..where(
                    (row) => row.eventType.equals('LearningActivityCheckpoint'),
                  ))
                  .get())
              .single;
      for (
        var index = 1;
        index <= DriftLearningRepository.maxActivityRecoveryCheckpoints;
        index += 1
      ) {
        final eventId = 'learning-activity-checkpoint:overflow-$index';
        await database
            .into(database.eventsV2)
            .insert(
              checkpointRow
                  .toCompanion(true)
                  .copyWith(
                    eventId: Value(eventId),
                    idempotencyKey: Value(eventId),
                  ),
            );
      }

      await expectLater(
        adapter.prepareSession(
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          categoryId: 'category:travel',
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('checkpoint recovery bound'),
          ),
        ),
      );
    });

    test(
      'attempt recovery rejects max plus one rows before event reads',
      () async {
        final prepared = await adapter.prepareSession(
          learning: learning,
          evidence: CurrentActivityEvidenceAdapter(learning: learning),
          categoryId: 'category:travel',
        );
        final owner = await owners.getOrCreateActiveOwner();
        final wordId = prepared.session.questions.first.word.id;
        for (
          var index = 0;
          index <= DriftLearningRepository.maxActivityRecoveryAttempts;
          index += 1
        ) {
          await database
              .into(database.answerAttempts)
              .insert(
                AnswerAttemptsCompanion.insert(
                  id: 'overflow-attempt-$index',
                  ownerId: owner.id,
                  sessionId: prepared.session.id,
                  wordId: wordId,
                  promptMode: 'matchingPair',
                  isCorrect: false,
                  attemptNumber: index + 1,
                  occurredAtUtcMs: DateTime.utc(
                    2026,
                    8,
                    25,
                    19,
                    0,
                    index,
                  ).millisecondsSinceEpoch,
                ),
              );
        }

        await expectLater(
          adapter.prepareSession(
            learning: learning,
            evidence: CurrentActivityEvidenceAdapter(learning: learning),
            categoryId: 'category:travel',
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('attempt recovery bound'),
            ),
          ),
        );
      },
    );

    test('checkpoint corruption rejects unrelated actor provenance', () async {
      final evidence = CurrentActivityEvidenceAdapter(learning: learning);
      await adapter.prepareSession(
        learning: learning,
        evidence: evidence,
        categoryId: 'category:travel',
      );
      await database
          .update(database.eventsV2)
          .write(
            const EventsV2Companion(actorIdentity: Value('unrelated-owner')),
          );

      await expectLater(
        adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
        ),
        throwsStateError,
      );
    });

    test(
      'checkpoint corruption rejects mutated immutable envelope metadata',
      () async {
        final evidence = CurrentActivityEvidenceAdapter(learning: learning);
        await adapter.prepareSession(
          learning: learning,
          evidence: evidence,
          categoryId: 'category:travel',
        );
        await database
            .update(database.eventsV2)
            .write(const EventsV2Companion(appVersion: Value('mutated')));

        await expectLater(
          adapter.prepareSession(
            learning: learning,
            evidence: evidence,
            categoryId: 'category:travel',
          ),
          throwsStateError,
        );
      },
    );

    test(
      'timeout waits an accepted lost-ack match then closes after exact retry',
      () async {
        final repository = _LostAckLearningRepository(
          DriftLearningRepository(database),
        );
        final retryLearning = LearningUseCases(
          owners: owners,
          repository: repository,
          generateId: () => 'timeout-retry-${++generatedId}',
          nowUtc: () => DateTime.utc(2026, 8, 25, 12, 0, generatedId),
          buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
        );
        final session = await retryLearning.startQuiz(
          categoryId: 'category:travel',
        );
        final review = adapter.createReview(
          session: session,
          learning: retryLearning,
          evidence: CurrentActivityEvidenceAdapter(learning: retryLearning),
          hintUsage: () => const HintUsageSnapshot.known(0),
        );
        addTearDown(review.dispose);
        final pair = review.pairSet.pairs.first;
        await review.selectWord(pair.word.id, responseTimeMs: 100);
        review.selectMeaning(pair.word.id, responseTimeMs: 200);

        await expectLater(review.timeout(), throwsStateError);
        expect(review.phase, MatchingReviewPhase.evidenceRetryRequired);
        expect(review.timeoutRequested, isTrue);
        await review.retryEvidence();
        final summary = await review.timeout();

        expect(summary.state, 'completed');
        expect(repository.commands, hasLength(2));
        expect(repository.commands.last.id, repository.commands.first.id);
        expect(
          await database.select(database.answerAttempts).get(),
          hasLength(1),
        );
      },
    );

    test('lost completion acknowledgement retries the frozen close', () async {
      final repository = _LostAckFinishLearningRepository(
        DriftLearningRepository(database),
      );
      final retryLearning = LearningUseCases(
        owners: owners,
        repository: repository,
        generateId: () => 'finish-retry-${++generatedId}',
        nowUtc: () => DateTime.utc(2026, 8, 25, 13, 0, generatedId),
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'f10-test'),
      );
      final session = await retryLearning.startQuiz(
        categoryId: 'category:travel',
      );
      final review = adapter.createReview(
        session: session,
        learning: retryLearning,
        evidence: CurrentActivityEvidenceAdapter(learning: retryLearning),
        hintUsage: () => const HintUsageSnapshot.known(0),
      );
      addTearDown(review.dispose);

      await expectLater(review.timeout(), throwsStateError);
      expect(review.phase, MatchingReviewPhase.completionRetryRequired);
      final summary = await review.retryCompletion();

      expect(summary.state, 'completed');
      expect(repository.closes, hasLength(2));
      expect(repository.closes.last, repository.closes.first);
      final sessions = await database.select(database.learningSessions).get();
      expect(sessions, hasLength(1));
      expect(sessions.single.state, 'completed');
    });
  });
}

Future<void> _setCanonicalCoreIdentities(
  AppDatabase database, {
  required int revision,
}) async {
  final words = await database.select(database.vocabularyWords).get();
  for (final word in words) {
    final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
      categoryId: word.categoryId,
      spelling: word.spelling,
      normalizedSpelling: word.normalizedSpelling,
      meaning: word.meaning,
      normalizedMeaning: word.normalizedMeaning,
      partOfSpeech: word.partOfSpeech,
      cefrLevel: word.cefrLevel,
      source: word.source,
      isGlobal: word.isGlobal,
    );
    await (database.update(
      database.vocabularyWords,
    )..where((candidate) => candidate.id.equals(word.id))).write(
      VocabularyWordsCompanion(
        contentRevision: Value(revision),
        contentChecksumSha256: Value(checksum),
      ),
    );
  }
}

String _matchingRevision(int revision, String coreChecksumSha256) =>
    LexicalPromptArtifactResolver.formatEvidenceContentRevision(
      promptMode: 'matchingPair',
      wordId: 'ignored-by-matching-format',
      revision: revision,
      checksumSha256:
          LexicalPromptArtifactResolver.canonicalPromptChecksumSha256(
            promptMode: 'matchingPair',
            coreChecksumSha256: coreChecksumSha256,
          ),
    );

QuizSession _session(List<QuizWord> words) => QuizSession(
  id: 'session:matching',
  startedAtUtc: DateTime.utc(2026, 8, 25, 9),
  questions: words
      .map((word) => QuizQuestion(word: word, options: const <String>[]))
      .toList(growable: false),
);

QuizWord _word(String id, String spelling, String meaning) => QuizWord(
  id: 'word:$id',
  categoryId: 'category:travel',
  spelling: spelling,
  normalizedSpelling: normalizeVocabularyText(spelling),
  meaning: meaning,
  normalizedMeaning: normalizeVocabularyText(meaning),
  partOfSpeech: 'noun',
);

EvidenceContext _context(String json) => EvidenceContext.fromJson(
  (jsonDecode(json) as Map<Object?, Object?>).cast<String, Object?>(),
);

({
  List<vocabulary_domain.VocabularyWord> words,
  Map<ContentIdentity, VerifiedContentManifest> artifacts,
})
_matchingLexicalArtifacts(QuizSession session) {
  final words = <vocabulary_domain.VocabularyWord>[];
  final artifacts = <ContentIdentity, VerifiedContentManifest>{};
  for (final question in session.questions) {
    final word = question.word;
    final revision = word.contentRevision!;
    final identity = ContentIdentity(
      type: ContentType.lexicalMetadata,
      id: word.id,
      revision: revision,
    );
    final distractors = <String, String>{
      for (final candidate in session.questions)
        if (candidate.word.id != word.id)
          candidate.word.id: 'Why ${candidate.word.spelling} is not the match.',
    };
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'schemaVersion': 4,
          'wordId': word.id,
          'contentRevision': revision,
          'englishDefinition': word.meaning,
          'ipa': null,
          'examples': <String>[],
          'synonyms': <String>[],
          'antonyms': <String>[],
          'acceptedSpellingVariants': <String>[],
          'audio': null,
          'contrastiveFeedback': <String, Object?>{
            'matchingPair': <String, Object?>{
              'correctOptionId': word.id,
              'correctRationale': '${word.spelling} is the exact match.',
              'distractorRationales': distractors,
            },
          },
        }),
      ),
    );
    final checksum = sha256.convert(bytes).toString();
    final rich = vocabulary_domain.RichLexicalMetadata.fromVerifiedArtifact(
      bytes: bytes,
      wordId: word.id,
      contentRevision: revision,
      verifiedArtifactChecksumSha256: checksum,
    );
    words.add(
      vocabulary_domain.VocabularyWord(
        id: word.id,
        ownerId: 'matching-owner',
        categoryId: word.categoryId,
        spelling: word.spelling,
        normalizedSpelling: word.normalizedSpelling!,
        meaning: word.meaning,
        normalizedMeaning: word.normalizedMeaning!,
        partOfSpeech: word.partOfSpeech,
        source: 'pack:f18',
        isGlobal: true,
        localRevision: 1,
        isDeleted: false,
        createdAtUtc: DateTime.utc(2026, 8, 1),
        updatedAtUtc: DateTime.utc(2026, 8, 1),
        contentRevision: revision,
        contentChecksumSha256: word.contentChecksumSha256,
        contentProvenance: ContentProvenance.packaged,
        contentReviewState: ContentReviewState.approved,
        contentPublicationState: ContentPublicationState.published,
        richMetadata: rich,
      ),
    );
    artifacts[identity] = VerifiedContentManifest(
      manifest: ContentManifest(
        storageId: 'manifest:${word.id}:$revision',
        identity: identity,
        checksumSha256: checksum,
        byteLength: bytes.length,
        provenance: ContentProvenance.packaged,
        sourceUri: 'asset://lexical/${word.id}.json',
        reviewState: ContentReviewState.approved,
        publicationState: ContentPublicationState.published,
        createdAtUtc: DateTime.utc(2026, 8, 1),
        reviewedAtUtc: DateTime.utc(2026, 8, 2),
        publishedAtUtc: DateTime.utc(2026, 8, 3),
      ),
      bytes: bytes,
    );
  }
  return (words: words, artifacts: artifacts);
}

final class _MatchingManifestRepository implements ContentManifestRepository {
  const _MatchingManifestRepository(this.artifacts);

  final Map<ContentIdentity, VerifiedContentManifest> artifacts;

  @override
  Future<VerifiedContentManifest> requireVerified(
    ContentIdentity identity,
  ) async {
    final artifact = artifacts[identity];
    if (artifact == null) {
      throw StateError('missing matching lexical artifact');
    }
    return artifact;
  }
}

Future<Map<String, Object?>> _projectionSnapshot(AppDatabase database) async =>
    <String, Object?>{
      'srs': (await database.select(database.srsStates).get())
          .map((row) => row.toJson())
          .toList(growable: false),
      'assessment': (await database.select(database.assessmentRuns).get())
          .map((row) => row.toJson())
          .toList(growable: false),
      'quest': (await database.select(database.questInstances).get())
          .map((row) => row.toJson())
          .toList(growable: false),
      'questObjectives':
          (await database.select(database.questObjectiveProgress).get())
              .map((row) => row.toJson())
              .toList(growable: false),
      'streak': (await database.select(database.streakStates).get())
          .map((row) => row.toJson())
          .toList(growable: false),
      'learningDays': (await database.select(database.learningDayLog).get())
          .map((row) => row.toJson())
          .toList(growable: false),
      'achievements': (await database.select(database.achievementUnlocks).get())
          .map((row) => row.toJson())
          .toList(growable: false),
      'xp': (await database.select(database.pointsLedgerEntries).get())
          .map((row) => row.toJson())
          .toList(growable: false),
      'coins': (await database.select(database.rewardTransactions).get())
          .map((row) => row.toJson())
          .toList(growable: false),
    };

final class _MutableRolloutProvider
    implements EvidencePolicyRolloutModeProvider {
  EvidencePolicyRolloutMode mode = EvidencePolicyRolloutMode.legacy;
  int calls = 0;

  @override
  Future<EvidencePolicyRolloutMode> resolve({
    required String ownerId,
    required EvidenceContext? evidenceContext,
  }) async {
    calls += 1;
    return mode;
  }
}

final class _MutableResearchProvider
    implements CurrentActivityResearchStateProvider {
  int calls = 0;
  bool fail = false;

  @override
  Future<CurrentActivityResearchSnapshot> resolveActivity({
    required String ownerId,
    required CurrentActivityInput input,
    required DateTime occurredAtUtc,
    required EvidencePolicyRolloutMode rolloutMode,
  }) async {
    calls += 1;
    if (fail) throw StateError('mutable research provider must not be reread');
    return const CurrentActivityResearchSnapshot.legacyCompatibility();
  }

  @override
  Future<LearningEventContext> resolve({
    required String ownerId,
    required EvidenceContext evidenceContext,
    required DateTime occurredAtUtc,
  }) => const BaselineLearningEventContextProvider().resolve(
    ownerId: ownerId,
    evidenceContext: evidenceContext,
    occurredAtUtc: occurredAtUtc,
  );
}

final class _LostAckLearningRepository implements LearningRepository {
  _LostAckLearningRepository(this.delegate);

  final LearningRepository delegate;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  bool _lostAcknowledgement = false;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    limit: limit,
  );

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) => delegate.finishSession(
    ownerId: ownerId,
    sessionId: sessionId,
    endedAtUtc: endedAtUtc,
  );

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    final result = await delegate.recordAnswer(command);
    if (!_lostAcknowledgement) {
      _lostAcknowledgement = true;
      throw StateError('simulated acknowledgement loss');
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LostAckFinishLearningRepository implements LearningRepository {
  _LostAckFinishLearningRepository(this.delegate);

  final LearningRepository delegate;
  final List<({String ownerId, String sessionId, DateTime endedAtUtc})> closes =
      <({String ownerId, String sessionId, DateTime endedAtUtc})>[];
  bool _lostAcknowledgement = false;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    limit: limit,
  );

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    closes.add((
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    ));
    final result = await delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
    if (!_lostAcknowledgement) {
      _lostAcknowledgement = true;
      throw StateError('simulated finish acknowledgement loss');
    }
    return result;
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) =>
      delegate.recordAnswer(command);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

enum _RecordFailure { none, beforeWrite, afterWrite }

enum _FinishFailure { none, afterWrite }

enum _CheckpointFailure { none, beforeWrite, afterWrite }

final class _RestartRecoveryRepository
    implements
        LearningRepository,
        LearningEvidenceReplayRepository,
        LearningSessionLifecycleRepository,
        LearningActivityRecoveryRepository {
  _RestartRecoveryRepository(
    this.delegate, {
    this.recordFailure = _RecordFailure.none,
    this.finishFailuresRemaining = 0,
    this.finishFailure = _FinishFailure.none,
  }) : checkpointFailure = _CheckpointFailure.none;

  final DriftLearningRepository delegate;
  _RecordFailure recordFailure;
  int finishFailuresRemaining;
  _FinishFailure finishFailure;
  _CheckpointFailure checkpointFailure;
  int? checkpointFailureRevision;
  LearningActivityRecovery Function(LearningActivityRecovery recovery)?
  recoveryTransform;
  Future<void> Function(LearningActivityRecovery? recovery)? afterRecoveryLoad;
  Future<void> Function()? afterCheckpointedStart;
  final List<RecordAnswerCommand> commands = <RecordAnswerCommand>[];
  final List<({String ownerId, String sessionId, DateTime endedAtUtc})> closes =
      <({String ownerId, String sessionId, DateTime endedAtUtc})>[];

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    limit: limit,
  );

  @override
  Future<void> startSession(LearningSessionDraft session) =>
      delegate.startSession(session);

  @override
  Future<void> startSessionWithCheckpoint({
    required LearningSessionDraft session,
    required LearningActivityCheckpoint checkpoint,
  }) async {
    await delegate.startSessionWithCheckpoint(
      session: session,
      checkpoint: checkpoint,
    );
    final after = afterCheckpointedStart;
    afterCheckpointedStart = null;
    await after?.call();
  }

  @override
  Future<LearningActivityRecovery?> loadLatestActivityRecovery({
    required String ownerId,
    required String activityType,
  }) async {
    final recovery = await delegate.loadLatestActivityRecovery(
      ownerId: ownerId,
      activityType: activityType,
    );
    final after = afterRecoveryLoad;
    afterRecoveryLoad = null;
    await after?.call(recovery);
    if (recovery == null) return null;
    return recoveryTransform?.call(recovery) ?? recovery;
  }

  @override
  Future<void> appendActivityCheckpoint({
    required String ownerId,
    required LearningActivityCheckpoint checkpoint,
  }) async {
    final failsThisRevision =
        checkpointFailureRevision == null ||
        checkpointFailureRevision == checkpoint.revision;
    if (failsThisRevision &&
        checkpointFailure == _CheckpointFailure.beforeWrite) {
      checkpointFailure = _CheckpointFailure.none;
      checkpointFailureRevision = null;
      throw StateError('simulated pre-write checkpoint failure');
    }
    await delegate.appendActivityCheckpoint(
      ownerId: ownerId,
      checkpoint: checkpoint,
    );
    if (failsThisRevision &&
        checkpointFailure == _CheckpointFailure.afterWrite) {
      checkpointFailure = _CheckpointFailure.none;
      checkpointFailureRevision = null;
      throw StateError('simulated checkpoint acknowledgement loss');
    }
  }

  @override
  Future<CommittedAnswerReplay?> replayCommittedAnswer(
    RecordAnswerCandidate candidate,
  ) => delegate.replayCommittedAnswer(candidate);

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) async {
    commands.add(command);
    if (recordFailure == _RecordFailure.beforeWrite) {
      recordFailure = _RecordFailure.none;
      throw StateError('simulated pre-write failure');
    }
    final result = await delegate.recordAnswer(command);
    if (recordFailure == _RecordFailure.afterWrite) {
      recordFailure = _RecordFailure.none;
      throw StateError('simulated lost acknowledgement');
    }
    return result;
  }

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) async {
    closes.add((
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    ));
    if (finishFailuresRemaining > 0) {
      finishFailuresRemaining -= 1;
      throw StateError('simulated pre-write close failure');
    }
    final result = await delegate.finishSession(
      ownerId: ownerId,
      sessionId: sessionId,
      endedAtUtc: endedAtUtc,
    );
    if (finishFailure == _FinishFailure.afterWrite) {
      finishFailure = _FinishFailure.none;
      throw StateError('simulated post-write close acknowledgement loss');
    }
    return result;
  }

  @override
  Future<LearningSessionSummary> abandonSession({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) => delegate.abandonSession(
    ownerId: ownerId,
    sessionId: sessionId,
    abandonedAtUtc: abandonedAtUtc,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
