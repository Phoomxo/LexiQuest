import 'dart:convert';

import 'learning_models.dart';

const _maxChecks = 64;
const _maxRevision = 0x7fffffff;
const _maxJsonBytes = 16 * 1024;
const _maxEpochMilliseconds = 8640000000000000;
final _controlCharacters = RegExp(r'[\x00-\x1f\x7f-\x9f]');

enum ReviewLadderPhase { intro, meaning, compare, advance, typed, result }

enum ReviewLadderAction {
  startMeaning,
  revealCard,
  checkMeaning,
  retryMeaning,
  startTyping,
  checkTyped,
}

final class ReviewLadderPair {
  const ReviewLadderPair({
    required this.target,
    required this.contrast,
    required this.categoryName,
    required this.reviewAttemptId,
  });

  final QuizWord target;
  final QuizWord contrast;
  final String categoryName;
  final String reviewAttemptId;

  bool sameAs(ReviewLadderPair other) =>
      reviewAttemptId == other.reviewAttemptId &&
      categoryName == other.categoryName &&
      _sameWord(target, other.target) &&
      _sameWord(contrast, other.contrast);
}

typedef ReviewMeaningCheck = ({
  int option,
  DateTime checkedAtUtc,
  bool assisted,
});
typedef ReviewTypedCheck = ({
  String text,
  DateTime checkedAtUtc,
  bool assisted,
});

final class ReviewLadderRound {
  ReviewLadderRound._({
    required this.sessionId,
    required this.pair,
    required this.revision,
    required this.phase,
    required this.cardShown,
    required this.typedHintShown,
    required List<ReviewMeaningCheck> meaningChecks,
    required this.typedCheck,
  }) : meaningChecks = List.unmodifiable(meaningChecks);

  factory ReviewLadderRound.initial({
    required String sessionId,
    required ReviewLadderPair pair,
  }) {
    final round = ReviewLadderRound._(
      sessionId: sessionId,
      pair: pair,
      revision: 0,
      phase: ReviewLadderPhase.intro,
      cardShown: false,
      typedHintShown: false,
      meaningChecks: const [],
      typedCheck: null,
    );
    _validateRound(round);
    return round;
  }

  static const typedPrompt = 'Meet me at the ____ tomorrow.';
  static const typedTranslation = 'พรุ่งนี้ไปเจอกันที่สถานี';
  static const completedSentence = 'Meet me at the station tomorrow.';

  final String sessionId;
  final ReviewLadderPair pair;
  final int revision;
  final ReviewLadderPhase phase;
  final bool cardShown;
  final bool typedHintShown;
  final List<ReviewMeaningCheck> meaningChecks;
  final ReviewTypedCheck? typedCheck;

  ReviewMeaningCheck? get independentChoice =>
      meaningChecks.where((check) => !check.assisted).firstOrNull;

  bool get latestMeaningCorrect => meaningChecks.lastOrNull?.option == 1;

  bool get typedCorrect => switch (typedCheck) {
    final check? =>
      normalizeQuizClozeAnswer(check.text) ==
          normalizeQuizClozeAnswer(pair.target.spelling),
    null => false,
  };

  ReviewLadderRound advance(
    ReviewLadderAction action, {
    required DateTime atUtc,
    int? option,
    String? text,
  }) {
    if (!atUtc.isUtc || !_validEpoch(atUtc.millisecondsSinceEpoch)) {
      throw ArgumentError.value(atUtc, 'atUtc', 'Expected a UTC instant');
    }
    if ((option != null) != (action == ReviewLadderAction.checkMeaning) ||
        (text != null) != (action == ReviewLadderAction.checkTyped) ||
        (option != null && !_validOption(option))) {
      throw ArgumentError('Invalid review ladder action input');
    }
    if (revision == _maxRevision ||
        (option != null && meaningChecks.length == _maxChecks)) {
      throw StateError('Review ladder action limit reached');
    }
    final nextPhase = switch ((phase, action)) {
      (ReviewLadderPhase.intro, ReviewLadderAction.startMeaning) =>
        ReviewLadderPhase.meaning,
      (ReviewLadderPhase.meaning, ReviewLadderAction.checkMeaning) =>
        option == 1 ? ReviewLadderPhase.advance : ReviewLadderPhase.compare,
      (
        ReviewLadderPhase.compare || ReviewLadderPhase.advance,
        ReviewLadderAction.retryMeaning,
      ) =>
        ReviewLadderPhase.meaning,
      (ReviewLadderPhase.advance, ReviewLadderAction.startTyping) =>
        ReviewLadderPhase.typed,
      (ReviewLadderPhase.typed, ReviewLadderAction.checkTyped) =>
        ReviewLadderPhase.result,
      (
        ReviewLadderPhase.intro ||
            ReviewLadderPhase.compare ||
            ReviewLadderPhase.advance ||
            ReviewLadderPhase.typed,
        ReviewLadderAction.revealCard,
      ) =>
        phase,
      _ => throw StateError(
        'Review ladder action is unavailable in this phase',
      ),
    };
    if (text != null) normalizeQuizClozeAnswer(text);
    final checkedAtUtc = DateTime.fromMillisecondsSinceEpoch(
      atUtc.millisecondsSinceEpoch,
      isUtc: true,
    );
    final revealsCard = action == ReviewLadderAction.revealCard;
    return ReviewLadderRound._(
      sessionId: sessionId,
      pair: pair,
      revision: revision + 1,
      phase: nextPhase,
      cardShown: cardShown || revealsCard,
      typedHintShown:
          typedHintShown || (revealsCard && phase == ReviewLadderPhase.typed),
      meaningChecks: [
        ...meaningChecks,
        if (option != null)
          (
            option: option,
            checkedAtUtc: checkedAtUtc,
            assisted: cardShown || meaningChecks.isNotEmpty,
          ),
      ],
      typedCheck: text == null
          ? typedCheck
          : (text: text, checkedAtUtc: checkedAtUtc, assisted: typedHintShown),
    );
  }
}

