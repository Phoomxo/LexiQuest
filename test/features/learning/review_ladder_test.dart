import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/review_ladder.dart';

final _at = DateTime.utc(2026, 11, 15, 1, 0, 0, 123, 999);

const _pair = ReviewLadderPair(
  target: QuizWord(
    id: 'word-station',
    categoryId: 'travel',
    spelling: 'station',
    meaning: 'สถานี',
    partOfSpeech: 'noun',
  ),
  contrast: QuizWord(
    id: 'word-platform',
    categoryId: 'travel',
    spelling: 'platform',
    meaning: 'ชานชาลา',
    partOfSpeech: 'noun',
  ),
  categoryName: 'การเดินทาง',
  reviewAttemptId: 'attempt:review:station',
);

ReviewLadderRound _open() =>
    ReviewLadderRound.initial(sessionId: 'review-ladder-1', pair: _pair);

void main() {
  test(
    'choice retry preserves the first answer and permits typed practice',
    () {
      var round = _open().advance(ReviewLadderAction.startMeaning, atUtc: _at);
      round = round.advance(
        ReviewLadderAction.checkMeaning,
        atUtc: _at,
        option: 0,
      );
      expect(round.phase, ReviewLadderPhase.compare);
      expect(round.latestMeaningCorrect, isFalse);
      expect(round.independentChoice?.option, 0);
      expect(
        () => round.advance(ReviewLadderAction.startTyping, atUtc: _at),
        throwsStateError,
      );
      round = round.advance(ReviewLadderAction.retryMeaning, atUtc: _at);
      round = round.advance(
        ReviewLadderAction.checkMeaning,
        atUtc: _at,
        option: 1,
      );
      expect(round.latestMeaningCorrect, isTrue);
      expect(round.meaningChecks.map((check) => check.assisted), [false, true]);

      round = round.advance(ReviewLadderAction.startTyping, atUtc: _at);
      round = round.advance(
        ReviewLadderAction.checkTyped,
        atUtc: _at,
        text: '  STATION  ',
      );
      final raw = encodeReviewLadderRound(round);
      final reopened = decodeReviewLadderRound(raw, sessionId: round.sessionId);
      expect(reopened.phase, ReviewLadderPhase.result);
      expect(reopened.pair.sameAs(_pair), isTrue);
      expect(reopened.independentChoice?.option, 0);
      expect(reopened.meaningChecks.last.assisted, isTrue);
      expect(reopened.typedCorrect, isTrue);
      expect(reopened.typedCheck?.text, '  STATION  ');
      expect(reopened.typedCheck?.assisted, isFalse);
      expect(
        reopened.typedCheck?.checkedAtUtc,
        DateTime.utc(2026, 11, 15, 1, 0, 0, 123),
      );
      expect(encodeReviewLadderRound(reopened), raw);
    },
  );

  test('card exposure and a typed hint remain distinct from checking', () {
    var round = _open().advance(ReviewLadderAction.revealCard, atUtc: _at);
    expect(round.phase, ReviewLadderPhase.intro);
    expect(round.cardShown, isTrue);
    expect(round.typedHintShown, isFalse);
    round = round.advance(ReviewLadderAction.startMeaning, atUtc: _at);
    round = round.advance(
      ReviewLadderAction.checkMeaning,
      atUtc: _at,
      option: 1,
    );
    expect(round.independentChoice, isNull);
    expect(round.meaningChecks.single.assisted, isTrue);
    round = round.advance(ReviewLadderAction.startTyping, atUtc: _at);
    round = round.advance(ReviewLadderAction.revealCard, atUtc: _at);
    expect(round.phase, ReviewLadderPhase.typed);
    expect(round.typedHintShown, isTrue);
    round = round.advance(
      ReviewLadderAction.checkTyped,
      atUtc: _at,
      text: 'wrong',
    );
    final reopened = decodeReviewLadderRound(
      encodeReviewLadderRound(round),
      sessionId: round.sessionId,
    );
    expect(reopened.typedCheck?.assisted, isTrue);
    expect(reopened.typedCorrect, isFalse);
  });

  test('decoder rejects forged phase, ordinal, or evidence fields', () {
    final round = _open()
        .advance(ReviewLadderAction.startMeaning, atUtc: _at)
        .advance(ReviewLadderAction.checkMeaning, atUtc: _at, option: 0);
    final fields =
        jsonDecode(encodeReviewLadderRound(round)) as Map<String, dynamic>;
    for (final changed in [
      {'v': 2},
      {'revision': 3},
      {'phase': 'advance'},
      {'typedHintShown': true},
      {
        'meaningChecks': [
          {'option': 0, 'atUtcMs': -1, 'assisted': false},
        ],
      },
      {
        'meaningChecks': [
          {'option': 0, 'atUtcMs': 1, 'assisted': true},
        ],
      },
    ]) {
      expect(
        () => decodeReviewLadderRound(
          jsonEncode({...fields, ...changed}),
          sessionId: round.sessionId,
        ),
        throwsFormatException,
      );
    }
  });
}
