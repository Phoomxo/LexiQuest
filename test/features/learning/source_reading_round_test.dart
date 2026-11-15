import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/source_reading_round.dart';

void main() {
  test('source continuation preserves first recall and a later draft', () {
    final firstAnswers = ['ctation', ' TICKET '];
    final edited = ['station', 'ticket'];
    final firstTime = DateTime.utc(2026, 11, 15, 0, 0, 0, 123, 999);
    final round = _round(
      SourceReadingDraft(
        phase: SourceReadingPhase.sentence,
        recall: edited,
        cues: ['สถานี\nรถไฟ', 'บัตร'],
        sentence: ' I live near the station. ',
        first: (answers: firstAnswers, checkedAtUtc: firstTime),
      ),
    );
    firstAnswers[0] = 'station';
    edited[1] = 'changed';

    final raw = encodeSourceReadingRound(round);
    final restored = decodeSourceReadingRound(raw, sessionId: round.sessionId);
    expect(restored.sessionId, round.sessionId);
    expect(restored.scope.sameAs(round.scope), isTrue);
    expect(restored.scope.sameAs(_scope([_ticket, _station])), isFalse);
    expect(restored.revision, round.revision);
    expect(restored.draft.phase, SourceReadingPhase.sentence);
    expect(restored.draft.recall, ['station', 'ticket']);
    expect(restored.draft.first!.answers, ['ctation', ' TICKET ']);
    expect(
      restored.draft.first!.checkedAtUtc,
      DateTime.utc(2026, 11, 15, 0, 0, 0, 123),
    );
    expect(restored.draft.cues, ['สถานี\nรถไฟ', 'บัตร']);
    expect(restored.draft.sentence, ' I live near the station. ');
    expect(encodeSourceReadingRound(restored), raw);
    expect(sourceRecallMatches(' TICKET ', 'ticket'), isTrue);
    expect(sourceRecallMatches('ctation', 'station'), isFalse);
    expect(raw, isNot(contains('passageText')));
    expect(raw, isNot(contains('ownerId')));
  });

  test('source continuation rejects broken phase, scope, and draft data', () {
    final initial = _round(SourceReadingDraft.initial(2));
    final raw = encodeSourceReadingRound(initial);
    final fields = jsonDecode(raw) as Map<String, dynamic>;
    final words = fields['words'] as List<dynamic>;
    final invalid = <Map<String, dynamic>>[
      {...fields, 'v': 2},
      {...fields, 'ownerId': 'unrelated-owner'},
      {...fields, 'passageDigest': 'AB' * 32},
      {
        ...fields,
        'words': [words.first, words.first],
      },
      {
        ...fields,
        'recall': ['', '', 'extra'],
      },
      {...fields, 'phase': 'summary'},
      {...fields, 'sentence': 'x' * (sourceReadingSentenceMaxLength + 1)},
      {
        ...fields,
        'phase': 'comparison',
        'first': {
          'answers': ['station', 'ticket'],
          'checkedAtUtcMs': 1000,
        },
      },
      {
        ...fields,
        'phase': 'comparison',
        'first': {
          'answers': ['ctation', 'ticket'],
          'checkedAtUtcMs': -1,
        },
      },
    ];
    for (final value in invalid) {
      expect(
        () => decodeSourceReadingRound(
          jsonEncode(value),
          sessionId: initial.sessionId,
        ),
        throwsFormatException,
      );
    }
  });
}

SourceReadingRound _round(SourceReadingDraft draft) => SourceReadingRound(
  sessionId: 'session-reading',
  scope: _scope([_station, _ticket]),
  revision: 8,
  draft: draft,
);

SourceReadingScope _scope(List<QuizWord> words) => SourceReadingScope(
  categoryId: 'travel',
  documentId: 'source-travel',
  documentRevision: 3,
  passageDigest: 'ab' * 32,
  words: words,
);

const _station = QuizWord(
  id: 'word-station',
  categoryId: 'travel',
  spelling: 'station',
  meaning: 'สถานี',
  partOfSpeech: 'noun',
  localRevision: 5,
);

const _ticket = QuizWord(
  id: 'word-ticket',
  categoryId: 'travel',
  spelling: 'ticket',
  meaning: 'ตั๋ว',
  partOfSpeech: 'noun',
);
