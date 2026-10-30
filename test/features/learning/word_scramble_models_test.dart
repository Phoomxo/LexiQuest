import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/word_scramble_letters.dart';

void main() {
  const original = QuizWord(
    id: 'synthetic-word',
    categoryId: 'synthetic-category',
    spelling: 'learning',
    meaning: 'synthetic meaning',
    partOfSpeech: 'noun',
    contentRevision: 'local-vocabulary-v1:1',
  );
  QuizWord word({String? spelling, String? meaning, String? revision}) =>
      QuizWord(
        id: original.id,
        categoryId: original.categoryId,
        spelling: spelling ?? original.spelling,
        meaning: meaning ?? original.meaning,
        partOfSpeech: original.partOfSpeech,
        contentRevision: revision ?? original.contentRevision,
      );
  LearningSessionDraft draft({String? id, String activity = 'wordScramble'}) =>
      LearningSessionDraft(
        id: id ?? '${WordScrambleSession.idPrefix}synthetic',
        ownerId: 'synthetic-owner',
        activityType: activity,
        startedAtUtc: DateTime.utc(2026, 10, 30),
        appVersion: 'test',
        buildId: 'test',
      );

  for (final target in ['learning', 'abab', 'e\u0301a', '👩‍💻a']) {
    test('stable helper preserves exact grapheme multiset for $target', () {
      final first = createStableScramble(target);
      expect(first, createStableScramble(target));
      expect(first.join(), isNot(target));
      expect([...first]..sort(), target.characters.toList()..sort());
    });
  }

  test('legacy helper keeps its one-letter and identical-letter behavior', () {
    expect(createStableScramble('a'), ['a']);
    expect(createStableScramble('aaa'), ['a', 'a', 'a']);
  });

  test(
    'accepted bank is immutable and its exact snapshot has a separate pin',
    () {
      final exercise = WordScrambleSession(session: draft(), word: original);
      expect(exercise.letters, createStableScramble(original.spelling));
      expect(() => exercise.letters[0] = 'x', throwsUnsupportedError);
      expect(exercise.wordContentRevision, 'local-vocabulary-v1:1');
      expect(exercise.evidenceContentRevision, startsWith('word-scramble-v1:'));
      expect(
        exercise.evidenceContentRevision,
        isNot(exercise.wordContentRevision),
      );
      expect(
        WordScrambleSession(
          session: draft(),
          word: original,
        ).evidenceContentRevision,
        exercise.evidenceContentRevision,
      );
      for (final changed in [
        word(meaning: 'changed'),
        word(revision: 'local-vocabulary-v1:2'),
      ]) {
        expect(
          WordScrambleSession(
            session: draft(),
            word: changed,
          ).evidenceContentRevision,
          isNot(exercise.evidenceContentRevision),
        );
      }
    },
  );

  for (final target in [
    '',
    'a',
    'aaa',
    'two words',
    'bad\nword',
    List.filled(121, 'x').join(),
  ]) {
    test('unsupported target $target cannot create an accepted exercise', () {
      final candidate = word(spelling: target);
      expect(WordScrambleSession.supportsTarget(candidate), isFalse);
      expect(
        () => WordScrambleSession(session: draft(), word: candidate),
        throwsArgumentError,
      );
    });
  }

  test('invalid original session and SQL pin are rejected at construction', () {
    for (final session in [
      draft(id: 'ordinary-session'),
      draft(activity: 'quiz'),
    ]) {
      expect(
        () => WordScrambleSession(session: session, word: original),
        throwsArgumentError,
      );
    }
    for (final revision in [
      'local-vocabulary-v1:0',
      'local-vocabulary-v1:1suffix',
      'invented',
    ]) {
      expect(
        () => WordScrambleSession(
          session: draft(),
          word: word(revision: revision),
        ),
        throwsArgumentError,
      );
    }
  });
}