String encodeReviewLadderRound(ReviewLadderRound round) {
  _validateRound(round);
  final pair = round.pair;
  final typed = round.typedCheck;
  final raw = jsonEncode({
    'v': 1,
    'kind': 'reviewLadder',
    'pair': {
      'target': _encodeWord(pair.target),
      'contrast': _encodeWord(pair.contrast),
      'categoryName': pair.categoryName,
      'reviewAttemptId': pair.reviewAttemptId,
    },
    'revision': round.revision,
    'phase': round.phase.name,
    'cardShown': round.cardShown,
    'typedHintShown': round.typedHintShown,
    'meaningChecks': [
      for (final check in round.meaningChecks)
        {
          'option': check.option,
          'atUtcMs': check.checkedAtUtc.millisecondsSinceEpoch,
          'assisted': check.assisted,
        },
    ],
    'typedCheck': typed == null
        ? null
        : {
            'text': typed.text,
            'atUtcMs': typed.checkedAtUtc.millisecondsSinceEpoch,
            'assisted': typed.assisted,
          },
  });
  _checkJsonSize(raw);
  return raw;
}

ReviewLadderRound decodeReviewLadderRound(
  String raw, {
  required String sessionId,
}) {
  _checkJsonSize(raw);
  final json = jsonDecode(raw);
  if (json case {
    'v': 1,
    'kind': 'reviewLadder',
    'pair': final Object? pair,
    'revision': final int revision,
    'phase': final String phase,
    'cardShown': final bool cardShown,
    'typedHintShown': final bool typedHintShown,
    'meaningChecks': final List<Object?> meanings,
    'typedCheck': final Object? typed,
  } when json.length == 9 && meanings.length <= _maxChecks) {
    final parsedPhase = ReviewLadderPhase.values
        .where((candidate) => candidate.name == phase)
        .firstOrNull;
    if (parsedPhase == null) {
      throw const FormatException('Invalid review ladder phase');
    }
    final round = ReviewLadderRound._(
      sessionId: sessionId,
      pair: _decodePair(pair),
      revision: revision,
      phase: parsedPhase,
      cardShown: cardShown,
      typedHintShown: typedHintShown,
      meaningChecks: [for (final check in meanings) _decodeMeaningCheck(check)],
      typedCheck: typed == null ? null : _decodeTypedCheck(typed),
    );
    _validateRound(round);
    return round;
  }
  throw const FormatException('Invalid review ladder round');
}

ReviewLadderPair _decodePair(Object? raw) {
  if (raw case {
    'target': final Object? target,
    'contrast': final Object? contrast,
    'categoryName': final String categoryName,
    'reviewAttemptId': final String reviewAttemptId,
  } when raw is Map<String, Object?> && raw.length == 4) {
    return ReviewLadderPair(
      target: _decodeWord(target),
      contrast: _decodeWord(contrast),
      categoryName: categoryName,
      reviewAttemptId: reviewAttemptId,
    );
  }
  throw const FormatException('Invalid review ladder pair');
}

Map<String, Object?> _encodeWord(QuizWord word) => {
  'id': word.id,
  'categoryId': word.categoryId,
  'spelling': word.spelling,
  'meaning': word.meaning,
  'partOfSpeech': word.partOfSpeech,
  'localRevision': word.localRevision,
};

QuizWord _decodeWord(Object? raw) {
  if (raw case {
    'id': final String id,
    'categoryId': final String categoryId,
    'spelling': final String spelling,
    'meaning': final String meaning,
    'partOfSpeech': final String partOfSpeech,
    'localRevision': final int localRevision,
  } when raw is Map<String, Object?> && raw.length == 6) {
    return QuizWord(
      id: id,
      categoryId: categoryId,
      spelling: spelling,
      meaning: meaning,
      partOfSpeech: partOfSpeech,
      localRevision: localRevision,
    );
  }
  throw const FormatException('Invalid review ladder vocabulary');
}

