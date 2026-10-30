import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

import '../../support/word_scramble_session_harness.dart';

void main() {
  late WordScrambleSessionHarness h;
  setUp(() async => h = await WordScrambleSessionHarness.open());
  tearDown(() => h.close());

  test(
    'prepare captures actual owned category and writes no durable fact',
    () async {
      final before = await h.storage.snapshot();
      final exercise = (await h.prepare())!;
      expect(exercise.ownerId, configuredOwnerId);
      expect(exercise.word.categoryId, configuredCategoryId);
      expect(exercise.wordContentRevision, 'local-vocabulary-v1:1');
      expect(exercise.session.activityType, 'wordScramble');
      expect(exercise.startedAtUtc, h.now);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'skips unchanged permutations but never falls back to another category',
    () async {
      await h.database.customStatement(
        "UPDATE vocabulary_words SET spelling = 'aaa' WHERE id = ?",
        [configuredWordIds.first],
      );
      final exercise = (await h.prepare())!;
      expect(exercise.word.id, isNot(configuredWordIds.first));
      expect(exercise.letters.join(), isNot(exercise.word.spelling));
      await h.database.customStatement(
        "UPDATE vocabulary_words SET spelling = 'a' WHERE owner_id = ?",
        [configuredOwnerId],
      );
      final before = await h.storage.snapshot();
      expect(await h.prepare(), isNull);
      expect(await h.prepare(categoryId: configuredOtherCategoryId), isNull);
      expect(await h.storage.snapshot(), before);
    },
  );

  test('finds a playable owned target after an unsupported first page', () async {
    for (var index = 0; index < 100; index++) {
      await h.storage.addWord(
        id: 'aaa-scramble-${index.toString().padLeft(3, '0')}',
        spelling: 'synthetic phrase $index',
        meaning: 'Synthetic multiword fixture',
      );
    }
    final firstPage = await h.repository.listQuizWords(
      ownerId: configuredOwnerId,
      categoryId: configuredCategoryId,
      limit: 100,
    );
    expect(firstPage, hasLength(100));
    expect(firstPage.any(WordScrambleSession.supportsTarget), isFalse);
    final before = await h.storage.snapshot();
    final exercise = await h.prepare();
    expect(exercise, isNotNull);
    expect(exercise!.word.id, configuredWordIds.first);
    expect(await h.storage.snapshot(), before);
  });

  test(
    'deleted owned category is unavailable without session allocation',
    () async {
      await h.database.customStatement(
        'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
        [configuredCategoryId],
      );
      final before = await h.storage.snapshot();
      expect(await h.prepare(), isNull);
      expect(await h.storage.snapshot(), before);
    },
  );

  for (final change in ['owner', 'current']) {
    test('final awaited owner read refuses changed $change', () async {
      final probe = _AfterVocabularyRead(() async {
        if (change == 'owner') {
          await h.storage.switchOwner(configuredOtherOwnerId);
        } else {
          h.current = false;
        }
      });
      await expectLater(
        h.database.runWithInterceptor(() => h.prepare(), interceptor: probe),
        throwsStateError,
      );
      expect(probe.fired, isTrue);
      expect(await h.storage.count('learning_sessions'), 0);
      expect(await h.storage.count('answer_attempts'), 0);
    });
  }

  for (final correct in [false, true]) {
    test(
      'answer derives $correct result with declared recreational evidence',
      () async {
        final exercise = (await h.prepare())!;
        final answer = h.answer(exercise, correct: correct);
        expect(answer.isCorrect, correct);
        expect(answer.promptMode, 'wordScramble');
        expect(answer.providerProvenance, isNull);
        expect(
          answer.evidenceContext.evidenceClass,
          EvidenceClass.recreational,
        );
        expect(answer.evidenceContext.skillId, 'word-scramble');
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
    'clock rollback creates neither poisoned answer nor finish identity',
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
      final closed = await h.learning.finishNativeExercise(
        h.learning.prepareNativeFinish(exercise, answer),
        stillCurrent: () => true,
      );
      expect(closed.state, 'completed');
    },
  );
}

final class _AfterVocabularyRead extends drift.QueryInterceptor {
  _AfterVocabularyRead(this.afterRead);
  final Future<void> Function() afterRead;
  bool fired = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    if (!fired && statement.toLowerCase().contains('from "vocabulary_words"')) {
      fired = true;
      await afterRead();
    }
    return result;
  }
}
