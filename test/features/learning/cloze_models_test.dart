import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/features/learning/domain/cloze_content.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

void main() {
  final start = DateTime.utc(2026, 10, 30, 12);
  const word = QuizWord(
    id: 'word-a',
    categoryId: 'category-a',
    spelling: 'station',
    meaning: 'สถานี',
    partOfSpeech: 'noun',
    contentRevision: 'local-vocabulary-v1:7',
  );
  const other = QuizWord(
    id: 'word-b',
    categoryId: 'category-a',
    spelling: 'ticket',
    meaning: 'ตั๋ว',
    partOfSpeech: 'noun',
    contentRevision: 'local-vocabulary-v1:2',
  );
  const third = QuizWord(
    id: 'word-c',
    categoryId: 'category-a',
    spelling: 'platform',
    meaning: 'ชานชาลา',
    partOfSpeech: 'noun',
    contentRevision: 'local-vocabulary-v1:3',
  );
  LearningSessionDraft draft({
    String id = 'session:cloze-v1:synthetic',
    String activity = 'cloze',
  }) => LearningSessionDraft(
    id: id,
    ownerId: 'owner-a',
    activityType: activity,
    startedAtUtc: start,
    appVersion: 'test',
    buildId: 'test',
  );
  ClozeContent content({
    String text = 'We visit the station today.',
    String model = 'synthetic-model',
    CefrLevel cefr = CefrLevel.unknown,
    bool cached = false,
  }) => ClozeContent.parse(
    targetSpelling: 'station',
    response: ContentResponse(
      text: text,
      kind: ContentKind.sentence,
      cefr: cefr,
      language: 'en',
      modelVersion: model,
      cached: cached,
    ),
  );
  List<Object?> wordTuple(QuizWord value) => [
    value.id,
    value.categoryId,
    value.spelling,
    value.meaning,
    value.partOfSpeech,
    value.contentRevision,
  ];

  test(
    'typed content digest binds complete actual snapshot and bounded model provenance',
    () {
      final admitted = content();
      final exercise = TypedClozeSession(
        session: draft(),
        word: word,
        content: admitted,
      );
      final tuple = [
        'cloze-v1',
        'typed',
        wordTuple(word),
        [
          admitted.sentence,
          admitted.gapStart,
          admitted.gapEnd,
          admitted.kind.wire,
          admitted.cefr.wire,
          admitted.language,
          admitted.modelVersion,
          admitted.cached,
        ],
        <Object?>[],
      ];
      expect(
        exercise.evidenceContentRevision,
        'cloze-v1:${sha256.convert(utf8.encode(jsonEncode(tuple)))}',
      );
      expect(exercise.wordContentRevision, 'local-vocabulary-v1:7');
      expect(
        exercise.providerProvenance,
        'cloze-model-v1:${sha256.convert(utf8.encode('synthetic-model'))}',
      );
      expect(exercise.providerProvenance.length, lessThanOrEqualTo(120));
      expect(exercise.content.cefr, CefrLevel.unknown);
      expect(exercise.variant, ClozeVariant.typed);
    },
  );

  test('choice digest eagerly freezes ordered complete options and target', () {
    final supplied = [word, other, third];
    final exercise = ChoiceClozeSession(
      session: draft(),
      word: word,
      content: content(),
      choices: supplied,
    );
    final original = exercise.evidenceContentRevision;
    supplied[0] = third;
    supplied.clear();
    expect(exercise.choices, [word, other, third]);
    expect(() => exercise.choices.clear(), throwsUnsupportedError);
    expect(exercise.evidenceContentRevision, original);
    final reordered = ChoiceClozeSession(
      session: draft(),
      word: word,
      content: content(),
      choices: [other, word, third],
    );
    expect(reordered.evidenceContentRevision, isNot(original));
    expect(
      original,
      isNot(
        TypedClozeSession(
          session: draft(),
          word: word,
          content: content(),
        ).evidenceContentRevision,
      ),
    );
    expect(exercise.variant, ClozeVariant.choice);
  });

  for (final changed in [
    'sentence',
    'model',
    'cefr',
    'cached',
    'meaning',
    'pin',
  ]) {
    test(
      'digest changes with actual $changed without rewriting requested metadata',
      () {
        final original = TypedClozeSession(
          session: draft(),
          word: word,
          content: content(),
        );
        final changedWord = QuizWord(
          id: word.id,
          categoryId: word.categoryId,
          spelling: word.spelling,
          meaning: changed == 'meaning' ? 'changed' : word.meaning,
          partOfSpeech: word.partOfSpeech,
          contentRevision: changed == 'pin'
              ? 'local-vocabulary-v1:8'
              : word.contentRevision,
        );
        final next = TypedClozeSession(
          session: draft(),
          word: changedWord,
          content: content(
            text: changed == 'sentence'
                ? 'They visit the station tomorrow.'
                : 'We visit the station today.',
            model: changed == 'model' ? 'other-model' : 'synthetic-model',
            cefr: changed == 'cefr' ? CefrLevel.b2 : CefrLevel.unknown,
            cached: changed == 'cached',
          ),
        );
        expect(
          next.evidenceContentRevision,
          isNot(original.evidenceContentRevision),
        );
      },
    );
  }

  for (final options in <List<QuizWord>>[
    [word, other],
    [word, other, third, third],
    [word, other, other],
    [
      other,
      third,
      const QuizWord(
        id: 'word-d',
        categoryId: 'category-a',
        spelling: 'journey',
        meaning: 'journey',
        partOfSpeech: 'noun',
        contentRevision: 'local-vocabulary-v1:1',
      ),
    ],
    [
      word,
      other,
      const QuizWord(
        id: 'word-x',
        categoryId: 'category-b',
        spelling: 'journey',
        meaning: 'journey',
        partOfSpeech: 'noun',
        contentRevision: 'local-vocabulary-v1:1',
      ),
    ],
    [
      word,
      other,
      const QuizWord(
        id: 'word-x',
        categoryId: 'category-a',
        spelling: 'TICKET',
        meaning: 'duplicate',
        partOfSpeech: 'noun',
        contentRevision: 'local-vocabulary-v1:1',
      ),
    ],
    [
      const QuizWord(
        id: 'word-a',
        categoryId: 'category-a',
        spelling: 'station',
        meaning: 'changed-target',
        partOfSpeech: 'noun',
        contentRevision: 'local-vocabulary-v1:7',
      ),
      other,
      third,
    ],
  ]) {
    test(
      'choice rejects invalid immutable option set ${options.map((w) => '${w.id}/${w.categoryId}/${w.spelling}/${w.meaning}').join(',')}',
      () {
        expect(
          () => ChoiceClozeSession(
            session: draft(),
            word: word,
            content: content(),
            choices: options,
          ),
          throwsArgumentError,
        );
      },
    );
  }

  test(
    'target-specific parsed gap cannot be reused for a different target',
    () {
      expect(
        () => TypedClozeSession(
          session: draft(),
          word: other,
          content: content(),
        ),
        throwsArgumentError,
      );
    },
  );

  for (final invalid in [
    draft(id: 'legacy-id'),
    draft(id: 'session:cloze-v1:'),
    draft(activity: 'dictation'),
  ]) {
    test(
      'new Cloze requires its own reserved session identity ${invalid.id}/${invalid.activityType}',
      () {
        expect(
          () => TypedClozeSession(
            session: invalid,
            word: word,
            content: content(),
          ),
          throwsArgumentError,
        );
      },
    );
  }
}
