import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/content_provider.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';
import '../../support/sentence_scramble_native_harness.dart'
    show SyntheticSentenceScrambleProvider;

void main() {
  late Directory directory;
  late ConfiguredQuizHarness storage;
  var nextId = 0;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'lexiquest-native-durable-resume-',
    );
    storage = await ConfiguredQuizHarness.open(
      file: File('${directory.path}/native.sqlite'),
    );
    nextId = 0;
  });
  tearDown(() async {
    await storage.close();
    await directory.delete(recursive: true);
  });

  LearningUseCases useCases({ContentProvider? provider}) => LearningUseCases(
    owners: storage.owners,
    repository: DriftLearningRepository(
      storage.database,
      ownerWrites: storage.ownerWrites,
    ),
    generateId: () => 'synthetic-native-resume-${++nextId}',
    nowUtc: () => storage.now,
    buildInfo: const AppBuildInfo(
      version: '1.0.0',
      buildId: 'synthetic-native-resume',
    ),
    contentProvider: provider,
  );

  test(
    'file restart resumes the exact admitted sentence without AI or read writes',
    () async {
      final source = SyntheticSentenceScrambleProvider(storage.database)
        ..response = (request) => ContentResponse(
          text: 'We visit the ${request.text} today.',
          kind: ContentKind.sentence,
          cefr: CefrLevel.b2,
          language: 'en',
          modelVersion: 'synthetic-provider/retained opaque revision7',
          cached: true,
        );
      final first = useCases(provider: source);
      final prepared = (await first.prepareSentenceScramble(
        categoryId: configuredCategoryId,
        stillCurrent: () => true,
      ))!;
      final original = await first.startNativeExercise(
        prepared,
        stillCurrent: () => true,
      );
      expect(source.requests, hasLength(1));
      final before = await storage.snapshot();
      storage = await storage.reopen();
      storage.now = storage.now.add(const Duration(hours: 17));
      final blockedProvider = _RejectRegeneration();
      final restarted = useCases(provider: blockedProvider);

      final state = await restarted.resumeNativeExercise(
        sessionId: original.id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );

      expect(state.phase, NativeCheckpointPhase.awaitingAnswer);
      final resumed = state.exercise as SentenceScrambleSession;
      expect(resumed.id, original.id);
      expect(resumed.ownerId, configuredOwnerId);
      expect(resumed.startedAtUtc, configuredStart);
      expect(_word(resumed.word), _word(original.word));
      expect(resumed.content.sentence, original.content.sentence);
      expect(resumed.content.tokens, original.content.tokens);
      expect(resumed.content.tokenOrder, original.content.tokenOrder);
      expect(resumed.content.cefr, CefrLevel.b2);
      expect(resumed.content.language, 'en');
      expect(
        resumed.content.modelVersion,
        'synthetic-provider/retained opaque revision7',
      );
      expect(resumed.content.cached, isTrue);
      expect(resumed.providerProvenance, original.providerProvenance);
      expect(resumed.evidenceContentRevision, original.evidenceContentRevision);
      expect(blockedProvider.calls, 0);
      expect(await storage.snapshot(), before);
      final row = await storage.session(original.id);
      expect(row['accepted_plan_id'], startsWith('native-plan-v1:'));
      expect(row['accepted_plan_json'], isNotNull);
      expect(row['checkpoint_json'], isNotNull);
      expect(state.checkpointRevision, row['checkpoint_revision']);

      final answer = restarted.prepareNativeAnswer(
        SentenceScrambleAnswerInput(
          exercise: resumed,
          response: resumed.content.sentence,
          responseTime: const Duration(milliseconds: 1234),
        ),
      );
      expect(
        (await restarted.commitNativeAnswer(
          resumed,
          answer,
          stillCurrent: () => true,
        )).inserted,
        isTrue,
      );
      final closed = await restarted.finishNativeExercise(
        restarted.prepareNativeFinish(resumed, answer),
        stillCurrent: () => true,
      );
      expect(
        (closed.id, closed.state, closed.correctCount, closed.wrongCount),
        (original.id, 'completed', 1, 0),
      );
      final attempt = await storage.database
          .select(storage.database.answerAttempts)
          .getSingle();
      expect(attempt.id, answer.id);
      expect(attempt.responseTimeMs, 1234);
      expect(attempt.occurredAtUtcMs, storage.now.millisecondsSinceEpoch);
      expect(attempt.providerProvenance, original.providerProvenance);
      final claims = await DriftSyncStore(storage.database).claimPending(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        limit: 10,
        leaseToken: 'synthetic-native-resume-lease',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: storage.now,
      );
      expect(claims, hasLength(1));
      final mutation = claims.single.mutation;
      expect(mutation.collection, SyncCollection.attempts);
      expect(mutation.payloadVersion, 2);
      expect(mutation.payload.keys.toSet(), {
        'sessionId',
        'wordId',
        'promptMode',
        'isCorrect',
        'responseTimeMs',
        'attemptNumber',
        'occurredAtUtcMs',
        'providerProvenance',
        'evidenceClass',
        'evidenceContext',
      });
      expect(
        jsonEncode(mutation.payload),
        isNot(contains(resumed.content.sentence)),
      );
      expect(await storage.count('learning_sessions'), 1);
      expect(await storage.count('answer_attempts'), 1);
      expect(await storage.count('learning_time_segments'), 0);
      expect(
        (await storage.researchCounts()).values.every((value) => value == 0),
        isTrue,
      );
    },
  );

  test(
    'file restart resumes the original Dictation target and start',
    () async {
      final first = useCases();
      final original = await first.startNativeExercise(
        (await first.prepareDictation(
          categoryId: configuredCategoryId,
          stillCurrent: () => true,
        ))!,
        stillCurrent: () => true,
      );
      final before = await storage.snapshot();
      storage = await storage.reopen();
      storage.now = storage.now.add(const Duration(hours: 17));
      final state = await useCases().resumeNativeExercise(
        sessionId: original.id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(state.phase, NativeCheckpointPhase.awaitingAnswer);
      final resumed = state.exercise as DictationSession;
      expect(resumed.id, original.id);
      expect(resumed.ownerId, configuredOwnerId);
      expect(resumed.startedAtUtc, configuredStart);
      expect(_word(resumed.word), _word(original.word));
      expect(resumed.wordContentRevision, original.wordContentRevision);
      expect(resumed.evidenceContentRevision, original.evidenceContentRevision);
      expect(await storage.snapshot(), before);
    },
  );

  test('restart still rejects copied and raw native write handles', () async {
    final first = useCases();
    final original = await first.startNativeExercise(
      (await first.prepareDictation(
        categoryId: configuredCategoryId,
        stillCurrent: () => true,
      ))!,
      stillCurrent: () => true,
    );
    final copied = DictationSession(
      session: original.session,
      word: original.word,
    );
    final command = first.prepareNativeAnswer(
      DictationAnswerInput(
        exercise: original,
        response: original.word.spelling,
        assisted: false,
        responseTime: const Duration(milliseconds: 1234),
      ),
    );
    storage = await storage.reopen();
    final restarted = useCases();
    final repository = restarted.repository as DriftLearningRepository;
    final before = await storage.snapshot();
    for (final unissued in [original, copied]) {
      await expectLater(
        repository.startNativeExercise(unissued, stillCurrent: () => true),
        throwsStateError,
      );
      await expectLater(
        repository.commitNativeAnswer(
          unissued,
          command,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
    }
    await expectLater(
      repository.startSession(original.session),
      throwsStateError,
    );
    await expectLater(repository.recordAnswer(command), throwsStateError);
    await expectLater(
      repository.finishSession(
        ownerId: configuredOwnerId,
        sessionId: original.id,
        endedAtUtc: storage.now,
      ),
      throwsStateError,
    );
    await expectLater(
      restarted.resumeNativeExercise(
        sessionId: '${DictationSession.idPrefix}synthetic-missing',
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      ),
      throwsStateError,
    );
    expect(await storage.snapshot(), before);
  });
}

List<Object?> _word(QuizWord word) => [
  word.id,
  word.categoryId,
  word.spelling,
  word.meaning,
  word.partOfSpeech,
  word.contentRevision,
];

final class _RejectRegeneration implements ContentProvider {
  int calls = 0;

  @override
  Future<ContentResponse> generate(ContentRequest request) async {
    calls++;
    throw StateError('Resume must not regenerate admitted teaching content');
  }
}
