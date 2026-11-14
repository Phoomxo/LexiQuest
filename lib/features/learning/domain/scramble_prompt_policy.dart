import 'learning_models.dart';

abstract final class ScramblePromptPolicy {
  static const _source =
      '21b34eaa:docs/design/2026-11-13-design-reset/learn_frames.py';
  static final _word = RegExp(r'^[A-Za-z]{2,24}$');
  static final _control = RegExp(r'[\x00-\x1f\x7f-\x9f]');

  static ({String sentence, String meaning, String pin})? sentenceFor(
    QuizWord word,
  ) {
    if (word.partOfSpeech.trim().toLowerCase() != 'noun') return null;
    return switch ((word.spelling.trim().toLowerCase(), word.meaning.trim())) {
      ('ticket', 'ตั๋ว') => (
        sentence: 'I have a ticket.',
        meaning: 'ฉันมีตั๋วหนึ่งใบ',
        pin: '$_source:194-211',
      ),
      ('platform', 'ชานชาลา') => (
        sentence: 'The train is at platform two.',
        meaning: 'รถไฟจอดอยู่ที่ชานชาลาสอง',
        pin: '$_source:157-171',
      ),
      _ => null,
    };
  }

  static QuizQuestion? first(List<QuizWord> words, QuizPromptKind kind) {
    for (final word in words) {
      if (word.spelling.toLowerCase() == 'ticket' &&
          sentenceFor(word) != null) {
        final authored = _build(word, kind);
        if (authored != null) return authored;
      }
    }
    for (final word in words) {
      final prompt = _build(word, kind);
      if (prompt != null) return prompt;
    }
    return null;
  }

  static QuizQuestion? _build(QuizWord word, QuizPromptKind kind) {
    final sentence = kind == QuizPromptKind.sentenceScramble;
    final authored = sentenceFor(word);
    if (sentence ? authored == null : !_word.hasMatch(word.spelling)) {
      return null;
    }
    final answer = sentence ? authored!.sentence : word.spelling;
    final hint = sentence
        ? authored!.meaning
        : word.meaning.trim().replaceAll(RegExp(r'\s+'), ' ');
    final parts = sentence ? answer.split(' ') : answer.split('');
    if (parts.length > QuizQuestion.maxScrambleTokens ||
        parts.toSet().length < 2 ||
        hint.isEmpty ||
        hint.length > 4096 ||
        _control.hasMatch(hint) ||
        word.meaning.length > 4096) {
      return null;
    }
    final tokens = [...parts.skip(1), parts.first];
    return QuizQuestion.scramble(
      word: word,
      kind: kind,
      prompt: hint,
      tokens: tokens,
      correctAnswer: answer,
      sourcePin: sentence ? authored!.pin : 'local-vocabulary:letter-tiles-v1',
    );
  }
}
