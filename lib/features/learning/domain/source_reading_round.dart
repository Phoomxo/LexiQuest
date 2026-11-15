import 'dart:convert';

import 'learning_models.dart';

const int sourceReadingRecallMaxLength = 120;
const int sourceReadingCueMaxLength = 500;
const int sourceReadingSentenceMaxLength = 500;

const _maxWords = 20;
const _maxJsonBytes = 128 * 1024;
const _maxEpochMilliseconds = 8640000000000000;
final _digestPattern = RegExp(r'^[0-9a-f]{64}$');
final _unsupportedControls = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]');

enum SourceReadingPhase {
  supported,
  reread,
  recall,
  comparison,
  correction,
  association,
  sentence,
  summary,
}

final class SourceReadingScope {
  SourceReadingScope({
    required this.categoryId,
    required this.documentId,
    required this.documentRevision,
    required this.passageDigest,
    required List<QuizWord> words,
  }) : words = List.unmodifiable(words);

  final String categoryId;
  final String documentId;
  final int documentRevision;
  final String passageDigest;
  final List<QuizWord> words;

  bool sameAs(SourceReadingScope other) {
    if (categoryId != other.categoryId ||
        documentId != other.documentId ||
        documentRevision != other.documentRevision ||
        passageDigest != other.passageDigest ||
        words.length != other.words.length) {
      return false;
    }
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      final otherWord = other.words[index];
      if (word.id != otherWord.id ||
          word.categoryId != otherWord.categoryId ||
          word.localRevision != otherWord.localRevision ||
          word.spelling != otherWord.spelling ||
          word.meaning != otherWord.meaning ||
          word.partOfSpeech != otherWord.partOfSpeech) {
        return false;
      }
    }
    return true;
  }
}

typedef SourceReadingFirstRecall = ({
  List<String> answers,
  DateTime checkedAtUtc,
});

final class SourceReadingDraft {
  SourceReadingDraft({
    required this.phase,
    required List<String> recall,
    required List<String> cues,
    required this.sentence,
    SourceReadingFirstRecall? first,
  }) : recall = List.unmodifiable(recall),
       cues = List.unmodifiable(cues),
       first = first == null
           ? null
           : (
               answers: List.unmodifiable(first.answers),
               checkedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                 first.checkedAtUtc.millisecondsSinceEpoch,
                 isUtc: first.checkedAtUtc.isUtc,
               ),
             );

  factory SourceReadingDraft.initial(int wordCount) {
    if (wordCount < 1 || wordCount > _maxWords) {
      throw RangeError.range(wordCount, 1, _maxWords, 'wordCount');
    }
    return SourceReadingDraft(
      phase: SourceReadingPhase.supported,
      recall: List.filled(wordCount, ''),
      cues: List.filled(wordCount, ''),
      sentence: '',
    );
  }

  final SourceReadingPhase phase;
  final List<String> recall;
  final List<String> cues;
  final String sentence;
  final SourceReadingFirstRecall? first;
}

final class SourceReadingRound {
  const SourceReadingRound({
    required this.sessionId,
    required this.scope,
    required this.revision,
    required this.draft,
  });

  final String sessionId;
  final SourceReadingScope scope;
  final int revision;
  final SourceReadingDraft draft;
}

bool sourceRecallMatches(String answer, String spelling) =>
    _foldAnswer(answer) == _foldAnswer(spelling);

String _foldAnswer(String answer) => answer.trim().toLowerCase();

String encodeSourceReadingRound(SourceReadingRound round) {
  _validateRound(round);
  final scope = round.scope;
  final draft = round.draft;
  final first = draft.first;
  final encoded = jsonEncode({
    'v': 1,
    'kind': 'sourceReading',
    'categoryId': scope.categoryId,
    'documentId': scope.documentId,
    'documentRevision': scope.documentRevision,
    'passageDigest': scope.passageDigest,
    'words': [
      for (final word in scope.words)
        {
          'id': word.id,
          'spelling': word.spelling,
          'meaning': word.meaning,
          'partOfSpeech': word.partOfSpeech,
          'localRevision': word.localRevision,
        },
    ],
    'revision': round.revision,
    'phase': draft.phase.name,
    'recall': draft.recall,
    'cues': draft.cues,
    'sentence': draft.sentence,
    'first': first == null
        ? null
        : {
            'answers': first.answers,
            'checkedAtUtcMs': first.checkedAtUtc.millisecondsSinceEpoch,
          },
  });
  _validateJsonSize(encoded);
  return encoded;
}

SourceReadingRound decodeSourceReadingRound(
  String raw, {
  required String sessionId,
}) {
  _validateJsonSize(raw);
  final json = jsonDecode(raw);
  if (json case {
    'v': 1,
    'kind': 'sourceReading',
    'categoryId': final String categoryId,
    'documentId': final String documentId,
    'documentRevision': final int documentRevision,
    'passageDigest': final String passageDigest,
    'words': final List<Object?> words,
    'revision': final int revision,
    'phase': final String phase,
    'recall': final List<Object?> recall,
    'cues': final List<Object?> cues,
    'sentence': final String sentence,
    'first': final Object? first,
  } when json.length == 13 && words.isNotEmpty && words.length <= _maxWords) {
    final parsedPhase = SourceReadingPhase.values
        .where((candidate) => candidate.name == phase)
        .firstOrNull;
    if (parsedPhase == null) {
      throw const FormatException('Invalid source reading phase');
    }
    final round = SourceReadingRound(
      sessionId: sessionId,
      scope: SourceReadingScope(
        categoryId: categoryId,
        documentId: documentId,
        documentRevision: documentRevision,
        passageDigest: passageDigest,
        words: [for (final word in words) _decodeWord(word, categoryId)],
      ),
      revision: revision,
      draft: SourceReadingDraft(
        phase: parsedPhase,
        recall: _decodeStrings(recall, words.length),
        cues: _decodeStrings(cues, words.length),
        sentence: sentence,
        first: _decodeFirst(first, words.length),
      ),
    );
    _validateRound(round);
    return round;
  }
  throw const FormatException('Invalid source reading round');
}

