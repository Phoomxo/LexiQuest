import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';

import '../../support/sentence_scramble_native_harness.dart';

void main() {
  late SentenceScrambleNativeHarness h;
  setUp(() async => h = await SentenceScrambleNativeHarness.open());
  tearDown(() => h.close());

  test(
    'missing provider returns unavailable without a request or durable fact',
    () async {
      final before = await h.storage.snapshot();
      expect(
        await h
            .useCases(withProvider: false)
            .prepareSentenceScramble(
              categoryId: configuredCategoryId,
              stillCurrent: () => true,
            ),
        isNull,
      );
      expect(h.provider.requests, isEmpty);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'one actual request uses owned anchor outside TX and retains actual metadata',
    () async {
      h.provider.response = (request) => _generated(
        'We visit the ${request.text} today.',
        cefr: CefrLevel.b2,
        model: 'synthetic-provider/opaque revision7',
        cached: true,
      );
      final before = await h.storage.snapshot();
      final exercise = (await h.prepare())!;
      expect(exercise.ownerId, configuredOwnerId);
      expect(exercise.word.categoryId, configuredCategoryId);
      expect(exercise.wordContentRevision, 'local-vocabulary-v1:1');
      expect(exercise.session.activityType, 'sentenceScramble');
      expect(exercise.startedAtUtc, h.now);
      expect(h.provider.requests, hasLength(1));
      expect(h.provider.requests.single.text, exercise.word.spelling);
      expect(h.provider.requests.single.kind, ContentKind.sentence);
      expect(h.provider.requests.single.language, 'en');
      expect(h.provider.transactionStates, [false]);
      expect(
        exercise.content.sentence,
        'We visit the ${exercise.word.spelling} today.',
      );
      expect(exercise.content.cefr, CefrLevel.b2);
      expect(
        exercise.content.modelVersion,
        'synthetic-provider/opaque revision7',
      );
      expect(exercise.content.cached, isTrue);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'unsupported first page is skipped before the single provider request',
    () async {
      for (var i = 0; i < 100; i++) {
        await h.storage.addWord(
          id: 'aaa-sentence-${i.toString().padLeft(3, '0')}',
          spelling: 'unsupported phrase $i',
          meaning: 'Synthetic unsupported seed',
        );
      }
      final first = await h.repository.listQuizWords(
        ownerId: configuredOwnerId,
        categoryId: configuredCategoryId,
        limit: 100,
      );
      expect(first, hasLength(100));
      final before = await h.storage.snapshot();
      final exercise = (await h.prepare())!;
      expect(exercise.word.id, configuredWordIds.first);
      expect(h.provider.requests, hasLength(1));
      expect(h.provider.requests.single.text, exercise.word.spelling);
      expect(await h.storage.snapshot(), before);
    },
  );

  for (final category in ['deleted', 'foreign']) {
    test(
      '$category selected category never falls back to another category',
      () async {
        if (category == 'deleted') {
          await h.database.customStatement(
            'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
            [configuredCategoryId],
          );
        }
        final before = await h.storage.snapshot();
        expect(
          await h.prepare(
            categoryId: category == 'foreign'
                ? configuredOtherCategoryId
                : configuredCategoryId,
          ),
          isNull,
        );
        expect(h.provider.requests, isEmpty);
        expect(await h.storage.snapshot(), before);
      },
    );
  }

  test('no supported owned anchor sends no generation request', () async {
    await h.database.customStatement(
      "UPDATE vocabulary_words SET spelling = 'two words' WHERE owner_id = ?",
      [configuredOwnerId],
    );
    final before = await h.storage.snapshot();
    expect(await h.prepare(), isNull);
    expect(h.provider.requests, isEmpty);
    expect(await h.storage.snapshot(), before);
  });

  test(
    'invalid first response does not generate for later eligible words',
    () async {
      h.provider.response = (request) => _generated(request.text);
      final before = await h.storage.snapshot();
      expect(await h.prepare(), isNull);
      expect(h.provider.requests, hasLength(1));
      expect(h.provider.requests.single.text, 'station');
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'repeated whole anchor is a playable sentence without a unique-gap rule',
    () async {
      h.provider.response = (request) =>
          _generated('${request.text} is ${request.text}.');
      final exercise = (await h.prepare())!;
      expect(exercise.content.sentence, 'station is station.');
      expect(h.provider.requests, hasLength(1));
      expect(h.answer(exercise).isCorrect, isTrue);
    },
  );

  test(
    'provider failure has one request and no fallback or durable write',
    () async {
      h.provider.beforeResponse = (_) async {
        throw const AiFailure(
          category: AiFailureCategory.network,
          message: 'synthetic offline',
        );
      };
      final before = await h.storage.snapshot();
      await expectLater(h.prepare(), throwsA(isA<AiFailure>()));
      expect(h.provider.requests, hasLength(1));
      expect(await h.storage.snapshot(), before);
    },
  );

  test('inherited transaction denies before generation', () async {
    final before = await h.storage.snapshot();
    await h.database.transaction(() async {
      await expectLater(h.prepare(), throwsStateError);
    });
    expect(h.provider.requests, isEmpty);
    expect(await h.storage.snapshot(), before);
  });

  test('initial hidden launch performs no generation or persistence', () async {
    h.current = false;
    final before = await h.storage.snapshot();
    await expectLater(h.prepare(), throwsStateError);
    expect(h.provider.requests, isEmpty);
    expect(await h.storage.snapshot(), before);
  });

  for (final change in ['owner', 'current']) {
    test('$change lost during provider await denies the stale draft', () async {
      final entered = Completer<void>();
      final release = Completer<void>();
      h.provider.beforeResponse = (_) async {
        entered.complete();
        await release.future;
      };
      final pending = h.prepare();
      final rejected = expectLater(pending, throwsStateError);
      await entered.future;
      if (change == 'owner') {
        await h.storage.switchOwner(configuredOtherOwnerId);
      } else {
        h.current = false;
      }
      release.complete();
      await rejected;
      expect(h.provider.requests, hasLength(1));
      expect(await h.storage.count('learning_sessions'), 0);
      expect(await h.storage.count('answer_attempts'), 0);
      expect(await h.storage.count('outbox_operations'), 0);
    });
  }

  for (final mutation in ['revision', 'category']) {
    test(
      '$mutation changed during generation cannot be accepted by the writer',
      () async {
        h.provider.beforeResponse = (_) async {
          if (mutation == 'revision') {
            await h.database.customStatement(
              'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
              [configuredWordIds.first],
            );
          } else {
            await h.database.customStatement(
              'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
              [configuredCategoryId],
            );
          }
        };
        final exercise = (await h.prepare())!;
        final before = await h.storage.snapshot();
        await expectLater(
          h.learning.startNativeExercise(exercise, stillCurrent: () => true),
          throwsStateError,
        );
        expect(h.provider.requests, hasLength(1));
        expect(await h.storage.snapshot(), before);
        expect(await h.storage.count('learning_sessions'), 0);
      },
    );
  }

  for (final change in ['owner', 'current', 'unchanged']) {
    test(
      'final actual ambient probe rechecks $change before sending the anchor',
      () async {
        final repository = _ProbeBoundaryRepository(
          h.repository,
          afterSecondProbe: change == 'owner'
              ? () => h.storage.switchOwner(configuredOtherOwnerId)
              : change == 'current'
              ? () async {
                  h.current = false;
                }
              : null,
        );
        final learning = LearningUseCases(
          owners: h.storage.owners,
          repository: repository,
          generateId: h.learning.generateId,
          nowUtc: () => h.now,
          buildInfo: h.learning.buildInfo,
          contentProvider: h.provider,
        );
        final pending = learning.prepareSentenceScramble(
          categoryId: configuredCategoryId,
          stillCurrent: () => h.current,
        );
        if (change == 'unchanged') {
          expect(await pending, isNotNull);
          expect(h.provider.requests, hasLength(1));
          expect(h.provider.transactionStates, [false]);
        } else {
          await expectLater(pending, throwsStateError);
          expect(h.provider.requests, isEmpty);
          expect(h.provider.transactionStates, isEmpty);
        }
        expect(repository.observations, [false, false]);
        expect(await h.storage.count('learning_sessions'), 0);
        expect(await h.storage.count('answer_attempts'), 0);
      },
    );
  }

  for (final correct in [false, true]) {
    test(
      'whole-sentence $correct answer has declared recreational pins and actual provenance',
      () async {
        final exercise = (await h.prepare())!;
        final answer = h.answer(exercise, correct: correct);
        expect(answer.isCorrect, correct);
        expect(answer.promptMode, 'sentenceScramble');
        expect(answer.providerProvenance, exercise.providerProvenance);
        expect(
          answer.evidenceContext.evidenceClass,
          EvidenceClass.recreational,
        );
        expect(answer.evidenceContext.skillId, 'sentence-scramble');
        expect(answer.evidenceContext.hintLevel, 0);
        expect(answer.evidenceContext.engagementAllowed, isFalse);
        expect(
          answer.evidenceContext.classificationSource,
          EvidenceClassificationSource.declared,
        );
        expect(
          answer.evidenceContext.contentRevision,
          exercise.evidenceContentRevision,
        );
        expect(answer.responseTimeMs, 1234);
        expect(await h.storage.count('answer_attempts'), 0);
      },
    );
  }

  test(
    'full sentence response exceeds word120 and normalizes whitespace only',
    () async {
      h.provider.response = (request) =>
          _generated('${request.text} ${List.filled(40, 'word').join(' ')}.');
      final exercise = (await h.prepare())!;
      expect(exercise.content.sentence.length, greaterThan(120));
      final response = exercise.content.tokens.join('\u00a0\t');
      expect(h.answer(exercise, response: response).isCorrect, isTrue);
      expect(
        h.answer(exercise, response: response.toUpperCase()).isCorrect,
        isFalse,
      );
      expect(
        h.answer(exercise, response: exercise.word.spelling).isCorrect,
        isFalse,
      );
      expect(
        h
            .answer(
              exercise,
              response: exercise.content.sentence.replaceAll('.', ''),
            )
            .isCorrect,
        isFalse,
      );
    },
  );

  test(
    'clock rollback does not poison the original answer or finish identity',
    () async {
      final exercise = await h.ready();
      h.now = exercise.startedAtUtc.subtract(const Duration(milliseconds: 1));
      expect(() => h.answer(exercise), throwsStateError);
      h.now = exercise.startedAtUtc;
      final answer = h.answer(exercise);
      await h.learning.commitNativeAnswer(
        exercise,
        answer,
        stillCurrent: () => true,
      );
      h.now = exercise.startedAtUtc.subtract(const Duration(milliseconds: 1));
      expect(
        () => h.learning.prepareNativeFinish(exercise, answer),
        throwsStateError,
      );
      h.now = exercise.startedAtUtc;
      final summary = await h.learning.finishNativeExercise(
        h.learning.prepareNativeFinish(exercise, answer),
        stillCurrent: () => true,
      );
      expect(summary.state, 'completed');
    },
  );
}

ContentResponse _generated(
  String text, {
  CefrLevel cefr = CefrLevel.unknown,
  String model = 'synthetic-sentence-test',
  bool cached = false,
}) => ContentResponse(
  text: text,
  kind: ContentKind.sentence,
  cefr: cefr,
  language: 'en',
  modelVersion: model,
  cached: cached,
);

final class _ProbeBoundaryRepository extends Fake
    implements LearningRepository, NativeExerciseRepository {
  _ProbeBoundaryRepository(this.delegate, {this.afterSecondProbe});
  final DriftLearningRepository delegate;
  final Future<void> Function()? afterSecondProbe;
  final List<bool> observations = [];

  @override
  Future<bool> hasAmbientTransaction() async {
    final actual = await delegate.hasAmbientTransaction();
    observations.add(actual);
    if (observations.length == 2) await afterSecondProbe?.call();
    return actual;
  }

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    Iterable<String>? wordIds,
    String? afterWordId,
    required int limit,
  }) => delegate.listQuizWords(
    ownerId: ownerId,
    categoryId: categoryId,
    wordIds: wordIds,
    afterWordId: afterWordId,
    limit: limit,
  );
}
