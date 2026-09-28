import '../../vocabulary/application/vocabulary_use_cases.dart';
import '../../vocabulary/domain/vocabulary_word.dart';
import '../../learning_packs/domain/content_manifest.dart';
import 'learning_models.dart';
import 'lexical_prompt_artifact_identity.dart';
import 'session_configuration.dart';

enum MeaningQuizDirection { wordToMeaning, meaningToWord }

final class InsufficientMeaningQuizOptions implements Exception {
  const InsufficientMeaningQuizOptions();
}

final class MeaningQuizQuestion {
  const MeaningQuizQuestion({
    required this.word,
    required this.direction,
    required this.prompt,
    required this.correctOption,
    required this.options,
    this.optionIdentities = const <String, String>{},
    this.contrastiveIdentity,
    this.contrastiveChecksumSha256,
    this.evidenceChecksumSha256,
  });

  final QuizWord word;
  final MeaningQuizDirection direction;
  final String prompt;
  final String correctOption;
  final List<String> options;
  final Map<String, String> optionIdentities;
  final ContentIdentity? contrastiveIdentity;
  final String? contrastiveChecksumSha256;
  final String? evidenceChecksumSha256;

  String? optionIdentity(String option) => optionIdentities[option];
}

/// Pure composition shared by admission and attached reviews.
List<MeaningQuizQuestion> composeMeaningQuiz(
  QuizSession session, {
  SessionDirection direction = SessionDirection.mixed,
  Iterable<VocabularyWord> lexicalWords = const <VocabularyWord>[],
  Iterable<QuizWord> distractorWords = const <QuizWord>[],
}) {
  final lexicalById = <String, VocabularyWord>{
    for (final word in lexicalWords) word.id: word,
  };
  final words = session.questions
      .map((question) => question.word)
      .toList(growable: false);
  final optionWords = <QuizWord>[...words, ...distractorWords];
  final questions = List<MeaningQuizQuestion>.unmodifiable(
    words.indexed.map((entry) {
      final index = entry.$1;
      final word = entry.$2;
      final questionDirection = switch (direction) {
        SessionDirection.forward => MeaningQuizDirection.wordToMeaning,
        SessionDirection.reverse => MeaningQuizDirection.meaningToWord,
        SessionDirection.mixed =>
          index.isEven
              ? MeaningQuizDirection.wordToMeaning
              : MeaningQuizDirection.meaningToWord,
      };
      final correctOption =
          questionDirection == MeaningQuizDirection.wordToMeaning
          ? word.meaning
          : word.spelling;
      final pool = _equivalentDistinctDistractors(
        words: optionWords,
        word: word,
        direction: questionDirection,
      );
      final lexical = lexicalById[word.id];
      final rich = lexical?.richMetadata;
      final promptMode = questionDirection == MeaningQuizDirection.wordToMeaning
          ? 'meaningChoice'
          : 'wordChoice';
      final artifactIdentity = lexical == null
          ? null
          : LexicalPromptArtifactResolver.resolveForAdapter(
              promptMode: promptMode,
              wordId: word.id,
              coreRevision: word.contentRevision ?? 0,
              coreChecksumSha256: word.contentChecksumSha256,
              verifiedArtifactRevision: rich?.verifiedContentRevision,
              verifiedArtifactChecksumSha256:
                  rich?.verifiedArtifactChecksumSha256,
            );
      final hasVerifiedLexicalMetadata =
          lexical != null &&
          lexical.isGlobal &&
          lexical.contentProvenance == ContentProvenance.packaged &&
          lexical.contentReviewState == ContentReviewState.approved &&
          lexical.contentPublicationState ==
              ContentPublicationState.published &&
          lexical.contentRevision == word.contentRevision &&
          rich?.verifiedContentRevision == lexical.contentRevision &&
          artifactIdentity != null;
      return MeaningQuizQuestion(
        word: word,
        direction: questionDirection,
        prompt: questionDirection == MeaningQuizDirection.wordToMeaning
            ? word.spelling
            : word.meaning,
        correctOption: correctOption,
        options: _pinOptions(
          correctOption: correctOption,
          candidates: pool.map((candidate) => candidate.label).toList(),
          seed: _stableSeed('${word.id}:${questionDirection.name}'),
        ),
        optionIdentities: <String, String>{
          correctOption: word.id,
          for (final candidate in pool) candidate.label: candidate.wordId,
        },
        contrastiveIdentity: hasVerifiedLexicalMetadata
            ? ContentIdentity(
                type: ContentType.lexicalMetadata,
                id: word.id,
                revision: lexical.contentRevision,
              )
            : null,
        contrastiveChecksumSha256: hasVerifiedLexicalMetadata
            ? artifactIdentity.verifiedArtifactChecksumSha256
            : null,
        evidenceChecksumSha256: hasVerifiedLexicalMetadata
            ? artifactIdentity.checksumSha256
            : null,
      );
    }),
  );
  if (distractorWords.isNotEmpty &&
      questions.any((question) => question.options.length < 2)) {
    throw const InsufficientMeaningQuizOptions();
  }
  return questions;
}

List<({String wordId, String label})> _equivalentDistinctDistractors({
  required List<QuizWord> words,
  required QuizWord word,
  required MeaningQuizDirection direction,
}) {
  final promptKey = direction == MeaningQuizDirection.wordToMeaning
      ? _spellingKey(word)
      : _meaningKey(word);
  final answerKey = direction == MeaningQuizDirection.wordToMeaning
      ? _meaningKey(word)
      : _spellingKey(word);
  final byAnswerKey = <String, ({String wordId, String label})>{};
  for (final candidate in words) {
    final candidatePromptKey = direction == MeaningQuizDirection.wordToMeaning
        ? _spellingKey(candidate)
        : _meaningKey(candidate);
    final candidateAnswerKey = direction == MeaningQuizDirection.wordToMeaning
        ? _meaningKey(candidate)
        : _spellingKey(candidate);
    if (candidatePromptKey == promptKey || candidateAnswerKey == answerKey) {
      continue;
    }
    byAnswerKey.putIfAbsent(
      candidateAnswerKey,
      () => (
        wordId: candidate.id,
        label: direction == MeaningQuizDirection.wordToMeaning
            ? candidate.meaning
            : candidate.spelling,
      ),
    );
  }
  final keys = byAnswerKey.keys.toList()..sort();
  return keys.map((key) => byAnswerKey[key]!).toList(growable: false);
}

String _spellingKey(QuizWord word) =>
    normalizeVocabularyText(word.normalizedSpelling ?? word.spelling);

String _meaningKey(QuizWord word) =>
    normalizeVocabularyText(word.normalizedMeaning ?? word.meaning);

List<String> _pinOptions({
  required String correctOption,
  required List<String> candidates,
  required int seed,
}) {
  final distractors = candidates
      .where((candidate) => candidate != correctOption)
      .toList(growable: false);
  final rotatedDistractors = distractors.isEmpty
      ? const <String>[]
      : <String>[
          ...distractors.skip(seed % distractors.length),
          ...distractors.take(seed % distractors.length),
        ];
  final options = <String>[correctOption, ...rotatedDistractors.take(3)];
  final offset = seed % options.length;
  return List<String>.unmodifiable(<String>[
    ...options.skip(offset),
    ...options.take(offset),
  ]);
}

int _stableSeed(String value) => value.codeUnits.fold<int>(
  17,
  (hash, unit) => ((hash * 31) + unit) & 0x7fffffff,
);