QuizWord _decodeWord(Object? data, String categoryId) {
  if (data case {
    'id': final String id,
    'spelling': final String spelling,
    'meaning': final String meaning,
    'partOfSpeech': final String partOfSpeech,
    'localRevision': final int localRevision,
  } when data is Map<String, Object?> && data.length == 5) {
    return QuizWord(
      id: id,
      categoryId: categoryId,
      spelling: spelling,
      meaning: meaning,
      partOfSpeech: partOfSpeech,
      localRevision: localRevision,
    );
  }
  throw const FormatException('Invalid source reading word');
}

SourceReadingFirstRecall? _decodeFirst(Object? data, int wordCount) {
  if (data == null) return null;
  if (data
      case {
        'answers': final List<Object?> answers,
        'checkedAtUtcMs': final int checkedAtUtcMs,
      }
      when data is Map<String, Object?> &&
          data.length == 2 &&
          _validEpoch(checkedAtUtcMs)) {
    return (
      answers: _decodeStrings(answers, wordCount),
      checkedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        checkedAtUtcMs,
        isUtc: true,
      ),
    );
  }
  throw const FormatException('Invalid first source recall');
}

List<String> _decodeStrings(List<Object?> values, int count) {
  if (values.length != count || values.any((value) => value is! String)) {
    throw const FormatException('Invalid source reading draft fields');
  }
  return values.cast<String>();
}

void _validateRound(SourceReadingRound round) {
  final scope = round.scope;
  final draft = round.draft;
  final words = scope.words;
  if (!_validId(round.sessionId) ||
      round.revision < 0 ||
      !_validId(scope.categoryId) ||
      !_validId(scope.documentId) ||
      scope.documentRevision < 1 ||
      scope.passageDigest.length != 64 ||
      !_digestPattern.hasMatch(scope.passageDigest) ||
      words.isEmpty ||
      words.length > _maxWords) {
    throw const FormatException('Invalid source reading scope');
  }
  final wordIds = <String>{};
  final spellings = <String>{};
  for (final word in words) {
    if (!_validId(word.id) ||
        !wordIds.add(word.id) ||
        word.categoryId != scope.categoryId ||
        word.localRevision < 1 ||
        word.spelling.trim().isEmpty ||
        !spellings.add(_foldAnswer(word.spelling)) ||
        !sourceReadingTextFits(word.spelling, sourceReadingRecallMaxLength) ||
        !sourceReadingTextFits(word.meaning, 500) ||
        !sourceReadingTextFits(word.partOfSpeech, 60)) {
      throw const FormatException('Invalid source reading word');
    }
  }

  if (!_validFields(draft.recall, words.length, sourceReadingRecallMaxLength) ||
      !_validFields(draft.cues, words.length, sourceReadingCueMaxLength) ||
      !sourceReadingTextFits(draft.sentence, sourceReadingSentenceMaxLength)) {
    throw const FormatException('Invalid source reading draft fields');
  }
  final first = draft.first;
  final checked = switch (draft.phase) {
    SourceReadingPhase.supported ||
    SourceReadingPhase.reread ||
    SourceReadingPhase.recall => false,
    _ => true,
  };
  if (checked != (first != null)) {
    throw const FormatException('First source recall does not match phase');
  }
  if (first == null) return;
  if (!first.checkedAtUtc.isUtc ||
      !_validEpoch(first.checkedAtUtc.millisecondsSinceEpoch) ||
      !_validFields(
        first.answers,
        words.length,
        sourceReadingRecallMaxLength,
      )) {
    throw const FormatException('Invalid first source recall');
  }
  if (draft.phase == SourceReadingPhase.comparison ||
      draft.phase == SourceReadingPhase.correction) {
    final hasMiss = words.asMap().entries.any(
      (entry) =>
          !sourceRecallMatches(first.answers[entry.key], entry.value.spelling),
    );
    if (!hasMiss) {
      throw const FormatException('Source correction requires a first miss');
    }
  }
}

bool _validFields(List<String> fields, int count, int maxLength) =>
    fields.length == count &&
    fields.every((value) => sourceReadingTextFits(value, maxLength));

bool _validId(String value) =>
    value.isNotEmpty &&
    value == value.trim() &&
    sourceReadingTextFits(value, 256);

bool sourceReadingTextFits(String value, int maxLength) =>
    value.length <= maxLength && !_unsupportedControls.hasMatch(value);

bool _validEpoch(int value) => value >= 0 && value <= _maxEpochMilliseconds;

void _validateJsonSize(String raw) {
  if (raw.length > _maxJsonBytes || utf8.encode(raw).length > _maxJsonBytes) {
    throw const FormatException('Source reading round exceeds storage limit');
  }
}