ReviewMeaningCheck _decodeMeaningCheck(Object? raw) {
  if (raw case {
    'option': final int option,
    'atUtcMs': final int atUtcMs,
    'assisted': final bool assisted,
  } when raw is Map<String, Object?> && raw.length == 3) {
    return (
      option: option,
      checkedAtUtc: _decodeTime(atUtcMs),
      assisted: assisted,
    );
  }
  throw const FormatException('Invalid review meaning check');
}

ReviewTypedCheck _decodeTypedCheck(Object? raw) {
  if (raw case {
    'text': final String text,
    'atUtcMs': final int atUtcMs,
    'assisted': final bool assisted,
  } when raw is Map<String, Object?> && raw.length == 3) {
    return (text: text, checkedAtUtc: _decodeTime(atUtcMs), assisted: assisted);
  }
  throw const FormatException('Invalid review typed check');
}

void _validateRound(ReviewLadderRound round) {
  final pair = round.pair;
  if (!_validId(round.sessionId) ||
      !_validId(pair.reviewAttemptId) ||
      !_validText(pair.categoryName, 80) ||
      pair.target.categoryId != pair.contrast.categoryId ||
      pair.target.id == pair.contrast.id ||
      !_validWord(pair.target, 'station', 'สถานี') ||
      !_validWord(pair.contrast, 'platform', 'ชานชาลา')) {
    throw const FormatException('Invalid review ladder pair');
  }

  final checks = round.meaningChecks;
  final typed = round.typedCheck;
  final latest = checks.lastOrNull;
  final inTypedPhase =
      round.phase == ReviewLadderPhase.typed ||
      round.phase == ReviewLadderPhase.result;
  final minimumSteps = switch (round.phase) {
    ReviewLadderPhase.intro => 0,
    ReviewLadderPhase.meaning => 1 + 2 * checks.length,
    ReviewLadderPhase.compare || ReviewLadderPhase.advance => 2 * checks.length,
    ReviewLadderPhase.typed => 1 + 2 * checks.length,
    ReviewLadderPhase.result => 2 + 2 * checks.length,
  };
  final minimumReveals =
      (round.cardShown ? 1 : 0) +
      (round.typedHintShown && checks.firstOrNull?.assisted == true ? 1 : 0);
  if (checks.length > _maxChecks ||
      round.revision < minimumSteps + minimumReveals ||
      round.revision > _maxRevision ||
      (!round.cardShown && round.revision != minimumSteps) ||
      (round.phase == ReviewLadderPhase.intro && checks.isNotEmpty) ||
      (round.phase == ReviewLadderPhase.compare && latest?.option != 0) ||
      ((round.phase == ReviewLadderPhase.advance || inTypedPhase) &&
          latest?.option != 1) ||
      (round.typedHintShown && (!round.cardShown || !inTypedPhase)) ||
      ((round.phase == ReviewLadderPhase.result) != (typed != null))) {
    throw const FormatException('Invalid review ladder phase or revision');
  }
  for (final (index, check) in checks.indexed) {
    if (!_validOption(check.option) ||
        !_validTime(check.checkedAtUtc) ||
        (index == 0 && check.assisted && !round.cardShown) ||
        (index > 0 && !check.assisted)) {
      throw const FormatException('Invalid review meaning check');
    }
  }
  if (typed != null) {
    if (typed.assisted != round.typedHintShown ||
        !_validTime(typed.checkedAtUtc)) {
      throw const FormatException('Invalid review typed check');
    }
    normalizeQuizClozeAnswer(typed.text);
  }
}

bool _sameWord(QuizWord left, QuizWord right) =>
    left.id == right.id &&
    left.categoryId == right.categoryId &&
    left.spelling == right.spelling &&
    left.meaning == right.meaning &&
    left.partOfSpeech == right.partOfSpeech &&
    left.localRevision == right.localRevision;

bool _validWord(QuizWord word, String spelling, String meaning) =>
    _validId(word.id) &&
    _validId(word.categoryId) &&
    word.localRevision > 0 &&
    _validText(word.spelling, 120) &&
    _validText(word.meaning, 500) &&
    _validText(word.partOfSpeech, 60) &&
    word.spelling.trim().toLowerCase() == spelling &&
    word.meaning.trim() == meaning &&
    word.partOfSpeech.trim().toLowerCase() == 'noun';

bool _validOption(int option) => option == 0 || option == 1;

bool _validText(String value, int maxLength) =>
    value.length <= maxLength &&
    value.trim().isNotEmpty &&
    !_controlCharacters.hasMatch(value);

bool _validId(String value) => value == value.trim() && _validText(value, 256);

bool _validEpoch(int value) => value >= 0 && value <= _maxEpochMilliseconds;

bool _validTime(DateTime time) =>
    time.isUtc && _validEpoch(time.millisecondsSinceEpoch);

DateTime _decodeTime(int milliseconds) {
  if (!_validEpoch(milliseconds)) {
    throw const FormatException('Invalid review ladder UTC instant');
  }
  return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

void _checkJsonSize(String raw) {
  if (raw.length > _maxJsonBytes || utf8.encode(raw).length > _maxJsonBytes) {
    throw const FormatException('Review ladder round exceeds storage limit');
  }
}
