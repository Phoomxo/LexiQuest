import 'dart:convert';

import 'learning_evidence_contract.dart';
import 'learning_models.dart';

final class QuizVocabularyChanged extends StateError {
  QuizVocabularyChanged()
    : super('Original quiz vocabulary is no longer current');
}

final class QuizOrigin {
  QuizOrigin({
    required this.route,
    required this.promptKind,
    this.categoryId,
    Iterable<String>? wordIds,
    this.parentId,
  }) : wordIds = wordIds == null ? null : List.unmodifiable(wordIds) {
    _requireId(route);
    if (categoryId case final id?) _requireId(id);
    if (parentId case final id?) _requireId(id);
    if (this.wordIds case final ids?) {
      if (ids.isEmpty || ids.length > _maxQuestions) {
        throw const FormatException('Invalid quiz selection size');
      }
      for (final id in ids) {
        _requireId(id);
      }
    }
  }

  final String route;
  final QuizPromptKind promptKind;
  final String? categoryId;
  final List<String>? wordIds;
  final String? parentId;

  @override
  bool operator ==(Object other) {
    if (other is! QuizOrigin ||
        route != other.route ||
        promptKind != other.promptKind ||
        categoryId != other.categoryId ||
        parentId != other.parentId) {
      return false;
    }
    final ids = wordIds;
    final otherIds = other.wordIds;
    if (ids == null || otherIds == null) return ids == otherIds;
    if (ids.length != otherIds.length) return false;
    for (var i = 0; i < ids.length; i++) {
      if (ids[i] != otherIds[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    route,
    promptKind,
    categoryId,
    parentId,
    wordIds == null ? null : Object.hashAll(wordIds!),
  );
}

final class QuizPlan {
  QuizPlan({
    required this.origin,
    required Iterable<QuizQuestion> questions,
    this.categoryName,
    this.returnLabel,
  }) : questions = List.unmodifiable([
         for (final q in questions)
           if (q.kind == QuizPromptKind.meaningChoice)
             QuizQuestion(word: q.word, options: List.unmodifiable(q.options))
           else
             q,
       ]) {
    _requireText(categoryName ?? '', allowEmpty: true);
    _requireText(returnLabel ?? '', allowEmpty: true);
    if (this.questions.isEmpty || this.questions.length > _maxQuestions) {
      throw const FormatException('Invalid quiz question count');
    }
    final requestedIds = origin.wordIds?.toSet();
    for (final q in this.questions) {
      if (q.kind != origin.promptKind ||
          (origin.categoryId != null &&
              q.word.categoryId != origin.categoryId) ||
          (requestedIds != null && !requestedIds.contains(q.word.id))) {
        throw const FormatException('Quiz question is outside its origin');
      }
      _validateQuestion(q);
    }
  }

  final QuizOrigin origin;
  final List<QuizQuestion> questions;
  final String? categoryName;
  final String? returnLabel;
}

enum QuizPhase { awaitingAnswer, feedback, finished }

enum QuizStep { pause, resume, retryQuestion, next, finish }

typedef QuizCursor = ({
  int revision,
  int slot,
  QuizPhase phase,
  String? lastAttemptId,
  int activeResponseMs,
});

// A null option records an explicit reveal. A missing response is separate.
typedef QuizResponse = ({int slot, int? selectedOption});
typedef QuizAdmission = ({int expectedRevision, QuizResponse response});

const QuizCursor initialQuizCursor = (
  revision: 0,
  slot: 0,
  phase: QuizPhase.awaitingAnswer,
  lastAttemptId: null,
  activeResponseMs: 0,
);

final class QuizRound {
  QuizRound({
    required this.sessionId,
    required this.startedAtUtc,
    required this.plan,
    required this.cursor,
    required this.isPaused,
    required this.committedAnswers,
    this.feedback,
    Iterable<QuizWord> mistakes = const [],
    this.summary,
  }) : mistakes = List.unmodifiable(mistakes);

  final String sessionId;
  final DateTime startedAtUtc;
  final QuizPlan plan;
  final QuizCursor cursor;
  final bool isPaused;
  final int committedAnswers;
  final QuizResponse? feedback;
  final List<QuizWord> mistakes;
  final LearningSessionSummary? summary;

  String get state => switch (cursor.phase) {
    QuizPhase.finished => 'completed',
    _ => isPaused ? 'paused' : 'active',
  };
}

const _version = 1;
const _maxQuestions = 100;
const _maxOptions = 4;
const _maxTextLength = 4096;
const _maxPlanBytes = 4 * 1024 * 1024;
const _maxSmallBytes = 4096;

String encodeQuizPlan(QuizPlan plan) => _encode({
  'v': _version,
  'origin': {
    'route': plan.origin.route,
    'promptKind': plan.origin.promptKind.name,
    'categoryId': plan.origin.categoryId,
    'wordIds': plan.origin.wordIds,
    'parentId': plan.origin.parentId,
  },
  'categoryName': plan.categoryName,
  'returnLabel': plan.returnLabel,
  'questions': plan.questions.map(_questionJson).toList(),
}, _maxPlanBytes);

QuizPlan decodeQuizPlan(String raw) {
  final json = _decode(raw, _maxPlanBytes);
  if (json
      case {
        'v': final int version,
        'origin': final Map<String, dynamic> origin,
        'categoryName': final String? categoryName,
        'returnLabel': final String? returnLabel,
        'questions': final List<dynamic> questions,
      }
      when version == _version &&
          json.length == 5 &&
          questions.length <= _maxQuestions) {
    return QuizPlan(
      origin: _decodeOrigin(origin),
      questions: questions.map(_decodeQuestion),
      categoryName: categoryName,
      returnLabel: returnLabel,
    );
  }
  throw const FormatException('Invalid quiz plan');
}

QuizOrigin _decodeOrigin(Map<String, dynamic> json) {
  if (json case {
    'route': final String route,
    'promptKind': final String kind,
    'categoryId': final String? categoryId,
    'wordIds': final List<dynamic>? wordIds,
    'parentId': final String? parentId,
  } when json.length == 5) {
    return QuizOrigin(
      route: route,
      promptKind: _named(QuizPromptKind.values, kind),
      categoryId: categoryId,
      wordIds: wordIds == null ? null : _strings(wordIds, _maxQuestions),
      parentId: parentId,
    );
  }
  throw const FormatException('Invalid quiz origin');
}

String encodeQuizCursor(QuizCursor cursor, {required QuizPlan plan}) {
  _validateCursor(cursor, plan);
  return _encode({
    'v': _version,
    'revision': cursor.revision,
    'slot': cursor.slot,
    'phase': cursor.phase.name,
    'lastAttemptId': cursor.lastAttemptId,
    'activeResponseMs': cursor.activeResponseMs,
  }, _maxSmallBytes);
}

QuizCursor decodeQuizCursor(String raw, {required QuizPlan plan}) {
  final json = _decode(raw, _maxSmallBytes);
  if (json case {
    'v': final int version,
    'revision': final int revision,
    'slot': final int slot,
    'phase': final String phase,
    'lastAttemptId': final String? lastAttemptId,
    'activeResponseMs': final int activeResponseMs,
  } when version == _version && json.length == 6) {
    final QuizCursor cursor = (
      revision: revision,
      slot: slot,
      phase: _named(QuizPhase.values, phase),
      lastAttemptId: lastAttemptId,
      activeResponseMs: activeResponseMs,
    );
    _validateCursor(cursor, plan);
    return cursor;
  }
  throw const FormatException('Invalid quiz continuation');
}

String encodeQuizResponse(QuizResponse response, {required QuizPlan plan}) {
  _validateResponse(response, plan);
  return _encode({
    'v': _version,
    'slot': response.slot,
    'selectedOption': response.selectedOption,
  }, _maxSmallBytes);
}

QuizResponse decodeQuizResponse(String raw, {required QuizPlan plan}) {
  final json = _decode(raw, _maxSmallBytes);
  if (json case {
    'v': final int version,
    'slot': final int slot,
    'selectedOption': final int? selectedOption,
  } when version == _version && json.length == 3) {
    final response = (slot: slot, selectedOption: selectedOption);
    _validateResponse(response, plan);
    return response;
  }
  throw const FormatException('Invalid quiz answer evidence');
}

Map<String, Object?> _questionJson(QuizQuestion q) => {
  'word': _wordJson(q.word),
  'kind': q.kind.name,
  'promptText': q.promptText,
  'options': q.options,
  'correctOption': q.options.indexOf(q.correctAnswer),
  'optionWords': q.optionWords == null
      ? null
      : {
          for (final option in q.options)
            option: _wordJson(q.optionWords![option]!),
        },
  'optionExplanations': q.optionExplanations == null
      ? null
      : {for (final option in q.options) option: q.optionExplanations![option]},
  'sourcePin': q.sourcePin,
};

QuizQuestion _decodeQuestion(Object? value) {
  if (value case {
    'word': final Object? target,
    'kind': final String kind,
    'promptText': final String promptText,
    'options': final List<dynamic> options,
    'correctOption': final int correctOption,
    'optionWords': final Map<String, dynamic>? optionWords,
    'optionExplanations': final Map<String, dynamic>? optionExplanations,
    'sourcePin': final String? sourcePin,
  } when value.length == 8) {
    final word = _decodeWord(target);
    final choices = _strings(options, _maxOptions);
    final question = switch (_named(QuizPromptKind.values, kind)) {
      QuizPromptKind.meaningChoice
          when optionWords == null &&
              optionExplanations == null &&
              sourcePin == null =>
        QuizQuestion(word: word, options: choices),
      QuizPromptKind.spellingChoice
          when optionWords != null &&
              optionExplanations == null &&
              sourcePin == null =>
        QuizQuestion.spellingChoice(
          word: word,
          options: choices,
          optionWords: _optionMap(optionWords, _decodeWord),
        ),
      QuizPromptKind.definitionChoice
          when optionWords != null &&
              optionExplanations != null &&
              sourcePin != null =>
        QuizQuestion.definitionChoice(
          word: word,
          options: choices,
          definition: promptText,
          optionWords: _optionMap(optionWords, _decodeWord),
          optionExplanations: _optionMap(optionExplanations, _string),
          sourcePin: sourcePin,
        ),
      _ => throw const FormatException('Missing quiz prompt evidence'),
    };
    if (question.promptText == promptText &&
        correctOption >= 0 &&
        correctOption < choices.length &&
        choices[correctOption] == question.correctAnswer) {
      return question;
    }
  }
  throw const FormatException('Invalid quiz question');
}

Map<String, Object?> _wordJson(QuizWord word) => {
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
  } when raw.length == 6) {
    return QuizWord(
      id: id,
      categoryId: categoryId,
      spelling: spelling,
      meaning: meaning,
      partOfSpeech: partOfSpeech,
      localRevision: localRevision,
    );
  }
  throw const FormatException('Invalid quiz word snapshot');
}

void _validateQuestion(QuizQuestion q) {
  _validateWord(q.word);
  _requireText(q.promptText);
  final options = q.options.toSet();
  if (options.length < 2 ||
      options.length > _maxOptions ||
      options.length != q.options.length ||
      !options.contains(q.correctAnswer)) {
    throw const FormatException('Invalid quiz options');
  }
  for (final option in options) {
    _requireText(option);
  }
  if (q.optionWords case final optionWords?) {
    if (optionWords.length != options.length ||
        !options.containsAll(optionWords.keys)) {
      throw const FormatException('Quiz option word is not displayed');
    }
    for (final entry in optionWords.entries) {
      _validateWord(entry.value);
      if (entry.key != entry.value.spelling) {
        throw const FormatException(
          'Quiz option word differs from its spelling',
        );
      }
    }
    final target = optionWords[q.correctAnswer]!;
    if (target.id != q.word.id ||
        target.categoryId != q.word.categoryId ||
        target.spelling != q.word.spelling ||
        target.meaning != q.word.meaning ||
        target.partOfSpeech != q.word.partOfSpeech ||
        target.localRevision != q.word.localRevision) {
      throw const FormatException(
        'Quiz correct option differs from its target',
      );
    }
  }
  if (q.kind == QuizPromptKind.definitionChoice) {
    _requireText(q.sourcePin ?? '');
    final explanations = q.optionExplanations!;
    if (explanations.length != options.length ||
        !options.containsAll(explanations.keys)) {
      throw const FormatException('Missing quiz option explanations');
    }
    for (final explanation in explanations.values) {
      _requireText(explanation);
    }
  }
}

void _validateWord(QuizWord word) {
  _requireId(word.id);
  _requireId(word.categoryId);
  _requireText(word.spelling);
  _requireText(word.meaning);
  _requireText(word.partOfSpeech, allowEmpty: true);
  if (word.localRevision <= 0) {
    throw const FormatException('Invalid quiz word revision');
  }
}

void _validateCursor(QuizCursor cursor, QuizPlan plan) {
  _requireSlot(cursor.slot, plan);
  final attemptId = cursor.lastAttemptId;
  if (cursor.revision < 0 ||
      (cursor.phase == QuizPhase.awaitingAnswer) != (attemptId == null) ||
      (cursor.phase == QuizPhase.finished &&
          cursor.slot != plan.questions.length - 1) ||
      cursor.activeResponseMs < 0 ||
      cursor.activeResponseMs > LearningEvidenceContract.maxResponseTimeMs) {
    throw const FormatException('Invalid quiz continuation phase or time');
  }
  if (attemptId != null) _requireId(attemptId);
}

void _validateResponse(QuizResponse response, QuizPlan plan) {
  _requireSlot(response.slot, plan);
  final option = response.selectedOption;
  if (option != null &&
      (option < 0 || option >= plan.questions[response.slot].options.length)) {
    throw const FormatException('Quiz selected option is not displayed');
  }
}

void _requireSlot(int slot, QuizPlan plan) {
  if (slot < 0 || slot >= plan.questions.length) {
    throw const FormatException('Quiz slot is outside the plan');
  }
}

void _requireId(String value) {
  if (!LearningEvidenceContract.validIdentifier(value)) {
    throw const FormatException('Invalid quiz identifier');
  }
}

void _requireText(String value, {bool allowEmpty = false}) {
  if (value.length > _maxTextLength || (!allowEmpty && value.trim().isEmpty)) {
    throw const FormatException('Invalid quiz display text');
  }
}

T _named<T extends Enum>(List<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw const FormatException('Unknown quiz enum value');
}

String _string(Object? value) {
  if (value is String) return value;
  throw const FormatException('Expected quiz string');
}

List<String> _strings(List<dynamic> values, int limit) {
  if (values.length > limit) {
    throw const FormatException('Too many quiz values');
  }
  return List.unmodifiable(values.map(_string));
}

Map<String, T> _optionMap<T>(
  Map<String, dynamic> raw,
  T Function(Object?) read,
) {
  if (raw.length > _maxOptions) {
    throw const FormatException('Too many quiz option details');
  }
  return raw.map((key, value) => MapEntry(key, read(value)));
}

String _encode(Map<String, Object?> value, int maxBytes) {
  final raw = jsonEncode(value);
  _requireSize(raw, maxBytes);
  return raw;
}

Map<String, dynamic> _decode(String raw, int maxBytes) {
  _requireSize(raw, maxBytes);
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, dynamic>) return decoded;
  throw const FormatException('Expected quiz JSON object');
}

void _requireSize(String raw, int maxBytes) {
  if (raw.length > maxBytes || utf8.encode(raw).length > maxBytes) {
    throw const FormatException('Quiz JSON exceeds size limit');
  }
}
