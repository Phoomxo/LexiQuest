import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/sentence_scramble_content.dart';

QuizWord word({
  String id = 'synthetic-word',
  String category = 'synthetic-category',
  String spelling = 'school',
  String meaning = 'synthetic owned meaning',
  String partOfSpeech = 'noun',
  String? revision = 'local-vocabulary-v1:7',
}) => QuizWord(
  id: id,
  categoryId: category,
  spelling: spelling,
  meaning: meaning,
  partOfSpeech: partOfSpeech,
  contentRevision: revision,
);

LearningSessionDraft draft({
  String id = 'session:sentence-scramble-v1:synthetic',
  String owner = 'synthetic-owner',
  String activity = 'sentenceScramble',
  DateTime? start,
}) => LearningSessionDraft(
  id: id,
  ownerId: owner,
  activityType: activity,
  startedAtUtc: start ?? DateTime.utc(2026, 10, 30, 12),
  appVersion: 'synthetic-app',
  buildId: 'synthetic-build',
);

SentenceScrambleContent content({
  String seed = 'school',
  String text = 'school — a place to learn.',
  String model = 'synthetic-model/r7',
  CefrLevel cefr = CefrLevel.unknown,
  bool cached = false,
}) => SentenceScrambleContent.parse(
  targetSpelling: seed,
  response: ContentResponse(
    text: text,
    kind: ContentKind.sentence,
    cefr: cefr,
    language: 'en',
    modelVersion: model,
    cached: cached,
  ),
);

SentenceScrambleSession exercise({
  LearningSessionDraft? session,
  QuizWord? anchor,
  SentenceScrambleContent? sentence,
}) => SentenceScrambleSession(
  session: session ?? draft(),
  word: anchor ?? word(),
  content: sentence ?? content(),
);

void main() {
  test('accepted sentence keeps owned anchor distinct from full target', () {
    final accepted = exercise();
    expect(accepted.id, 'session:sentence-scramble-v1:synthetic');
    expect(accepted.ownerId, 'synthetic-owner');
    expect(accepted.startedAtUtc, DateTime.utc(2026, 10, 30, 12));
    expect(accepted.word.spelling, 'school');
    expect(accepted.content.sentence, 'school — a place to learn.');
    expect(accepted.wordContentRevision, 'local-vocabulary-v1:7');
    expect(accepted.tokenOrder, same(accepted.content.tokenOrder));
    expect(() => accepted.tokenOrder[0] = 0, throwsUnsupportedError);
    expect(
      accepted.evidenceContentRevision,
      matches(RegExp(r'^sentence-scramble-v1:[0-9a-f]{64}$')),
    );
    expect(
      accepted.providerProvenance,
      'sentence-scramble-model-v1:${sha256.convert(utf8.encode('synthetic-model/r7'))}',
    );
    expect(
      accepted.providerProvenance.length,
      lessThanOrEqualTo(LearningEvidenceContract.maxProviderProvenanceLength),
    );
  });

  test('hash pins the full ownerless word content bank and actual metadata', () {
    final accepted = exercise();
    final source = [
      'sentence-scramble-v1',
      [
        'synthetic-word',
        'synthetic-category',
        'school',
        'synthetic owned meaning',
        'noun',
        'local-vocabulary-v1:7',
      ],
      [
        accepted.content.sentence,
        accepted.content.tokens,
        accepted.content.tokenOrder,
        'sentence',
        'unknown',
        'en',
        'synthetic-model/r7',
        false,
      ],
    ];
    expect(
      accepted.evidenceContentRevision,
      'sentence-scramble-v1:${sha256.convert(utf8.encode(jsonEncode(source)))}',
    );
    for (final changed in [
      exercise(anchor: word(id: 'another-word')),
      exercise(anchor: word(category: 'another-category')),
      exercise(anchor: word(meaning: 'another captured meaning')),
      exercise(anchor: word(partOfSpeech: 'verb')),
      exercise(anchor: word(revision: 'local-vocabulary-v1:8')),
      exercise(sentence: content(text: 'school feels calm.')),
      exercise(sentence: content(model: 'synthetic-model/r8')),
      exercise(sentence: content(cefr: CefrLevel.b1)),
      exercise(sentence: content(cached: true)),
      exercise(
        anchor: word(spelling: 'School'),
        sentence: content(seed: 'School'),
      ),
    ]) {
      expect(
        changed.evidenceContentRevision,
        isNot(accepted.evidenceContentRevision),
      );
    }
    final sameFacts = exercise(
      session: draft(
        id: 'session:sentence-scramble-v1:other',
        owner: 'another-owner',
        start: DateTime.utc(2026, 10, 31),
      ),
    );
    expect(sameFacts.evidenceContentRevision, accepted.evidenceContentRevision);
    expect(sameFacts.providerProvenance, accepted.providerProvenance);
  });

  test('raw source whitespace canonicalizes before content identity', () {
    final first = exercise(sentence: content(text: 'school feels calm.'));
    final second = exercise(
      sentence: content(text: '\tschool\u00a0feels\ncalm.\r\n'),
    );
    expect(first.evidenceContentRevision, second.evidenceContentRevision);
    expect(first.tokenOrder, second.tokenOrder);
  });

  test('original lexical seed must match exact owned anchor spelling', () {
    expect(
      () => exercise(anchor: word(spelling: 'School')),
      throwsArgumentError,
    );
    expect(
      () => exercise(anchor: word(spelling: 'place')),
      throwsArgumentError,
    );
  });

  test('invalid draft and unpinned anchors cannot mint accepted handles', () {
    for (final invalid in [
      draft(id: 'bare-session'),
      draft(id: SentenceScrambleSession.idPrefix),
      draft(owner: ''),
      draft(activity: 'wordScramble'),
      draft(start: DateTime(2026, 10, 30)),
    ]) {
      expect(() => exercise(session: invalid), throwsArgumentError);
    }
    for (final invalid in [
      word(id: ''),
      word(category: ''),
      word(revision: null),
      word(revision: 'local-vocabulary-v1:0'),
      word(revision: 'local-vocabulary-v1:7trailing'),
    ]) {
      expect(() => exercise(anchor: invalid), throwsArgumentError);
    }
  });

  test('typed sentence is not limited to a word-sized response', () {
    final target = 'school ${List.filled(40, 'word').join(' ')}';
    final accepted = exercise(sentence: content(text: target));
    final input = SentenceScrambleAnswerInput(
      exercise: accepted,
      response: target,
      responseTime: const Duration(milliseconds: 456),
    );
    expect(input.response.length, greaterThan(120));
    expect(input.exercise, same(accepted));
    expect(input.responseTime, const Duration(milliseconds: 456));
    expect(accepted.content.matchesResponse(input.response), isTrue);
  });
}
